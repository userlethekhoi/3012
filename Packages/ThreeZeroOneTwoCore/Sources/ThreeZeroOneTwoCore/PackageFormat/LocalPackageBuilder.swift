import CryptoKit
import Foundation

public struct LocalPackageSource: Sendable {
    public let id: String
    public let sourceURL: URL
    public let bundleID: String
    public let relativePath: String
    public let operation: PackageOperation

    public init(
        id: String,
        sourceURL: URL,
        bundleID: String,
        relativePath: String,
        operation: PackageOperation
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.bundleID = bundleID
        self.relativePath = relativePath
        self.operation = operation
    }
}

public enum LocalPackageBuilderError: Error, Equatable {
    case noSources
    case tooManySources
    case invalidSource(String)
    case duplicateDestination(String)
    case packageTooLarge
    case invalidPrivateKey
}

public enum LocalPackageBuilder {
    public static func build(
        name: String,
        version: String = "1.0.0",
        publisherKeyID: String,
        privateKeyData: Data,
        sources: [LocalPackageSource],
        outputURL: URL,
        chunkSize: Int = 1_024 * 1_024
    ) throws -> Data {
        guard !sources.isEmpty else { throw LocalPackageBuilderError.noSources }
        guard sources.count <= PackageReader.maximumEntries else {
            throw LocalPackageBuilderError.tooManySources
        }
        guard chunkSize > 0 else { throw FileIntegrityError.invalidChunkSize }
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        } catch {
            throw LocalPackageBuilderError.invalidPrivateKey
        }

        var destinations = Set<String>()
        var totalPayloadBytes: UInt64 = 0
        var entries: [PackageEntry] = []
        for source in sources {
            do {
                try PackagePathValidator.validate(source.relativePath)
            } catch {
                throw LocalPackageBuilderError.invalidSource(source.id)
            }
            guard validIdentifier(source.id), !source.bundleID.isEmpty else {
                throw LocalPackageBuilderError.invalidSource(source.id)
            }
            let destinationKey = source.bundleID + "\n" + source.relativePath
            guard destinations.insert(destinationKey).inserted else {
                throw LocalPackageBuilderError.duplicateDestination(source.relativePath)
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source.sourceURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw LocalPackageBuilderError.invalidSource(source.id)
            }
            let digest = try StreamingSHA256.digest(of: source.sourceURL, chunkSize: chunkSize)
            guard digest.byteCount >= 0 else {
                throw LocalPackageBuilderError.invalidSource(source.id)
            }
            let byteCount = UInt64(digest.byteCount)
            guard byteCount <= PackageReader.maximumPackageBytes,
                  totalPayloadBytes <= PackageReader.maximumPackageBytes - byteCount else {
                throw LocalPackageBuilderError.packageTooLarge
            }
            totalPayloadBytes += byteCount
            entries.append(PackageEntry(
                id: source.id,
                bundleID: source.bundleID,
                relativePath: source.relativePath,
                operation: source.operation,
                length: digest.byteCount,
                sha256: digest.hex
            ))
        }

        let manifest = PackageManifest(
            packageID: UUID().uuidString,
            name: name,
            version: version,
            publisherKeyID: publisherKeyID,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            minAppVersion: "0.1.0",
            entries: entries
        )
        let canonical = try PackageCanonicalizer.encode(manifest)
        let signature = try privateKey.signature(for: canonical).base64EncodedString()
        let document = PackageDocument(signed: manifest, signature: signature)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(document)
        guard manifestData.count <= Int(PackageReader.maximumManifestBytes),
              UInt64(manifestData.count) + PackageReader.headerLength + totalPayloadBytes
                <= PackageReader.maximumPackageBytes else {
            throw LocalPackageBuilderError.packageTooLarge
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try output.write(contentsOf: PackageReader.magic)
            var length = UInt64(manifestData.count).bigEndian
            let lengthData = withUnsafeBytes(of: &length) { Data($0) }
            try output.write(contentsOf: lengthData)
            try output.write(contentsOf: manifestData)
            for source in sources {
                try append(source.sourceURL, to: output, chunkSize: chunkSize)
            }
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return privateKey.publicKey.rawRepresentation
    }

    private static func append(_ sourceURL: URL, to output: FileHandle, chunkSize: Int) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        while true {
            let data = try input.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else { break }
            try output.write(contentsOf: data)
        }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) ||
            (byte >= 65 && byte <= 90) ||
            (byte >= 97 && byte <= 122) ||
            byte == 45 || byte == 46 || byte == 95
        }
    }
}
