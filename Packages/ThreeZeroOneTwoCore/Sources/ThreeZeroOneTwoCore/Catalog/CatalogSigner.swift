import CryptoKit
import Foundation

public enum CatalogSigningError: Error, Equatable {
    case invalidPrivateKey
}

public enum CatalogSigner {
    public static func sign(
        payload: CatalogPayload,
        privateKeyData: Data
    ) throws -> CatalogDocument {
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        } catch {
            throw CatalogSigningError.invalidPrivateKey
        }
        let canonical = try CatalogCanonicalizer.encode(payload)
        let signature = try privateKey.signature(for: canonical).base64EncodedString()
        return CatalogDocument(signed: payload, signature: signature)
    }

    public static func publicKey(for privateKeyData: Data) throws -> Data {
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
                .publicKey.rawRepresentation
        } catch {
            throw CatalogSigningError.invalidPrivateKey
        }
    }
}
