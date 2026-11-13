import Foundation
import SwiftUI

@MainActor
public final class WorkspaceManager: ObservableObject {
    @Published public private(set) var rootURL: URL
    @Published public private(set) var fileTree: [FileNode] = []
    @Published public var openTabs: [OpenTab] = []
    @Published public var activeTabID: URL?
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [(url: URL, line: Int, preview: String)] = []
    @Published public private(set) var fileStatuses: [String: WorkspaceFileDiffStatus] = [:]

    private var baselineSnapshots: [String: String] = [:]
    private var deletedGhostContents: [String: String] = [:]

    public var onFileSavedOrChanged: (() -> Void)?
    public var onAnyTabSavedWithURL: ((URL, String) -> Void)?

    public var activeTab: OpenTab? {
        guard let activeTabID else { return nil }
        return openTabs.first(where: { $0.id == activeTabID })
    }

    public var totalDecoratedFilesCount: Int {
        fileStatuses.values.filter { $0 != .unchanged }.count
    }

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let defaultWorkspace = docs.appendingPathComponent("Workspace", isDirectory: true)
        self.rootURL = defaultWorkspace
        bootstrapDefaultWorkspaceIfNeeded(at: defaultWorkspace)
        loadOrInitializeBaseline(at: defaultWorkspace)
        reloadTree()
        let indexFile = defaultWorkspace.appendingPathComponent("index.html")
        if FileManager.default.fileExists(atPath: indexFile.path) {
            openFile(at: indexFile)
        } else if let firstFile = flattenFiles(in: fileTree).first {
            openFile(at: firstFile)
        }
    }

    private func bootstrapDefaultWorkspaceIfNeeded(at root: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let existing = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        guard existing.isEmpty else { return }

        let html = """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>3012 Live Server</title>
          <link rel="stylesheet" href="style.css" />
        </head>
        <body>
          <div class="container">
            <span class="badge">LIVE SERVER :5500</span>
            <h1>3012 Mobile IDE</h1>
            <p>Sửa code trong <b>3012</b> và mở <code>localhost:5500</code> trên <b>Safari</b> để xem tự động Hot-Reload!</p>
            <button id="counterBtn">Bấm thử: 0</button>
          </div>
          <script src="app.js"></script>
        </body>
        </html>
        """

        let css = """
        * { box-sizing: border-box; }
        body {
          margin: 0;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          background: radial-gradient(circle at top, #1e293b, #0f172a);
          color: #f8fafc;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 20px;
        }
        .container {
          background: rgba(30, 41, 59, 0.85);
          border: 1px solid rgba(148, 163, 184, 0.25);
          border-radius: 20px;
          padding: 28px;
          max-width: 440px;
          text-align: center;
          box-shadow: 0 20px 50px rgba(0, 0, 0, 0.4);
        }
        .badge {
          background: #3b82f6;
          color: white;
          font-size: 11px;
          font-weight: 700;
          padding: 4px 10px;
          border-radius: 999px;
          letter-spacing: 0.08em;
        }
        button {
          margin-top: 16px;
          background: #10b981;
          color: #052e16;
          border: none;
          padding: 12px 22px;
          border-radius: 12px;
          font-size: 15px;
          font-weight: 700;
          cursor: pointer;
        }
        """

        let js = """
        let count = 0;
        const btn = document.getElementById("counterBtn");
        if (btn) {
          btn.addEventListener("click", () => {
            count++;
            btn.textContent = `Bấm thử: ${count}`;
            console.log("Counter updated:", count);
          });
        }
        """

        let cpp = """
        #include <iostream>
        #include <vector>
        #include <algorithm>

        int main() {
            std::vector<int> nums = {42, 7, 19, 88, 3};
            std::sort(nums.begin(), nums.end());
            std::cout << "3012 Zero-Config C++20 Sorted: ";
            for (int n : nums) std::cout << n << " ";
            std::cout << "\\n";
            return 0;
        }
        """

        let py = """
        def fib(n: int):
            a, b = 0, 1
            res = []
            for _ in range(n):
                res.append(a)
                a, b = b, a + b
            return res

        print("3012 Zero-Config Python:", fib(10))
        """

        let swiftSample = CodeLanguage.swift.starterTemplate
        let readmeSample = """
        # 3012 Mobile IDE Workspace

        Chào mừng bạn đến với **3012** — AI-Native Mobile IDE trên iOS.

        ## Kiến trúc thực thi nhanh
        ```mermaid
        flowchart LR
            Editor["3012 Code Editor"] --> Live["Live Server :5500"]
            Editor --> Runner["Zero-Config Runner / SSH VPS"]
            Editor --> Agent["Coding Agent + Diff Review"]
        ```

        - Bấm biểu tượng **Preview** trên thanh công cụ khi mở file `.md` để xem trực tiếp tài liệu và sơ đồ Mermaid.
        """

        try? html.write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try? css.write(to: root.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try? js.write(to: root.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
        try? cpp.write(to: root.appendingPathComponent("main.cpp"), atomically: true, encoding: .utf8)
        try? py.write(to: root.appendingPathComponent("script.py"), atomically: true, encoding: .utf8)
        try? swiftSample.write(to: root.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        try? readmeSample.write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }

    public func reloadTree() {
        fileTree = buildNodes(at: rootURL)
        recomputeAllFileStatuses()
    }

    private func buildNodes(at directory: URL) -> [FileNode] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var dirs: [FileNode] = []
        var files: [FileNode] = []
        var existingNamesLower = Set<String>()

        for url in items {
            existingNamesLower.insert(url.lastPathComponent.lowercased())
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = buildNodes(at: url)
                dirs.append(FileNode(url: url, isDirectory: true, children: children))
            } else {
                files.append(FileNode(url: url, isDirectory: false, isDeletedGhost: false, children: nil))
            }
        }

        // Inject recently deleted / baseline-deleted files belonging to this exact folder so they show in Red ("D")
        let dirStandardPath = directory.standardizedFileURL.path
        let allDeletedRelPaths = Set(deletedGhostContents.keys).union(
            baselineSnapshots.keys.filter { rel in
                !fm.fileExists(atPath: rootURL.appendingPathComponent(rel).path)
            }
        )
        for rel in allDeletedRelPaths {
            let deletedURL = rootURL.appendingPathComponent(rel)
            let parentPath = deletedURL.deletingLastPathComponent().standardizedFileURL.path
            if parentPath == dirStandardPath && !existingNamesLower.contains(deletedURL.lastPathComponent.lowercased()) {
                files.append(FileNode(url: deletedURL, isDirectory: false, isDeletedGhost: true, children: nil))
            }
        }

        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return dirs + files
    }

    public func flattenFiles(in nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
            if node.isDeletedGhost { continue }
            if node.isDirectory, let children = node.children {
                result.append(contentsOf: flattenFiles(in: children))
            } else {
                result.append(node.url)
            }
        }
        return result
    }

    public func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath.hasPrefix(rootPath) {
            var rel = String(targetPath.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel.isEmpty ? url.lastPathComponent : rel
        }
        return url.lastPathComponent
    }

    public func workspaceSummaryTree() -> String {
        let urls = flattenFiles(in: fileTree)
        if urls.isEmpty { return "(Empty workspace)" }
        return urls.map { "- \(relativePath(for: $0))" }.joined(separator: "\n")
    }

    public func openFile(at url: URL) {
        if let existing = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            activeTabID = existing.id
            return
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let tab = OpenTab(fileURL: url, content: text)
        openTabs.append(tab)
        activeTabID = tab.id
    }

    public func updateActiveContent(_ newText: String, selectedRange: NSRange? = nil, autoSave: Bool = true) {
        guard let activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        openTabs[idx].content = newText
        if let selectedRange {
            openTabs[idx].selectedRangeLocation = selectedRange.location
            openTabs[idx].selectedRangeLength = selectedRange.length
        }
        if autoSave {
            try? newText.write(to: openTabs[idx].fileURL, atomically: true, encoding: .utf8)
            openTabs[idx].savedContent = newText
            onFileSavedOrChanged?()
            onAnyTabSavedWithURL?(openTabs[idx].fileURL, newText)
        }
        updateSingleFileStatus(for: openTabs[idx].fileURL, liveContent: newText)
    }

    public func updateSelectionOnly(_ range: NSRange) {
        guard let activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        openTabs[idx].selectedRangeLocation = range.location
        openTabs[idx].selectedRangeLength = range.length
    }

    public func setLanguageOverrideForActiveTab(_ overrideLanguage: CodeLanguage?) {
        guard let activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        openTabs[idx].languageOverride = overrideLanguage
    }

    public func selectedSnippetInActiveTab() -> String? {
        guard let tab = activeTab, tab.selectedRangeLength > 0 else { return nil }
        let ns = tab.content as NSString
        let safeRange = NSIntersectionRange(
            NSRange(location: 0, length: ns.length),
            NSRange(location: tab.selectedRangeLocation, length: tab.selectedRangeLength)
        )
        guard safeRange.length > 0 else { return nil }
        return ns.substring(with: safeRange)
    }

    public func saveActiveTab() {
        guard let activeTabID,
              let idx = openTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        try? openTabs[idx].content.write(to: openTabs[idx].fileURL, atomically: true, encoding: .utf8)
        openTabs[idx].savedContent = openTabs[idx].content
        updateSingleFileStatus(for: openTabs[idx].fileURL, liveContent: openTabs[idx].content)
        onFileSavedOrChanged?()
        onAnyTabSavedWithURL?(openTabs[idx].fileURL, openTabs[idx].content)
    }

    public func saveAllTabs() {
        for idx in openTabs.indices {
            try? openTabs[idx].content.write(to: openTabs[idx].fileURL, atomically: true, encoding: .utf8)
            openTabs[idx].savedContent = openTabs[idx].content
        }
        recomputeAllFileStatuses()
        onFileSavedOrChanged?()
    }

    public func closeTab(_ tabID: URL) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        try? openTabs[idx].content.write(to: openTabs[idx].fileURL, atomically: true, encoding: .utf8)
        openTabs.remove(at: idx)
        if activeTabID == tabID {
            activeTabID = openTabs.last?.id
        }
    }

    @discardableResult
    public func createFile(named rawName: String, in directory: URL? = nil, initialContent: String? = nil) -> URL? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let parent = directory ?? rootURL
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let target = parent.appendingPathComponent(name)
        let rel = relativePath(for: target)
        deletedGhostContents.removeValue(forKey: rel)
        saveDeletedGhostsMeta()
        let lang = CodeLanguage.detect(from: target)
        let body = initialContent ?? lang.starterTemplate
        do {
            try body.write(to: target, atomically: true, encoding: .utf8)
            reloadTree()
            openFile(at: target)
            onFileSavedOrChanged?()
            return target
        } catch {
            return nil
        }
    }

    public func applyAgentFileEdit(relativePath: String, newContent: String) {
        let cleaned = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleaned.isEmpty else { return }
        let targetURL = rootURL.appendingPathComponent(cleaned)
        let parent = targetURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? newContent.write(to: targetURL, atomically: true, encoding: .utf8)

        if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
            openTabs[idx].content = newContent
            openTabs[idx].savedContent = newContent
            activeTabID = openTabs[idx].id
        } else {
            reloadTree()
            openFile(at: targetURL)
            return
        }
        reloadTree()
        onFileSavedOrChanged?()
    }

    public func createFolder(named rawName: String, in directory: URL? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let target = (directory ?? rootURL).appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        reloadTree()
    }

    public func deleteItem(at url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir {
            let rel = relativePath(for: url)
            let priorContent = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL })?.content
                ?? (try? String(contentsOf: url, encoding: .utf8))
                ?? baselineSnapshots[rel]
                ?? ""
            deletedGhostContents[rel] = priorContent
            saveDeletedGhostsMeta()
        }
        if let tab = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            openTabs.removeAll { $0.id == tab.id }
            if activeTabID == tab.id {
                activeTabID = openTabs.last?.id
            }
        }
        try? FileManager.default.removeItem(at: url)
        reloadTree()
        onFileSavedOrChanged?()
    }

    public func restoreDeletedFile(at url: URL) {
        let rel = relativePath(for: url)
        let restoredBody = deletedGhostContents[rel] ?? baselineSnapshots[rel] ?? ""
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? restoredBody.write(to: url, atomically: true, encoding: .utf8)
        deletedGhostContents.removeValue(forKey: rel)
        saveDeletedGhostsMeta()
        reloadTree()
        openFile(at: url)
        onFileSavedOrChanged?()
    }

    public func dismissDeletedGhost(at url: URL) {
        let rel = relativePath(for: url)
        deletedGhostContents.removeValue(forKey: rel)
        baselineSnapshots.removeValue(forKey: rel)
        saveDeletedGhostsMeta()
        saveBaselineMeta()
        reloadTree()
    }

    public func renameItem(at url: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            let oldRel = relativePath(for: url)
            let newRel = relativePath(for: dest)
            if let baseVal = baselineSnapshots.removeValue(forKey: oldRel) {
                baselineSnapshots[newRel] = baseVal
                saveBaselineMeta()
            }
            if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
                let content = openTabs[idx].content
                let wasActive = (activeTabID == openTabs[idx].id)
                openTabs.remove(at: idx)
                let updated = OpenTab(fileURL: dest, content: content)
                openTabs.insert(updated, at: idx)
                if wasActive { activeTabID = updated.id }
            }
            reloadTree()
            onFileSavedOrChanged?()
        } catch {}
    }

    public func switchWorkspaceFolder(to externalURL: URL) {
        _ = externalURL.startAccessingSecurityScopedResource()
        self.rootURL = externalURL
        self.openTabs.removeAll()
        self.activeTabID = nil
        loadOrInitializeBaseline(at: externalURL)
        reloadTree()
        if let first = flattenFiles(in: fileTree).first {
            openFile(at: first)
        }
    }

    // MARK: - VS Code Working-Tree Diff Baseline & Status Decoration Engine
    private var baselineMetaURL: URL {
        rootURL.appendingPathComponent(".3012baseline.json")
    }

    private var deletedGhostsMetaURL: URL {
        rootURL.appendingPathComponent(".3012deleted.json")
    }

    private func loadOrInitializeBaseline(at root: URL) {
        deletedGhostContents = [:]
        if let ghostData = try? Data(contentsOf: root.appendingPathComponent(".3012deleted.json")),
           let decodedGhosts = try? JSONDecoder().decode([String: String].self, from: ghostData) {
            deletedGhostContents = decodedGhosts
        }

        if let data = try? Data(contentsOf: root.appendingPathComponent(".3012baseline.json")),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            baselineSnapshots = decoded
            return
        }

        // Seed initial clean baseline from existing files on disk
        baselineSnapshots = snapshotCurrentDiskTextFiles(at: root)
        saveBaselineMeta()
    }

    public func resetDiffBaselineToCurrentDisk(with customSnapshot: [String: String]? = nil) {
        baselineSnapshots = customSnapshot ?? snapshotCurrentDiskTextFiles(at: rootURL)
        deletedGhostContents.removeAll()
        saveBaselineMeta()
        saveDeletedGhostsMeta()
        reloadTree()
    }

    private func saveBaselineMeta() {
        if let data = try? JSONEncoder().encode(baselineSnapshots) {
            try? data.write(to: baselineMetaURL, options: .atomic)
        }
    }

    private func saveDeletedGhostsMeta() {
        if deletedGhostContents.isEmpty {
            try? FileManager.default.removeItem(at: deletedGhostsMetaURL)
        } else if let data = try? JSONEncoder().encode(deletedGhostContents) {
            try? data.write(to: deletedGhostsMetaURL, options: .atomic)
        }
    }

    private func snapshotCurrentDiskTextFiles(at root: URL) -> [String: String] {
        var map: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return map }

        let rootPrefix = root.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text.utf8.count < 512_000 else { continue }
            var rel = fileURL.standardizedFileURL.path
            if rel.hasPrefix(rootPrefix) {
                rel = String(rel.dropFirst(rootPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if !rel.isEmpty {
                map[rel] = text
            }
        }
        return map
    }

    private func updateSingleFileStatus(for url: URL, liveContent: String) {
        let rel = relativePath(for: url)
        let status = WorkspaceFileDiffStatus.classify(
            baselineContent: baselineSnapshots[rel],
            currentContent: liveContent
        )
        if fileStatuses[rel] != status {
            if status == .unchanged {
                fileStatuses.removeValue(forKey: rel)
            } else {
                fileStatuses[rel] = status
            }
        }
    }

    public func recomputeAllFileStatuses() {
        var updated: [String: WorkspaceFileDiffStatus] = [:]
        let diskFiles = snapshotCurrentDiskTextFiles(at: rootURL)

        for (rel, diskContent) in diskFiles {
            let openContent = openTabs.first(where: { relativePath(for: $0.fileURL) == rel })?.content
            let status = WorkspaceFileDiffStatus.classify(
                baselineContent: baselineSnapshots[rel],
                currentContent: openContent ?? diskContent
            )
            if status != .unchanged {
                updated[rel] = status
            }
        }

        let deletedPaths = Set(deletedGhostContents.keys).union(
            baselineSnapshots.keys.filter { diskFiles[$0] == nil }
        )
        for delRel in deletedPaths where diskFiles[delRel] == nil {
            updated[delRel] = .deleted
        }

        if fileStatuses != updated {
            fileStatuses = updated
        }
    }

    public func diffStatus(for url: URL, isDeletedGhost: Bool = false) -> WorkspaceFileDiffStatus {
        if isDeletedGhost { return .deleted }
        let rel = relativePath(for: url)
        return fileStatuses[rel] ?? .unchanged
    }

    public func folderDiffStatus(for node: FileNode) -> WorkspaceFileDiffStatus {
        guard node.isDirectory, let children = node.children else { return .unchanged }
        var highest: WorkspaceFileDiffStatus = .unchanged
        for child in children {
            let childStatus = child.isDirectory ? folderDiffStatus(for: child) : diffStatus(for: child.url, isDeletedGhost: child.isDeletedGhost)
            if childStatus.priorityRank > highest.priorityRank {
                highest = childStatus
            }
        }
        return highest
    }

    public func performWorkspaceSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        var hits: [(url: URL, line: Int, preview: String)] = []
        for fileURL in flattenFiles(in: fileTree) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (idx, lineText) in lines.enumerated() {
                if lineText.localizedCaseInsensitiveContains(trimmed) {
                    hits.append((fileURL, idx + 1, lineText.trimmingCharacters(in: .whitespaces)))
                    if hits.count >= 100 { break }
                }
            }
            if hits.count >= 100 { break }
        }
        searchResults = hits
    }
}
