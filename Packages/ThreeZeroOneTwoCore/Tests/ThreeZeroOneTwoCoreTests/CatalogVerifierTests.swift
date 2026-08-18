import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class CatalogVerifierTests: XCTestCase {
    func testValidSignedCatalog() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = makePayload()
        let canonical = try CatalogCanonicalizer.encode(payload)
        let signature = try privateKey.signature(for: canonical).base64EncodedString()
        let document = CatalogDocument(signed: payload, signature: signature)
        let verifier = CatalogVerifier(
            trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
        )

        let verified = try verifier.verify(document)

        XCTAssertEqual(verified.payload, payload)
        XCTAssertEqual(verified.canonicalData, canonical)
    }

    func testTamperedCatalogIsRejected() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let original = makePayload(revision: 1)
        let signature = try privateKey.signature(
            for: CatalogCanonicalizer.encode(original)
        ).base64EncodedString()
        let tampered = makePayload(revision: 2)
        let verifier = CatalogVerifier(
            trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
        )

        XCTAssertThrowsError(
            try verifier.verify(CatalogDocument(signed: tampered, signature: signature))
        ) { error in
            XCTAssertEqual(error as? CatalogTrustError, .invalidSignature)
        }
    }

    func testDuplicatePatchIDIsRejectedBeforeTrust() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let patch = makePatch()
        let payload = CatalogPayload(
            revision: 1,
            channel: .stable,
            generatedAt: "2026-08-18T00:00:00Z",
            publisherKeyID: "test-key",
            patches: [patch, patch]
        )
        let signature = try privateKey.signature(
            for: CatalogCanonicalizer.encode(payload)
        ).base64EncodedString()
        let verifier = CatalogVerifier(
            trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
        )

        XCTAssertThrowsError(
            try verifier.verify(CatalogDocument(signed: payload, signature: signature))
        ) { error in
            XCTAssertEqual(error as? CatalogTrustError, .duplicatePatchID(patch.id))
        }
    }

    private func makePayload(revision: Int = 1) -> CatalogPayload {
        CatalogPayload(
            revision: revision,
            channel: .stable,
            generatedAt: "2026-08-18T00:00:00Z",
            publisherKeyID: "test-key",
            patches: [makePatch()]
        )
    }

    private func makePatch() -> CatalogPatch {
        CatalogPatch(
            id: "appearance-sample",
            name: "Appearance Sample",
            summary: "Signed catalog test entry.",
            version: "1.0.0",
            category: "Appearance",
            downloadURL: "https://cdn.example.com/appearance-sample/1.0.0.3012pkg",
            fileSize: 1_024,
            sha256: String(repeating: "a", count: 64),
            minAppVersion: "0.1.0",
            minIOS: "16.0",
            targetBundleIDs: ["com.example.target"],
            updatedAt: "2026-08-18T00:00:00Z"
        )
    }
}
