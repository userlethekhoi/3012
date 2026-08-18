import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ThreeZeroOneTwoCore

final class CatalogRepositoryTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testRefreshStoresETagAndUses304Cache() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let documentData = try makeDocumentData(privateKey: privateKey, revision: 7)
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["ETag": "\"revision-7\""]
                )!
                return (response, documentData)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"revision-7\"")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 304,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data())
        }

        let repository = makeRepository(
            cacheURL: cacheURL,
            publicKey: privateKey.publicKey.rawRepresentation
        )
        let first = try await repository.refresh()
        let second = try await repository.refresh()

        XCTAssertEqual(first.payload.revision, 7)
        XCTAssertEqual(second, first)
        XCTAssertEqual(requestCount, 2)
    }

    func testOlderSignedRevisionIsRejected() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let revision10 = try makeDocumentData(privateKey: privateKey, revision: 10)
        let revision9 = try makeDocumentData(privateKey: privateKey, revision: 9)
        var requestCount = 0
        MockURLProtocol.handler = { request in
            requestCount += 1
            let data = requestCount == 1 ? revision10 : revision9
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, data)
        }
        let repository = makeRepository(
            cacheURL: cacheURL,
            publicKey: privateKey.publicKey.rawRepresentation
        )
        _ = try await repository.refresh()

        do {
            _ = try await repository.refresh()
            XCTFail("Expected revision rollback rejection")
        } catch {
            XCTAssertEqual(
                error as? CatalogRepositoryError,
                .revisionRollback(cached: 10, received: 9)
            )
        }
    }

    private func makeRepository(cacheURL: URL, publicKey: Data) -> CatalogRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return CatalogRepository(
            catalogURL: URL(string: "https://catalog.example.com/stable.json")!,
            session: URLSession(configuration: configuration),
            cache: CatalogCache(directoryURL: cacheURL),
            verifier: CatalogVerifier(trustedPublicKeys: ["test-key": publicKey])
        )
    }

    private func makeDocumentData(
        privateKey: Curve25519.Signing.PrivateKey,
        revision: Int
    ) throws -> Data {
        let payload = CatalogPayload(
            revision: revision,
            channel: .stable,
            generatedAt: "2026-08-18T00:00:00Z",
            publisherKeyID: "test-key",
            patches: []
        )
        let signature = try privateKey.signature(
            for: CatalogCanonicalizer.encode(payload)
        ).base64EncodedString()
        return try JSONEncoder().encode(
            CatalogDocument(signed: payload, signature: signature)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
