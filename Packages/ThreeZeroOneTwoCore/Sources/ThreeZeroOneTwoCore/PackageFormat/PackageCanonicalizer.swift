import Foundation

public enum PackageCanonicalizer {
    public static func encode(_ manifest: PackageManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }
}
