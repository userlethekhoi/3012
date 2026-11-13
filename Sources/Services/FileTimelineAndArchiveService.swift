import Foundation
import ZIPFoundation

public struct FileTimelineSnapshot: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let label: String
    public let content: String
    public let lineCount: Int

    public init(label: String, content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.label = label
        self.content = content
        self.lineCount = content.components(separatedBy: "\n").count
    }
}

@MainActor
public final class FileTimelineAndArchiveService: ObservableObject {
    public static let shared = FileTimelineAndArchiveService()
    @Published public private(set) var activeFileSnapshots: [FileTimelineSnapshot] = []
    @Published public var archiveStatusMessage: String = ""

    private let storageRoot: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageRoot = appSupport.appendingPathComponent("3012FileTimeline", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
    }

    // MARK: - Local File Version Timeline
    public func loadSnapshots(for fileURL: URL) {
        let storeURL = timelineJSONURL(for: fileURL)
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([FileTimelineSnapshot].self, from: data) else {
            activeFileSnapshots = []
            return
        }
        activeFileSnapshots = decoded
    }

    public func recordSnapshot(for fileURL: URL, content: String, label: String = "Auto-Save") {
        let storeURL = timelineJSONURL(for: fileURL)
        var history: [FileTimelineSnapshot] = []
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([FileTimelineSnapshot].self, from: data) {
            history = decoded
        }

        // Deduplicate if identical to latest snapshot
        if let latest = history.first, latest.content == content {
            activeFileSnapshots = history
            return
        }

        // Avoid spamming snapshots within 12 seconds unless forced label != Auto-Save
        if label == "Auto-Save",
           let latest = history.first,
           Date().timeIntervalSince(latest.timestamp) < 12 {
            history[0] = FileTimelineSnapshot(label: label, content: content)
        } else {
            history.insert(FileTimelineSnapshot(label: label, content: content), at: 0)
        }

        if history.count > 20 {
            history = Array(history.prefix(20))
        }

        if let encoded = try? JSONEncoder().encode(history) {
            try? encoded.write(to: storeURL, options: .atomic)
        }
        activeFileSnapshots = history
    }

    private func timelineJSONURL(for fileURL: URL) -> URL {
        let key = Data(fileURL.standardizedFileURL.path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let safeKey = String(key.suffix(64))
        return storageRoot.appendingPathComponent("\(safeKey).json")
    }

    // MARK: - Export & Import Project .zip
    public func exportProjectZip(workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        let projectName = workspaceRoot.lastPathComponent.isEmpty ? "3012Project" : workspaceRoot.lastPathComponent
        let destZip = fm.temporaryDirectory.appendingPathComponent("\(projectName).zip")
        if fm.fileExists(atPath: destZip.path) {
            try? fm.removeItem(at: destZip)
        }
        do {
            try fm.zipItem(at: workspaceRoot, to: destZip, shouldKeepParent: true)
            archiveStatusMessage = "Đã đóng gói \(projectName).zip sẵn sàng chia sẻ."
            return destZip
        } catch {
            archiveStatusMessage = "Lỗi nén .zip: \(error.localizedDescription)"
            return nil
        }
    }

    public func importProjectZip(from zipURL: URL, into documentsRoot: URL) -> URL? {
        let fm = FileManager.default
        let didAccess = zipURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { zipURL.stopAccessingSecurityScopedResource() }
        }

        try? fm.createDirectory(at: documentsRoot, withIntermediateDirectories: true)

        let rawBase = zipURL.deletingPathExtension().lastPathComponent
        let baseName = rawBase.isEmpty ? "ImportedProject" : rawBase

        // Copy archive to local temporary storage first using NSFileCoordinator so iCloud / FileProvider URLs never fail
        let localZipCopy = fm.temporaryDirectory.appendingPathComponent("zip_in_\(UUID().uuidString)_\(zipURL.lastPathComponent)")
        defer { try? fm.removeItem(at: localZipCopy) }

        var copiedArchive = copyExternalFileToLocalTemp(sourceURL: zipURL, destinationURL: localZipCopy)
        if !copiedArchive && fm.fileExists(atPath: zipURL.path) {
            do {
                try fm.copyItem(at: zipURL, to: localZipCopy)
                copiedArchive = true
            } catch {}
        }

        let archiveToRead = copiedArchive ? localZipCopy : zipURL

        let tempExtract = fm.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempExtract) }

        do {
            try unzipArchiveWithFallbackEncodings(from: archiveToRead, to: tempExtract)
            purgeMacOSArchiveJunk(in: tempExtract)

            let children = ((try? fm.contentsOfDirectory(
                at: tempExtract,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []).filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }

            let sourceDir: URL
            let preferredFolderName: String
            if children.count == 1,
               ((try? children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
                sourceDir = children[0]
                preferredFolderName = children[0].lastPathComponent
            } else {
                sourceDir = tempExtract
                preferredFolderName = baseName
            }

            var targetFolder = documentsRoot.appendingPathComponent(preferredFolderName, isDirectory: true)
            if fm.fileExists(atPath: targetFolder.path) {
                targetFolder = documentsRoot.appendingPathComponent("\(preferredFolderName)-\(Int(Date().timeIntervalSince1970) % 10000)", isDirectory: true)
            }
            try fm.copyItem(at: sourceDir, to: targetFolder)
            purgeMacOSArchiveJunk(in: targetFolder)
            archiveStatusMessage = "Đã giải nén & nhập dự án: \(targetFolder.lastPathComponent)"
            return targetFolder
        } catch {
            archiveStatusMessage = "Lỗi giải nén .zip: \(error.localizedDescription)"
            return nil
        }
    }

    public func extractZipInPlace(from zipURL: URL, into destinationParent: URL? = nil) -> URL? {
        let fm = FileManager.default
        let didAccess = zipURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { zipURL.stopAccessingSecurityScopedResource() }
        }

        let parentDir = destinationParent ?? zipURL.deletingLastPathComponent()
        try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let rawBase = zipURL.deletingPathExtension().lastPathComponent
        let baseName = rawBase.isEmpty ? "Extracted" : rawBase

        let localZipCopy = fm.temporaryDirectory.appendingPathComponent("zip_inplace_\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: localZipCopy) }
        let archiveToRead = copyExternalFileToLocalTemp(sourceURL: zipURL, destinationURL: localZipCopy) ? localZipCopy : zipURL

        let tempExtract = fm.temporaryDirectory.appendingPathComponent("extract_\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempExtract) }

        do {
            try unzipArchiveWithFallbackEncodings(from: archiveToRead, to: tempExtract)
            purgeMacOSArchiveJunk(in: tempExtract)

            let children = ((try? fm.contentsOfDirectory(
                at: tempExtract,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []).filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }

            let sourceToCopy: URL
            let folderName: String
            if children.count == 1,
               ((try? children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
                sourceToCopy = children[0]
                folderName = children[0].lastPathComponent
            } else {
                sourceToCopy = tempExtract
                folderName = baseName
            }

            var targetFolder = parentDir.appendingPathComponent(folderName, isDirectory: true)
            if fm.fileExists(atPath: targetFolder.path) {
                targetFolder = parentDir.appendingPathComponent("\(folderName)-\(Int(Date().timeIntervalSince1970) % 10000)", isDirectory: true)
            }
            try fm.copyItem(at: sourceToCopy, to: targetFolder)
            purgeMacOSArchiveJunk(in: targetFolder)
            archiveStatusMessage = "Đã giải nén \(zipURL.lastPathComponent) -> \(targetFolder.lastPathComponent)/"
            return targetFolder
        } catch {
            archiveStatusMessage = "Lỗi giải nén .zip: \(error.localizedDescription)"
            return nil
        }
    }

    private func copyExternalFileToLocalTemp(sourceURL: URL, destinationURL: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }
        var copySuccess = false
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: sourceURL, options: .withoutChanges, error: &coordError) { coordinatedURL in
            do {
                try fm.copyItem(at: coordinatedURL, to: destinationURL)
                copySuccess = true
            } catch {
                if let data = try? Data(contentsOf: coordinatedURL) {
                    try? data.write(to: destinationURL, options: .atomic)
                    copySuccess = fm.fileExists(atPath: destinationURL.path)
                }
            }
        }
        if !copySuccess, let data = try? Data(contentsOf: sourceURL) {
            try? data.write(to: destinationURL, options: .atomic)
            copySuccess = fm.fileExists(atPath: destinationURL.path)
        }
        return copySuccess
    }

    private func unzipArchiveWithFallbackEncodings(from archiveURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        do {
            try fm.unzipItem(at: archiveURL, to: destinationURL, skipCRC32: false, pathEncoding: .utf8)
        } catch {
            // Clear partial files before retry with isoLatin1 / Windows codepage fallback
            if let items = try? fm.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil) {
                for item in items { try? fm.removeItem(at: item) }
            }
            do {
                try fm.unzipItem(at: archiveURL, to: destinationURL, skipCRC32: false, pathEncoding: .isoLatin1)
            } catch {
                if let items = try? fm.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil) {
                    for item in items { try? fm.removeItem(at: item) }
                }
                try fm.unzipItem(at: archiveURL, to: destinationURL)
            }
        }
    }

    private func purgeMacOSArchiveJunk(in directory: URL) {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in items {
                let name = item.lastPathComponent
                if name == "__MACOSX" || name == ".DS_Store" {
                    try? fm.removeItem(at: item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false {
                    purgeMacOSArchiveJunk(in: item)
                }
            }
        }
    }
}
