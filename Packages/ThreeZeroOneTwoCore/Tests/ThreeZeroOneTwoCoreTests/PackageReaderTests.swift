import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class PackageReaderTests: XCTestCase {
    func testSignedPackageAndPayloadVerify() throws {
        let fixture = try makePackage(relativePath: "Library/Preferences/config.json")
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let reader = PackageReader(
            trustedPublicKeys: ["test-key": fixture.publicKey]
        )

        let package = try reader.inspect(fileURL: fixture.url)
        try reader.verifyPayloads(package, chunkSize: 3)

        XCTAssertEqual(package.manifest.name, "Test Package")
        XCTAssertEqual(package.entries.count, 1)
        XCTAssertEqual(package.entries[0].entry.relativePath, "Library/Preferences/config.json")
    }

    func testTamperedPayloadIsRejected() throws {
        let fixture = try makePackage(relativePath: "Documents/file.bin")
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let handle = try FileHandle(forWritingTo: fixture.url)
        let endOffset = try handle.seekToEnd()
        try handle.seek(toOffset: endOffset - 1)
        try handle.write(contentsOf: Data([0xFF]))
        try handle.close()
        let reader = PackageReader(
            trustedPublicKeys: ["test-key": fixture.publicKey]
        )
        let package = try reader.inspect(fileURL: fixture.url)

        XCTAssertThrowsError(try reader.verifyPayloads(package)) { error in
            XCTAssertEqual(error as? PackageFormatError, .payloadDigestMismatch("entry-1"))
        }
    }

    func testTraversalPathIsRejected() throws {
        let fixture = try makePackage(relativePath: "../outside.txt")
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let reader = PackageReader(
            trustedPublicKeys: ["test-key": fixture.publicKey]
        )

        XCTAssertThrowsError(try reader.inspect(fileURL: fixture.url)) { error in
            XCTAssertEqual(error as? PackageFormatError, .invalidEntry("entry-1"))
        }
    }

    func testTrailingBytesAreRejected() throws {
        let fixture = try makePackage(relativePath: "Documents/file.bin")
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let handle = try FileHandle(forWritingTo: fixture.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        let reader = PackageReader(
            trustedPublicKeys: ["test-key": fixture.publicKey]
        )

        XCTAssertThrowsError(try reader.inspect(fileURL: fixture.url)) { error in
            XCTAssertEqual(error as? PackageFormatError, .packageLengthMismatch)
        }
    }

    private func makePackage(relativePath: String) throws -> (url: URL, publicKey: Data) {
        let payload = Data("{\"enabled\":true}".utf8)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let manifest = PackageManifest(
            packageID: UUID().uuidString,
            name: "Test Package",
            version: "1.0.0",
            publisherKeyID: "test-key",
            createdAt: "2026-08-18T00:00:00Z",
            minAppVersion: "0.1.0",
            entries: [
                PackageEntry(
                    id: "entry-1",
                    bundleID: "com.example.target",
                    relativePath: relativePath,
                    operation: .replaceFile,
                    length: Int64(payload.count),
                    sha256: digest
                )
            ]
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(
            for: PackageCanonicalizer.encode(manifest)
        ).base64EncodedString()
        let document = PackageDocument(signed: manifest, signature: signature)
        let manifestData = try JSONEncoder().encode(document)

        var fileData = PackageReader.magic
        var length = UInt64(manifestData.count).bigEndian
        withUnsafeBytes(of: &length) { fileData.append(contentsOf: $0) }
        fileData.append(manifestData)
        fileData.append(payload)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try fileData.write(to: url)
        return (url, privateKey.publicKey.rawRepresentation)
    }
}
