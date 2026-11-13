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

    public var onFileSavedOrChanged: (() -> Void)?
    public var onAnyTabSavedWithURL: ((URL, String) -> Void)?

    public var activeTab: OpenTab? {
        guard let activeTabID else { return nil }
        return openTabs.first(where: { $0.id == activeTabID })
    }

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let defaultWorkspace = docs.appendingPathComponent("Workspace", isDirectory: true)
        self.rootURL = defaultWorkspace
        bootstrapDefaultWorkspaceIfNeeded(at: defaultWorkspace)
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
    }

    private func buildNodes(at directory: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var dirs: [FileNode] = []
        var files: [FileNode] = []

        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = buildNodes(at: url)
                dirs.append(FileNode(url: url, isDirectory: true, children: children))
            } else {
                files.append(FileNode(url: url, isDirectory: false, children: nil))
            }
        }

        dirs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return dirs + files
    }

    public func flattenFiles(in nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
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
        onFileSavedOrChanged?()
        onAnyTabSavedWithURL?(openTabs[idx].fileURL, openTabs[idx].content)
    }

    public func saveAllTabs() {
        for idx in openTabs.indices {
            try? openTabs[idx].content.write(to: openTabs[idx].fileURL, atomically: true, encoding: .utf8)
            openTabs[idx].savedContent = openTabs[idx].content
        }
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
        if let tab = openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            closeTab(tab.id)
        }
        try? FileManager.default.removeItem(at: url)
        reloadTree()
        onFileSavedOrChanged?()
    }

    public func renameItem(at url: URL, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
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
        reloadTree()
        if let first = flattenFiles(in: fileTree).first {
            openFile(at: first)
        }
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
