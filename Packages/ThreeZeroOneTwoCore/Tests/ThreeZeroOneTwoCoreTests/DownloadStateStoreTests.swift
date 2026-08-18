import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class DownloadStateStoreTests: XCTestCase {
    func testRecordsPersistAcrossStoreInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("downloads.json")
        let record = DownloadRecord(
            packageID: "package-1",
            remoteURL: URL(string: "https://cdn.example.com/package.3012pkg")!,
            expectedSHA256: String(repeating: "a", count: 64),
            expectedSize: 200 * 1_024 * 1_024,
            status: .paused,
            bytesReceived: 42,
            resumeDataFilename: "resume.data"
        )

        try await DownloadStateStore(fileURL: fileURL).save([record])
        let restored = try await DownloadStateStore(fileURL: fileURL).load()

        XCTAssertEqual(restored, [record])
    }

    func testMissingStateFileReturnsEmptyList() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("downloads.json")
        let records = try await DownloadStateStore(fileURL: fileURL).load()
        XCTAssertTrue(records.isEmpty)
    }
}
