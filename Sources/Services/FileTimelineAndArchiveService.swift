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

        let baseName = zipURL.deletingPathExtension().lastPathComponent
        let tempExtract = fm.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempExtract) }

        do {
            try fm.unzipItem(at: zipURL, to: tempExtract)
            let children = (try? fm.contentsOfDirectory(at: tempExtract, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            let sourceDir: URL
            if children.count == 1,
               ((try? children[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
                sourceDir = children[0]
            } else {
                sourceDir = tempExtract
            }

            var targetFolder = documentsRoot.appendingPathComponent(baseName, isDirectory: true)
            if fm.fileExists(atPath: targetFolder.path) {
                targetFolder = documentsRoot.appendingPathComponent("\(baseName)-\(Int(Date().timeIntervalSince1970) % 10000)", isDirectory: true)
            }
            try fm.copyItem(at: sourceDir, to: targetFolder)
            archiveStatusMessage = "Đã nhập dự án \(targetFolder.lastPathComponent)."
            return targetFolder
        } catch {
            archiveStatusMessage = "Lỗi giải nén .zip: \(error.localizedDescription)"
            return nil
        }
    }
}
