import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class LocalPackageBuilderTests: XCTestCase {
    func testBuildsAndVerifiesFileBasedPackage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("large.bin")
        let output = directory.appendingPathComponent("manual.3012pkg")
        let handle = FileManager.default.createFile(atPath: source.path, contents: nil)
        XCTAssertTrue(handle)
        let writer = try FileHandle(forWritingTo: source)
        let block = Data(repeating: 0xA5, count: 1_024 * 1_024)
        for _ in 0..<8 { try writer.write(contentsOf: block) }
        try writer.close()
        let key = Curve25519.Signing.PrivateKey()

        let publicKey = try LocalPackageBuilder.build(
            name: "Manual Large Patch",
            publisherKeyID: "local-test",
            privateKeyData: key.rawRepresentation,
            sources: [
                LocalPackageSource(
                    id: "large-file",
                    sourceURL: source,
                    bundleID: "manual.selected-folder",
                    relativePath: "Data/large.bin",
                    operation: .createFile
                )
            ],
            outputURL: output,
            chunkSize: 64 * 1_024
        )
        let reader = PackageReader(trustedPublicKeys: ["local-test": publicKey])
        let package = try reader.inspect(fileURL: output)
        try reader.verifyPayloads(package, chunkSize: 32 * 1_024)

        XCTAssertEqual(package.entries.first?.entry.length, 8 * 1_024 * 1_024)
    }

    func testDuplicateManualDestinationIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("file.bin")
        try Data([1]).write(to: source)
        let key = Curve25519.Signing.PrivateKey()
        let sources = ["one", "two"].map { id in
            LocalPackageSource(
                id: id,
                sourceURL: source,
                bundleID: "manual.selected-folder",
                relativePath: "same.bin",
                operation: .replaceFile
            )
        }

        XCTAssertThrowsError(try LocalPackageBuilder.build(
            name: "Duplicate",
            publisherKeyID: "local-test",
            privateKeyData: key.rawRepresentation,
            sources: sources,
            outputURL: directory.appendingPathComponent("duplicate.3012pkg")
        )) { error in
            XCTAssertEqual(error as? LocalPackageBuilderError, .duplicateDestination("same.bin"))
        }
    }
}
