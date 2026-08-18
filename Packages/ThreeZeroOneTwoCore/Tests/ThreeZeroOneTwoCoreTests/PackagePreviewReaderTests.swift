import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class PackagePreviewReaderTests: XCTestCase {
    func testReadsBoundedUnverifiedMetadata() throws {
        let url = try makePreviewPackage()
        defer { try? FileManager.default.removeItem(at: url) }

        let preview = try PackagePreviewReader.read(fileURL: url)

        XCTAssertEqual(preview.name, "Preview Package")
        XCTAssertEqual(preview.version, "2.0.0")
        XCTAssertEqual(preview.publisherKeyID, "production-2026")
        XCTAssertEqual(preview.entryCount, 1)
        XCTAssertEqual(preview.payloadBytes, 4)
    }

    func testInvalidMagicIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0, count: 16).write(to: url)

        XCTAssertThrowsError(try PackagePreviewReader.read(fileURL: url)) { error in
            XCTAssertEqual(error as? PackagePreviewError, .invalidMagic)
        }
    }

    private func makePreviewPackage() throws -> URL {
        let manifest = PackageManifest(
            packageID: UUID().uuidString,
            name: "Preview Package",
            version: "2.0.0",
            publisherKeyID: "production-2026",
            createdAt: "2026-08-18T00:00:00Z",
            minAppVersion: "0.1.0",
            entries: [
                PackageEntry(
                    id: "file",
                    bundleID: "com.example.target",
                    relativePath: "Documents/file.bin",
                    operation: .createFile,
                    length: 4,
                    sha256: String(repeating: "0", count: 64)
                )
            ]
        )
        let document = PackageDocument(signed: manifest, signature: "unverified")
        let manifestData = try JSONEncoder().encode(document)
        var data = PackageReader.magic
        var length = UInt64(manifestData.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(manifestData)
        data.append(Data([1, 2, 3, 4]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }
}
