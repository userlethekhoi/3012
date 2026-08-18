import CryptoKit
import Foundation

public enum CatalogTrustError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidRevision
    case invalidTimestamp
    case unknownPublisher(String)
    case invalidSignatureEncoding
    case invalidPublicKey
    case invalidSignature
    case tooManyEntries
    case duplicatePatchID(String)
    case invalidPatch(String)
}

public struct CatalogVerifier: Sendable {
    public static let maximumEntries = 1_000
    public static let maximumPatchBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    private let trustedPublicKeys: [String: Data]

    public init(trustedPublicKeys: [String: Data]) {
        self.trustedPublicKeys = trustedPublicKeys
    }

    public func verify(_ document: CatalogDocument) throws -> VerifiedCatalog {
        let payload = document.signed
        guard payload.schemaVersion == 1 else {
            throw CatalogTrustError.unsupportedSchema(payload.schemaVersion)
        }
        guard payload.revision >= 0 else {
            throw CatalogTrustError.invalidRevision
        }
        guard ISO8601DateFormatter().date(from: payload.generatedAt) != nil else {
            throw CatalogTrustError.invalidTimestamp
        }
        guard payload.patches.count <= Self.maximumEntries else {
            throw CatalogTrustError.tooManyEntries
        }

        var seenIDs = Set<String>()
        for patch in payload.patches {
            guard seenIDs.insert(patch.id).inserted else {
                throw CatalogTrustError.duplicatePatchID(patch.id)
            }
            try validate(patch)
        }

        guard let keyData = trustedPublicKeys[payload.publisherKeyID] else {
            throw CatalogTrustError.unknownPublisher(payload.publisherKeyID)
        }
        guard let signature = Data(base64Encoded: document.signature) else {
            throw CatalogTrustError.invalidSignatureEncoding
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw CatalogTrustError.invalidPublicKey
        }

        let canonicalData = try CatalogCanonicalizer.encode(payload)
        guard publicKey.isValidSignature(signature, for: canonicalData) else {
            throw CatalogTrustError.invalidSignature
        }
        return VerifiedCatalog(payload: payload, canonicalData: canonicalData)
    }

    private func validate(_ patch: CatalogPatch) throws {
        let identifier = patch.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              identifier.count <= 128,
              identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              !patch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              patch.name.count <= 160,
              patch.summary.count <= 1_000,
              !patch.version.isEmpty,
              patch.fileSize > 0,
              patch.fileSize <= Self.maximumPatchBytes,
              isSHA256(patch.sha256),
              ISO8601DateFormatter().date(from: patch.updatedAt) != nil,
              let url = URL(string: patch.downloadURL),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              patch.targetBundleIDs.count <= 32,
              patch.targetBundleIDs.allSatisfy({ !$0.isEmpty && $0.count <= 255 }) else {
            throw CatalogTrustError.invalidPatch(patch.id)
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\Character.isHexDigit)
    }
}
