import Foundation
import Security
import Crypto
import Citadel

public enum KeychainVault {
    private static let serviceName = "com.dev.app3012.vault"

    private static var fallbackDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(".3012vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fallbackFileURL(forKey key: String) -> URL {
        let safe = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return fallbackDirectory.appendingPathComponent(safe)
    }

    public static func saveData(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        let fallbackURL = fallbackFileURL(forKey: key)
        if status == errSecSuccess {
            try? FileManager.default.removeItem(at: fallbackURL)
        } else {
            try? data.write(to: fallbackURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    public static func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        return try? Data(contentsOf: fallbackFileURL(forKey: key))
    }

    public static func saveString(_ value: String, forKey key: String) {
        saveData(Data(value.utf8), forKey: key)
    }

    public static func loadString(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: fallbackFileURL(forKey: key))
    }

    // MARK: - Ed25519 SSH Key Pair Generation & Storage
    public struct GeneratedSSHKeyPair {
        public let publicKeyAuthorizedLine: String
        public let privateKeyOpenSSHPEM: String
        public let rawPrivateKey: Data
    }

    public static func generateOrLoadDeviceEd25519Key(keyID: String = "default-ed25519", regenerate: Bool = false) -> GeneratedSSHKeyPair {
        let storageKey = "ssh.ed25519.\(keyID)"
        let privateKey: Curve25519.Signing.PrivateKey
        if !regenerate,
           let existingRaw = loadData(forKey: storageKey),
           let restored = try? Curve25519.Signing.PrivateKey(rawRepresentation: existingRaw) {
            privateKey = restored
        } else {
            let fresh = Curve25519.Signing.PrivateKey()
            saveData(fresh.rawRepresentation, forKey: storageKey)
            privateKey = fresh
        }

        let pubLine = formatOpenSSHEd25519PublicKey(privateKey.publicKey.rawRepresentation, comment: "3012-mobile-ide")
        let privPEM = privateKey.makeSSHRepresentation(comment: "3012-mobile-ide")
        return GeneratedSSHKeyPair(
            publicKeyAuthorizedLine: pubLine,
            privateKeyOpenSSHPEM: privPEM,
            rawPrivateKey: privateKey.rawRepresentation
        )
    }

    private static func formatOpenSSHEd25519PublicKey(_ rawPub32Bytes: Data, comment: String) -> String {
        var wire = Data()
        let keyTypeBytes = Array("ssh-ed25519".utf8)
        var typeLen = UInt32(keyTypeBytes.count).bigEndian
        wire.append(Data(bytes: &typeLen, count: 4))
        wire.append(contentsOf: keyTypeBytes)

        var pubLen = UInt32(rawPub32Bytes.count).bigEndian
        wire.append(Data(bytes: &pubLen, count: 4))
        wire.append(rawPub32Bytes)

        return "ssh-ed25519 \(wire.base64EncodedString()) \(comment)"
    }
}
