import Foundation
import UIKit
import JavaScriptCore
import Runestone

// MARK: - 1. Autocomplete Models
public enum CompletionKind: String {
    case snippet = "Snippet"
    case symbol = "Symbol"
    case keyword = "Keyword"
    case stdlib = "Stdlib"

    public var systemIcon: String {
        switch self {
        case .snippet: return "text.badge.plus"
        case .symbol: return "cube"
        case .keyword: return "chevron.left.forwardslash.chevron.right"
        case .stdlib: return "function"
        }
    }
}

public struct CompletionCandidate: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let insertText: String
    public let detail: String
    public let kind: CompletionKind
    public let replaceRange: NSRange

    public init(
        label: String,
        insertText: String,
        detail: String,
        kind: CompletionKind,
        replaceRange: NSRange
    ) {
        self.id = "\(kind.rawValue)-\(label)"
        self.label = label
        self.insertText = insertText
        self.detail = detail
        self.kind = kind
        self.replaceRange = replaceRange
    }
}

// MARK: - 2. Inline Diagnostics Models
public enum DiagnosticSeverity: String, Equatable {
    case error
    case warning

    public var systemIcon: String {
        switch self {
        case .error: return "xmark.octagon"
        case .warning: return "exclamationmark.triangle"
        }
    }
}

public struct EditorDiagnostic: Identifiable, Equatable {
    public let id: String
    public let line: Int        // 1-based line number
    public let column: Int      // 1-based column number
    public let severity: DiagnosticSeverity
    public let message: String
    public let range: NSRange   // UTF-16 range inside document for Runestone HighlightedRange

    public init(line: Int, column: Int = 1, severity: DiagnosticSeverity, message: String, range: NSRange) {
        self.id = "\(severity.rawValue)-\(line)-\(column)-\(message)"
        self.line = max(1, line)
        self.column = max(1, column)
        self.severity = severity
        self.message = message
        self.range = range
    }
}

// MARK: - 3. Symbol Outline & Breadcrumb Models
public struct DocumentSymbolItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let detail: String
    public let systemIcon: String
    public let line: Int        // 1-based line
    public let range: NSRange

    public init(name: String, detail: String, systemIcon: String, line: Int, range: NSRange) {
        self.id = "\(line)-\(name)"
        self.name = name
        self.detail = detail
        self.systemIcon = systemIcon
        self.line = line
        self.range = range
    }
}

// MARK: - 4. Code Intelligence Service
@MainActor
public final class CodeIntelligenceService: ObservableObject {
    @Published public var completions: [CompletionCandidate] = []
    @Published public var diagnostics: [EditorDiagnostic] = []
    @Published public var symbols: [DocumentSymbolItem] = []
    @Published public var activeBreadcrumbSymbol: String? = nil

    private var diagnosticsTask: Task<Void, Never>?

    public init() {}

    public var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    public func makeRunestoneHighlightedRanges(enabled: Bool) -> [HighlightedRange] {
        guard enabled, !diagnostics.isEmpty else { return [] }
        return diagnostics.compactMap { diag in
            guard diag.range.length > 0 else { return nil }
            let tint: UIColor = (diag.severity == .error)
                ? UIColor.systemRed.withAlphaComponent(0.28)
                : UIColor.systemOrange.withAlphaComponent(0.22)
            return HighlightedRange(
                id: diag.id,
                range: diag.range,
                color: tint,
                cornerRadius: 3
            )
        }
    }

    // MARK: - Live Code Completion
    public func updateCompletions(
        in text: String,
        selectedRange: NSRange,
        language: CodeLanguage,
        snippets: [CodeSnippetItem],
        enabled: Bool
    ) {
        guard enabled, selectedRange.length == 0 else {
            if !completions.isEmpty { completions = [] }
            return
        }
        let nsText = text as NSString
        let cursor = min(max(0, selectedRange.location), nsText.length)
        guard cursor > 0 else {
            if !completions.isEmpty { completions = [] }
            return
        }

        // Scan backwards for identifier prefix ([A-Za-z0-9_#@<!])
        var start = cursor
        while start > 0 {
            let ch = nsText.character(at: start - 1)
            guard let scalar = UnicodeScalar(ch) else { break }
            let isIdent = CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "#" || scalar == "@" || scalar == ":"
            if isIdent {
                start -= 1
            } else {
                break
            }
        }

        let prefixLen = cursor - start
        guard prefixLen >= 2 else {
            if !completions.isEmpty { completions = [] }
            return
        }

        let replaceRange = NSRange(location: start, length: prefixLen)
        let prefix = nsText.substring(with: replaceRange)
        let lowerPrefix = prefix.lowercased()

        var results: [CompletionCandidate] = []
        var seenLabels = Set<String>()

        // 1. Matching Snippets
        for snip in snippets where (snip.language == "all" || snip.language.lowercased() == language.defaultExtension || snip.language.lowercased() == language.rawValue.lowercased()) {
            if snip.prefix.lowercased().hasPrefix(lowerPrefix), snip.prefix != prefix {
                if seenLabels.insert(snip.prefix).inserted {
                    results.append(CompletionCandidate(
                        label: snip.prefix,
                        insertText: snip.body,
                        detail: snip.title,
                        kind: .snippet,
                        replaceRange: replaceRange
                    ))
                }
            }
        }

        // 2. Symbols / Identifiers in Current Document
        let identRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]{2,}\b"#)
        if let identRegex {
            let matches = identRegex.matches(in: text, range: NSRange(location: 0, length: min(nsText.length, 60_000)))
            for m in matches {
                let word = nsText.substring(with: m.range)
                if word != prefix && word.lowercased().hasPrefix(lowerPrefix) {
                    if seenLabels.insert(word).inserted {
                        results.append(CompletionCandidate(
                            label: word,
                            insertText: word,
                            detail: "Workspace Symbol",
                            kind: .symbol,
                            replaceRange: replaceRange
                        ))
                    }
                }
                if results.count >= 24 { break }
            }
        }

        // 3. Language Keywords & Stdlib APIs
        for (kw, detail, isStdlib) in Self.languageCatalog(for: language) {
            if kw != prefix && kw.lowercased().hasPrefix(lowerPrefix) {
                if seenLabels.insert(kw).inserted {
                    let insertion: String
                    if language == .html && !kw.hasPrefix("<") && detail == "HTML Tag" {
                        insertion = "<\(kw)></\(kw)>"
                    } else {
                        insertion = kw
                    }
                    results.append(CompletionCandidate(
                        label: kw,
                        insertText: insertion,
                        detail: detail,
                        kind: isStdlib ? .stdlib : .keyword,
                        replaceRange: replaceRange
                    ))
                }
            }
        }

        // Sort exact case-prefix matches first, then shorter labels
        results.sort { a, b in
            let aExact = a.label.hasPrefix(prefix)
            let bExact = b.label.hasPrefix(prefix)
            if aExact != bExact { return aExact && !bExact }
            if a.kind != b.kind && (a.kind == .snippet || b.kind == .snippet) {
                return a.kind == .snippet
            }
            return a.label.count < b.label.count
        }

        completions = Array(results.prefix(8))
    }

    public func clearCompletions() {
        if !completions.isEmpty {
            completions = []
        }
    }

    // MARK: - Debounced Live Diagnostics & Symbol Extraction
    public func scheduleAnalysis(
        code: String,
        language: CodeLanguage,
        fileName: String,
        cursorLocation: Int,
        diagnosticsEnabled: Bool,
        sshService: SSHWorkspaceService?
    ) {
        // Update symbols & breadcrumb synchronously if small, or inside task
        let extracted = Self.extractSymbols(from: code, language: language)
        self.symbols = extracted
        updateActiveBreadcrumb(cursorLocation: cursorLocation, in: code)

        diagnosticsTask?.cancel()
        guard diagnosticsEnabled else {
            if !diagnostics.isEmpty { diagnostics = [] }
            return
        }

        diagnosticsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000) // 420ms debounce
            guard !Task.isCancelled else { return }

            var found = Self.runFastOfflineDiagnostics(code: code, language: language)

            // If connected to SSH VPS and editing C/C++/Python, enrich with real compiler syntax check!
            if let ssh = sshService, ssh.isConnected, (language == .c || language == .cpp || language == .python) {
                let remoteDiags = await Self.runRemoteCompilerDiagnostics(
                    code: code,
                    language: language,
                    sshService: ssh
                )
                if !Task.isCancelled, !remoteDiags.isEmpty {
                    found = remoteDiags
                }
            }

            guard !Task.isCancelled else { return }
            self?.diagnostics = found
        }
    }

    public func updateActiveBreadcrumb(cursorLocation: Int, in code: String) {
        guard !symbols.isEmpty else {
            activeBreadcrumbSymbol = nil
            return
        }
        let ns = code as NSString
        let safeLoc = min(max(0, cursorLocation), ns.length)
        let prefix = ns.substring(to: safeLoc)
        let currentLine = prefix.components(separatedBy: "\n").count

        var currentSym: String? = nil
        for sym in symbols where sym.line <= currentLine {
            currentSym = sym.name
        }
        activeBreadcrumbSymbol = currentSym
    }

    // MARK: - Offline Real-Time Syntax & Lint Analyzer
    public static func runFastOfflineDiagnostics(code: String, language: CodeLanguage) -> [EditorDiagnostic] {
        let lines = code.components(separatedBy: "\n")
        let lineOffsets = computeLineUTF16Offsets(lines: lines)
        var issues: [EditorDiagnostic] = []

        func lineNSRange(_ oneBasedLine: Int) -> NSRange {
            let idx = min(max(0, oneBasedLine - 1), max(0, lines.count - 1))
            guard idx < lineOffsets.count else { return NSRange(location: 0, length: 0) }
            let len = (lines[idx] as NSString).length
            return NSRange(location: lineOffsets[idx], length: max(len, 1))
        }

        // 1. JSON Exact Parser Check
        if language == .json {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            do {
                _ = try JSONSerialization.jsonObject(with: Data(code.utf8), options: [.fragmentsAllowed])
                return []
            } catch let err as NSError {
                let debugDesc = (err.userInfo["NSDebugDescription"] as? String) ?? err.localizedDescription
                let lineNum = extractFirstInt(in: debugDesc, after: "line ") ?? extractFirstInt(in: debugDesc, after: "around line ") ?? 1
                issues.append(EditorDiagnostic(
                    line: lineNum,
                    severity: .error,
                    message: "JSON Syntax Error: \(debugDesc)",
                    range: lineNSRange(lineNum)
                ))
                return issues
            }
        }

        // 2. JavaScript Exact Syntax Check via iOS JavaScriptCore
        if language == .javascript {
            if let ctx = JSContext() {
                var jsSyntaxDiag: EditorDiagnostic?
                ctx.exceptionHandler = { _, exc in
                    guard let exc else { return }
                    let msg = exc.toString() ?? "JavaScript Syntax Error"
                    // Subtract 1 line for wrapper function header
                    let rawLine = Int(exc.forProperty("line")?.toInt32() ?? 2) - 1
                    let clampedLine = min(max(1, rawLine), max(1, lines.count))
                    jsSyntaxDiag = EditorDiagnostic(
                        line: clampedLine,
                        severity: .error,
                        message: msg,
                        range: lineNSRange(clampedLine)
                    )
                }
                let escaped = code
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "${", with: "\\${")
                _ = ctx.evaluateScript("new Function(`\\n\(escaped)\\n`);")
                if let diag = jsSyntaxDiag {
                    issues.append(diag)
                }
            }
        }

        // 3. HTML Unclosed / Mismatched Tag Check
        if language == .html {
            let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr", "!doctype"]
            let tagRegex = try? NSRegularExpression(pattern: #"<\s*(/?)\s*([a-zA-Z0-9!-]+)([^>]*?)(/?)>"#)
            var tagStack: [(name: String, line: Int)] = []
            if let tagRegex {
                for (i, line) in lines.enumerated() {
                    let nsLine = line as NSString
                    for m in tagRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                        let isClosing = nsLine.substring(with: m.range(at: 1)) == "/"
                        let rawTag = nsLine.substring(with: m.range(at: 2)).lowercased()
                        let selfClosing = nsLine.substring(with: m.range(at: 4)) == "/"
                        if rawTag.hasPrefix("!--") || voidTags.contains(rawTag) || selfClosing { continue }
                        if isClosing {
                            if let lastIdx = tagStack.lastIndex(where: { $0.name == rawTag }) {
                                // Any unclosed inner tags above lastIdx are errors
                                for unclosed in tagStack[(lastIdx + 1)...] {
                                    issues.append(EditorDiagnostic(
                                        line: unclosed.line,
                                        severity: .warning,
                                        message: "Thẻ <\(unclosed.name)> chưa được đóng trước </\(rawTag)>.",
                                        range: lineNSRange(unclosed.line)
                                    ))
                                }
                                tagStack.removeSubrange(lastIdx...)
                            } else {
                                issues.append(EditorDiagnostic(
                                    line: i + 1,
                                    severity: .error,
                                    message: "Thẻ đóng </\(rawTag)> dư thừa (không có thẻ mở tương ứng).",
                                    range: lineNSRange(i + 1)
                                ))
                            }
                        } else {
                            tagStack.append((rawTag, i + 1))
                        }
                    }
                }
                for leftover in tagStack.suffix(5) {
                    issues.append(EditorDiagnostic(
                        line: leftover.line,
                        severity: .warning,
                        message: "Thẻ <\(leftover.name)> chưa có thẻ đóng </\(leftover.name)>.",
                        range: lineNSRange(leftover.line)
                    ))
                }
            }
            return Array(issues.prefix(20))
        }

        // 4. Universal Comment/String-Aware Bracket Balance + Language Lint (C/C++/Python/TS/Swift/CSS/ObjC)
        if language != .markdown && language != .plainText {
            var stack: [(ch: Character, line: Int, col: Int)] = []
            let matchingOpen: [Character: Character] = [")": "(", "}": "{", "]": "["]
            let matchingClose: [Character: Character] = ["(": ")", "{": "}", "[": "]"]
            var inBlockComment = false

            for (idx, line) in lines.enumerated() {
                let lineNo = idx + 1
                let chars = Array(line)
                var cIdx = 0
                var inStringQuote: Character? = nil

                while cIdx < chars.count {
                    let c = chars[cIdx]
                    if inBlockComment {
                        if c == "*" && cIdx + 1 < chars.count && chars[cIdx + 1] == "/" {
                            inBlockComment = false
                            cIdx += 2
                            continue
                        }
                        cIdx += 1
                        continue
                    }

                    if let q = inStringQuote {
                        if c == "\\" {
                            cIdx += 2
                            continue
                        } else if c == q {
                            inStringQuote = nil
                        }
                        cIdx += 1
                        continue
                    }

                    // Line comments
                    if (language == .python || language == .shell) && c == "#" {
                        break
                    }
                    if c == "/" && cIdx + 1 < chars.count {
                        if chars[cIdx + 1] == "/" { break }
                        if chars[cIdx + 1] == "*" {
                            inBlockComment = true
                            cIdx += 2
                            continue
                        }
                    }

                    if c == "\"" || c == "'" || c == "`" {
                        // Skip Python triple quotes naive false positive
                        if cIdx + 2 < chars.count && chars[cIdx + 1] == c && chars[cIdx + 2] == c {
                            break
                        }
                        inStringQuote = c
                        cIdx += 1
                        continue
                    }

                    if c == "(" || c == "{" || c == "[" {
                        stack.append((c, lineNo, cIdx + 1))
                    } else if let expected = matchingOpen[c] {
                        if let top = stack.last, top.ch == expected {
                            stack.removeLast()
                        } else {
                            issues.append(EditorDiagnostic(
                                line: lineNo,
                                column: cIdx + 1,
                                severity: .error,
                                message: "Dấu ngoặc đóng '\(c)' không khớp.",
                                range: lineNSRange(lineNo)
                            ))
                        }
                    }
                    cIdx += 1
                }

                // Unclosed single-line string literal check (excluding backtick template literals)
                if let q = inStringQuote, q != "`" {
                    issues.append(EditorDiagnostic(
                        line: lineNo,
                        severity: .error,
                        message: "Chuỗi ký tự mở bằng \(q) chưa được đóng trên dòng \(lineNo).",
                        range: lineNSRange(lineNo)
                    ))
                }

                // Python block header colon check
                if language == .python {
                    let stripped = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let pyBlockRegex = #"^(def\s+\w+\(.*\)|class\s+\w+.*|if\s+.+|elif\s+.+|else|for\s+.+|while\s+.+|try|except.*|finally|with\s+.+)$"#
                    if !stripped.isEmpty,
                       !stripped.hasSuffix(":"),
                       !stripped.hasSuffix("\\"),
                       !stripped.hasSuffix(","),
                       !stripped.hasSuffix("("),
                       stripped.range(of: pyBlockRegex, options: .regularExpression) != nil {
                        issues.append(EditorDiagnostic(
                            line: lineNo,
                            severity: .error,
                            message: "Thiếu dấu ':' ở cuối câu lệnh khối Python.",
                            range: lineNSRange(lineNo)
                        ))
                    }
                }

                // C / C++ missing semicolon heuristic on return / #include errors
                if language == .c || language == .cpp || language == .objectiveC {
                    let trimmed = line.components(separatedBy: "//").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    if trimmed.hasPrefix("return ") && !trimmed.hasSuffix(";") && !trimmed.hasSuffix("{") && !trimmed.hasSuffix(",") {
                        issues.append(EditorDiagnostic(
                            line: lineNo,
                            severity: .warning,
                            message: "Có thể thiếu dấu ';' ở cuối lệnh return.",
                            range: lineNSRange(lineNo)
                        ))
                    }
                }
            }

            for unclosed in stack.suffix(8) {
                let want = matchingClose[unclosed.ch] ?? ")"
                issues.append(EditorDiagnostic(
                    line: unclosed.line,
                    column: unclosed.col,
                    severity: .error,
                    message: "Dấu '\(unclosed.ch)' mở tại dòng \(unclosed.line) chưa có dấu đóng '\(want)'.",
                    range: lineNSRange(unclosed.line)
                ))
            }
        }

        return Array(issues.prefix(25))
    }

    // MARK: - Remote VPS Compiler / LSP Diagnostics Parser
    private static func runRemoteCompilerDiagnostics(
        code: String,
        language: CodeLanguage,
        sshService: SSHWorkspaceService
    ) async -> [EditorDiagnostic] {
        let b64 = Data(code.utf8).base64EncodedString()
        let cmd: String
        switch language {
        case .cpp:
            cmd = "echo '\(b64)' | base64 -d | g++ -std=c++20 -fsyntax-only -Wall -x c++ - 2>&1"
        case .c:
            cmd = "echo '\(b64)' | base64 -d | gcc -std=c17 -fsyntax-only -Wall -x c - 2>&1"
        case .python:
            cmd = "mkdir -p /tmp/3012_diag && echo '\(b64)' | base64 -d > /tmp/3012_diag/live.py && python3 -m py_compile /tmp/3012_diag/live.py 2>&1"
        default:
            return []
        }

        let raw = await sshService.executeCommandOnVPS(cmd)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lines = code.components(separatedBy: "\n")
        let offsets = computeLineUTF16Offsets(lines: lines)
        func rangeForLine(_ l: Int) -> NSRange {
            let idx = min(max(0, l - 1), max(0, lines.count - 1))
            guard idx < offsets.count else { return NSRange(location: 0, length: 0) }
            return NSRange(location: offsets[idx], length: max((lines[idx] as NSString).length, 1))
        }

        var parsed: [EditorDiagnostic] = []
        // GCC/Clang format: <stdin>:12:5: error: expected ';' before '}' token
        let gccRegex = try? NSRegularExpression(pattern: #":(\d+):(\d+):\s*(fatal error|error|warning):\s*(.+)$"#)
        // Python py_compile format: File "...", line 8
        let pyLineRegex = try? NSRegularExpression(pattern: #"line\s+(\d+)"#)

        for outLine in trimmed.components(separatedBy: "\n") {
            let ns = outLine as NSString
            if let m = gccRegex?.firstMatch(in: outLine, range: NSRange(location: 0, length: ns.length)) {
                let lineNum = Int(ns.substring(with: m.range(at: 1))) ?? 1
                let colNum = Int(ns.substring(with: m.range(at: 2))) ?? 1
                let sevStr = ns.substring(with: m.range(at: 3))
                let msg = ns.substring(with: m.range(at: 4))
                parsed.append(EditorDiagnostic(
                    line: lineNum,
                    column: colNum,
                    severity: sevStr.contains("warning") ? .warning : .error,
                    message: msg,
                    range: rangeForLine(lineNum)
                ))
            } else if language == .python,
                      let pm = pyLineRegex?.firstMatch(in: outLine, range: NSRange(location: 0, length: ns.length)) {
                let lineNum = Int(ns.substring(with: pm.range(at: 1))) ?? 1
                parsed.append(EditorDiagnostic(
                    line: lineNum,
                    severity: .error,
                    message: trimmed.components(separatedBy: "\n").last ?? outLine,
                    range: rangeForLine(lineNum)
                ))
            }
        }
        return parsed
    }

    // MARK: - Symbol Outline Extractor (Functions, Classes, Structs, Markdown Headings, HTML Sections)
    public static func extractSymbols(from code: String, language: CodeLanguage) -> [DocumentSymbolItem] {
        let lines = code.components(separatedBy: "\n")
        let offsets = computeLineUTF16Offsets(lines: lines)
        var items: [DocumentSymbolItem] = []

        let patterns: [(regex: String, group: Int, kind: String, icon: String)]
        switch language {
        case .swift:
            patterns = [
                (#"\b(class|struct|enum|protocol|actor|extension)\s+([A-Za-z_][A-Za-z0-9_.]*)"#, 2, "Type", "cube"),
                (#"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, 1, "Function", "function")
            ]
        case .c, .cpp, .objectiveC:
            patterns = [
                (#"\b(class|struct|namespace|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#, 2, "Type", "cube"),
                (#"^\s*(?:[A-Za-z_][A-Za-z0-9_:<>\*\s&]+)\s+([A-Za-z_~][A-Za-z0-9_:]*)\s*\([^;]*\)\s*(?:const)?\s*\{"#, 1, "Function", "function")
            ]
        case .python:
            patterns = [
                (#"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#, 1, "Class", "cube"),
                (#"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, 1, "Function", "function")
            ]
        case .javascript, .typescript:
            patterns = [
                (#"\b(class|interface|type|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, 2, "Type", "cube"),
                (#"\b(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\("#, 1, "Function", "function"),
                (#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>"#, 1, "Arrow Fn", "function")
            ]
        case .html:
            patterns = [
                (#"<(header|nav|main|section|article|footer|form|script|style)[^>]*>"#, 1, "Section", "chevron.left.forwardslash.chevron.right"),
                (#"id\s*=\s*["']([^"']+)["']"#, 1, "#id", "number")
            ]
        case .css:
            patterns = [
                (#"^\s*([.#a-zA-Z][^{]+)\s*\{"#, 1, "Selector", "curlybraces")
            ]
        case .markdown:
            patterns = [
                (#"^(#{1,4}\s+.+)$"#, 1, "Heading", "list.bullet.indent")
            ]
        case .shell:
            patterns = [
                (#"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"#, 1, "Function", "terminal")
            ]
        default:
            patterns = []
        }

        let compiled = patterns.compactMap { pat -> (NSRegularExpression, Int, String, String)? in
            guard let rx = try? NSRegularExpression(pattern: pat.regex) else { return nil }
            return (rx, pat.group, pat.kind, pat.icon)
        }
        guard !compiled.isEmpty else { return [] }

        for (i, line) in lines.enumerated() {
            let nsLine = line as NSString
            guard nsLine.length > 0 else { continue }
            for (rx, grp, kind, icon) in compiled {
                if let m = rx.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                   m.numberOfRanges > grp {
                    let rawName = nsLine.substring(with: m.range(at: grp)).trimmingCharacters(in: .whitespaces)
                    let disallowed: Set<String> = ["if", "for", "while", "switch", "catch"]
                    guard !rawName.isEmpty, !disallowed.contains(rawName) else { continue }
                    let docRange = NSRange(location: offsets[i], length: nsLine.length)
                    items.append(DocumentSymbolItem(
                        name: rawName,
                        detail: "\(kind) • Line \(i + 1)",
                        systemIcon: icon,
                        line: i + 1,
                        range: docRange
                    ))
                    break
                }
            }
        }
        return items
    }

    // MARK: - Helpers & Keyword Catalog
    private static func computeLineUTF16Offsets(lines: [String]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(lines.count)
        var running = 0
        for line in lines {
            offsets.append(running)
            running += (line as NSString).length + 1 // +1 for '\n'
        }
        return offsets
    }

    private static func extractFirstInt(in text: String, after marker: String) -> Int? {
        guard let r = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let tail = text[r.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func languageCatalog(for language: CodeLanguage) -> [(String, String, Bool)] {
        switch language {
        case .cpp, .c, .objectiveC:
            return [
                ("#include", "Preprocessor", false), ("#define", "Preprocessor", false), ("#pragma once", "Header Guard", false),
                ("iostream", "C++ Stream Header", true), ("vector", "std::vector", true), ("string", "std::string", true),
                ("algorithm", "STL Algorithms", true), ("unordered_map", "Hash Map", true), ("map", "Balanced Tree Map", true),
                ("queue", "FIFO Queue", true), ("priority_queue", "Heap", true), ("cmath", "Math Library", true),
                ("std::cout", "Standard Output", true), ("std::cin", "Standard Input", true), ("std::endl", "Newline Flush", true),
                ("std::vector", "Dynamic Array", true), ("std::sort", "Sort Range", true), ("std::pair", "Tuple Pair", true),
                ("printf", "C Formatted Print", true), ("scanf", "C Formatted Input", true), ("malloc", "Heap Alloc", true),
                ("return", "Keyword", false), ("const", "Keyword", false), ("constexpr", "Keyword", false),
                ("auto", "Type Deduction", false), ("struct", "Keyword", false), ("class", "Keyword", false),
                ("namespace", "Keyword", false), ("template", "Keyword", false), ("typename", "Keyword", false),
                ("public:", "Access", false), ("private:", "Access", false), ("virtual", "Keyword", false),
                ("override", "Keyword", false), ("nullptr", "Null Pointer", false), ("sizeof", "Operator", false)
            ]
        case .python:
            return [
                ("def", "Function", false), ("class", "Class", false), ("import", "Import", false), ("from", "From Import", false),
                ("return", "Return", false), ("async", "Async", false), ("await", "Await", false), ("yield", "Generator", false),
                ("lambda", "Anonymous Fn", false), ("elif", "Conditional", false), ("except", "Exception", false), ("finally", "Finally", false),
                ("with", "Context Manager", false), ("assert", "Assertion", false), ("True", "Boolean", false), ("False", "Boolean", false), ("None", "NoneType", false),
                ("print", "Built-in", true), ("input", "Built-in", true), ("range", "Built-in", true), ("enumerate", "Built-in", true),
                ("len", "Built-in", true), ("sorted", "Built-in", true), ("zip", "Built-in", true), ("isinstance", "Built-in", true),
                ("__init__", "Constructor", true), ("__name__", "Module Name", true)
            ]
        case .javascript, .typescript:
            return [
                ("function", "Keyword", false), ("const", "Keyword", false), ("let", "Keyword", false), ("async", "Keyword", false),
                ("await", "Keyword", false), ("return", "Keyword", false), ("export", "ES Module", false), ("import", "ES Module", false),
                ("interface", "TS Interface", false), ("type", "TS Type", false), ("implements", "TS Keyword", false), ("readonly", "TS Keyword", false),
                ("console.log", "Console API", true), ("console.error", "Console API", true), ("document.querySelector", "DOM API", true),
                ("document.getElementById", "DOM API", true), ("addEventListener", "DOM Event", true), ("fetch", "Fetch HTTP API", true),
                ("JSON.stringify", "JSON API", true), ("JSON.parse", "JSON API", true), ("Promise.all", "Promise API", true),
                ("setTimeout", "Timer API", true), ("localStorage", "Web Storage", true)
            ]
        case .html:
            return [
                ("div", "HTML Tag", false), ("section", "HTML Tag", false), ("main", "HTML Tag", false), ("header", "HTML Tag", false),
                ("footer", "HTML Tag", false), ("nav", "HTML Tag", false), ("button", "HTML Tag", false), ("input", "HTML Tag", false),
                ("script", "HTML Tag", false), ("style", "HTML Tag", false), ("canvas", "HTML Tag", false), ("form", "HTML Tag", false),
                ("class=\"\"", "Attribute", true), ("id=\"\"", "Attribute", true), ("href=\"\"", "Attribute", true), ("src=\"\"", "Attribute", true)
            ]
        case .css:
            return [
                ("display: flex;", "Flexbox", true), ("display: grid;", "CSS Grid", true), ("justify-content: center;", "Layout", true),
                ("align-items: center;", "Layout", true), ("background-color:", "Color", true), ("border-radius:", "Border", true),
                ("padding:", "Spacing", true), ("margin:", "Spacing", true), ("box-shadow:", "Effect", true), ("transition:", "Animation", true),
                ("@media (max-width: 768px)", "Responsive", false), ("position: relative;", "Position", true)
            ]
        case .swift:
            return [
                ("import", "Keyword", false), ("struct", "Keyword", false), ("class", "Keyword", false), ("enum", "Keyword", false),
                ("protocol", "Keyword", false), ("extension", "Keyword", false), ("func", "Keyword", false), ("guard", "Keyword", false),
                ("async", "Concurrency", false), ("await", "Concurrency", false), ("throws", "Error", false), ("@Published", "Combine", true),
                ("@State", "SwiftUI", true), ("@MainActor", "Concurrency", true), ("VStack", "SwiftUI", true), ("HStack", "SwiftUI", true)
            ]
        default:
            return []
        }
    }
}
