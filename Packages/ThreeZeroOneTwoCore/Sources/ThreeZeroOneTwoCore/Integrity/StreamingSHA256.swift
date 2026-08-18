import CryptoKit
import Foundation

public enum FileIntegrityError: Error, Equatable {
    case invalidChunkSize
    case sizeMismatch(expected: Int64, actual: Int64)
    case digestMismatch(expected: String, actual: String)
}

public enum StreamingSHA256 {
    public static func digest(
        of fileURL: URL,
        chunkSize: Int = 1_024 * 1_024
    ) throws -> (hex: String, byteCount: Int64) {
        guard chunkSize > 0 else { throw FileIntegrityError.invalidChunkSize }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        var count: Int64 = 0
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
            count += Int64(data.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, count)
    }

    public static func verify(
        fileURL: URL,
        expectedSize: Int64,
        expectedSHA256: String,
        chunkSize: Int = 1_024 * 1_024
    ) throws {
        let result = try digest(of: fileURL, chunkSize: chunkSize)
        guard result.byteCount == expectedSize else {
            throw FileIntegrityError.sizeMismatch(expected: expectedSize, actual: result.byteCount)
        }
        let expected = expectedSHA256.lowercased()
        guard result.hex == expected else {
            throw FileIntegrityError.digestMismatch(expected: expected, actual: result.hex)
        }
    }
}
