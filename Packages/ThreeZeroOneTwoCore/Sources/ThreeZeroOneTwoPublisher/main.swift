import Foundation
import ThreeZeroOneTwoCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PublisherError: Error, CustomStringConvertible {
    case usage
    case missingSigningKey
    case invalidSigningKey

    var description: String {
        switch self {
        case .usage:
            return "Usage: 3012-publisher sign-catalog <payload.json> <catalog.json> | package-metadata <package.3012pkg> <https-url>"
        case .missingSigningKey:
            return "THREE_ZERO_ONE_TWO_SIGNING_KEY_BASE64 is required"
        case .invalidSigningKey:
            return "The signing key must be a valid Base64 Ed25519 private key"
        }
    }
}

func signCatalog(input: String, output: String) throws {
    guard let encodedKey = ProcessInfo.processInfo.environment["THREE_ZERO_ONE_TWO_SIGNING_KEY_BASE64"] else {
        throw PublisherError.missingSigningKey
    }
    guard let privateKey = Data(base64Encoded: encodedKey) else {
        throw PublisherError.invalidSigningKey
    }
    let decoder = JSONDecoder()
    let payload = try decoder.decode(CatalogPayload.self, from: Data(contentsOf: URL(fileURLWithPath: input)))
    let document = try CatalogSigner.sign(payload: payload, privateKeyData: privateKey)
    let publicKey = try CatalogSigner.publicKey(for: privateKey)
    _ = try CatalogVerifier(trustedPublicKeys: [payload.publisherKeyID: publicKey]).verify(document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(document).write(to: URL(fileURLWithPath: output), options: .atomic)
}

func packageMetadata(input: String, downloadURL: String) throws {
    guard let url = URL(string: downloadURL), url.scheme?.lowercased() == "https" else {
        throw PublisherError.usage
    }
    let fileURL = URL(fileURLWithPath: input)
    let result = try StreamingSHA256.digest(of: fileURL)
    let metadata: [String: Any] = [
        "downloadURL": downloadURL,
        "fileSize": result.byteCount,
        "sha256": result.hex
    ]
    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else { throw PublisherError.usage }
    switch arguments[1] {
    case "sign-catalog":
        try signCatalog(input: arguments[2], output: arguments[3])
    case "package-metadata":
        try packageMetadata(input: arguments[2], downloadURL: arguments[3])
    default:
        throw PublisherError.usage
    }
} catch {
    FileHandle.standardError.write(Data("3012-publisher: \(error)\n".utf8))
    exit(1)
}
