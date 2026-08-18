import Foundation

public enum CatalogCanonicalizer {
    public static func encode(_ payload: CatalogPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }
}
