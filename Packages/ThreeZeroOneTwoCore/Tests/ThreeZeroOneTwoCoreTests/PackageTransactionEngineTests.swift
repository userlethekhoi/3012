import CryptoKit
import Foundation
import XCTest
@testable import ThreeZeroOneTwoCore

final class PackageTransactionEngineTests: XCTestCase {
    private enum SimulatedError: Error {
        case writeFailed
    }

    func testApplyAndRestoreReplaceAndCreateEntries() throws {
        let workspace = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let target = workspace.appendingPathComponent("target", isDirectory: true)
        let backups = workspace.appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let original = target.appendingPathComponent("existing.txt")
        try Data("original".utf8).write(to: original)

        let fixture = try makePackage(entries: [
            ("replace", "existing.txt", .replaceFile, Data("updated".utf8)),
            ("create", "nested/new.txt", .createFile, Data("created".utf8))
        ])
        let reader = PackageReader(trustedPublicKeys: ["test-key": fixture.publicKey])
        let package = try reader.inspect(fileURL: fixture.url)
        let engine = PackageTransactionEngine(packageReader: reader, chunkSize: 2)

        let result = try engine.apply(
            package: package,
            targetRoots: ["com.example.target": target],
            backupRoot: backups
        )

        XCTAssertEqual(try String(contentsOf: original), "updated")
        XCTAssertEqual(
            try String(contentsOf: target.appendingPathComponent("nested/new.txt")),
            "created"
        )
        XCTAssertEqual(try engine.loadJournal(at: result.journalURL).status, .completed)

        try engine.restore(
            journalURL: result.journalURL,
            targetRoots: ["com.example.target": target]
        )

        XCTAssertEqual(try String(contentsOf: original), "original")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("nested/new.txt").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: target.appendingPathComponent("nested").path
        ))
        XCTAssertEqual(try engine.loadJournal(at: result.journalURL).status, .rolledBack)
    }

    func testPreflightFailureDoesNotModifyEarlierEntry() throws {
        let workspace = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let target = workspace.appendingPathComponent("target", isDirectory: true)
        let backups = workspace.appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let original = target.appendingPathComponent("existing.txt")
        try Data("original".utf8).write(to: original)

        let fixture = try makePackage(entries: [
            ("replace", "existing.txt", .replaceFile, Data("updated".utf8)),
            ("missing", "missing.txt", .replaceFile, Data("never-written".utf8))
        ])
        let reader = PackageReader(trustedPublicKeys: ["test-key": fixture.publicKey])
        let package = try reader.inspect(fileURL: fixture.url)
        let engine = PackageTransactionEngine(packageReader: reader)

        XCTAssertThrowsError(try engine.apply(
            package: package,
            targetRoots: ["com.example.target": target],
            backupRoot: backups
        )) { error in
            XCTAssertEqual(
                error as? PackageTransactionError,
                .replacementTargetMissing("missing.txt")
            )
        }
        XCTAssertEqual(try String(contentsOf: original), "original")
    }

    func testFailureAfterFirstWriteRollsBackAppliedEntry() throws {
        let workspace = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let target = workspace.appendingPathComponent("target", isDirectory: true)
        let backups = workspace.appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let first = target.appendingPathComponent("first.txt")
        let second = target.appendingPathComponent("second.txt")
        try Data("first-original".utf8).write(to: first)
        try Data("second-original".utf8).write(to: second)

        let fixture = try makePackage(entries: [
            ("first", "first.txt", .replaceFile, Data("first-new".utf8)),
            ("second", "second.txt", .replaceFile, Data("second-new".utf8))
        ])
        let reader = PackageReader(trustedPublicKeys: ["test-key": fixture.publicKey])
        let package = try reader.inspect(fileURL: fixture.url)
        let engine = PackageTransactionEngine(packageReader: reader) { entry in
            if entry.id == "second" { throw SimulatedError.writeFailed }
        }

        XCTAssertThrowsError(try engine.apply(
            package: package,
            targetRoots: ["com.example.target": target],
            backupRoot: backups
        ))
        XCTAssertEqual(try String(contentsOf: first), "first-original")
        XCTAssertEqual(try String(contentsOf: second), "second-original")

        let transactionDirectories = try FileManager.default.contentsOfDirectory(
            at: backups,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(transactionDirectories.count, 1)
        let journalURL = transactionDirectories[0].appendingPathComponent("journal.json")
        XCTAssertEqual(try engine.loadJournal(at: journalURL).status, .rolledBack)
    }

    func testUnsafeEntryIdentifierIsRejected() throws {
        let fixture = try makePackage(entries: [
            ("../escape", "file.txt", .createFile, Data("data".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        let reader = PackageReader(trustedPublicKeys: ["test-key": fixture.publicKey])

        XCTAssertThrowsError(try reader.inspect(fileURL: fixture.url)) { error in
            XCTAssertEqual(error as? PackageFormatError, .invalidEntry("../escape"))
        }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePackage(
        entries: [(id: String, path: String, operation: PackageOperation, data: Data)]
    ) throws -> (url: URL, publicKey: Data) {
        let packageEntries = entries.map { item in
            PackageEntry(
                id: item.id,
                bundleID: "com.example.target",
                relativePath: item.path,
                operation: item.operation,
                length: Int64(item.data.count),
                sha256: SHA256.hash(data: item.data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            )
        }
        let manifest = PackageManifest(
            packageID: UUID().uuidString,
            name: "Transaction Test",
            version: "1.0.0",
            publisherKeyID: "test-key",
            createdAt: "2026-08-18T00:00:00Z",
            minAppVersion: "0.1.0",
            entries: packageEntries
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(
            for: PackageCanonicalizer.encode(manifest)
        ).base64EncodedString()
        let document = PackageDocument(signed: manifest, signature: signature)
        let manifestData = try JSONEncoder().encode(document)
        var packageData = PackageReader.magic
        var manifestLength = UInt64(manifestData.count).bigEndian
        withUnsafeBytes(of: &manifestLength) { packageData.append(contentsOf: $0) }
        packageData.append(manifestData)
        for entry in entries { packageData.append(entry.data) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try packageData.write(to: url)
        return (url, privateKey.publicKey.rawRepresentation)
    }
}
