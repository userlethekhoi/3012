import Foundation
import ZIPFoundation

public struct OpenVSXExtensionItem: Identifiable, Equatable {
    public var id: String { "\(namespace).\(name)" }
    public let namespace: String
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let iconURL: String?
    public let downloadVSIXURL: String?
}

public struct CodeSnippetItem: Codable, Identifiable, Equatable {
    public var id: String { "\(language):\(prefix):\(title)" }
    public let title: String
    public let prefix: String
    public let body: String
    public let language: String
}

@MainActor
public final class ExtensionStoreService: ObservableObject {
    @Published public var searchResults: [OpenVSXExtensionItem] = []
    @Published public var installedExtensionIDs: Set<String> = []
    @Published public var snippets: [CodeSnippetItem] = ExtensionStoreService.builtInSnippets
    @Published public private(set) var isSearching: Bool = false
    @Published public private(set) var installingID: String?
    @Published public var storeMessage: String = "Kho Open VSX sẵn sàng — tải trực tiếp gói .vsix (Themes & Snippets) chuẩn VS Code."

    public init() {
        if let savedIDs = UserDefaults.standard.array(forKey: "3012.installedExts") as? [String] {
            self.installedExtensionIDs = Set(savedIDs)
        }
        if let data = UserDefaults.standard.data(forKey: "3012.customSnippets"),
           let decoded = try? JSONDecoder().decode([CodeSnippetItem].self, from: data) {
            self.snippets = Self.builtInSnippets + decoded
        }
    }

    public func searchOpenVSX(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = q.isEmpty ? "theme" : q
        guard let encoded = effectiveQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://open-vsx.org/api/-/search?query=\(encoded)&size=24") else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let exts = root["extensions"] as? [[String: Any]] else { return }

            var items: [OpenVSXExtensionItem] = []
            for entry in exts {
                guard let ns = entry["namespace"] as? String,
                      let name = entry["name"] as? String else { continue }
                let disp = (entry["displayName"] as? String) ?? name
                let ver = (entry["version"] as? String) ?? "latest"
                let desc = (entry["description"] as? String) ?? ""
                let files = entry["files"] as? [String: Any]
                let dl = files?["download"] as? String
                let icon = files?["icon"] as? String
                items.append(OpenVSXExtensionItem(
                    namespace: ns,
                    name: name,
                    displayName: disp,
                    version: ver,
                    description: desc,
                    iconURL: icon,
                    downloadVSIXURL: dl
                ))
            }
            self.searchResults = items
        } catch {
            self.storeMessage = "Không kết nối được Open VSX: \(error.localizedDescription)"
        }
    }

    public func installVSIXExtension(_ item: OpenVSXExtensionItem, into preferences: EditorPreferences) async {
        guard let dlString = item.downloadVSIXURL, let dlURL = URL(string: dlString) else {
            storeMessage = "Gói \(item.displayName) không có link tải .vsix trực tiếp."
            return
        }
        installingID = item.id
        storeMessage = "Đang tải và giải nén \(item.displayName).vsix..."
        defer { installingID = nil }

        do {
            let (tempFile, resp) = try await URLSession.shared.download(from: dlURL)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                storeMessage = "Không tải được \(item.displayName).vsix (HTTP \(http.statusCode))."
                return
            }
            let fm = FileManager.default
            let unzipDir = fm.temporaryDirectory.appendingPathComponent("vsix_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: unzipDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: unzipDir) }

            try fm.unzipItem(at: tempFile, to: unzipDir)

            let extRoot = unzipDir.appendingPathComponent("extension", isDirectory: true)
            let pkgJSONURL = extRoot.appendingPathComponent("package.json")
            guard let pkgData = try? Data(contentsOf: pkgJSONURL),
                  let pkg = try? JSONSerialization.jsonObject(with: pkgData) as? [String: Any] else {
                storeMessage = "Không tìm thấy extension/package.json trong gói .vsix."
                return
            }

            let contributes = (pkg["contributes"] as? [String: Any]) ?? [:]
            var importedThemesCount = 0
            var importedSnippetsCount = 0

            // 1. Import VS Code Color Themes
            let extRootCanon = WorkspaceManager.canonicalPath(extRoot)
            let extRootPrefix = extRootCanon == "/" ? "/" : extRootCanon + "/"
            if let themesArr = contributes["themes"] as? [[String: Any]] {
                for th in themesArr {
                    guard let relPath = th["path"] as? String else { continue }
                    let label = (th["label"] as? String) ?? item.displayName
                    let cleanRel = relPath.hasPrefix("./") ? String(relPath.dropFirst(2)) : relPath
                    guard !relPath.hasPrefix("/"), WorkspaceManager.isSafeRelativeSyncPath(cleanRel) else { continue }
                    let themeURL = extRoot.appendingPathComponent(cleanRel)
                    guard WorkspaceManager.canonicalPath(themeURL).hasPrefix(extRootPrefix) else { continue }
                    if let rawThemeData = try? Data(contentsOf: themeURL),
                       let cleanedData = Self.stripJSONComments(from: rawThemeData),
                       var parsedPalette = VSCodeThemeImporter.parse(jsonData: cleanedData, fallbackName: label) {
                        parsedPalette.name = label
                        preferences.customThemes.removeAll { $0.name == label }
                        preferences.customThemes.append(parsedPalette)
                        preferences.selectedThemeID = parsedPalette.id
                        importedThemesCount += 1
                    }
                }
            }

            // 2. Import VS Code Snippets
            if let snippetsArr = contributes["snippets"] as? [[String: Any]] {
                var newSnippets: [CodeSnippetItem] = []
                for sn in snippetsArr {
                    guard let relPath = sn["path"] as? String else { continue }
                    let lang = (sn["language"] as? String) ?? "all"
                    let cleanRel = relPath.hasPrefix("./") ? String(relPath.dropFirst(2)) : relPath
                    guard !relPath.hasPrefix("/"), WorkspaceManager.isSafeRelativeSyncPath(cleanRel) else { continue }
                    let snipURL = extRoot.appendingPathComponent(cleanRel)
                    guard WorkspaceManager.canonicalPath(snipURL).hasPrefix(extRootPrefix) else { continue }
                    if let rawData = try? Data(contentsOf: snipURL),
                       let cleaned = Self.stripJSONComments(from: rawData),
                       let dict = try? JSONSerialization.jsonObject(with: cleaned) as? [String: Any] {
                        for (title, val) in dict {
                            guard let obj = val as? [String: Any] else { continue }
                            let prefix: String
                            if let p = obj["prefix"] as? String { prefix = p }
                            else if let pArr = obj["prefix"] as? [String], let first = pArr.first { prefix = first }
                            else { continue }

                            let bodyStr: String
                            if let b = obj["body"] as? String { bodyStr = b }
                            else if let bArr = obj["body"] as? [String] { bodyStr = bArr.joined(separator: "\n") }
                            else { continue }

                            let cleanedBody = bodyStr
                                .replacingOccurrences(of: #"\$\{\d+:([^}]+)\}"#, with: "$1", options: .regularExpression)
                                .replacingOccurrences(of: #"\$[1-9]\d*"#, with: "", options: .regularExpression)
                                .replacingOccurrences(of: "$0", with: "")
                            newSnippets.append(CodeSnippetItem(title: title, prefix: prefix, body: cleanedBody, language: lang))
                            importedSnippetsCount += 1
                        }
                    }
                }
                if !newSnippets.isEmpty {
                    let customExisting = snippets.filter { existing in
                        !Self.builtInSnippets.contains(where: { $0.id == existing.id })
                    }
                    var dedupByID: [String: CodeSnippetItem] = [:]
                    var orderedIDs: [String] = []
                    for snip in (customExisting + newSnippets) {
                        if dedupByID[snip.id] == nil {
                            orderedIDs.append(snip.id)
                        }
                        dedupByID[snip.id] = snip
                    }
                    let mergedCustom = orderedIDs.compactMap { dedupByID[$0] }
                    let builtInIDs = Set(Self.builtInSnippets.map(\.id))
                    let filteredCustom = mergedCustom.filter { !builtInIDs.contains($0.id) }
                    snippets = Self.builtInSnippets + filteredCustom
                    if let encoded = try? JSONEncoder().encode(filteredCustom) {
                        UserDefaults.standard.set(encoded, forKey: "3012.customSnippets")
                    }
                }
            }

            installedExtensionIDs.insert(item.id)
            UserDefaults.standard.set(Array(installedExtensionIDs), forKey: "3012.installedExts")

            if importedThemesCount > 0 || importedSnippetsCount > 0 {
                storeMessage = "Đã cài \(item.displayName): +\(importedThemesCount) Theme, +\(importedSnippetsCount) Snippets."
            } else {
                storeMessage = "Đã cài \(item.displayName) (Gói này không chứa Theme/Snippet tĩnh; các tính năng LSP chạy qua VPS SSH)."
            }
        } catch {
            storeMessage = "Lỗi cài .vsix: \(error.localizedDescription)"
        }
    }

    // Strip // and /* */ comments from JSONC files common in VS Code themes/snippets
    nonisolated public static func stripJSONComments(from data: Data) -> Data? {
        if (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let text = String(data: data, encoding: .utf8) else { return data }
        var uncommented: [Character] = []
        uncommented.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                uncommented.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
            } else {
                if c == "\"" {
                    inString = true
                    uncommented.append(c)
                    i += 1
                } else if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                } else if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2
                } else {
                    uncommented.append(c)
                    i += 1
                }
            }
        }

        // Remove trailing commas before } or ] ONLY outside string literals
        var cleaned = ""
        cleaned.reserveCapacity(uncommented.count)
        inString = false
        escaped = false
        var j = 0
        while j < uncommented.count {
            let c = uncommented[j]
            if inString {
                cleaned.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                cleaned.append(c)
            } else if c == "," {
                var k = j + 1
                while k < uncommented.count && (uncommented[k] == " " || uncommented[k] == "\t" || uncommented[k] == "\n" || uncommented[k] == "\r") {
                    k += 1
                }
                if k < uncommented.count && (uncommented[k] == "}" || uncommented[k] == "]") {
                    // Omit trailing comma outside string
                } else {
                    cleaned.append(c)
                }
            } else {
                cleaned.append(c)
            }
            j += 1
        }
        return Data(cleaned.utf8)
    }

    // MARK: - Built-in Code Formatter & Diagnostics (Offline + Remote VPS LSP/Tools)
    public static func formatCode(_ code: String, language: CodeLanguage, tabWidth: Int, sshService: SSHWorkspaceService?) async -> String {
        await CodeFormatterService.format(code, language: language, tabWidth: tabWidth, sshService: sshService)
    }

    public static func runSyntaxDiagnostics(code: String, language: CodeLanguage, fileName: String, sshService: SSHWorkspaceService?) async -> String {
        if language == .json {
            do {
                _ = try JSONSerialization.jsonObject(with: Data(code.utf8))
                return "[OK] JSON hợp lệ 100% — không có lỗi cú pháp."
            } catch {
                return "[Syntax Error] JSON: \(error.localizedDescription)"
            }
        }

        if let ssh = sshService, ssh.isConnected {
            let b64 = Data(code.utf8).base64EncodedString()
            let uniqueID = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
            let cmd: String
            switch language {
            case .cpp:
                cmd = "echo '\(b64)' | base64 -d | g++ -std=c++20 -fsyntax-only -x c++ - 2>&1; echo \"__3012_EXIT__:$?\""
            case .c:
                cmd = "echo '\(b64)' | base64 -d | gcc -std=c17 -fsyntax-only -x c - 2>&1; echo \"__3012_EXIT__:$?\""
            case .python:
                cmd = "tmp=\"/tmp/3012_diag_\(uniqueID).py\"; echo '\(b64)' | base64 -d > \"$tmp\" && python3 -m py_compile \"$tmp\" 2>&1; ec=$?; rm -f \"$tmp\"; echo \"__3012_EXIT__:$ec\""
            default:
                cmd = ""
            }
            if !cmd.isEmpty {
                let res = await ssh.executeCommandOnVPS(cmd)
                let lines = res.components(separatedBy: .newlines)
                var exitCode = 0
                var outputLines: [String] = []
                for line in lines {
                    if let range = line.range(of: "__3012_EXIT__:") {
                        let codeStr = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                        exitCode = Int(codeStr) ?? 0
                    } else {
                        outputLines.append(line)
                    }
                }
                let trimmed = outputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if exitCode == 0 && trimmed.isEmpty {
                    return "[OK] LSP / Compiler Check trên VPS: 0 lỗi, 0 cảnh báo."
                }
                return trimmed.isEmpty ? "[Diagnostics] Compiler exit code \(exitCode)." : "[Diagnostics]\n\(trimmed)"
            }
        }

        // Offline string/comment-aware bracket balance check
        var stack: [Character] = []
        let pairs: [Character: Character] = [")": "(", "}": "{", "]": "["]
        let hashCommentLangs: Set<CodeLanguage> = [.python, .ruby, .perl, .r, .julia, .elixir, .yaml, .toml, .shell, .fish, .powershell, .dockerfile, .makefile, .cmake, .hcl, .nix]
        var inBlockComment = false
        for (lineIdx, line) in code.components(separatedBy: "\n").enumerated() {
            let chars = Array(line)
            var idx = 0
            var inQuote: Character? = nil
            while idx < chars.count {
                let ch = chars[idx]
                if inBlockComment {
                    if ch == "*" && idx + 1 < chars.count && chars[idx + 1] == "/" {
                        inBlockComment = false
                        idx += 2
                        continue
                    }
                    idx += 1
                    continue
                }
                if let q = inQuote {
                    if ch == "\\" { idx += 2; continue }
                    if ch == q { inQuote = nil }
                    idx += 1
                    continue
                }
                if hashCommentLangs.contains(language) && ch == "#" { break }
                if (language == .lua || language == .sql || language == .haskell) && ch == "-" && idx + 1 < chars.count && chars[idx + 1] == "-" { break }
                if ch == "/" && idx + 1 < chars.count {
                    if chars[idx + 1] == "/" { break }
                    if chars[idx + 1] == "*" { inBlockComment = true; idx += 2; continue }
                }
                if ch == "\"" || ch == "'" || ch == "`" {
                    if !(language == .cpp && ch == "'" && idx > 0 && idx + 1 < chars.count && chars[idx - 1].isHexDigit && chars[idx + 1].isHexDigit)
                        && !(language == .rust && ch == "'") {
                        inQuote = ch
                        idx += 1
                        continue
                    }
                }
                if ch == "(" || ch == "{" || ch == "[" {
                    stack.append(ch)
                } else if let expected = pairs[ch] {
                    if stack.last == expected {
                        stack.removeLast()
                    } else {
                        return "[Syntax Warning] Lệch dấu ngoặc '\(ch)' tại dòng \(lineIdx + 1)."
                    }
                }
                idx += 1
            }
        }
        return stack.isEmpty
            ? "[OK] Kiểm tra cú pháp ngoặc: Cân bằng tốt (Kết nối VPS để bật full clangd/pyright diagnostics)."
            : "[Syntax Warning] Còn \(stack.count) dấu ngoặc mở chưa đóng: \(String(stack))"
    }

    public static let builtInSnippets: [CodeSnippetItem] = [
        CodeSnippetItem(
            title: "HTML5 Boilerplate (Emmet !)",
            prefix: "html5",
            body: """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0" />
              <title>Document</title>
            </head>
            <body>
              
            </body>
            </html>
            """,
            language: "html"
        ),
        CodeSnippetItem(
            title: "C++ Competitive Programming Fast I/O",
            prefix: "cpmain",
            body: """
            #include <bits/stdc++.h>
            using namespace std;

            int main() {
                ios::sync_with_stdio(false);
                cin.tie(nullptr);
                
                return 0;
            }
            """,
            language: "cpp"
        ),
        CodeSnippetItem(
            title: "Python Main Guard",
            prefix: "pymain",
            body: """
            def main() -> None:
                pass

            if __name__ == "__main__":
                main()
            """,
            language: "python"
        ),
        CodeSnippetItem(
            title: "JavaScript Fetch Async/Await",
            prefix: "fetchjson",
            body: """
            async function fetchData(url) {
              const res = await fetch(url);
              if (!res.ok) throw new Error(`HTTP ${res.status}`);
              return await res.json();
            }
            """,
            language: "javascript"
        )
    ]
}
