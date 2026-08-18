import Foundation

public struct PackagePreview: Equatable, Sendable {
    public let packageID: String
    public let name: String
    public let version: String
    public let publisherKeyID: String
    public let entryCount: Int
    public let payloadBytes: Int64

    public init(
        packageID: String,
        name: String,
        version: String,
        publisherKeyID: String,
        entryCount: Int,
        payloadBytes: Int64
    ) {
        self.packageID = packageID
        self.name = name
        self.version = version
        self.publisherKeyID = publisherKeyID
        self.entryCount = entryCount
        self.payloadBytes = payloadBytes
    }
}

public enum PackagePreviewError: Error, Equatable {
    case fileTooLarge
    case truncated
    case invalidMagic
    case invalidManifestLength
    case invalidManifest
}

public enum PackagePreviewReader {
    public static func read(fileURL: URL) throws -> PackagePreview {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize <= PackageReader.maximumPackageBytes else {
            throw PackagePreviewError.fileTooLarge
        }
        guard fileSize >= PackageReader.headerLength else {
            throw PackagePreviewError.truncated
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard try readExactly(handle, count: 8) == PackageReader.magic else {
            throw PackagePreviewError.invalidMagic
        }
        let lengthData = try readExactly(handle, count: 8)
        let manifestLength = lengthData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard manifestLength > 0,
              manifestLength <= PackageReader.maximumManifestBytes,
              PackageReader.headerLength + manifestLength <= fileSize else {
            throw PackagePreviewError.invalidManifestLength
        }
        let manifestData = try readExactly(handle, count: Int(manifestLength))
        let document: PackageDocument
        do {
            document = try JSONDecoder().decode(PackageDocument.self, from: manifestData)
        } catch {
            throw PackagePreviewError.invalidManifest
        }
        guard document.signed.entries.count <= PackageReader.maximumEntries else {
            throw PackagePreviewError.invalidManifest
        }
        var payloadBytes: Int64 = 0
        for entry in document.signed.entries {
            guard entry.length >= 0, payloadBytes <= Int64.max - entry.length else {
                throw PackagePreviewError.invalidManifest
            }
            payloadBytes += entry.length
        }
        guard UInt64(payloadBytes) == fileSize - PackageReader.headerLength - manifestLength else {
            throw PackagePreviewError.invalidManifest
        }
        return PackagePreview(
            packageID: document.signed.packageID,
            name: document.signed.name,
            version: document.signed.version,
            publisherKeyID: document.signed.publisherKeyID,
            entryCount: document.signed.entries.count,
            payloadBytes: payloadBytes
        )
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            let data = try handle.read(upToCount: count - result.count) ?? Data()
            guard !data.isEmpty else { throw PackagePreviewError.truncated }
            result.append(data)
        }
        return result
    }
}
