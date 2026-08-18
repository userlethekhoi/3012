import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class CatalogSignerTests: XCTestCase {
    func testSignedCatalogVerifiesWithDerivedPublicKey() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = CatalogPayload(
            revision: 8,
            channel: .stable,
            generatedAt: "2026-08-18T00:00:00Z",
            publisherKeyID: "publisher-2026",
            patches: []
        )

        let document = try CatalogSigner.sign(
            payload: payload,
            privateKeyData: privateKey.rawRepresentation
        )
        let verified = try CatalogVerifier(trustedPublicKeys: [
            "publisher-2026": try CatalogSigner.publicKey(for: privateKey.rawRepresentation)
        ]).verify(document)

        XCTAssertEqual(verified.payload, payload)
    }

    func testInvalidPrivateKeyIsRejected() {
        let payload = CatalogPayload(
            revision: 0,
            channel: .beta,
            generatedAt: "2026-08-18T00:00:00Z",
            publisherKeyID: "test",
            patches: []
        )
        XCTAssertThrowsError(try CatalogSigner.sign(payload: payload, privateKeyData: Data())) { error in
            XCTAssertEqual(error as? CatalogSigningError, .invalidPrivateKey)
        }
    }
}
