import Foundation

public struct CachedCatalogMetadata: Codable, Equatable, Sendable {
    public let etag: String?
    public let storedAt: String

    public init(etag: String?, storedAt: String) {
        self.etag = etag
        self.storedAt = storedAt
    }
}

public actor CatalogCache {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public func save(data: Data, etag: String?) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let metadata = CachedCatalogMetadata(
            etag: etag,
            storedAt: ISO8601DateFormatter().string(from: Date())
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try data.write(to: catalogURL, options: .atomic)
        try metadataData.write(to: metadataURL, options: .atomic)
    }

    public func load() throws -> (data: Data, metadata: CachedCatalogMetadata)? {
        guard fileManager.fileExists(atPath: catalogURL.path),
              fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: catalogURL, options: .mappedIfSafe)
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(CachedCatalogMetadata.self, from: metadataData)
        return (data, metadata)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private var catalogURL: URL { directoryURL.appendingPathComponent("catalog.json") }
    private var metadataURL: URL { directoryURL.appendingPathComponent("metadata.json") }
}
