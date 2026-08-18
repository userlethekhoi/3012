import Foundation

public struct PackageTransactionEngine {
    private let packageReader: PackageReader
    private let fileManager: FileManager
    private let chunkSize: Int

    public init(
        packageReader: PackageReader,
        fileManager: FileManager = .default,
        chunkSize: Int = 1_024 * 1_024
    ) {
        self.packageReader = packageReader
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    public func apply(
        package: VerifiedPackage,
        targetRoots: [String: URL],
        backupRoot: URL
    ) throws -> TransactionResult {
        try packageReader.verifyPayloads(package, chunkSize: chunkSize)
        try validateDirectory(backupRoot)

        let transactionID = UUID().uuidString
        let transactionDirectory = backupRoot.appendingPathComponent(transactionID, isDirectory: true)
        let backupsDirectory = transactionDirectory.appendingPathComponent("backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let journalURL = transactionDirectory.appendingPathComponent("journal.json")

        var journal = try prepareJournal(
            package: package,
            transactionID: transactionID,
            targetRoots: targetRoots
        )

        do {
            try createBackups(journal: journal, targetRoots: targetRoots, transactionDirectory: transactionDirectory)
            try persist(journal, at: journalURL)
            journal.status = .applying
            try persist(journal, at: journalURL)

            for index in package.entries.indices {
                journal.entries[index].status = .applying
                try persist(journal, at: journalURL)
                let createdDirectories = try applyEntry(
                    package.entries[index],
                    packageURL: package.fileURL,
                    targetRoots: targetRoots,
                    transactionID: transactionID
                )
                journal.entries[index].createdDirectories = createdDirectories
                journal.entries[index].status = .applied
                try persist(journal, at: journalURL)
            }

            journal.status = .completed
            try persist(journal, at: journalURL)
            return TransactionResult(transactionID: transactionID, journalURL: journalURL)
        } catch {
            try? rollback(&journal, targetRoots: targetRoots, transactionDirectory: transactionDirectory, journalURL: journalURL)
            throw error
        }
    }

    public func restore(journalURL: URL, targetRoots: [String: URL]) throws {
        var journal = try loadJournal(at: journalURL)
        guard journal.status == .completed else {
            throw PackageTransactionError.transactionNotRestorable
        }
        let transactionDirectory = journalURL.deletingLastPathComponent()
        try rollback(
            &journal,
            targetRoots: targetRoots,
            transactionDirectory: transactionDirectory,
            journalURL: journalURL
        )
    }

    public func loadJournal(at url: URL) throws -> TransactionJournal {
        do {
            let journal = try JSONDecoder().decode(TransactionJournal.self, from: Data(contentsOf: url))
            guard journal.schemaVersion == 1, UUID(uuidString: journal.transactionID) != nil else {
                throw PackageTransactionError.invalidJournal
            }
            return journal
        } catch let error as PackageTransactionError {
            throw error
        } catch {
            throw PackageTransactionError.invalidJournal
        }
    }

    private func prepareJournal(
        package: VerifiedPackage,
        transactionID: String,
        targetRoots: [String: URL]
    ) throws -> TransactionJournal {
        var receipts: [TransactionEntryReceipt] = []
        for verifiedEntry in package.entries {
            let entry = verifiedEntry.entry
            guard let root = targetRoots[entry.bundleID] else {
                throw PackageTransactionError.missingTargetRoot(entry.bundleID)
            }
            try validateDirectory(root)
            let destination = try safeDestination(root: root, relativePath: entry.relativePath)
            let exists = fileManager.fileExists(atPath: destination.path)
            switch entry.operation {
            case .replaceFile where !exists:
                throw PackageTransactionError.replacementTargetMissing(entry.relativePath)
            case .createFile where exists:
                throw PackageTransactionError.createTargetAlreadyExists(entry.relativePath)
            default:
                break
            }
            let backupPath = exists ? "backups/\(entry.id)" : nil
            receipts.append(TransactionEntryReceipt(
                entryID: entry.id,
                bundleID: entry.bundleID,
                relativePath: entry.relativePath,
                operation: entry.operation,
                originalExisted: exists,
                backupRelativePath: backupPath,
                createdDirectories: [],
                status: .pending
            ))
        }
        return TransactionJournal(
            schemaVersion: 1,
            transactionID: transactionID,
            packageID: package.manifest.packageID,
            packageVersion: package.manifest.version,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            status: .prepared,
            entries: receipts
        )
    }

    private func createBackups(
        journal: TransactionJournal,
        targetRoots: [String: URL],
        transactionDirectory: URL
    ) throws {
        for receipt in journal.entries where receipt.originalExisted {
            guard let root = targetRoots[receipt.bundleID],
                  let backupPath = receipt.backupRelativePath else {
                throw PackageTransactionError.invalidJournal
            }
            let source = try safeDestination(root: root, relativePath: receipt.relativePath)
            let backup = try PackagePathValidator.destination(
                root: transactionDirectory,
                relativePath: backupPath
            )
            try fileManager.copyItem(at: source, to: backup)
        }
    }

    private func applyEntry(
        _ verifiedEntry: VerifiedPackageEntry,
        packageURL: URL,
        targetRoots: [String: URL],
        transactionID: String
    ) throws -> [String] {
        let entry = verifiedEntry.entry
        guard let root = targetRoots[entry.bundleID] else {
            throw PackageTransactionError.missingTargetRoot(entry.bundleID)
        }
        let destination = try safeDestination(root: root, relativePath: entry.relativePath)
        let createdDirectories = try createParentDirectories(for: destination, root: root)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".3012-\(transactionID)-\(entry.id).tmp")
        if fileManager.fileExists(atPath: temporary.path) {
            try fileManager.removeItem(at: temporary)
        }
        fileManager.createFile(atPath: temporary.path, contents: nil)
        do {
            try copyPayload(
                packageURL: packageURL,
                offset: verifiedEntry.payloadOffset,
                length: entry.length,
                destination: temporary
            )
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            try? removeEmptyDirectories(createdDirectories, root: root)
            throw error
        }
        return createdDirectories
    }

    private func copyPayload(packageURL: URL, offset: UInt64, length: Int64, destination: URL) throws {
        let source = try FileHandle(forReadingFrom: packageURL)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? source.close()
            try? output.close()
        }
        try source.seek(toOffset: offset)
        var remaining = length
        while remaining > 0 {
            let count = Int(min(Int64(chunkSize), remaining))
            let data = try source.read(upToCount: count) ?? Data()
            guard !data.isEmpty else { throw PackageFormatError.truncated }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
        try output.synchronize()
    }

    private func rollback(
        _ journal: inout TransactionJournal,
        targetRoots: [String: URL],
        transactionDirectory: URL,
        journalURL: URL
    ) throws {
        journal.status = .rollingBack
        try persist(journal, at: journalURL)
        for index in journal.entries.indices.reversed() {
            let receipt = journal.entries[index]
            guard receipt.status == .applying || receipt.status == .applied else { continue }
            guard let root = targetRoots[receipt.bundleID] else {
                throw PackageTransactionError.missingTargetRoot(receipt.bundleID)
            }
            let destination = try safeDestination(root: root, relativePath: receipt.relativePath)
            if receipt.originalExisted {
                guard let backupPath = receipt.backupRelativePath else {
                    throw PackageTransactionError.invalidJournal
                }
                let backup = try PackagePathValidator.destination(
                    root: transactionDirectory,
                    relativePath: backupPath
                )
                guard fileManager.fileExists(atPath: backup.path) else {
                    throw PackageTransactionError.invalidJournal
                }
                let temporary = destination.deletingLastPathComponent()
                    .appendingPathComponent(".3012-restore-\(journal.transactionID)-\(receipt.entryID).tmp")
                try? fileManager.removeItem(at: temporary)
                try fileManager.copyItem(at: backup, to: temporary)
                if fileManager.fileExists(atPath: destination.path) {
                    _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: destination)
                }
            } else if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try removeEmptyDirectories(receipt.createdDirectories, root: root)
            journal.entries[index].status = .restored
            try persist(journal, at: journalURL)
        }
        journal.status = .rolledBack
        try persist(journal, at: journalURL)
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PackageTransactionError.invalidTargetRoot(url.path)
        }
        if try isSymbolicLink(url) {
            throw PackageTransactionError.symbolicLink(url.path)
        }
    }

    private func safeDestination(root: URL, relativePath: String) throws -> URL {
        let destination = try PackagePathValidator.destination(root: root, relativePath: relativePath)
        var current = root.standardizedFileURL
        for component in relativePath.split(separator: "/") {
            current.appendPathComponent(String(component))
            if fileManager.fileExists(atPath: current.path), try isSymbolicLink(current) {
                throw PackageTransactionError.symbolicLink(relativePath)
            }
        }
        return destination
    }

    private func isSymbolicLink(_ url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func createParentDirectories(for destination: URL, root: URL) throws -> [String] {
        let parent = destination.deletingLastPathComponent()
        var current = root.standardizedFileURL
        var created: [String] = []
        var relativeComponents: [String] = []
        let rootComponents = current.pathComponents.count
        for component in parent.standardizedFileURL.pathComponents.dropFirst(rootComponents) {
            relativeComponents.append(component)
            current.appendPathComponent(component, isDirectory: true)
            if !fileManager.fileExists(atPath: current.path) {
                try fileManager.createDirectory(at: current, withIntermediateDirectories: false)
                created.append(relativeComponents.joined(separator: "/"))
            } else if try isSymbolicLink(current) {
                throw PackageTransactionError.symbolicLink(current.path)
            }
        }
        return created
    }

    private func removeEmptyDirectories(_ paths: [String], root: URL) throws {
        for path in paths.reversed() {
            let directory = try PackagePathValidator.destination(root: root, relativePath: path)
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            if contents.isEmpty {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    private func persist(_ journal: TransactionJournal, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: url, options: .atomic)
    }
}
