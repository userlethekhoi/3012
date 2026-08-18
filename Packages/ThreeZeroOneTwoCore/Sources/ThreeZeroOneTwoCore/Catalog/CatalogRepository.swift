#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Foundation

public enum CatalogRepositoryError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge
    case notModifiedWithoutCache
    case revisionRollback(cached: Int, received: Int)
}

public actor CatalogRepository {
    public static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let catalogURL: URL
    private let session: URLSession
    private let cache: CatalogCache
    private let verifier: CatalogVerifier
    private let decoder = JSONDecoder()

    public init(
        catalogURL: URL,
        session: URLSession = .shared,
        cache: CatalogCache,
        verifier: CatalogVerifier
    ) {
        self.catalogURL = catalogURL
        self.session = session
        self.cache = cache
        self.verifier = verifier
    }

    public func loadCached() async throws -> VerifiedCatalog? {
        guard let cached = try await cache.load() else { return nil }
        return try decodeAndVerify(cached.data)
    }

    public func refresh() async throws -> VerifiedCatalog {
        let cached = try await cache.load()
        let cachedVerified = try cached.map { try decodeAndVerify($0.data) }

        var request = URLRequest(url: catalogURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cached?.metadata.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CatalogRepositoryError.invalidResponse
        }
        if httpResponse.statusCode == 304 {
            guard let cachedVerified else {
                throw CatalogRepositoryError.notModifiedWithoutCache
            }
            return cachedVerified
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CatalogRepositoryError.httpStatus(httpResponse.statusCode)
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw CatalogRepositoryError.responseTooLarge
        }

        let received = try decodeAndVerify(data)
        if let cachedRevision = cachedVerified?.payload.revision,
           received.payload.revision < cachedRevision {
            throw CatalogRepositoryError.revisionRollback(
                cached: cachedRevision,
                received: received.payload.revision
            )
        }

        try await cache.save(
            data: data,
            etag: httpResponse.value(forHTTPHeaderField: "ETag")
        )
        return received
    }

    private func decodeAndVerify(_ data: Data) throws -> VerifiedCatalog {
        let document = try decoder.decode(CatalogDocument.self, from: data)
        return try verifier.verify(document)
    }
}
