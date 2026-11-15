import Foundation
import SwiftUI

public enum WorkspaceMutationEvent: Equatable {
    case upsertFile(relativePath: String, content: String)
    case deleteItem(relativePath: String, isDirectory: Bool)
    case renameItem(oldRelativePath: String, newRelativePath: String, isDirectory: Bool)
    case createDirectory(relativePath: String)
}

public enum ProjectStarterKind: String, CaseIterable, Identifiable {
    case modernWebLanding
    case cppCompetitive
    case pythonAutomation
    case markdownDocs

    public var id: String { rawValue }

    public var folderPrefix: String {
        switch self {
        case .modernWebLanding: return "WebStarter"
        case .cppCompetitive: return "CPPSolution"
        case .pythonAutomation: return "PyBotScript"
        case .markdownDocs: return "DocsMermaid"
        }
    }
}

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
    @Published public private(set) var workspaceDisplayName: String = "Workspace"
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
    public var onWorkspaceMutation: ((WorkspaceMutationEvent) -> Void)?
    public var suppressOutboundSyncEvents: Bool = false

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
        self.workspaceDisplayName = defaultWorkspace.lastPathComponent
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
            let name = url.lastPathComponent
            if name == "_ExternalFolders" || name == "Inbox" { continue }
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

    private func persistTabContentIfTextFile(_ tab: OpenTab, emitSync: Bool = true) {
        let ext = tab.fileURL.pathExtension.lowercased()
        guard !isArchiveOrBinaryExtension(ext) else { return }
        try? tab.content.write(to: tab.fileURL, atomically: true, encoding: .utf8)
        syncFileChangeBackToExternalMirror(localFileURL: tab.fileURL, content: tab.content)
        if emitSync && !suppressOutboundSyncEvents {
            let rel = relativePath(for: tab.fileURL)
            if !rel.isEmpty {
                onWorkspaceMutation?(.upsertFile(relativePath: rel, content: tab.content))
            }
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
            let hadUnsaved = openTabs[idx].content != openTabs[idx].savedContent
            persistTabContentIfTextFile(openTabs[idx])
            openTabs[idx].savedContent = openTabs[idx].content
            if hadUnsaved {
                onAnyTabSavedWithURL?(openTabs[idx].fileURL, openTabs[idx].content)
            }
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
            if !suppressOutboundSyncEvents && !rel.isEmpty {
                onWorkspaceMutation?(.upsertFile(relativePath: rel, content: body))
            }
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
        if let existing = openTabs.first(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL })?.content
            ?? (try? String(contentsOf: targetURL, encoding: .utf8)),
           existing != newContent {
            FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: existing, label: "AI Agent")
        }
        try? newContent.write(to: targetURL, atomically: true, encoding: .utf8)
        syncFileChangeBackToExternalMirror(localFileURL: targetURL, content: newContent)

        if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
            openTabs[idx].content = newContent
            openTabs[idx].savedContent = newContent
            activeTabID = openTabs[idx].id
        } else {
            reloadTree()
            openFile(at: targetURL)
            if !suppressOutboundSyncEvents {
                onWorkspaceMutation?(.upsertFile(relativePath: cleaned, content: newContent))
            }
            return
        }
        reloadTree()
        onFileSavedOrChanged?()
        if !suppressOutboundSyncEvents {
            onWorkspaceMutation?(.upsertFile(relativePath: cleaned, content: newContent))
        }
    }

    public func createFolder(named rawName: String, in directory: URL? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let target = (directory ?? rootURL).appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let rel = relativePath(for: target)
        if let externalRoot = externalMirroredFolderURL, !rel.isEmpty {
            try? FileManager.default.createDirectory(at: externalRoot.appendingPathComponent(rel, isDirectory: true), withIntermediateDirectories: true)
        }
        reloadTree()
        if !suppressOutboundSyncEvents && !rel.isEmpty {
            onWorkspaceMutation?(.createDirectory(relativePath: rel))
        }
    }

    public func deleteItem(at url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let stdPath = url.standardizedFileURL.path
        let prefixPath = stdPath + "/"
        let rel = relativePath(for: url)

        if isDir {
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                var savedGhosts = 0
                for case let childURL as URL in enumerator {
                    let childIsDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard !childIsDir else { continue }
                    let childRel = relativePath(for: childURL)
                    if let content = openTabs.first(where: { $0.fileURL.standardizedFileURL == childURL.standardizedFileURL })?.content
                        ?? (try? String(contentsOf: childURL, encoding: .utf8)) {
                        deletedGhostContents[childRel] = content
                        savedGhosts += 1
                    }
                    if savedGhosts >= 50 { break }
                }
                saveDeletedGhostsMeta()
            }
            openTabs.removeAll { tab in
                let tPath = tab.fileURL.standardizedFileURL.path
                return tPath == stdPath || tPath.hasPrefix(prefixPath)
            }
            if let activeID = activeTabID, !openTabs.contains(where: { $0.id == activeID }) {
                activeTabID = openTabs.last?.id
            }
            let linkedKeysToRemove = externalSingleFileURLs.keys.filter { $0 == stdPath || $0.hasPrefix(prefixPath) }
            for key in linkedKeysToRemove {
                if let entry = externalSingleFileURLs.removeValue(forKey: key), entry.hasScope {
                    entry.url.stopAccessingSecurityScopedResource()
                }
            }
        } else {
            let priorContent = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL })?.content
                ?? (try? String(contentsOf: url, encoding: .utf8))
                ?? baselineSnapshots[rel]
                ?? ""
            deletedGhostContents[rel] = priorContent
            saveDeletedGhostsMeta()
            if let tab = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
                openTabs.removeAll { $0.id == tab.id }
                if activeTabID == tab.id {
                    activeTabID = openTabs.last?.id
                }
            }
            if let entry = externalSingleFileURLs.removeValue(forKey: stdPath), entry.hasScope {
                entry.url.stopAccessingSecurityScopedResource()
            }
        }

        if let externalRoot = externalMirroredFolderURL, !rel.isEmpty {
            let extTarget = externalRoot.appendingPathComponent(rel)
            try? FileManager.default.removeItem(at: extTarget)
        }
        try? FileManager.default.removeItem(at: url)
        reloadTree()
        onFileSavedOrChanged?()
        if !suppressOutboundSyncEvents && !rel.isEmpty {
            onWorkspaceMutation?(.deleteItem(relativePath: rel, isDirectory: isDir))
        }
    }

    public func restoreDeletedFile(at url: URL) {
        let rel = relativePath(for: url)
        let restoredBody = deletedGhostContents[rel] ?? baselineSnapshots[rel] ?? ""
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try? restoredBody.write(to: url, atomically: true, encoding: .utf8)
        syncFileChangeBackToExternalMirror(localFileURL: url, content: restoredBody)
        deletedGhostContents.removeValue(forKey: rel)
        saveDeletedGhostsMeta()
        reloadTree()
        openFile(at: url)
        onFileSavedOrChanged?()
        if !suppressOutboundSyncEvents && !rel.isEmpty {
            onWorkspaceMutation?(.upsertFile(relativePath: rel, content: restoredBody))
        }
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
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let dest = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        let oldStd = url.standardizedFileURL.path
        let oldPrefix = oldStd + "/"
        let oldRel = relativePath(for: url)
        let newRel = relativePath(for: dest)

        do {
            try FileManager.default.moveItem(at: url, to: dest)
            if isDir {
                let oldBaselinePrefix = oldRel + "/"
                let matchingBaseKeys = baselineSnapshots.keys.filter { $0 == oldRel || $0.hasPrefix(oldBaselinePrefix) }
                for k in matchingBaseKeys {
                    if let val = baselineSnapshots.removeValue(forKey: k) {
                        let suffix = String(k.dropFirst(oldRel.count))
                        baselineSnapshots[newRel + suffix] = val
                    }
                }
                if !matchingBaseKeys.isEmpty { saveBaselineMeta() }

                let oldActiveID = activeTabID
                for idx in openTabs.indices {
                    let tPath = openTabs[idx].fileURL.standardizedFileURL.path
                    if tPath == oldStd || tPath.hasPrefix(oldPrefix) {
                        let tail = String(tPath.dropFirst(oldStd.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let newTabURL = tail.isEmpty ? dest : dest.appendingPathComponent(tail)
                        let oldTab = openTabs[idx]
                        var replacement = OpenTab(
                            fileURL: newTabURL,
                            content: oldTab.content,
                            languageOverride: oldTab.languageOverride,
                            isPinned: oldTab.isPinned
                        )
                        replacement.savedContent = oldTab.savedContent
                        replacement.selectedRangeLocation = oldTab.selectedRangeLocation
                        replacement.selectedRangeLength = oldTab.selectedRangeLength
                        openTabs[idx] = replacement
                        if oldActiveID == oldTab.id {
                            activeTabID = replacement.id
                        }
                    }
                }
            } else {
                if let baseVal = baselineSnapshots.removeValue(forKey: oldRel) {
                    baselineSnapshots[newRel] = baseVal
                    saveBaselineMeta()
                }
                if let entry = externalSingleFileURLs.removeValue(forKey: oldStd) {
                    externalSingleFileURLs[dest.standardizedFileURL.path] = entry
                }
                if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
                    let oldTab = openTabs[idx]
                    let wasActive = (activeTabID == oldTab.id)
                    openTabs.remove(at: idx)
                    var updated = OpenTab(
                        fileURL: dest,
                        content: oldTab.content,
                        languageOverride: oldTab.languageOverride,
                        isPinned: oldTab.isPinned
                    )
                    updated.savedContent = oldTab.savedContent
                    updated.selectedRangeLocation = oldTab.selectedRangeLocation
                    updated.selectedRangeLength = oldTab.selectedRangeLength
                    openTabs.insert(updated, at: idx)
                    if wasActive { activeTabID = updated.id }
                }
            }

            if let externalRoot = externalMirroredFolderURL, !oldRel.isEmpty, !newRel.isEmpty {
                let extSrc = externalRoot.appendingPathComponent(oldRel)
                let extDst = externalRoot.appendingPathComponent(newRel)
                try? FileManager.default.moveItem(at: extSrc, to: extDst)
            }

            reloadTree()
            onFileSavedOrChanged?()
            if !suppressOutboundSyncEvents && !oldRel.isEmpty && !newRel.isEmpty {
                onWorkspaceMutation?(.renameItem(oldRelativePath: oldRel, newRelativePath: newRel, isDirectory: isDir))
            }
        } catch {}
    }

    private func stableShortHash(_ input: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for b in input.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%08llx", hash & 0xFFFF_FFFF)
    }

    public func switchWorkspaceFolder(to externalURL: URL) {
        if externalURL.pathExtension.lowercased() == "zip" {
            importAndOpenZip(from: externalURL)
            return
        }

        // Persist any unsaved buffer edits before closing the current workspace
        saveAllTabs()

        if let prevMirror = externalMirroredFolderURL, externalMirrorHasSecurityScope {
            prevMirror.stopAccessingSecurityScopedResource()
            externalMirroredFolderURL = nil
            externalMirrorHasSecurityScope = false
        }
        releaseExternalSingleFileScopes()

        let fm = FileManager.default
        let docsStd = documentsDirectory.standardizedFileURL.path
        let targetStd = externalURL.standardizedFileURL.path
        let rawFolderName = externalURL.lastPathComponent
        let safeFolderName = rawFolderName.isEmpty ? "ExternalProject" : rawFolderName

        if targetStd == docsStd || targetStd.hasPrefix(docsStd + "/") {
            // Already inside Documents/ container -> full direct R/W
            try? fm.createDirectory(at: externalURL, withIntermediateDirectories: true)
            self.rootURL = externalURL
            self.workspaceDisplayName = safeFolderName
            self.externalMirroredFolderURL = nil
            self.externalMirrorHasSecurityScope = false
        } else {
            // External folder picked from Files.app / iCloud Drive / Downloads:
            // Coordinate-mirror into Documents/_ExternalFolders/<FolderName>-<Hash> to prevent collisions
            // while holding security scope + bookmark to sync file edits back on save.
            let hasScope = externalURL.startAccessingSecurityScopedResource()
            if let bookmark = try? externalURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "3012.lastExternalFolderBookmark")
            }

            let mirrorContainer = documentsDirectory.appendingPathComponent("_ExternalFolders", isDirectory: true)
            try? fm.createDirectory(at: mirrorContainer, withIntermediateDirectories: true)
            let localMirror = mirrorContainer.appendingPathComponent("\(safeFolderName)-\(stableShortHash(targetStd))", isDirectory: true)
            let copied = mirrorExternalDirectory(from: externalURL, to: localMirror)
            if copied {
                self.rootURL = localMirror
                self.workspaceDisplayName = safeFolderName
                self.externalMirroredFolderURL = externalURL
                self.externalMirrorHasSecurityScope = hasScope
            } else {
                // Fallback to direct folder access if mirror copy couldn't run
                self.rootURL = externalURL
                self.workspaceDisplayName = safeFolderName
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
        statusBannerMessage = "Đã mở thư mục: \(self.workspaceDisplayName)"
        onFileSavedOrChanged?()
    }

    @discardableResult
    public func importAndOpenZip(from zipURL: URL) -> Bool {
        saveAllTabs()
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
        self.workspaceDisplayName = importedDir.lastPathComponent
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
            let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            let isDir = vals?.isDirectory ?? false
            if vals?.isUbiquitousItem == true && vals?.ubiquitousItemDownloadingStatus != .current {
                try? fm.startDownloadingUbiquitousItem(at: item)
            }
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
    public static func metaDirectory(for root: URL) -> URL {
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

    private func workspaceMetaDirectory(for root: URL) -> URL {
        Self.metaDirectory(for: root)
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

    public func performWorkspaceSearch(_ query: String, caseSensitive: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        var hits: [(url: URL, line: Int, preview: String)] = []
        for fileURL in flattenFiles(in: fileTree) {
            let stdURL = fileURL.standardizedFileURL
            let bufferContent = openTabs.first(where: { $0.fileURL.standardizedFileURL == stdURL })?.content
            guard let content = bufferContent ?? readTextWithEncodingFallback(from: fileURL) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (idx, lineText) in lines.enumerated() {
                let matched = caseSensitive
                    ? lineText.contains(trimmed)
                    : lineText.localizedCaseInsensitiveContains(trimmed)
                if matched {
                    hits.append((fileURL, idx + 1, lineText.trimmingCharacters(in: .whitespaces)))
                    if hits.count >= 150 { break }
                }
            }
            if hits.count >= 150 { break }
        }
        searchResults = hits
    }

    @discardableResult
    public func performWorkspaceReplace(query: String, replacement: String, caseSensitive: Bool = false) -> (filesUpdated: Int, replacements: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0, 0) }
        var filesUpdated = 0
        var totalReplacements = 0
        let compareOpts: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        for fileURL in flattenFiles(in: fileTree) {
            let ext = fileURL.pathExtension.lowercased()
            guard !isArchiveOrBinaryExtension(ext) else { continue }
            let stdURL = fileURL.standardizedFileURL
            let openIdx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == stdURL })
            guard let original = openIdx.map({ openTabs[$0].content }) ?? readTextWithEncodingFallback(from: fileURL) else { continue }

            var countInFile = 0
            var searchStart = original.startIndex
            while let foundRange = original.range(of: trimmed, options: compareOpts, range: searchStart..<original.endIndex) {
                countInFile += 1
                searchStart = foundRange.upperBound
            }
            guard countInFile > 0 else { continue }

            let updatedText = original.replacingOccurrences(of: trimmed, with: replacement, options: compareOpts)
            FileTimelineAndArchiveService.shared.recordSnapshot(for: fileURL, content: original, label: "Find & Replace")
            try? updatedText.write(to: fileURL, atomically: true, encoding: .utf8)
            syncFileChangeBackToExternalMirror(localFileURL: fileURL, content: updatedText)

            if let openIdx {
                openTabs[openIdx].content = updatedText
                openTabs[openIdx].savedContent = updatedText
                onAnyTabSavedWithURL?(fileURL, updatedText)
            }

            let rel = relativePath(for: fileURL)
            if !suppressOutboundSyncEvents && !rel.isEmpty {
                onWorkspaceMutation?(.upsertFile(relativePath: rel, content: updatedText))
            }
            filesUpdated += 1
            totalReplacements += countInFile
        }

        if filesUpdated > 0 {
            recomputeAllFileStatuses()
            onFileSavedOrChanged?()
            performWorkspaceSearch(query, caseSensitive: caseSensitive)
            statusBannerMessage = "Đã thay thế \(totalReplacements) vị trí trong \(filesUpdated) file."
        }
        return (filesUpdated, totalReplacements)
    }

    // MARK: - Two-Way PC Sync Inbound Operations (Zero Echo)
    private func isSafeRelativeSyncPath(_ rel: String) -> Bool {
        let trimmed = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/").map(String.init)
        return !parts.contains("..") && !parts.contains(".") && !trimmed.contains("\\")
    }

    public func collectAllSyncableTextFiles(maxFileBytes: Int = 512_000) -> [String: String] {
        var result = snapshotCurrentDiskTextFiles(at: rootURL)
        for tab in openTabs {
            let rel = relativePath(for: tab.fileURL)
            guard !rel.isEmpty, !isArchiveOrBinaryExtension(tab.fileURL.pathExtension.lowercased()) else { continue }
            if tab.content.utf8.count < maxFileBytes {
                result[rel] = tab.content
            }
        }
        return result
    }

    public func applyRemoteUpsert(relativePath rel: String, content: String, recordConflictTimeline: Bool = true) {
        guard isSafeRelativeSyncPath(rel) else { return }
        let targetURL = rootURL.appendingPathComponent(rel)
        let prevSuppression = suppressOutboundSyncEvents
        suppressOutboundSyncEvents = true
        defer { suppressOutboundSyncEvents = prevSuppression }

        if recordConflictTimeline {
            if let openIdx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }),
               openTabs[openIdx].isDirty,
               openTabs[openIdx].content != content {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: openTabs[openIdx].content, label: "PC Sync Conflict Backup")
            } else if let diskPrev = readTextWithEncodingFallback(from: targetURL), diskPrev != content {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: diskPrev, label: "PC Sync Before")
            }
        }

        try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: targetURL, atomically: true, encoding: .utf8)
        syncFileChangeBackToExternalMirror(localFileURL: targetURL, content: content)
        deletedGhostContents.removeValue(forKey: rel)

        if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
            let clampedLoc = min(openTabs[idx].selectedRangeLocation, (content as NSString).length)
            openTabs[idx].content = content
            openTabs[idx].savedContent = content
            openTabs[idx].selectedRangeLocation = clampedLoc
            openTabs[idx].selectedRangeLength = 0
        }

        reloadTree()
        onFileSavedOrChanged?()
    }

    public func applyRemoteDelete(relativePath rel: String) {
        guard isSafeRelativeSyncPath(rel) else { return }
        let targetURL = rootURL.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return }
        let prevSuppression = suppressOutboundSyncEvents
        suppressOutboundSyncEvents = true
        defer { suppressOutboundSyncEvents = prevSuppression }
        deleteItem(at: targetURL)
    }

    public func applyRemoteRename(oldRelativePath: String, newRelativePath: String) {
        guard isSafeRelativeSyncPath(oldRelativePath), isSafeRelativeSyncPath(newRelativePath) else { return }
        let srcURL = rootURL.appendingPathComponent(oldRelativePath)
        let dstURL = rootURL.appendingPathComponent(newRelativePath)
        guard FileManager.default.fileExists(atPath: srcURL.path) else { return }
        let prevSuppression = suppressOutboundSyncEvents
        suppressOutboundSyncEvents = true
        defer { suppressOutboundSyncEvents = prevSuppression }

        try? FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if srcURL.deletingLastPathComponent().standardizedFileURL == dstURL.deletingLastPathComponent().standardizedFileURL {
            renameItem(at: srcURL, to: dstURL.lastPathComponent)
        } else {
            try? FileManager.default.moveItem(at: srcURL, to: dstURL)
            if let oldIdx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == srcURL.standardizedFileURL }) {
                let oldTab = openTabs[oldIdx]
                var updated = OpenTab(fileURL: dstURL, content: oldTab.content, languageOverride: oldTab.languageOverride, isPinned: oldTab.isPinned)
                updated.savedContent = oldTab.savedContent
                openTabs[oldIdx] = updated
                if activeTabID == oldTab.id { activeTabID = updated.id }
            }
            reloadTree()
            onFileSavedOrChanged?()
        }
    }

    public func applyRemoteCreateDirectory(relativePath rel: String) {
        guard isSafeRelativeSyncPath(rel) else { return }
        let dirURL = rootURL.appendingPathComponent(rel, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        reloadTree()
    }

    public func applyRemoteFullSnapshot(_ files: [String: String]) {
        let prevSuppression = suppressOutboundSyncEvents
        suppressOutboundSyncEvents = true
        defer { suppressOutboundSyncEvents = prevSuppression }

        for (rel, content) in files {
            guard isSafeRelativeSyncPath(rel) else { continue }
            let targetURL = rootURL.appendingPathComponent(rel)
            if let existing = openTabs.first(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL })?.content
                ?? readTextWithEncodingFallback(from: targetURL),
               existing != content {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: existing, label: "PC Sync Pull")
            }
            try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: targetURL, atomically: true, encoding: .utf8)
            syncFileChangeBackToExternalMirror(localFileURL: targetURL, content: content)
            if let idx = openTabs.firstIndex(where: { $0.fileURL.standardizedFileURL == targetURL.standardizedFileURL }) {
                openTabs[idx].content = content
                openTabs[idx].savedContent = content
            }
        }
        reloadTree()
        onFileSavedOrChanged?()
    }

    // MARK: - 1-Tap Project Starter Templates
    @discardableResult
    public func scaffoldStarterTemplate(kind: ProjectStarterKind) -> URL {
        saveAllTabs()
        let folderName = "\(kind.folderPrefix)_\(Int(Date().timeIntervalSince1970) % 10000)"
        let target = documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let files: [String: String]
        switch kind {
        case .modernWebLanding:
            files = [
                "index.html": """
                <!DOCTYPE html>
                <html lang="vi">
                <head>
                  <meta charset="UTF-8" />
                  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
                  <title>\(folderName) - 3012 Live Web</title>
                  <link rel="stylesheet" href="styles.css" />
                </head>
                <body>
                  <main class="card">
                    <span class="tag">LIVE :5500</span>
                    <h1>\(folderName)</h1>
                    <p>Chỉnh sửa HTML/CSS/JS trong 3012 Mobile IDE và chia sẻ link ngay lập tức.</p>
                    <button id="actionBtn">Bấm thử tương tác</button>
                    <p id="statusText" class="muted"></p>
                  </main>
                  <script src="app.js"></script>
                </body>
                </html>
                """,
                "styles.css": """
                :root { color-scheme: dark; }
                * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
                body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0f172a; color: #f8fafc; padding: 20px; }
                .card { max-width: 440px; width: 100%; background: #1e293b; border: 1px solid #334155; border-radius: 16px; padding: 24px; }
                .tag { display: inline-block; font-size: 11px; font-weight: 700; padding: 4px 10px; border-radius: 999px; background: #0284c7; color: #fff; }
                button { width: 100%; padding: 12px; border: 0; border-radius: 10px; background: #10b981; color: #052e16; font-weight: 700; font-size: 15px; cursor: pointer; }
                .muted { color: #94a3b8; font-size: 13px; min-height: 18px; }
                """,
                "app.js": """
                let clicks = 0;
                const btn = document.getElementById("actionBtn");
                const statusText = document.getElementById("statusText");
                if (btn && statusText) {
                  btn.addEventListener("click", () => {
                    clicks += 1;
                    statusText.textContent = `Đã tương tác ${clicks} lần lúc ${new Date().toLocaleTimeString()}`;
                    console.log("Interactive click:", clicks);
                  });
                }
                """
            ]
        case .cppCompetitive:
            files = [
                "main.cpp": """
                #include <bits/stdc++.h>
                using namespace std;

                int main() {
                    ios::sync_with_stdio(false);
                    cin.tie(nullptr);

                    int n;
                    if (!(cin >> n)) return 0;
                    vector<long long> a(n);
                    for (int i = 0; i < n; ++i) cin >> a[i];
                    sort(a.begin(), a.end());
                    for (int i = 0; i < n; ++i) {
                        if (i) cout << ' ';
                        cout << a[i];
                    }
                    cout << '\\n';
                    return 0;
                }
                """,
                "input.txt": "5\n42 7 19 88 3\n",
                "README.md": "# C++20 Competitive Programming\n\n- Bấm **Run** để chạy nhanh ~1-2s qua Smart Execution Router.\n- Dùng **Developer Tools -> CP Multi-Test Judge** để chấm nhiều test case tự động.\n"
            ]
        case .pythonAutomation:
            files = [
                "main.py": """
                import json
                from datetime import datetime

                def build_summary(items):
                    return {
                        "total": len(items),
                        "sum": sum(items),
                        "avg": round(sum(items) / max(1, len(items)), 2),
                        "timestamp": datetime.utcnow().isoformat() + "Z",
                    }

                if __name__ == "__main__":
                    sample = [12, 25, 38, 44, 51]
                    print(json.dumps(build_summary(sample), ensure_ascii=False, indent=2))
                """,
                "requirements.txt": "requests>=2.31.0\n",
                "README.md": "# Python Automation Starter\n\nChạy Python 3.12 ổn định trong 1 chạm không lỗi PID 1.\n"
            ]
        case .markdownDocs:
            files = [
                "README.md": """
                # Tài Liệu Hệ Thống & Sơ Đồ Mermaid

                ## Luồng Đồng Bộ 2 Chiều PC <-> Mobile
                ```mermaid
                sequenceDiagram
                    participant PC as VS Code / PC Folder
                    participant Relay as 3012-pc-sync (Wi-Fi / 4G)
                    participant App as 3012 iOS IDE
                    PC->>Relay: Save file (fs.watch)
                    Relay->>App: WebSocket JSON upsert
                    App-->>PC: Auto-Save Patch (2-Way)
                ```
                """,
                "NOTES.md": "# Ghi chú nhanh\n\n- Bấm nút Preview khi đang mở `.md` để render đầy đủ Markdown & Mermaid.\n"
            ]
        }

        for (rel, body) in files {
            let fileURL = target.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? body.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        switchWorkspaceFolder(to: target)
        return target
    }
}
