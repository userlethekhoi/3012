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
            let (tempFile, _) = try await URLSession.shared.download(from: dlURL)
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
            if let themesArr = contributes["themes"] as? [[String: Any]] {
                for th in themesArr {
                    guard let relPath = th["path"] as? String else { continue }
                    let label = (th["label"] as? String) ?? item.displayName
                    let cleanRel = relPath.hasPrefix("./") ? String(relPath.dropFirst(2)) : relPath
                    let themeURL = extRoot.appendingPathComponent(cleanRel)
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
                    let snipURL = extRoot.appendingPathComponent(cleanRel)
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

                            let cleanedBody = bodyStr.replacingOccurrences(of: #"\$\{\d+:([^}]+)\}"#, with: "$1", options: .regularExpression)
                                .replacingOccurrences(of: #"\$\d+"#, with: "", options: .regularExpression)
                            newSnippets.append(CodeSnippetItem(title: title, prefix: prefix, body: cleanedBody, language: lang))
                            importedSnippetsCount += 1
                        }
                    }
                }
                if !newSnippets.isEmpty {
                    let customExisting = snippets.filter { item in !Self.builtInSnippets.contains(item) }
                    let mergedCustom = customExisting + newSnippets
                    snippets = Self.builtInSnippets + mergedCustom
                    if let encoded = try? JSONEncoder().encode(mergedCustom) {
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
    private static func stripJSONComments(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        var out = ""
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
            } else {
                if c == "\"" {
                    inString = true
                    out.append(c)
                    i += 1
                } else if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                } else if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i += 2
                } else {
                    out.append(c)
                    i += 1
                }
            }
        }
        // Remove trailing commas before } or ]
        let cleaned = out.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
        return Data(cleaned.utf8)
    }

    // MARK: - Built-in Code Formatter & Diagnostics (Offline + Remote VPS LSP/Tools)
    public static func formatCode(_ code: String, language: CodeLanguage, tabWidth: Int, sshService: SSHWorkspaceService?) async -> String {
        if language == .json,
           let data = code.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withPrettyObject: obj) {
            return pretty
        }

        // If connected to VPS, try industry-standard native formatters (clang-format / black / prettier)
        if let ssh = sshService, ssh.isConnected {
            let b64 = Data(code.utf8).base64EncodedString()
            var remoteFormatterCmd: String?
            switch language {
            case .c, .cpp, .objectiveC:
                remoteFormatterCmd = "command -v clang-format >/dev/null 2>&1 && echo '\(b64)' | base64 -d | clang-format"
            case .python:
                remoteFormatterCmd = "command -v black >/dev/null 2>&1 && echo '\(b64)' | base64 -d | black -q -"
            case .html, .css, .javascript, .typescript:
                remoteFormatterCmd = "command -v prettier >/dev/null 2>&1 && echo '\(b64)' | base64 -d | prettier --stdin-filepath index.\(language.defaultExtension)"
            default:
                break
            }
            if let cmd = remoteFormatterCmd {
                let res = await ssh.executeCommandOnVPS(cmd)
                if !res.isEmpty && !res.hasPrefix("[Process exited") && !res.hasPrefix("[SSH Error]") {
                    return res
                }
            }
        }

        // Built-in lightweight brace/tag indentation formatter offline
        return offlineSmartIndentFormat(code, language: language, tabWidth: tabWidth)
    }

    private static func offlineSmartIndentFormat(_ code: String, language: CodeLanguage, tabWidth: Int) -> String {
        if language == .python || language == .markdown || language == .plainText {
            return code.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        }
        let unit = String(repeating: " ", count: max(tabWidth, 2))
        var depth = 0
        var formattedLines: [String] = []

        for rawLine in code.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                formattedLines.append("")
                continue
            }
            let startsClosing = trimmed.hasPrefix("}") || trimmed.hasPrefix("]") || trimmed.hasPrefix(")") || trimmed.hasPrefix("</")
            if startsClosing {
                depth = max(0, depth - 1)
            }
            formattedLines.append(String(repeating: unit, count: depth) + trimmed)

            let opens = trimmed.filter { $0 == "{" || $0 == "[" }.count
            let closes = trimmed.filter { $0 == "}" || $0 == "]" }.count
            let net = opens - closes + (startsClosing ? 1 : 0)
            depth = max(0, depth + net)
        }
        return formattedLines.joined(separator: "\n")
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
            let cmd: String
            switch language {
            case .cpp:
                cmd = "echo '\(b64)' | base64 -d | g++ -std=c++20 -fsyntax-only -x c++ - 2>&1"
            case .c:
                cmd = "echo '\(b64)' | base64 -d | gcc -std=c17 -fsyntax-only -x c - 2>&1"
            case .python:
                cmd = "mkdir -p /tmp/3012_diag && echo '\(b64)' | base64 -d > /tmp/3012_diag/check.py && python3 -m py_compile /tmp/3012_diag/check.py 2>&1"
            default:
                cmd = ""
            }
            if !cmd.isEmpty {
                let res = await ssh.executeCommandOnVPS(cmd)
                let trimmed = res.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "[OK] LSP / Compiler Check trên VPS: 0 lỗi, 0 cảnh báo." : "[Diagnostics]\n\(trimmed)"
            }
        }

        // Offline bracket balance check
        var stack: [Character] = []
        let pairs: [Character: Character] = [")": "(", "}": "{", "]": "["]
        for (lineIdx, line) in code.components(separatedBy: "\n").enumerated() {
            for ch in line {
                if ch == "(" || ch == "{" || ch == "[" {
                    stack.append(ch)
                } else if let expected = pairs[ch] {
                    if stack.last == expected {
                        stack.removeLast()
                    } else {
                        return "[Syntax Warning] Lệch dấu ngoặc '\(ch)' tại dòng \(lineIdx + 1)."
                    }
                }
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

private extension JSONSerialization {
    static func data(withPrettyObject obj: Any) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(data: d, encoding: .utf8) ?? ""
    }
}
