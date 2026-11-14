import Foundation
import SwiftUI

public struct ClosedTabRecord: Equatable {
    public let fileURL: URL
    public let content: String
    public let languageOverride: CodeLanguage?
    public let isPinned: Bool
    public let selectedRangeLocation: Int

    public init(
        fileURL: URL,
        content: String,
        languageOverride: CodeLanguage? = nil,
        isPinned: Bool = false,
        selectedRangeLocation: Int = 0
    ) {
        self.fileURL = fileURL
        self.content = content
        self.languageOverride = languageOverride
        self.isPinned = isPinned
        self.selectedRangeLocation = selectedRangeLocation
    }
}

@MainActor
public final class WorkspaceManager: ObservableObject {
    @Published public private(set) var rootURL: URL
    @Published public private(set) var availableWorkspaces: [URL] = []
    @Published public var statusBannerMessage: String? = nil
    @Published public private(set) var fileTree: [FileNode] = []
    @Published public var openTabs: [OpenTab] = []
    @Published public var activeTabID: URL?
    @Published public private(set) var recentlyClosedTabs: [ClosedTabRecord] = []
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [(url: URL, line: Int, preview: String)] = []
    @Published public private(set) var fileStatuses: [String: WorkspaceFileDiffStatus] = [:]

    public var canReopenClosedTab: Bool { !recentlyClosedTabs.isEmpty }

    private var baselineSnapshots: [String: String] = [:]
    private var deletedGhostContents: [String: String] = [:]
    private var externalMirroredFolderURL: URL? = nil
    private var externalMirrorHasSecurityScope: Bool = false
    private var externalSingleFileURLs: [String: (url: URL, hasScope: Bool)] = [:]

    private func releaseExternalSingleFileScopes() {
        for entry in externalSingleFileURLs.values where entry.hasScope {
            entry.url.stopAccessingSecurityScopedResource()
        }
        externalSingleFileURLs.removeAll()
    }

    public var onFileSavedOrChanged: (() -> Void)?
    public var onAnyTabSavedWithURL: ((URL, String) -> Void)?

    public var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

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
        refreshAvailableWorkspaces()
        openPreferredEntryFile()
    }

    public func refreshAvailableWorkspaces() {
        let fm = FileManager.default
        let docs = documentsDirectory
        let defaultWorkspace = docs.appendingPathComponent("Workspace", isDirectory: true)
        if !fm.fileExists(atPath: defaultWorkspace.path) {
            try? fm.createDirectory(at: defaultWorkspace, withIntermediateDirectories: true)
        }
        let items = (try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var folders: [URL] = []
        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                folders.append(url)
            }
        }
        folders.sort { a, b in
            if a.lastPathComponent == "Workspace" { return true }
            if b.lastPathComponent == "Workspace" { return false }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
        availableWorkspaces = folders
    }

    public func createNewProjectWorkspace(named rawName: String) {
        let clean = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        let folderName = clean.isEmpty ? "Project_\(Int(Date().timeIntervalSince1970) % 10000)" : clean
        let target = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let readme = target.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? "# \(folderName)\n\nCreated in 3012 Mobile IDE.\n".write(to: readme, atomically: true, encoding: .utf8)
        }
        switchWorkspaceFolder(to: target)
    }

    private func openPreferredEntryFile() {
        let flat = flattenFiles(in: fileTree)
        let preferredNames = ["index.html", "main.cpp", "main.c", "main.py", "app.py", "index.js", "main.js", "Tweak.xm", "Tweak.x", "Main.swift", "Package.swift", "README.md"]
        for name in preferredNames {
            if let match = flat.first(where: { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }) {
                openFile(at: match)
                return
            }
        }
        let nonArchiveFiles = flat.filter { !isArchiveOrBinaryExtension($0.pathExtension.lowercased()) }
        if let first = nonArchiveFiles.first ?? flat.first {
            openFile(at: first)
        }
    }

    private func isArchiveOrBinaryExtension(_ ext: String) -> Bool {
        ["zip", "rar", "7z", "tar", "gz", "deb", "ipa", "dylib", "o", "a", "so", "png", "jpg", "jpeg", "gif", "webp", "ico", "pdf", "woff", "woff2", "ttf", "otf", "mp3", "mp4", "mov", "sqlite", "db"].contains(ext)
    }

    private func persistTabContentIfTextFile(_ tab: OpenTab) {
        let ext = tab.fileURL.pathExtension.lowercased()
        guard !isArchiveOrBinaryExtension(ext) else { return }
        try? tab.content.write(to: tab.fileURL, atomically: true, encoding: .utf8)
        syncFileChangeBackToExternalMirror(localFileURL: tab.fileURL, content: tab.content)
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
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            extractZipAtURL(url)
            return
        }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            switchWorkspaceFolder(to: url)
            return
        }
        if let existing = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            activeTabID = existing.id
            return
        }
        let text: String
        if isArchiveOrBinaryExtension(ext) {
            text = "// [Binary / Archive File: \(url.lastPathComponent)]\n// Không thể hiển thị trực tiếp dưới dạng văn bản."
        } else {
            text = readTextWithEncodingFallback(from: url) ?? ""
        }
        recentlyClosedTabs.removeAll { $0.fileURL.standardizedFileURL == url.standardizedFileURL }
        let tab = OpenTab(fileURL: url, content: text)
        let insertIdx = openTabs.firstIndex(where: { !$0.isPinned }) ?? openTabs.count
        openTabs.insert(tab, at: insertIdx)
        activeTabID = tab.id
    }

    private func readTextWithEncodingFallback(from url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        if let utf16 = try? String(contentsOf: url, encoding: .utf16) {
            return utf16
        }
        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            return latin1
        }
        return nil
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
            persistTabContentIfTextFile(openTabs[idx])
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
        persistTabContentIfTextFile(openTabs[idx])
        openTabs[idx].savedContent = openTabs[idx].content
        updateSingleFileStatus(for: openTabs[idx].fileURL, liveContent: openTabs[idx].content)
        onFileSavedOrChanged?()
        onAnyTabSavedWithURL?(openTabs[idx].fileURL, openTabs[idx].content)
    }

    public func saveAllTabs() {
        for idx in openTabs.indices {
            persistTabContentIfTextFile(openTabs[idx])
            openTabs[idx].savedContent = openTabs[idx].content
        }
        recomputeAllFileStatuses()
        onFileSavedOrChanged?()
    }

    private func recordClosedTab(_ tab: OpenTab) {
        let std = tab.fileURL.standardizedFileURL
        recentlyClosedTabs.removeAll { $0.fileURL.standardizedFileURL == std }
        recentlyClosedTabs.insert(
            ClosedTabRecord(
                fileURL: tab.fileURL,
                content: tab.content,
                languageOverride: tab.languageOverride,
                isPinned: tab.isPinned,
                selectedRangeLocation: tab.selectedRangeLocation
            ),
            at: 0
        )
        if recentlyClosedTabs.count > 25 {
            recentlyClosedTabs.removeLast(recentlyClosedTabs.count - 25)
        }
    }

    public func togglePinTab(_ tabID: URL) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].isPinned.toggle()
        let pinned = openTabs.filter { $0.isPinned }
        let unpinned = openTabs.filter { !$0.isPinned }
        openTabs = pinned + unpinned
    }

    public func closeTab(_ tabID: URL) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let closing = openTabs[idx]
        persistTabContentIfTextFile(closing)
        recordClosedTab(closing)
        openTabs.remove(at: idx)
        if activeTabID == tabID {
            if openTabs.indices.contains(idx) {
                activeTabID = openTabs[idx].id
            } else {
                activeTabID = openTabs.first?.id
            }
        }
    }

    public func closeOtherTabs(keeping tabID: URL) {
        let toClose = openTabs.filter { $0.id != tabID && !$0.isPinned }
        for tab in toClose {
            persistTabContentIfTextFile(tab)
            recordClosedTab(tab)
        }
        openTabs.removeAll { $0.id != tabID && !$0.isPinned }
        if !openTabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = openTabs.first(where: { $0.id == tabID })?.id ?? openTabs.first?.id
        }
    }

    public func closeAllTabs() {
        let hasUnpinned = openTabs.contains { !$0.isPinned }
        let toClose = hasUnpinned ? openTabs.filter { !$0.isPinned } : openTabs
        for tab in toClose {
            persistTabContentIfTextFile(tab)
            recordClosedTab(tab)
        }
        if hasUnpinned {
            openTabs.removeAll { !$0.isPinned }
            if let current = activeTabID, !openTabs.contains(where: { $0.id == current }) {
                activeTabID = openTabs.first?.id
            }
        } else {
            openTabs.removeAll()
            activeTabID = nil
        }
    }

    public func reopenLastClosedTab() {
        guard !recentlyClosedTabs.isEmpty else { return }
        let record = recentlyClosedTabs.removeFirst()
        let fm = FileManager.default
        if !fm.fileExists(atPath: record.fileURL.path) {
            let parent = record.fileURL.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try? record.content.write(to: record.fileURL, atomically: true, encoding: .utf8)
            syncFileChangeBackToExternalMirror(localFileURL: record.fileURL, content: record.content)
            reloadTree()
        }
        if let existingIdx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == record.fileURL.standardizedFileURL }) {
            openTabs[existingIdx].languageOverride = record.languageOverride
            openTabs[existingIdx].selectedRangeLocation = record.selectedRangeLocation
            activeTabID = openTabs[existingIdx].id
            return
        }
        let diskText = readTextWithEncodingFallback(from: record.fileURL) ?? record.content
        var restored = OpenTab(
            fileURL: record.fileURL,
            content: diskText,
            languageOverride: record.languageOverride,
            isPinned: record.isPinned
        )
        restored.selectedRangeLocation = record.selectedRangeLocation
        if restored.isPinned {
            openTabs.insert(restored, at: 0)
        } else {
            let insertIdx = openTabs.firstIndex(where: { !$0.isPinned }) ?? openTabs.count
            openTabs.insert(restored, at: insertIdx)
        }
        activeTabID = restored.id
    }

    public func moveTabToFront(_ tabID: URL) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else {
            activeTabID = tabID
            return
        }
        let tab = openTabs.remove(at: idx)
        if tab.isPinned {
            openTabs.insert(tab, at: 0)
        } else {
            let insertIdx = openTabs.firstIndex(where: { !$0.isPinned }) ?? openTabs.count
            openTabs.insert(tab, at: insertIdx)
        }
        activeTabID = tab.id
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
            syncFileChangeBackToExternalMirror(localFileURL: target, content: body)
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
        syncFileChangeBackToExternalMirror(localFileURL: targetURL, content: newContent)

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
                let oldTab = openTabs[idx]
                let wasActive = (activeTabID == oldTab.id)
                openTabs.remove(at: idx)
                let updated = OpenTab(
                    fileURL: dest,
                    content: oldTab.content,
                    languageOverride: oldTab.languageOverride,
                    isPinned: oldTab.isPinned
                )
                openTabs.insert(updated, at: idx)
                if wasActive { activeTabID = updated.id }
            }
            reloadTree()
            onFileSavedOrChanged?()
        } catch {}
    }

    public func switchWorkspaceFolder(to externalURL: URL) {
        if externalURL.pathExtension.lowercased() == "zip" {
            importAndOpenZip(from: externalURL)
            return
        }

        if let prevMirror = externalMirroredFolderURL, externalMirrorHasSecurityScope {
            prevMirror.stopAccessingSecurityScopedResource()
            externalMirroredFolderURL = nil
            externalMirrorHasSecurityScope = false
        }
        releaseExternalSingleFileScopes()

        let fm = FileManager.default
        let docsStd = documentsDirectory.standardizedFileURL.path
        let targetStd = externalURL.standardizedFileURL.path

        if targetStd == docsStd || targetStd.hasPrefix(docsStd + "/") {
            // Already inside Documents/ container -> full direct R/W
            try? fm.createDirectory(at: externalURL, withIntermediateDirectories: true)
            self.rootURL = externalURL
            self.externalMirroredFolderURL = nil
            self.externalMirrorHasSecurityScope = false
        } else {
            // External folder picked from Files.app / iCloud Drive / Downloads:
            // Coordinate-mirror into Documents/<FolderName> for 100% reliable LiveServer/Terminal/Theos R/W
            // while holding security scope + bookmark to sync file edits back on save.
            let hasScope = externalURL.startAccessingSecurityScopedResource()
            if let bookmark = try? externalURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "3012.lastExternalFolderBookmark")
            }

            let rawFolderName = externalURL.lastPathComponent
            let safeFolderName = rawFolderName.isEmpty ? "ExternalProject" : rawFolderName
            let localMirror = documentsDirectory.appendingPathComponent(safeFolderName, isDirectory: true)
            let copied = mirrorExternalDirectory(from: externalURL, to: localMirror)
            if copied {
                self.rootURL = localMirror
                self.externalMirroredFolderURL = externalURL
                self.externalMirrorHasSecurityScope = hasScope
            } else {
                // Fallback to direct folder access if mirror copy couldn't run
                self.rootURL = externalURL
                self.externalMirroredFolderURL = nil
                self.externalMirrorHasSecurityScope = hasScope
            }
        }

        self.openTabs.removeAll()
        self.recentlyClosedTabs.removeAll()
        self.activeTabID = nil
        loadOrInitializeBaseline(at: self.rootURL)
        reloadTree()
        refreshAvailableWorkspaces()
        openPreferredEntryFile()
        statusBannerMessage = "Đã mở thư mục: \(self.rootURL.lastPathComponent)"
        onFileSavedOrChanged?()
    }

    @discardableResult
    public func importAndOpenZip(from zipURL: URL) -> Bool {
        guard let importedDir = FileTimelineAndArchiveService.shared.importProjectZip(from: zipURL, into: documentsDirectory) else {
            statusBannerMessage = FileTimelineAndArchiveService.shared.archiveStatusMessage
            return false
        }
        if let prevMirror = externalMirroredFolderURL, externalMirrorHasSecurityScope {
            prevMirror.stopAccessingSecurityScopedResource()
            externalMirroredFolderURL = nil
            externalMirrorHasSecurityScope = false
        }
        releaseExternalSingleFileScopes()
        self.rootURL = importedDir
        self.openTabs.removeAll()
        self.recentlyClosedTabs.removeAll()
        self.activeTabID = nil
        loadOrInitializeBaseline(at: importedDir)
        reloadTree()
        refreshAvailableWorkspaces()
        openPreferredEntryFile()
        statusBannerMessage = "Đã giải nén & mở dự án: \(importedDir.lastPathComponent)"
        onFileSavedOrChanged?()
        return true
    }

    public func extractZipAtURL(_ zipURL: URL) {
        if let extractedDir = FileTimelineAndArchiveService.shared.extractZipInPlace(from: zipURL) {
            reloadTree()
            let flatInExtracted = flattenFiles(in: buildNodes(at: extractedDir))
                .filter { !isArchiveOrBinaryExtension($0.pathExtension.lowercased()) }
            if let firstFile = flatInExtracted.first {
                openFile(at: firstFile)
            }
            statusBannerMessage = "Đã giải nén \(zipURL.lastPathComponent) -> \(extractedDir.lastPathComponent)/"
            onFileSavedOrChanged?()
        } else {
            statusBannerMessage = FileTimelineAndArchiveService.shared.archiveStatusMessage
        }
    }

    public func openExternalSingleFile(from externalURL: URL) {
        let hasScope = externalURL.startAccessingSecurityScopedResource()
        let ext = externalURL.pathExtension.lowercased()
        let isDir = (try? externalURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if ext == "zip" {
            defer {
                if hasScope { externalURL.stopAccessingSecurityScopedResource() }
            }
            importAndOpenZip(from: externalURL)
            return
        }
        if isDir {
            if hasScope { externalURL.stopAccessingSecurityScopedResource() }
            switchWorkspaceFolder(to: externalURL)
            return
        }

        let docsStd = documentsDirectory.standardizedFileURL.path
        let targetStd = externalURL.standardizedFileURL.path
        if targetStd.hasPrefix(docsStd + "/") {
            if hasScope { externalURL.stopAccessingSecurityScopedResource() }
            reloadTree()
            openFile(at: externalURL)
            statusBannerMessage = "Đã mở file: \(externalURL.lastPathComponent)"
            return
        }

        // External standalone file from Files.app / iCloud Drive / Downloads:
        // Copy into active workspace so Live Server, 1-Tap Run, Terminal & AI Agent work immediately,
        // and retain security scope so edits sync back to the original external file on save.
        let dest = rootURL.appendingPathComponent(externalURL.lastPathComponent)
        var fileData: Data? = nil
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordErr: NSError?
        coordinator.coordinate(readingItemAt: externalURL, options: .withoutChanges, error: &coordErr) { coordURL in
            fileData = try? Data(contentsOf: coordURL)
        }
        if fileData == nil {
            fileData = try? Data(contentsOf: externalURL)
        }

        guard let data = fileData else {
            if hasScope { externalURL.stopAccessingSecurityScopedResource() }
            statusBannerMessage = "Không đọc được file: \(externalURL.lastPathComponent)"
            return
        }

        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
        } catch {
            if hasScope { externalURL.stopAccessingSecurityScopedResource() }
            statusBannerMessage = "Không thể lưu bản sao file \(externalURL.lastPathComponent): \(error.localizedDescription)"
            return
        }

        let destKey = dest.standardizedFileURL.path
        if let oldEntry = externalSingleFileURLs[destKey],
           oldEntry.hasScope,
           oldEntry.url.standardizedFileURL != externalURL.standardizedFileURL {
            oldEntry.url.stopAccessingSecurityScopedResource()
        }
        externalSingleFileURLs[destKey] = (url: externalURL, hasScope: hasScope)

        reloadTree()
        if let existingIdx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == dest.standardizedFileURL }) {
            let refreshed = readTextWithEncodingFallback(from: dest) ?? openTabs[existingIdx].content
            openTabs[existingIdx].content = refreshed
            openTabs[existingIdx].savedContent = refreshed
            activeTabID = openTabs[existingIdx].id
        } else {
            openFile(at: dest)
        }
        statusBannerMessage = "Đã mở file lẻ: \(dest.lastPathComponent)"
        onFileSavedOrChanged?()
    }

    public func handleIncomingURL(_ url: URL) {
        openExternalSingleFile(from: url)
    }

    private func mirrorExternalDirectory(from externalURL: URL, to localMirror: URL) -> Bool {
        let fm = FileManager.default
        var success = false
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?

        coordinator.coordinate(readingItemAt: externalURL, options: .withoutChanges, error: &coordError) { coordinatedURL in
            let tempCopy = fm.temporaryDirectory.appendingPathComponent("mirror_\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.copyItem(at: coordinatedURL, to: tempCopy)
                if fm.fileExists(atPath: localMirror.path) {
                    try? fm.removeItem(at: localMirror)
                }
                try fm.createDirectory(at: localMirror.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: tempCopy, to: localMirror)
                success = true
            } catch {
                try? fm.removeItem(at: tempCopy)
                // Manual recursive fallback for FileProviders that disallow directory-level copyItem
                do {
                    if fm.fileExists(atPath: localMirror.path) {
                        try? fm.removeItem(at: localMirror)
                    }
                    try fm.createDirectory(at: localMirror, withIntermediateDirectories: true)
                    copyDirectoryContentsRecursively(from: coordinatedURL, to: localMirror)
                    success = true
                } catch {
                    success = false
                }
            }
        }
        return success
    }

    private func copyDirectoryContentsRecursively(from srcDir: URL, to dstDir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return
        }
        for item in items {
            let name = item.lastPathComponent
            if name == ".DS_Store" || name == "__MACOSX" { continue }
            let dstItem = dstDir.appendingPathComponent(name)
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                try? fm.createDirectory(at: dstItem, withIntermediateDirectories: true)
                copyDirectoryContentsRecursively(from: item, to: dstItem)
            } else {
                if let data = try? Data(contentsOf: item) {
                    try? data.write(to: dstItem, options: .atomic)
                } else {
                    try? fm.copyItem(at: item, to: dstItem)
                }
            }
        }
    }

    private func syncFileChangeBackToExternalMirror(localFileURL: URL, content: String) {
        let localKey = localFileURL.standardizedFileURL.path
        if let linked = externalSingleFileURLs[localKey] {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordErr: NSError?
            var wrote = false
            coordinator.coordinate(writingItemAt: linked.url, options: .forReplacing, error: &coordErr) { coordinatedURL in
                if (try? content.write(to: coordinatedURL, atomically: true, encoding: .utf8)) != nil {
                    wrote = true
                }
            }
            if !wrote {
                try? content.write(to: linked.url, atomically: true, encoding: .utf8)
            }
        }
        guard let externalRoot = externalMirroredFolderURL else { return }
        let rel = relativePath(for: localFileURL)
        guard !rel.isEmpty else { return }
        let extTarget = externalRoot.appendingPathComponent(rel)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordErr: NSError?
        coordinator.coordinate(writingItemAt: extTarget, options: .forReplacing, error: &coordErr) { coordinatedURL in
            try? FileManager.default.createDirectory(at: coordinatedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - VS Code Working-Tree Diff Baseline & Status Decoration Engine
    private func workspaceMetaDirectory(for root: URL) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let rawKey = root.standardizedFileURL.path.data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") ?? "default"
        let safeKey = String(rawKey.suffix(64))
        let dir = appSupport
            .appendingPathComponent("3012WorkspaceMeta", isDirectory: true)
            .appendingPathComponent(safeKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var baselineMetaURL: URL {
        workspaceMetaDirectory(for: rootURL).appendingPathComponent("baseline.json")
    }

    private var deletedGhostsMetaURL: URL {
        workspaceMetaDirectory(for: rootURL).appendingPathComponent("deleted.json")
    }

    private func loadOrInitializeBaseline(at root: URL) {
        deletedGhostContents = [:]
        let metaDir = workspaceMetaDirectory(for: root)
        let newGhostURL = metaDir.appendingPathComponent("deleted.json")
        let legacyGhostURL = root.appendingPathComponent(".3012deleted.json")

        if let ghostData = (try? Data(contentsOf: newGhostURL)) ?? (try? Data(contentsOf: legacyGhostURL)),
           let decodedGhosts = try? JSONDecoder().decode([String: String].self, from: ghostData) {
            deletedGhostContents = decodedGhosts
        }

        let newBaselineURL = metaDir.appendingPathComponent("baseline.json")
        let legacyBaselineURL = root.appendingPathComponent(".3012baseline.json")

        if let data = (try? Data(contentsOf: newBaselineURL)) ?? (try? Data(contentsOf: legacyBaselineURL)),
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
