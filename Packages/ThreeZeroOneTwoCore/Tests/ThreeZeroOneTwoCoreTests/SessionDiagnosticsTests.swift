import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class SessionDiagnosticsTests: XCTestCase {
    func testRedactorRemovesCredentialsAndContainerUUIDs() {
        let input = "Authorization=abc123 bearer live.token UUID 123E4567-E89B-12D3-A456-426614174000"
        let output = PrivacyRedactor.redact(input)

        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("live.token"))
        XCTAssertFalse(output.contains("123E4567-E89B-12D3-A456-426614174000"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testRotationKeepsCurrentAndBoundedArchives() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RotatingTextLogStore(
            directory: directory,
            maximumFileBytes: 20,
            archiveCount: 2
        )

        try store.append("first-entry")
        try store.append("second-entry")
        try store.append("third-entry")
        try store.append("fourth-entry")

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(index: 0).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(index: 1).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(index: 2).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(index: 3).path))
        XCTAssertTrue(try String(contentsOf: store.fileURL(index: 0)).contains("fourth-entry"))
    }
}
