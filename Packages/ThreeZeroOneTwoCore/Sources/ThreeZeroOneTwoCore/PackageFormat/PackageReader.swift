import CryptoKit
import Foundation

public enum PackageFormatError: Error, Equatable {
    case fileTooLarge
    case truncated
    case invalidMagic
    case invalidManifestLength
    case unsupportedSchema(Int)
    case invalidPackageID
    case invalidManifest
    case unknownPublisher(String)
    case invalidPublicKey
    case invalidSignatureEncoding
    case invalidSignature
    case tooManyEntries
    case duplicateEntryID(String)
    case duplicateDestination(String)
    case invalidEntry(String)
    case packageLengthMismatch
    case payloadDigestMismatch(String)
}

public struct PackageReader: Sendable {
    public static let magic = Data([0x33, 0x30, 0x31, 0x32, 0x50, 0x4B, 0x47, 0x00])
    public static let headerLength: UInt64 = 16
    public static let maximumManifestBytes: UInt64 = 2 * 1_024 * 1_024
    public static let maximumPackageBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    public static let maximumEntries = 10_000

    private let trustedPublicKeys: [String: Data]

    public init(trustedPublicKeys: [String: Data]) {
        self.trustedPublicKeys = trustedPublicKeys
    }

    public func inspect(fileURL: URL) throws -> VerifiedPackage {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize <= Self.maximumPackageBytes else { throw PackageFormatError.fileTooLarge }
        guard fileSize >= Self.headerLength else { throw PackageFormatError.truncated }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard try readExactly(handle: handle, count: 8) == Self.magic else {
            throw PackageFormatError.invalidMagic
        }
        let lengthData = try readExactly(handle: handle, count: 8)
        let manifestLength = decodeUInt64(lengthData)
        guard manifestLength > 0,
              manifestLength <= Self.maximumManifestBytes,
              Self.headerLength + manifestLength <= fileSize else {
            throw PackageFormatError.invalidManifestLength
        }
        let manifestData = try readExactly(handle: handle, count: Int(manifestLength))
        let document: PackageDocument
        do {
            document = try JSONDecoder().decode(PackageDocument.self, from: manifestData)
        } catch {
            throw PackageFormatError.invalidManifest
        }

        try verifyManifest(document)
        let entries = try validateEntries(
            document.signed.entries,
            payloadStart: Self.headerLength + manifestLength,
            fileSize: fileSize
        )
        return VerifiedPackage(fileURL: fileURL, manifest: document.signed, entries: entries)
    }

    public func verifyPayloads(_ package: VerifiedPackage, chunkSize: Int = 1_024 * 1_024) throws {
        guard chunkSize > 0 else { throw FileIntegrityError.invalidChunkSize }
        let handle = try FileHandle(forReadingFrom: package.fileURL)
        defer { try? handle.close() }

        for verifiedEntry in package.entries {
            try handle.seek(toOffset: verifiedEntry.payloadOffset)
            var remaining = verifiedEntry.entry.length
            var hasher = SHA256()
            while remaining > 0 {
                let requested = Int(min(Int64(chunkSize), remaining))
                let data = try handle.read(upToCount: requested) ?? Data()
                guard !data.isEmpty else { throw PackageFormatError.truncated }
                hasher.update(data: data)
                remaining -= Int64(data.count)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == verifiedEntry.entry.sha256.lowercased() else {
                throw PackageFormatError.payloadDigestMismatch(verifiedEntry.entry.id)
            }
        }
    }

    private func verifyManifest(_ document: PackageDocument) throws {
        let manifest = document.signed
        guard manifest.schemaVersion == 1 else {
            throw PackageFormatError.unsupportedSchema(manifest.schemaVersion)
        }
        guard UUID(uuidString: manifest.packageID) != nil else {
            throw PackageFormatError.invalidPackageID
        }
        guard !manifest.name.isEmpty,
              manifest.name.count <= 160,
              !manifest.version.isEmpty,
              manifest.version.count <= 64,
              ISO8601DateFormatter().date(from: manifest.createdAt) != nil else {
            throw PackageFormatError.invalidManifest
        }
        guard let keyData = trustedPublicKeys[manifest.publisherKeyID] else {
            throw PackageFormatError.unknownPublisher(manifest.publisherKeyID)
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw PackageFormatError.invalidPublicKey
        }
        guard let signature = Data(base64Encoded: document.signature) else {
            throw PackageFormatError.invalidSignatureEncoding
        }
        let canonical = try PackageCanonicalizer.encode(manifest)
        guard publicKey.isValidSignature(signature, for: canonical) else {
            throw PackageFormatError.invalidSignature
        }
    }

    private func validateEntries(
        _ entries: [PackageEntry],
        payloadStart: UInt64,
        fileSize: UInt64
    ) throws -> [VerifiedPackageEntry] {
        guard entries.count <= Self.maximumEntries else { throw PackageFormatError.tooManyEntries }
        var ids = Set<String>()
        var destinations = Set<String>()
        var offset = payloadStart
        var result: [VerifiedPackageEntry] = []

        for entry in entries {
            guard ids.insert(entry.id).inserted else {
                throw PackageFormatError.duplicateEntryID(entry.id)
            }
            let destinationKey = entry.bundleID + "\n" + entry.relativePath
            guard destinations.insert(destinationKey).inserted else {
                throw PackageFormatError.duplicateDestination(entry.relativePath)
            }
            do {
                try PackagePathValidator.validate(entry.relativePath)
            } catch {
                throw PackageFormatError.invalidEntry(entry.id)
            }
            guard !entry.id.isEmpty,
                  entry.id.count <= 128,
                  entry.id.utf8.allSatisfy({ byte in
                      (byte >= 48 && byte <= 57) ||
                      (byte >= 65 && byte <= 90) ||
                      (byte >= 97 && byte <= 122) ||
                      byte == 45 || byte == 46 || byte == 95
                  }),
                  !entry.bundleID.isEmpty,
                  entry.bundleID.count <= 255,
                  entry.length >= 0,
                  entry.sha256.count == 64,
                  entry.sha256.allSatisfy(\Character.isHexDigit) else {
                throw PackageFormatError.invalidEntry(entry.id)
            }
            let unsignedLength = UInt64(entry.length)
            guard offset <= fileSize,
                  unsignedLength <= fileSize - offset else {
                throw PackageFormatError.packageLengthMismatch
            }
            result.append(VerifiedPackageEntry(entry: entry, payloadOffset: offset))
            offset += unsignedLength
        }
        guard offset == fileSize else { throw PackageFormatError.packageLengthMismatch }
        return result
    }

    private func readExactly(handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let data = try handle.read(upToCount: count - result.count) ?? Data()
            guard !data.isEmpty else { throw PackageFormatError.truncated }
            result.append(data)
        }
        return result
    }

    private func decodeUInt64(_ data: Data) -> UInt64 {
        data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
