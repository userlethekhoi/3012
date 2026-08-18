import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class StreamingSHA256Tests: XCTestCase {
    func testStreamingDigestMatchesCryptoKit() throws {
        let data = Data((0..<32_768).map { UInt8($0 % 251) })
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try StreamingSHA256.digest(of: fileURL, chunkSize: 257)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(result.hex, expected)
        XCTAssertEqual(result.byteCount, Int64(data.count))
    }

    func testSizeMismatchIsReported() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("3012".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertThrowsError(
            try StreamingSHA256.verify(
                fileURL: fileURL,
                expectedSize: 999,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(
                error as? FileIntegrityError,
                .sizeMismatch(expected: 999, actual: 4)
            )
        }
    }
}
