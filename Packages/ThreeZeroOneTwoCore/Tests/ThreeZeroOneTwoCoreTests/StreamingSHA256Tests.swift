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

    func testTwoHundredMegabyteFileIsProcessedAsAStream() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let handle = try FileHandle(forWritingTo: fileURL)
        let oneMegabyte = Data(repeating: 0x30, count: 1_024 * 1_024)
        for _ in 0..<200 {
            try handle.write(contentsOf: oneMegabyte)
        }
        try handle.close()

        let result = try StreamingSHA256.digest(of: fileURL)

        XCTAssertEqual(result.byteCount, 200 * 1_024 * 1_024)
        XCTAssertEqual(result.hex.count, 64)
    }
}
