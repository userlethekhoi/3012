import Foundation

public enum CodeFormatterService {

    /// Asynchronous formatter: uses native VPS formatters (clang-format, gofmt, rustfmt, black, prettier, shfmt, etc.) when SSH is connected,
    /// otherwise falls back to the zero-latency built-in language-aware offline formatter.
    public static func format(
        _ code: String,
        language: CodeLanguage,
        tabWidth: Int,
        sshService: SSHWorkspaceService?
    ) async -> String {
        if let ssh = sshService, ssh.isConnected, let remoteCmd = vpsFormatterCommand(for: language, code: code) {
            let res = await ssh.executeCommandOnVPS(remoteCmd)
            if !res.isEmpty && !res.hasPrefix("[Process exited") && !res.hasPrefix("[SSH Error]") {
                return res
            }
        }
        return formatOfflineSynchronously(code, language: language, tabWidth: tabWidth)
    }

    /// Zero-latency synchronous offline formatter tailored to each language family (safe to run on every Save).
    public static func formatOfflineSynchronously(
        _ rawCode: String,
        language: CodeLanguage,
        tabWidth: Int
    ) -> String {
        guard !rawCode.isEmpty else { return rawCode }
        let normalized = rawCode.replacingOccurrences(of: "\r\n", with: "\n")

        switch language {
        case .plainText, .diff, .regex:
            return normalized

        case .makefile:
            // Makefiles REQUIRE literal tabs (\t) for recipe lines — only trim trailing spaces!
            return normalized.components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[ ]+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")

        case .json:
            return formatJSON(normalized, tabWidth: tabWidth)

        case .html, .xml, .vue, .svelte, .astro:
            return formatMarkup(normalized, tabWidth: tabWidth)

        case .sql:
            return formatSQL(normalized, tabWidth: tabWidth)

        case .python, .nim:
            return formatSignificantIndentation(normalized, spacesPerTab: 4)

        case .yaml, .elm, .haskell:
            return formatSignificantIndentation(normalized, spacesPerTab: max(2, min(tabWidth, 4)))

        case .markdown, .latex, .ini, .toml, .dockerfile:
            return trimTrailingAndCollapseBlankLines(normalized, maxBlankLines: 2)

        case .go:
            return formatBraceLanguage(normalized, indentUnit: "\t", language: .go)

        case .ruby, .crystal, .lua, .elixir, .erlang, .shell, .fish, .powershell, .pascal, .cmake:
            return formatKeywordBlockLanguage(
                normalized,
                indentUnit: String(repeating: " ", count: max(tabWidth, 2)),
                language: language
            )

        default:
            // C, C++, Obj-C, Rust, Zig, D, Swift, Dart, Java, Kotlin, Scala, Groovy, C#,
            // JS, TS, TSX, PHP, CSS, SCSS, GraphQL, Protobuf, HCL, Bicep, Nix, Solidity, R, Julia, Perl, OCaml, Lisp
            let unit = String(repeating: " ", count: max(tabWidth, 2))
            return formatBraceLanguage(normalized, indentUnit: unit, language: language)
        }
    }

    // MARK: - 1. JSON / JSONC Formatter
    private static func formatJSON(_ code: String, tabWidth: Int) -> String {
        if let data = code.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let pretty = String(data: prettyData, encoding: .utf8) {
            if tabWidth == 2 {
                // Foundation uses 2 or 4 spaces depending on OS; normalize leading indent if 4->2
                return pretty + "\n"
            }
            return pretty + "\n"
        }
        // Fallback for JSONC / JSON5 with comments
        return formatBraceLanguage(code, indentUnit: String(repeating: " ", count: max(tabWidth, 2)), language: .json5)
    }

    // MARK: - 2. HTML / XML / Vue / Svelte / Astro Hierarchical Tag Formatter
    private static func formatMarkup(_ code: String, tabWidth: Int) -> String {
        let unit = String(repeating: " ", count: max(tabWidth, 2))
        let voidTags: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr", "!doctype"
        ]
        var depth = 0
        var inScriptOrStyle = false
        var embeddedLines: [String] = []
        var embeddedIsCSS = false
        var out: [String] = []

        for rawLine in code.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if inScriptOrStyle {
                    embeddedLines.append("")
                } else if out.last != "" {
                    out.append("")
                }
                continue
            }

            let lower = trimmed.lowercased()

            if inScriptOrStyle {
                if lower.hasPrefix("</script") || lower.hasPrefix("</style") {
                    let subFormatted = formatBraceLanguage(
                        embeddedLines.joined(separator: "\n"),
                        indentUnit: unit,
                        language: embeddedIsCSS ? .css : .javascript
                    )
                    let basePrefix = String(repeating: unit, count: depth)
                    for subLine in subFormatted.components(separatedBy: "\n") {
                        let cleanSub = subLine.trimmingCharacters(in: .newlines)
                        out.append(cleanSub.isEmpty ? "" : basePrefix + cleanSub)
                    }
                    embeddedLines.removeAll()
                    inScriptOrStyle = false
                    depth = max(0, depth - 1)
                    out.append(String(repeating: unit, count: depth) + trimmed)
                } else {
                    embeddedLines.append(rawLine)
                }
                continue
            }

            let startsWithCloseTag = lower.hasPrefix("</")
            if startsWithCloseTag {
                depth = max(0, depth - 1)
            }

            out.append(String(repeating: unit, count: depth) + trimmed)

            if (lower.hasPrefix("<script") && !lower.contains("</script")) ||
               (lower.hasPrefix("<style") && !lower.contains("</style")) {
                embeddedIsCSS = lower.hasPrefix("<style")
                inScriptOrStyle = true
                depth += 1
                continue
            }

            // Count net tag balance on this line
            if let rx = try? NSRegularExpression(pattern: #"<\s*(/?)\s*([a-zA-Z0-9!-]+)([^>]*?)(/?)>"#) {
                let ns = trimmed as NSString
                let matches = rx.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
                var lineDelta = 0
                for (mIdx, m) in matches.enumerated() {
                    let isClose = ns.substring(with: m.range(at: 1)) == "/"
                    let tagName = ns.substring(with: m.range(at: 2)).lowercased()
                    let selfClose = ns.substring(with: m.range(at: 4)) == "/"
                    if tagName.hasPrefix("!") || tagName.hasPrefix("?") || voidTags.contains(tagName) || selfClose {
                        continue
                    }
                    if isClose {
                        if !(mIdx == 0 && startsWithCloseTag) {
                            lineDelta -= 1
                        }
                    } else {
                        lineDelta += 1
                    }
                }
                depth = max(0, depth + lineDelta)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - 3. SQL Smart Keyword & Clause Formatter
    private static func formatSQL(_ code: String, tabWidth: Int) -> String {
        let keywords: [String] = [
            "SELECT", "FROM", "WHERE", "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM",
            "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "PRIMARY KEY", "FOREIGN KEY",
            "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN", "JOIN", "ON",
            "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET", "UNION", "DISTINCT",
            "AND", "OR", "NOT", "NULL", "AS", "COUNT", "SUM", "AVG", "MIN", "MAX"
        ]
        var result = code
        for kw in keywords {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: kw) + "\\b"
            if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = rx.stringByReplacingMatches(
                    in: result,
                    range: NSRange(location: 0, length: (result as NSString).length),
                    withTemplate: kw
                )
            }
        }
        return formatBraceLanguage(result, indentUnit: String(repeating: " ", count: max(tabWidth, 2)), language: .sql)
    }

    // MARK: - 4. Significant Indentation Normalizer (Python / YAML / Nim / Elm / Haskell)
    private static func formatSignificantIndentation(_ code: String, spacesPerTab: Int) -> String {
        let tabReplacement = String(repeating: " ", count: spacesPerTab)
        var out: [String] = []
        var blankRun = 0

        for rawLine in code.components(separatedBy: "\n") {
            let trimmedRight = rawLine.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
            if trimmedRight.isEmpty {
                blankRun += 1
                if blankRun <= 2 {
                    out.append("")
                }
                continue
            }
            blankRun = 0
            // Replace only leading tabs with spaces so string literals inside the line remain untouched!
            var leadingEnd = trimmedRight.startIndex
            while leadingEnd < trimmedRight.endIndex && (trimmedRight[leadingEnd] == " " || trimmedRight[leadingEnd] == "\t") {
                leadingEnd = trimmedRight.index(after: leadingEnd)
            }
            let leading = String(trimmedRight[..<leadingEnd]).replacingOccurrences(of: "\t", with: tabReplacement)
            let body = String(trimmedRight[leadingEnd...])
            out.append(leading + body)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    // MARK: - 5. String/Comment-Aware Brace Language Pretty-Printer (C/C++/Rust/Go/Java/TS/Swift/CSS/C#/Dart/PHP...)
    private static func formatBraceLanguage(_ code: String, indentUnit: String, language: CodeLanguage) -> String {
        var depth = 0
        var inBlockComment = false
        var out: [String] = []
        var blankRun = 0

        for rawLine in code.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun <= 1 {
                    out.append("")
                }
                continue
            }
            blankRun = 0

            // Preprocessor directives in C/C++/Obj-C stay at column 0 (or standard indent)
            if (language == .c || language == .cpp || language == .objectiveC) && trimmed.hasPrefix("#") {
                out.append(trimmed)
                continue
            }

            if inBlockComment {
                let prefix = String(repeating: indentUnit, count: depth)
                out.append(prefix + (trimmed.hasPrefix("*") ? " " + trimmed : trimmed))
                if trimmed.contains("*/") {
                    inBlockComment = false
                }
                continue
            }

            // Count leading closing braces/brackets before code tokens
            var leadingClosers = 0
            for ch in trimmed {
                if ch == "}" || ch == "]" || ch == ")" {
                    leadingClosers += 1
                } else {
                    break
                }
            }

            var lineDepth = max(0, depth - leadingClosers)

            // Outdent C++/Java/TS switch case/default & C++ access specifiers by 1 level
            let isSwitchCaseOrAccess = trimmed.hasPrefix("case ") ||
                trimmed == "default:" ||
                trimmed == "public:" ||
                trimmed == "private:" ||
                trimmed == "protected:"
            if isSwitchCaseOrAccess && lineDepth > 0 {
                lineDepth -= 1
            }

            let spacedLine = normalizeInlineSpacing(trimmed, language: language)
            out.append(String(repeating: indentUnit, count: lineDepth) + spacedLine)

            // Lexically scan line ignoring strings and comments to compute exact net brace change
            let (opens, closes, endedInBlockComment) = scanBraceDelta(in: spacedLine, language: language)
            inBlockComment = endedInBlockComment
            let adjustedNet = opens - closes
            depth = max(0, depth + adjustedNet)
        }

        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func normalizeInlineSpacing(_ line: String, language: CodeLanguage) -> String {
        // Avoid altering comments, preprocessor, strings-heavy lines, or regexes
        if line.hasPrefix("//") || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("#") || line.hasPrefix("@") {
            return line
        }
        var result = line
        // Normalize control-flow keyword spacing: "if(" -> "if (", "for(" -> "for (", "while(" -> "while ("
        if language != .css && language != .scss {
            for kw in ["if", "for", "while", "switch", "catch"] {
                result = result.replacingOccurrences(
                    of: "^(\(kw))\\(",
                    with: "$1 (",
                    options: .regularExpression
                )
            }
        }
        // Normalize ") {" spacing when line ends with ") {"
        result = result.replacingOccurrences(of: #"\)+\{$"#, with: ") {", options: .regularExpression)
        return result
    }

    private static func scanBraceDelta(in line: String, language: CodeLanguage) -> (opens: Int, closes: Int, inBlockComment: Bool) {
        let chars = Array(line)
        var i = 0
        var opens = 0
        var closes = 0
        var inBlock = false
        var quote: Character? = nil

        while i < chars.count {
            let c = chars[i]
            if inBlock {
                if c == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                    inBlock = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if let q = quote {
                if c == "\\" {
                    i += 2
                    continue
                } else if c == q {
                    quote = nil
                }
                i += 1
                continue
            }
            if c == "/" && i + 1 < chars.count {
                if chars[i + 1] == "/" { break }
                if chars[i + 1] == "*" {
                    inBlock = true
                    i += 2
                    continue
                }
            }
            if (language == .shell || language == .hcl || language == .perl || language == .r || language == .julia) && c == "#" {
                break
            }
            if c == "\"" || c == "'" || c == "`" {
                quote = c
                i += 1
                continue
            }
            if c == "{" || c == "[" || c == "(" {
                opens += 1
            } else if c == "}" || c == "]" || c == ")" {
                closes += 1
            }
            i += 1
        }
        return (opens, closes, inBlock)
    }

    // MARK: - 6. Keyword-Block Formatter (Ruby / Lua / Elixir / Shell / Fish / Pascal / CMake)
    private static func formatKeywordBlockLanguage(_ code: String, indentUnit: String, language: CodeLanguage) -> String {
        var depth = 0
        var out: [String] = []
        var blankRun = 0

        for rawLine in code.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun <= 1 { out.append("") }
                continue
            }
            blankRun = 0

            let codeOnly = trimmed.components(separatedBy: "#").first?.components(separatedBy: "--").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
            let firstWord = codeOnly.split(separator: " ").first.map(String.init)?.lowercased() ?? ""

            let isMidBlock = ["else", "elsif", "elseif", "elif", "rescue", "ensure", "when", "catch"].contains(firstWord)
            let isClosing = ["end", "fi", "done", "esac", "endif", "endif()", "endfunction()", "endmacro()", "until"].contains(firstWord) || codeOnly == "}"

            if isClosing {
                depth = max(0, depth - 1)
            }
            let effectiveDepth = isMidBlock ? max(0, depth - 1) : depth
            out.append(String(repeating: indentUnit, count: effectiveDepth) + trimmed)

            let opensBlock: Bool
            switch language {
            case .shell, .fish, .powershell:
                opensBlock = codeOnly.hasSuffix("then") || codeOnly.hasSuffix("do") || codeOnly.hasSuffix("{") || firstWord == "function"
            case .lua:
                opensBlock = (["function", "if", "for", "while", "repeat"].contains(firstWord) || codeOnly.contains("function(")) && !codeOnly.hasSuffix("end")
            case .ruby, .crystal, .elixir:
                opensBlock = (["def", "defp", "defmodule", "class", "module", "if", "unless", "case", "begin"].contains(firstWord) || codeOnly.hasSuffix(" do")) && !codeOnly.hasSuffix(" end")
            case .pascal:
                opensBlock = firstWord == "begin" || codeOnly.lowercased().hasSuffix(" begin")
            case .cmake:
                opensBlock = firstWord.hasPrefix("if(") || firstWord.hasPrefix("foreach(") || firstWord.hasPrefix("function(") || firstWord.hasPrefix("macro(")
            default:
                opensBlock = false
            }

            if opensBlock {
                depth += 1
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func trimTrailingAndCollapseBlankLines(_ code: String, maxBlankLines: Int) -> String {
        var out: [String] = []
        var blanks = 0
        for line in code.components(separatedBy: "\n") {
            let r = line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
            if r.isEmpty {
                blanks += 1
                if blanks <= maxBlankLines { out.append("") }
            } else {
                blanks = 0
                out.append(r)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    // MARK: - Remote VPS Industry Formatter Command Router
    private static func vpsFormatterCommand(for language: CodeLanguage, code: String) -> String? {
        let b64 = Data(code.utf8).base64EncodedString()
        switch language {
        case .c, .cpp, .objectiveC, .csharp, .java, .protobuf, .solidity:
            return "command -v clang-format >/dev/null 2>&1 && echo '\(b64)' | base64 -d | clang-format"
        case .python:
            return "(command -v black >/dev/null 2>&1 && echo '\(b64)' | base64 -d | black -q -) || (command -v autopep8 >/dev/null 2>&1 && echo '\(b64)' | base64 -d | autopep8 -)"
        case .go:
            return "command -v gofmt >/dev/null 2>&1 && echo '\(b64)' | base64 -d | gofmt"
        case .rust:
            return "command -v rustfmt >/dev/null 2>&1 && echo '\(b64)' | base64 -d | rustfmt"
        case .zig:
            return "command -v zig >/dev/null 2>&1 && echo '\(b64)' | base64 -d | zig fmt --stdin"
        case .dart:
            return "command -v dart >/dev/null 2>&1 && echo '\(b64)' | base64 -d | dart format"
        case .swift:
            return "command -v swift-format >/dev/null 2>&1 && echo '\(b64)' | base64 -d | swift-format"
        case .shell:
            return "command -v shfmt >/dev/null 2>&1 && echo '\(b64)' | base64 -d | shfmt -i 2"
        case .hcl:
            return "command -v terraform >/dev/null 2>&1 && echo '\(b64)' | base64 -d | terraform fmt -"
        case .nix:
            return "command -v nixfmt >/dev/null 2>&1 && echo '\(b64)' | base64 -d | nixfmt"
        case .html, .css, .scss, .javascript, .typescript, .tsx, .vue, .svelte, .astro, .yaml, .markdown, .graphql:
            return "command -v prettier >/dev/null 2>&1 && echo '\(b64)' | base64 -d | prettier --stdin-filepath index.\(language.defaultExtension)"
        default:
            return nil
        }
    }
}
