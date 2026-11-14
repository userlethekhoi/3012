import Foundation
import UIKit
import JavaScriptCore
import Runestone

// MARK: - 1. VS Code-Grade IntelliSense Models
public enum CompletionKind: String, Sendable {
    case emmet = "Emmet"
    case snippet = "Snippet"
    case method = "Method"
    case function = "Function"
    case type = "Type"
    case property = "Property"
    case variable = "Symbol"
    case keyword = "Keyword"
    case module = "Header"

    public var systemIcon: String {
        switch self {
        case .emmet: return "chevron.left.forwardslash.chevron.right"
        case .snippet: return "text.badge.plus"
        case .method: return "cube.transparent"
        case .function: return "function"
        case .type: return "cube"
        case .property: return "slider.horizontal.3"
        case .variable: return "character.textbox"
        case .keyword: return "command"
        case .module: return "shippingbox"
        }
    }
}

public struct CompletionCandidate: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let insertText: String
    public let cursorOffsetInInsert: Int?
    public let detail: String
    public let kind: CompletionKind
    public let replaceRange: NSRange
    public let score: Int

    public init(
        label: String,
        rawTemplate: String,
        detail: String,
        kind: CompletionKind,
        replaceRange: NSRange,
        score: Int = 500
    ) {
        self.id = "\(kind.rawValue)-\(label)-\(detail)"
        self.label = label
        if let markerRange = rawTemplate.range(of: "$0") {
            let prefixStr = String(rawTemplate[..<markerRange.lowerBound])
            let cursorUTF16 = (prefixStr as NSString).length
            self.insertText = rawTemplate.replacingOccurrences(of: "$0", with: "")
            self.cursorOffsetInInsert = cursorUTF16
        } else {
            self.insertText = rawTemplate
            self.cursorOffsetInInsert = nil
        }
        self.detail = detail
        self.kind = kind
        self.replaceRange = replaceRange
        self.score = score
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

// MARK: - 3. Symbol Outline & Cross-File Signature Models
public struct DocumentSymbolItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let signature: String
    public let detail: String
    public let systemIcon: String
    public let line: Int
    public let range: NSRange

    public init(name: String, signature: String = "", detail: String, systemIcon: String, line: Int, range: NSRange) {
        self.id = "\(line)-\(name)"
        self.name = name
        self.signature = signature.isEmpty ? name : signature
        self.detail = detail
        self.systemIcon = systemIcon
        self.line = line
        self.range = range
    }
}

public struct WorkspaceIndexedSymbol: Equatable, Sendable {
    public let name: String
    public let signature: String
    public let kind: CompletionKind
    public let fileName: String
}

// MARK: - 4. Smart Code Intelligence Service
@MainActor
public final class CodeIntelligenceService: ObservableObject {
    @Published public var completions: [CompletionCandidate] = []
    @Published public var activeSignatureHint: String? = nil
    @Published public var diagnostics: [EditorDiagnostic] = []
    @Published public var symbols: [DocumentSymbolItem] = []
    @Published public var activeBreadcrumbSymbol: String? = nil

    private var diagnosticsTask: Task<Void, Never>?
    private var workspaceSymbols: [WorkspaceIndexedSymbol] = []
    private var recentAcceptedLabels: [String] = []

    public init() {}

    public var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }

    public func recordAcceptedCompletion(_ label: String) {
        recentAcceptedLabels.removeAll { $0 == label }
        recentAcceptedLabels.insert(label, at: 0)
        if recentAcceptedLabels.count > 30 {
            recentAcceptedLabels.removeLast()
        }
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

    // MARK: - Cross-File Workspace Symbol & Signature Indexer
    public func reindexWorkspaceFiles(_ fileURLs: [URL]) {
        let urls = Array(fileURLs.prefix(80))
        Task.detached(priority: .utility) {
            var collected: [WorkspaceIndexedSymbol] = []
            var seen = Set<String>()
            for url in urls {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lang = CodeLanguage.detect(from: url, contentSample: String(content.prefix(600)))
                let docSyms = CodeIntelligenceService.extractSymbols(from: content, language: lang)
                let fName = url.lastPathComponent
                for s in docSyms {
                    let key = "\(s.name)|\(fName)"
                    if seen.insert(key).inserted {
                        let k: CompletionKind = s.systemIcon == "function" ? .function : .type
                        collected.append(WorkspaceIndexedSymbol(
                            name: s.name,
                            signature: s.signature,
                            kind: k,
                            fileName: fName
                        ))
                    }
                }
            }
            let finalCollected = collected
            await MainActor.run { [weak self] in
                self?.workspaceSymbols = finalCollected
            }
        }
    }

    // MARK: - VS Code Dimmed Inline Ghost Preview Text Helper
    public static func ghostPreviewText(for candidate: CompletionCandidate, in text: String, cursor: Int) -> String? {
        let ns = text as NSString
        guard candidate.replaceRange.location >= 0,
              candidate.replaceRange.location + candidate.replaceRange.length <= ns.length,
              cursor == candidate.replaceRange.location + candidate.replaceRange.length else {
            return nil
        }

        func compactSingleLine(_ raw: String) -> String {
            let trimmed = raw.replacingOccurrences(of: #"\s*\n\s*"#, with: " ↵ ", options: .regularExpression)
            if trimmed.count > 68 {
                return String(trimmed.prefix(65)) + "..."
            }
            return trimmed
        }

        if candidate.replaceRange.length == 0 {
            let preview = compactSingleLine(candidate.insertText)
            return preview.isEmpty ? nil : preview
        }

        let typedPrefix = ns.substring(with: candidate.replaceRange)
        if let prefixRange = candidate.insertText.range(of: typedPrefix, options: [.caseInsensitive, .anchored]) {
            let remaining = String(candidate.insertText[prefixRange.upperBound...])
            let preview = compactSingleLine(remaining)
            return preview.isEmpty ? nil : preview
        }

        let fallback = compactSingleLine(candidate.insertText)
        return fallback.isEmpty ? nil : " → \(fallback)"
    }

    // MARK: - Embedded Web Block Detector (<style> -> CSS, <script> -> JS inside HTML/Vue/Svelte)
    private static func detectEmbeddedWebLanguage(nsText: NSString, cursor: Int, baseLanguage: CodeLanguage) -> CodeLanguage {
        guard [.html, .vue, .svelte, .astro].contains(baseLanguage), cursor > 0 else {
            return baseLanguage
        }
        let lookbackStart = max(0, cursor - 8000)
        let slice = nsText.substring(with: NSRange(location: lookbackStart, length: cursor - lookbackStart)).lowercased()

        func isInside(tag: String) -> Bool {
            guard let openMatch = slice.range(of: "<\(tag)(?=\\s|>)", options: [.regularExpression, .backwards]) else {
                return false
            }
            let closeMatch = slice.range(of: "</\(tag)", options: [.backwards])
            if let closeMatch, closeMatch.upperBound > openMatch.upperBound {
                return false
            }
            return slice[openMatch.upperBound...].contains(">")
        }

        if isInside(tag: "style") {
            return .css
        }
        if isInside(tag: "script") {
            return .javascript
        }
        return baseLanguage
    }

    // MARK: - Smart VS Code IntelliSense (Fuzzy + CamelCase + Member Dot/Scope + Emmet + HTML Tag/Attr + Signature Hints)
    public func updateCompletions(
        in text: String,
        selectedRange: NSRange,
        language: CodeLanguage,
        snippets: [CodeSnippetItem],
        enabled: Bool
    ) {
        guard enabled, selectedRange.length == 0 else {
            clearCompletions()
            return
        }
        let nsText = text as NSString
        let cursor = min(max(0, selectedRange.location), nsText.length)
        guard cursor > 0 else {
            clearCompletions()
            return
        }

        // Update Live Function Parameter Signature Help
        updateSignatureHelp(nsText: nsText, cursor: cursor)

        let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
        let linePrefix = nsText.substring(with: NSRange(location: lineRange.location, length: cursor - lineRange.location))
        let lineEnd = lineRange.location + lineRange.length
        let lineSuffix = lineEnd > cursor ? nsText.substring(with: NSRange(location: cursor, length: lineEnd - cursor)) : ""

        let isTypingClosingTag = linePrefix.range(of: #"</[A-Za-z0-9-]*$"#, options: .regularExpression) != nil
        let effectiveLanguage = isTypingClosingTag
            ? language
            : Self.detectEmbeddedWebLanguage(nsText: nsText, cursor: cursor, baseLanguage: language)

        // 1. Check C/C++ #include <header> context
        if (effectiveLanguage == .c || effectiveLanguage == .cpp || effectiveLanguage == .objectiveC),
           let incMatch = linePrefix.range(of: #"#include\s*[<"][A-Za-z0-9_./]*$"#, options: .regularExpression) {
            let fullMatch = String(linePrefix[incMatch])
            let headerQuery: String
            if let openIdx = fullMatch.lastIndex(where: { $0 == "<" || $0 == "\"" }) {
                headerQuery = String(fullMatch[fullMatch.index(after: openIdx)...])
            } else {
                headerQuery = ""
            }
            let repRange = NSRange(location: cursor - (headerQuery as NSString).length, length: (headerQuery as NSString).length)
            let headers = [
                "iostream", "vector", "string", "algorithm", "unordered_map", "unordered_set",
                "map", "set", "queue", "stack", "deque", "cmath", "numeric", "memory",
                "functional", "iomanip", "sstream", "fstream", "optional", "variant",
                "bits/stdc++.h", "stdio.h", "stdlib.h", "stdint.h", "stdbool.h", "string.h"
            ]
            completions = headers.compactMap { h -> CompletionCandidate? in
                guard headerQuery.isEmpty || Self.fuzzyScore(query: headerQuery, candidate: h) > 0 else { return nil }
                let closing = fullMatch.contains("<") ? ">" : "\""
                return CompletionCandidate(
                    label: h,
                    rawTemplate: "\(h)\(closing)$0",
                    detail: "Standard Header",
                    kind: .module,
                    replaceRange: repRange,
                    score: 1000
                )
            }
            return
        }

        // 1.5 Deep Step-by-Step HTML / XML / JSX Context (<tag>, attributes, values, auto-close)
        if [.html, .xml, .vue, .svelte, .astro, .tsx].contains(effectiveLanguage) {
            let htmlContextResults = Self.htmlContextCompletions(
                nsText: nsText,
                linePrefix: linePrefix,
                lineSuffix: lineSuffix,
                cursor: cursor
            )
            if !htmlContextResults.isEmpty {
                completions = htmlContextResults
                return
            }

            if let emmet = Self.tryExpandEmmet(linePrefix: linePrefix, cursor: cursor) {
                completions = [emmet]
                return
            }
        }

        // 2. CSS Property Value Context (after `property: ...`)
        if effectiveLanguage == .css || effectiveLanguage == .scss {
            if let cssValMatches = Self.cssValueCompletions(linePrefix: linePrefix, cursor: cursor), !cssValMatches.isEmpty {
                completions = cssValMatches
                return
            }
        }

        // 3. Check Member Access Trigger (`.` or `->` or `::`)
        if let memberCtx = Self.extractMemberAccessContext(linePrefix: linePrefix, cursor: cursor) {
            let memberItems = Self.memberCatalog(receiver: memberCtx.receiver, accessor: memberCtx.accessor, language: effectiveLanguage)
            var matched: [CompletionCandidate] = []
            for item in memberItems {
                let sc = memberCtx.memberPrefix.isEmpty ? 950 : Self.fuzzyScore(query: memberCtx.memberPrefix, candidate: item.label)
                if sc > 0 {
                    matched.append(CompletionCandidate(
                        label: item.label,
                        rawTemplate: item.template,
                        detail: item.detail,
                        kind: item.kind,
                        replaceRange: memberCtx.replaceRange,
                        score: sc
                    ))
                }
            }
            if !matched.isEmpty {
                matched.sort { $0.score > $1.score }
                completions = Array(matched.prefix(10))
                return
            }
        }

        // 4. General Identifier / Keyword / Fuzzy Subsequence / CamelCase Scan (1+ characters)
        let allowHyphen = (effectiveLanguage == .css || effectiveLanguage == .scss)
        var start = cursor
        while start > 0 {
            let ch = nsText.character(at: start - 1)
            guard let scalar = UnicodeScalar(ch) else { break }
            let isIdent = CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "#" || scalar == "@" || scalar == "$" || scalar == "%"
                || (allowHyphen && scalar == "-")
            if isIdent {
                start -= 1
            } else {
                break
            }
        }

        let prefixLen = cursor - start
        guard prefixLen >= 1 else {
            if !completions.isEmpty { completions = [] }
            return
        }

        let replaceRange = NSRange(location: start, length: prefixLen)
        let prefix = nsText.substring(with: replaceRange)

        var results: [CompletionCandidate] = []
        var seenLabels = Set<String>()

        func addCandidate(label: String, template: String, detail: String, kind: CompletionKind, bonus: Int = 0) {
            guard label.lowercased() != prefix.lowercased() else { return }
            let baseScore = Self.fuzzyScore(query: prefix, candidate: label)
            guard baseScore > 0 else { return }
            guard seenLabels.insert(label).inserted else { return }
            let recencyBonus = recentAcceptedLabels.contains(label) ? 140 : 0
            results.append(CompletionCandidate(
                label: label,
                rawTemplate: template,
                detail: detail,
                kind: kind,
                replaceRange: replaceRange,
                score: baseScore + bonus + recencyBonus
            ))
        }

        // A. Built-in & OpenVSX Snippets
        for snip in snippets where (snip.language == "all" || snip.language.lowercased() == effectiveLanguage.defaultExtension.lowercased() || snip.language.lowercased() == effectiveLanguage.rawValue.lowercased()) {
            addCandidate(label: snip.prefix, template: snip.body, detail: snip.title, kind: .snippet, bonus: 110)
        }

        // B. Smart Language Templates, Keywords & Stdlib APIs
        for entry in Self.smartLanguageCatalog(for: effectiveLanguage) {
            addCandidate(label: entry.label, template: entry.template, detail: entry.detail, kind: entry.kind, bonus: (entry.kind == .snippet || entry.kind == .emmet) ? 95 : 45)
        }

        // C. Current File Symbols with Exact Signatures
        for sym in symbols {
            let tpl = sym.systemIcon == "function" ? "\(sym.name)($0)" : sym.name
            let k: CompletionKind = sym.systemIcon == "function" ? .function : .type
            addCandidate(label: sym.name, template: tpl, detail: sym.signature, kind: k, bonus: 80)
        }

        // D. Cross-File Workspace Symbols
        for wSym in workspaceSymbols {
            let tpl = wSym.kind == .function ? "\(wSym.name)($0)" : wSym.name
            addCandidate(label: wSym.name, template: tpl, detail: "\(wSym.signature) • \(wSym.fileName)", kind: wSym.kind, bonus: 50)
        }

        // E. Identifiers in Active Buffer (Variables, Parameters, Local Names)
        if let identRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]{2,}\b"#) {
            let scanLen = min(nsText.length, 75_000)
            let matches = identRegex.matches(in: text, range: NSRange(location: 0, length: scanLen))
            for m in matches {
                let word = nsText.substring(with: m.range)
                addCandidate(label: word, template: word, detail: "Local Identifier", kind: .variable, bonus: 25)
                if results.count >= 45 { break }
            }
        }

        results.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.label.count < b.label.count
        }

        completions = Array(results.prefix(12))
    }

    public func clearCompletions() {
        if !completions.isEmpty { completions = [] }
        if activeSignatureHint != nil { activeSignatureHint = nil }
    }

    // MARK: - Live Parameter Signature Hint (VS Code Parameter Callout)
    private func updateSignatureHelp(nsText: NSString, cursor: Int) {
        let lookbackStart = max(0, cursor - 160)
        let slice = nsText.substring(with: NSRange(location: lookbackStart, length: cursor - lookbackStart))
        // Walk backwards to find an unclosed '('
        var parenDepth = 0
        let chars = Array(slice)
        var openParenIdx: Int? = nil
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            let c = chars[i]
            if c == ")" { parenDepth += 1 }
            else if c == "(" {
                if parenDepth == 0 {
                    openParenIdx = i
                    break
                } else {
                    parenDepth -= 1
                }
            } else if c == ";" || c == "{" || c == "}" {
                break
            }
        }
        guard let pIdx = openParenIdx, pIdx > 0 else {
            activeSignatureHint = nil
            return
        }
        var nameStart = pIdx
        while nameStart > 0 && (chars[nameStart - 1].isLetter || chars[nameStart - 1].isNumber || chars[nameStart - 1] == "_") {
            nameStart -= 1
        }
        let fnName = String(chars[nameStart..<pIdx])
        guard !fnName.isEmpty, !["if", "for", "while", "switch", "catch"].contains(fnName) else {
            activeSignatureHint = nil
            return
        }
        if let localMatch = symbols.first(where: { $0.name == fnName }) {
            activeSignatureHint = localMatch.signature
        } else if let wsMatch = workspaceSymbols.first(where: { $0.name == fnName }) {
            activeSignatureHint = "\(wsMatch.signature)  [\(wsMatch.fileName)]"
        } else {
            activeSignatureHint = nil
        }
    }

    // MARK: - VS Code Fuzzy & CamelCase Subsequence Scorer
    public static func fuzzyScore(query: String, candidate: String) -> Int {
        guard !query.isEmpty else { return 500 }
        if candidate == query { return 0 }
        let qLower = query.lowercased()
        let cLower = candidate.lowercased()

        // 1. Exact Case Prefix
        if candidate.hasPrefix(query) {
            return 1200 - min(candidate.count, 60)
        }
        // 2. Case-Insensitive Prefix
        if cLower.hasPrefix(qLower) {
            return 1080 - min(candidate.count, 60)
        }
        // 3. Suffix after namespace/dot (e.g. "cout" matches "std::cout")
        if let sep = cLower.lastIndex(where: { $0 == ":" || $0 == "." }),
           cLower[cLower.index(after: sep)...].hasPrefix(qLower) {
            return 1020 - min(candidate.count, 60)
        }

        // 4. CamelCase / snake_case Acronym & Boundary Subsequence Match
        let qChars = Array(qLower)
        let origChars = Array(candidate)
        let cChars = Array(cLower)
        var qIdx = 0
        var boundaryHits = 0
        var consecutiveHits = 0
        var lastMatchIdx = -2

        for (cIdx, ch) in cChars.enumerated() {
            if qIdx < qChars.count && ch == qChars[qIdx] {
                let isBoundary = (cIdx == 0)
                    || origChars[cIdx].isUppercase
                    || (cIdx > 0 && ["_", ".", ":", "-"].contains(origChars[cIdx - 1]))
                if isBoundary { boundaryHits += 1 }
                if cIdx == lastMatchIdx + 1 { consecutiveHits += 1 }
                lastMatchIdx = cIdx
                qIdx += 1
            }
        }

        guard qIdx == qChars.count else { return 0 }

        if boundaryHits == qChars.count {
            // Pure camelCase / snake_case acronym match like "gEBI" -> "getElementById" or "pb" -> "push_back"
            return 940 - min(candidate.count, 60)
        }
        if cLower.contains(qLower) {
            return 800 - min(candidate.count, 60)
        }
        // Require at least half the characters to be boundary or consecutive to avoid noisy matches
        if boundaryHits + consecutiveHits >= max(1, qChars.count - 1) {
            return 640 + (boundaryHits * 25) + (consecutiveHits * 15) - min(candidate.count, 60)
        }
        return 0
    }

    // MARK: - Deep Step-by-Step HTML / XML / JSX Context Completions
    private static func htmlContextCompletions(
        nsText: NSString,
        linePrefix: String,
        lineSuffix: String,
        cursor: Int
    ) -> [CompletionCandidate] {
        let voidTags: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"
        ]
        let blockTags: Set<String> = [
            "html", "head", "body", "div", "section", "main", "header", "footer",
            "nav", "article", "aside", "ul", "ol", "table", "thead", "tbody",
            "tr", "form", "select", "script", "style", "template"
        ]
        let nsPrefix = linePrefix as NSString

        // 1. Closing Tag Context: "</" or "</di"
        if let closeRx = try? NSRegularExpression(pattern: #"</([A-Za-z0-9-]*)$"#),
           let cm = closeRx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) {
            let fullMatchRange = cm.range
            let query = nsPrefix.substring(with: cm.range(at: 1)).lowercased()
            let repRange = NSRange(location: cursor - fullMatchRange.length, length: fullMatchRange.length)

            let beforeLen = max(0, cursor - fullMatchRange.length)
            let scanLen = min(beforeLen, 20_000)
            let scanStart = beforeLen - scanLen
            let scanSlice = nsText.substring(with: NSRange(location: scanStart, length: scanLen))

            var openStack: [String] = []
            if let tagRx = try? NSRegularExpression(pattern: #"<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9-]*)([^>]*?)(/?)>"#) {
                let nsSlice = scanSlice as NSString
                for tm in tagRx.matches(in: scanSlice, range: NSRange(location: 0, length: nsSlice.length)) {
                    let isClose = nsSlice.substring(with: tm.range(at: 1)) == "/"
                    let tName = nsSlice.substring(with: tm.range(at: 2)).lowercased()
                    let isSelfClose = nsSlice.substring(with: tm.range(at: 4)) == "/"
                    if voidTags.contains(tName) || isSelfClose { continue }
                    if isClose {
                        if let idx = openStack.lastIndex(of: tName) {
                            openStack.removeSubrange(idx...)
                        }
                    } else {
                        openStack.append(tName)
                    }
                }
            }

            var orderedTags: [String] = []
            var seen = Set<String>()
            for t in openStack.reversed() {
                if seen.insert(t).inserted { orderedTags.append(t) }
            }
            for fallback in ["div", "span", "p", "section", "button", "a", "li", "ul", "body", "html", "head", "style", "script"] {
                if seen.insert(fallback).inserted { orderedTags.append(fallback) }
            }

            var results: [CompletionCandidate] = []
            for (idx, tag) in orderedTags.enumerated() {
                let score: Int
                if query.isEmpty {
                    score = 1600 - idx * 20
                } else {
                    let fs = fuzzyScore(query: query, candidate: tag)
                    guard fs > 0 else { continue }
                    score = fs + (openStack.last == tag ? 350 : (openStack.contains(tag) ? 200 : 0))
                }
                results.append(CompletionCandidate(
                    label: "</\(tag)>",
                    rawTemplate: "</\(tag)>$0",
                    detail: openStack.last == tag ? "Close <\(tag)>" : "Closing Tag",
                    kind: .emmet,
                    replaceRange: repRange,
                    score: score
                ))
            }
            results.sort { $0.score > $1.score }
            return Array(results.prefix(8))
        }

        // 2. Auto-Close Immediately After Opening Tag: "<div class=\"card\">"
        let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespaces)
        if !trimmedPrefix.hasSuffix("/>"),
           let justClosedRx = try? NSRegularExpression(pattern: #"<\s*([A-Za-z][A-Za-z0-9-]*)(?:\s+[^<>]*)?>$"#),
           let jm = justClosedRx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) {
            let tag = nsPrefix.substring(with: jm.range(at: 1))
            let lowerTag = tag.lowercased()
            let trimmedSuffix = lineSuffix.trimmingCharacters(in: .whitespaces).lowercased()
            if !voidTags.contains(lowerTag) && !trimmedSuffix.hasPrefix("</\(lowerTag)") {
                let repRange = NSRange(location: cursor, length: 0)
                var items = [
                    CompletionCandidate(
                        label: "</\(tag)>",
                        rawTemplate: "$0</\(tag)>",
                        detail: "Auto-close <\(tag)>",
                        kind: .emmet,
                        replaceRange: repRange,
                        score: 1580
                    )
                ]
                if blockTags.contains(lowerTag) {
                    let indent = String(linePrefix.prefix { $0 == " " || $0 == "\t" })
                    items.append(CompletionCandidate(
                        label: "</\(tag)> (block)",
                        rawTemplate: "\n\(indent)  $0\n\(indent)</\(tag)>",
                        detail: "Multi-line <\(tag)>",
                        kind: .emmet,
                        replaceRange: repRange,
                        score: 1560
                    ))
                }
                return items
            }
        }

        // 3. Inside Unclosed Opening Tag: "<div " or "<input typ" or "<input type=\"b"
        if let openTagRx = try? NSRegularExpression(pattern: #"<\s*([A-Za-z][A-Za-z0-9-]*)(\s+[^<>]*)$"#),
           let om = openTagRx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) {
            let tag = nsPrefix.substring(with: om.range(at: 1)).lowercased()
            let attrTail = nsPrefix.substring(with: om.range(at: 2))
            let nsTail = attrTail as NSString

            // 3a. Inside attribute value quotes: attr="valPrefix
            if let valRx = try? NSRegularExpression(pattern: #"\s([A-Za-z][A-Za-z0-9-:]*)=["']([^"'<>]*)$"#),
               let vm = valRx.firstMatch(in: attrTail, range: NSRange(location: 0, length: nsTail.length)) {
                let attrName = nsTail.substring(with: vm.range(at: 1)).lowercased()
                let valQuery = nsTail.substring(with: vm.range(at: 2))
                let repRange = NSRange(location: cursor - (valQuery as NSString).length, length: (valQuery as NSString).length)
                let suggestions = htmlAttributeValues(for: attrName, tag: tag)
                var out: [CompletionCandidate] = []
                for (idx, val) in suggestions.enumerated() {
                    let sc = valQuery.isEmpty ? (1300 - idx * 10) : fuzzyScore(query: valQuery, candidate: val)
                    guard sc > 0 else { continue }
                    out.append(CompletionCandidate(
                        label: val,
                        rawTemplate: val,
                        detail: "\(attrName) value",
                        kind: .property,
                        replaceRange: repRange,
                        score: sc
                    ))
                }
                out.sort { $0.score > $1.score }
                return Array(out.prefix(10))
            }

            // 3b. Attribute name completion (only when quotes are balanced)
            let doubleQuotes = attrTail.filter { $0 == "\"" }.count
            let singleQuotes = attrTail.filter { $0 == "'" }.count
            if doubleQuotes % 2 == 0 && singleQuotes % 2 == 0,
               let attrRx = try? NSRegularExpression(pattern: #"([A-Za-z-]*)$"#),
               let am = attrRx.firstMatch(in: attrTail, range: NSRange(location: 0, length: nsTail.length)) {
                let attrQuery = nsTail.substring(with: am.range(at: 1))
                let repRange = NSRange(location: cursor - (attrQuery as NSString).length, length: (attrQuery as NSString).length)
                let catalog = htmlAttributesCatalog(for: tag)
                var out: [CompletionCandidate] = []
                for (idx, item) in catalog.enumerated() {
                    let sc = attrQuery.isEmpty ? (1320 - idx * 10) : fuzzyScore(query: attrQuery, candidate: item.label)
                    guard sc > 0 else { continue }
                    out.append(CompletionCandidate(
                        label: item.label,
                        rawTemplate: item.template,
                        detail: item.detail,
                        kind: .property,
                        replaceRange: repRange,
                        score: sc
                    ))
                }
                out.sort { $0.score > $1.score }
                return Array(out.prefix(10))
            }
        }

        // 4. Opening Tag Trigger: "<" or "<di" or "<!"
        if let tagStartRx = try? NSRegularExpression(pattern: #"<([!A-Za-z0-9-]*)$"#),
           let tm = tagStartRx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) {
            let fullMatch = tm.range
            let query = nsPrefix.substring(with: tm.range(at: 1))
            let repRange = NSRange(location: cursor - fullMatch.length, length: fullMatch.length)
            let tags = htmlTagCatalog()
            var out: [CompletionCandidate] = []
            for (idx, item) in tags.enumerated() {
                let sc: Int
                if query.isEmpty {
                    sc = 1480 - idx * 8
                } else {
                    let fs = fuzzyScore(query: query, candidate: item.tag)
                    guard fs > 0 else { continue }
                    sc = fs + 200
                }
                out.append(CompletionCandidate(
                    label: "<\(item.tag)>",
                    rawTemplate: item.template,
                    detail: item.detail,
                    kind: .emmet,
                    replaceRange: repRange,
                    score: sc
                ))
            }
            out.sort { $0.score > $1.score }
            return Array(out.prefix(12))
        }

        return []
    }

    private static func htmlTagCatalog() -> [(tag: String, template: String, detail: String)] {
        [
            ("div", "<div>$0</div>", "Container block"),
            ("div class", "<div class=\"$0\"></div>", "Div + class"),
            ("p", "<p>$0</p>", "Paragraph"),
            ("span", "<span>$0</span>", "Inline text"),
            ("h1", "<h1>$0</h1>", "Heading 1"),
            ("h2", "<h2>$0</h2>", "Heading 2"),
            ("h3", "<h3>$0</h3>", "Heading 3"),
            ("button", "<button type=\"button\">$0</button>", "Interactive button"),
            ("a", "<a href=\"$0\"></a>", "Hyperlink"),
            ("img", "<img src=\"$0\" alt=\"\" />", "Image element"),
            ("input", "<input type=\"text\" placeholder=\"$0\" />", "Form input"),
            ("form", "<form action=\"$0\" method=\"POST\">\n  \n</form>", "Form wrapper"),
            ("label", "<label for=\"$0\"></label>", "Input label"),
            ("textarea", "<textarea rows=\"4\" placeholder=\"$0\"></textarea>", "Multi-line text"),
            ("select", "<select name=\"$0\">\n  <option value=\"\"></option>\n</select>", "Dropdown select"),
            ("option", "<option value=\"$0\"></option>", "Select option"),
            ("ul", "<ul>\n  <li>$0</li>\n</ul>", "Unordered list"),
            ("ol", "<ol>\n  <li>$0</li>\n</ol>", "Ordered list"),
            ("li", "<li>$0</li>", "List item"),
            ("section", "<section>$0</section>", "Document section"),
            ("main", "<main>$0</main>", "Main content"),
            ("header", "<header>$0</header>", "Header section"),
            ("nav", "<nav>$0</nav>", "Navigation links"),
            ("article", "<article>$0</article>", "Article content"),
            ("aside", "<aside>$0</aside>", "Sidebar content"),
            ("footer", "<footer>$0</footer>", "Footer section"),
            ("table", "<table>\n  <thead>\n    <tr><th>$0</th></tr>\n  </thead>\n  <tbody>\n    <tr><td></td></tr>\n  </tbody>\n</table>", "HTML Table"),
            ("tr", "<tr>\n  <td>$0</td>\n</tr>", "Table row"),
            ("td", "<td>$0</td>", "Table cell"),
            ("th", "<th>$0</th>", "Table header cell"),
            ("script", "<script src=\"$0\"></script>", "External JS"),
            ("script inline", "<script>\n  $0\n</script>", "Inline JavaScript"),
            ("style", "<style>\n  $0\n</style>", "Inline CSS"),
            ("link", "<link rel=\"stylesheet\" href=\"$0style.css\" />", "Stylesheet link"),
            ("meta", "<meta name=\"$0\" content=\"\" />", "Metadata tag"),
            ("title", "<title>$0</title>", "Document title"),
            ("head", "<head>\n  <meta charset=\"UTF-8\" />\n  <title>$0</title>\n</head>", "Document head"),
            ("body", "<body>\n  $0\n</body>", "Document body"),
            ("!DOCTYPE html", "<!DOCTYPE html>\n<html lang=\"vi\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <title>$0</title>\n</head>\n<body>\n  \n</body>\n</html>", "HTML5 Skeleton"),
            ("br", "<br />", "Line break"),
            ("hr", "<hr />", "Horizontal rule"),
            ("iframe", "<iframe src=\"$0\" frameborder=\"0\"></iframe>", "Embedded frame"),
            ("canvas", "<canvas id=\"$0\" width=\"400\" height=\"300\"></canvas>", "2D/WebGL Canvas"),
            ("video", "<video src=\"$0\" controls></video>", "Video player"),
            ("audio", "<audio src=\"$0\" controls></audio>", "Audio player"),
            ("strong", "<strong>$0</strong>", "Bold importance"),
            ("code", "<code>$0</code>", "Inline code"),
            ("pre", "<pre><code>$0</code></pre>", "Code block")
        ]
    }

    private static func htmlAttributesCatalog(for tag: String) -> [(label: String, template: String, detail: String)] {
        var specific: [(String, String, String)] = []
        switch tag {
        case "a":
            specific = [
                ("href", "href=\"$0\"", "Link URL"),
                ("target", "target=\"_blank$0\"", "Open window/tab"),
                ("rel", "rel=\"noopener noreferrer$0\"", "Link relation"),
                ("download", "download=\"$0\"", "Download filename")
            ]
        case "img":
            specific = [
                ("src", "src=\"$0\"", "Image URL/path"),
                ("alt", "alt=\"$0\"", "Alternative text"),
                ("width", "width=\"$0\"", "Image width"),
                ("height", "height=\"$0\"", "Image height"),
                ("loading", "loading=\"lazy$0\"", "Lazy loading")
            ]
        case "link":
            specific = [
                ("rel", "rel=\"stylesheet$0\"", "Relation"),
                ("href", "href=\"$0\"", "Stylesheet URL"),
                ("type", "type=\"text/css$0\"", "MIME type")
            ]
        case "script":
            specific = [
                ("src", "src=\"$0\"", "Script file path"),
                ("type", "type=\"module$0\"", "ES Module / script type"),
                ("defer", "defer", "Defer execution"),
                ("async", "async", "Async download")
            ]
        case "input":
            specific = [
                ("type", "type=\"text$0\"", "Input type"),
                ("placeholder", "placeholder=\"$0\"", "Hint text"),
                ("name", "name=\"$0\"", "Field name"),
                ("value", "value=\"$0\"", "Initial value"),
                ("required", "required", "Required field"),
                ("disabled", "disabled", "Disable input"),
                ("autocomplete", "autocomplete=\"$0\"", "Browser autofill")
            ]
        case "button":
            specific = [
                ("type", "type=\"button$0\"", "button / submit / reset"),
                ("onclick", "onclick=\"$0\"", "Click handler"),
                ("disabled", "disabled", "Disable button")
            ]
        case "form":
            specific = [
                ("action", "action=\"$0\"", "Submit endpoint"),
                ("method", "method=\"POST$0\"", "HTTP method"),
                ("onsubmit", "onsubmit=\"$0\"", "Submit handler")
            ]
        case "meta":
            specific = [
                ("charset", "charset=\"UTF-8\"", "Document encoding"),
                ("name", "name=\"viewport$0\"", "Metadata key"),
                ("content", "content=\"$0\"", "Metadata content")
            ]
        case "label":
            specific = [("for", "for=\"$0\"", "Target input id")]
        case "video", "audio":
            specific = [
                ("src", "src=\"$0\"", "Media URL"),
                ("controls", "controls", "Show media controls"),
                ("autoplay", "autoplay", "Auto play"),
                ("loop", "loop", "Loop playback"),
                ("muted", "muted", "Mute audio")
            ]
        default:
            break
        }

        let globals: [(String, String, String)] = [
            ("class", "class=\"$0\"", "CSS classes"),
            ("id", "id=\"$0\"", "Unique element ID"),
            ("style", "style=\"$0\"", "Inline CSS style"),
            ("onclick", "onclick=\"$0\"", "Click JS handler"),
            ("oninput", "oninput=\"$0\"", "Input JS handler"),
            ("onchange", "onchange=\"$0\"", "Change JS handler"),
            ("title", "title=\"$0\"", "Hover tooltip"),
            ("data-", "data-$0=\"\"", "Custom data attribute"),
            ("aria-label", "aria-label=\"$0\"", "Accessibility label"),
            ("hidden", "hidden", "Hide element")
        ]
        var seen = Set<String>()
        return (specific + globals).filter { seen.insert($0.0).inserted }
    }

    private static func htmlAttributeValues(for attr: String, tag: String) -> [String] {
        switch attr {
        case "type":
            if tag == "button" { return ["button", "submit", "reset"] }
            if tag == "script" { return ["module", "text/javascript", "application/json"] }
            if tag == "link" { return ["text/css", "image/x-icon"] }
            return ["text", "button", "submit", "password", "email", "number", "checkbox", "radio", "file", "search", "date", "range", "hidden"]
        case "rel":
            return ["stylesheet", "icon", "noopener noreferrer", "preload", "preconnect", "canonical"]
        case "target":
            return ["_blank", "_self", "_parent", "_top"]
        case "method":
            return ["POST", "GET", "dialog"]
        case "loading":
            return ["lazy", "eager"]
        case "charset":
            return ["UTF-8"]
        case "lang":
            return ["vi", "en", "ja", "ko", "zh-CN"]
        case "name":
            return tag == "meta" ? ["viewport", "description", "keywords", "author", "theme-color"] : ["username", "email", "password", "search"]
        default:
            return []
        }
    }

    // MARK: - CSS Property Value Completion (`.css`, `.scss`, `<style>`)
    private static func cssValueCompletions(linePrefix: String, cursor: Int) -> [CompletionCandidate]? {
        let nsPrefix = linePrefix as NSString
        guard let rx = try? NSRegularExpression(pattern: #"([a-zA-Z-]+)\s*:\s*([^;{}]*)$"#),
              let m = rx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) else {
            return nil
        }
        let prop = nsPrefix.substring(with: m.range(at: 1)).lowercased()
        let valPrefix = nsPrefix.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        let repLen = (nsPrefix.substring(with: m.range(at: 2)) as NSString).length
        let repRange = NSRange(location: cursor - repLen, length: repLen)

        let values: [String]
        switch prop {
        case "display":
            values = ["flex", "grid", "block", "inline-flex", "inline-block", "none"]
        case "position":
            values = ["relative", "absolute", "fixed", "sticky", "static"]
        case "justify-content":
            values = ["center", "space-between", "space-around", "flex-start", "flex-end", "space-evenly"]
        case "align-items":
            values = ["center", "flex-start", "flex-end", "stretch", "baseline"]
        case "flex-direction":
            values = ["row", "column", "row-reverse", "column-reverse"]
        case "text-align":
            values = ["center", "left", "right", "justify"]
        case "cursor":
            values = ["pointer", "default", "not-allowed", "grab", "text"]
        case "overflow", "overflow-x", "overflow-y":
            values = ["hidden", "auto", "scroll", "visible"]
        case "box-sizing":
            values = ["border-box", "content-box"]
        case "font-weight":
            values = ["600", "700", "500", "400", "bold", "normal"]
        default:
            return nil
        }

        var out: [CompletionCandidate] = []
        for (idx, val) in values.enumerated() {
            let sc = valPrefix.isEmpty ? (1250 - idx * 10) : fuzzyScore(query: valPrefix, candidate: val)
            guard sc > 0 else { continue }
            out.append(CompletionCandidate(
                label: val,
                rawTemplate: "\(val);$0",
                detail: "\(prop) value",
                kind: .property,
                replaceRange: repRange,
                score: sc
            ))
        }
        out.sort { $0.score > $1.score }
        return out.isEmpty ? nil : out
    }

    // MARK: - Emmet HTML / JSX Abbreviation Expander
    private static func tryExpandEmmet(linePrefix: String, cursor: Int) -> CompletionCandidate? {
        let trimmedLeft = linePrefix.trimmingCharacters(in: .whitespaces)
        guard !trimmedLeft.isEmpty, !trimmedLeft.contains(" "), !trimmedLeft.hasPrefix("<") else { return nil }

        let repLen = (trimmedLeft as NSString).length
        let repRange = NSRange(location: cursor - repLen, length: repLen)

        if trimmedLeft == "!" {
            let html5 = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1.0" />
              <title>$0Document</title>
            </head>
            <body>
              
            </body>
            </html>
            """
            return CompletionCandidate(label: "! (HTML5 Boilerplate)", rawTemplate: html5, detail: "Emmet Abbreviation", kind: .emmet, replaceRange: repRange, score: 1400)
        }

        // ul>li*N pattern
        if let multRx = try? NSRegularExpression(pattern: #"^([a-zA-Z][a-zA-Z0-9]*)>([a-zA-Z][a-zA-Z0-9]*)\*(\d{1,2})$"#),
           let m = multRx.firstMatch(in: trimmedLeft, range: NSRange(location: 0, length: repLen)) {
            let ns = trimmedLeft as NSString
            let parent = ns.substring(with: m.range(at: 1))
            let child = ns.substring(with: m.range(at: 2))
            let count = min(max(Int(ns.substring(with: m.range(at: 3))) ?? 3, 1), 12)
            let children = (0..<count).map { idx in
                idx == 0 ? "  <\(child)>$0</\(child)>" : "  <\(child)></\(child)>"
            }.joined(separator: "\n")
            let expanded = "<\(parent)>\n\(children)\n</\(parent)>"
            return CompletionCandidate(label: trimmedLeft, rawTemplate: expanded, detail: "Emmet Repeat", kind: .emmet, replaceRange: repRange, score: 1380)
        }

        // tag.class1.class2 or tag#id.class or .class
        if let tagClassRx = try? NSRegularExpression(pattern: #"^([a-zA-Z][a-zA-Z0-9]*)?(#[a-zA-Z0-9_-]+)?((\.[a-zA-Z0-9_-]+)+)$"#),
           let m = tagClassRx.firstMatch(in: trimmedLeft, range: NSRange(location: 0, length: repLen)) {
            let ns = trimmedLeft as NSString
            let tag = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : "div"
            let idPart = m.range(at: 2).location != NSNotFound ? String(ns.substring(with: m.range(at: 2)).dropFirst()) : nil
            let classesPart = ns.substring(with: m.range(at: 3)).split(separator: ".").joined(separator: " ")
            var attrs = ""
            if let idPart { attrs += " id=\"\(idPart)\"" }
            if !classesPart.isEmpty { attrs += " class=\"\(classesPart)\"" }
            let expanded = "<\(tag)\(attrs)>$0</\(tag)>"
            return CompletionCandidate(label: trimmedLeft, rawTemplate: expanded, detail: "Emmet → <\(tag)\(attrs)>", kind: .emmet, replaceRange: repRange, score: 1360)
        }

        return nil
    }

    // MARK: - Member Access Context Extractor (`.` / `->` / `::`)
    private static func extractMemberAccessContext(linePrefix: String, cursor: Int) -> (receiver: String, accessor: String, memberPrefix: String, replaceRange: NSRange)? {
        let pattern = #"([A-Za-z_][A-Za-z0-9_.]*)(\.|->|::)([A-Za-z0-9_]*)$"#
        guard let rx = try? NSRegularExpression(pattern: pattern),
              let m = rx.firstMatch(in: linePrefix, range: NSRange(location: 0, length: (linePrefix as NSString).length)) else {
            return nil
        }
        let ns = linePrefix as NSString
        let receiver = ns.substring(with: m.range(at: 1))
        let accessor = ns.substring(with: m.range(at: 2))
        let memberPrefix = ns.substring(with: m.range(at: 3))
        let memLen = (memberPrefix as NSString).length
        let repRange = NSRange(location: cursor - memLen, length: memLen)
        return (receiver, accessor, memberPrefix, repRange)
    }

    private static func memberCatalog(receiver: String, accessor: String, language: CodeLanguage) -> [(label: String, template: String, detail: String, kind: CompletionKind)] {
        if accessor == "::" {
            if receiver == "std" {
                return [
                    ("cout", "cout << $0 << '\\n';", "std::ostream", .property),
                    ("cin", "cin >> $0;", "std::istream", .property),
                    ("vector", "vector<$0>", "Dynamic Array", .type),
                    ("string", "string", "UTF-8 String", .type),
                    ("unordered_map", "unordered_map<$0>", "Hash Table", .type),
                    ("map", "map<$0>", "Ordered Map", .type),
                    ("set", "set<$0>", "Ordered Set", .type),
                    ("priority_queue", "priority_queue<$0>", "Max/Min Heap", .type),
                    ("pair", "pair<$0>", "2-Tuple", .type),
                    ("sort", "sort($0.begin(), .end());", "<algorithm>", .function),
                    ("max", "max($0)", "<algorithm>", .function),
                    ("min", "min($0)", "<algorithm>", .function),
                    ("make_unique", "make_unique<$0>()", "<memory>", .function),
                    ("make_shared", "make_shared<$0>()", "<memory>", .function)
                ]
            }
            if language == .rust {
                return [
                    ("new", "new()", "Constructor", .function),
                    ("from", "from($0)", "From Trait", .function),
                    ("with_capacity", "with_capacity($0)", "Preallocate", .function),
                    ("default", "default()", "Default Trait", .function)
                ]
            }
        }

        // Specific Well-Known Receivers
        switch receiver {
        case "console":
            return [
                ("log", "log($0)", "Console Info", .method),
                ("error", "error($0)", "Console Error", .method),
                ("warn", "warn($0)", "Console Warning", .method),
                ("table", "table($0)", "Tabular View", .method),
                ("time", "time('$0')", "Start Timer", .method),
                ("timeEnd", "timeEnd('$0')", "End Timer", .method)
            ]
        case "document":
            return [
                ("querySelector", "querySelector('$0')", "Element | null", .method),
                ("querySelectorAll", "querySelectorAll('$0')", "NodeList", .method),
                ("getElementById", "getElementById('$0')", "HTMLElement | null", .method),
                ("createElement", "createElement('$0')", "HTMLElement", .method),
                ("addEventListener", "addEventListener('$0', (e) => {\n  \n})", "DOM Event", .method),
                ("body", "body", "HTMLBodyElement", .property)
            ]
        case "Math":
            return [
                ("max", "max($0)", "Number", .method),
                ("min", "min($0)", "Number", .method),
                ("floor", "floor($0)", "Integer Floor", .method),
                ("ceil", "ceil($0)", "Integer Ceil", .method),
                ("round", "round($0)", "Nearest Int", .method),
                ("random", "random()", "0.0 ..< 1.0", .method),
                ("sqrt", "sqrt($0)", "Square Root", .method)
            ]
        case "JSON":
            return [
                ("stringify", "stringify($0, null, 2)", "Serialize JSON", .method),
                ("parse", "parse($0)", "Parse JSON", .method)
            ]
        case "fmt":
            return [
                ("Println", "Println($0)", "fmt.Println", .function),
                ("Printf", "Printf(\"$0\\n\", )", "fmt.Printf", .function),
                ("Sprintf", "Sprintf(\"$0\", )", "Format String", .function),
                ("Errorf", "Errorf(\"$0\")", "Format Error", .function)
            ]
        case "System", "System.out":
            return receiver == "System"
                ? [("out.println", "out.println($0);", "Print Line", .method)]
                : [
                    ("println", "println($0);", "Print Line", .method),
                    ("printf", "printf(\"$0\\n\", );", "Formatted Print", .method),
                    ("print", "print($0);", "Print", .method)
                ]
        case "Console":
            return [
                ("WriteLine", "WriteLine($0);", "C# Stdout", .method),
                ("Write", "Write($0);", "C# Print", .method),
                ("ReadLine", "ReadLine()", "C# Stdin", .method)
            ]
        default:
            break
        }

        // Language-Specific Generic Member Suggestions
        switch language {
        case .cpp, .c:
            return [
                ("push_back", "push_back($0)", "Append Element", .method),
                ("emplace_back", "emplace_back($0)", "Construct In-Place", .method),
                ("pop_back", "pop_back()", "Remove Last", .method),
                ("begin", "begin()", "Iterator Start", .method),
                ("end", "end()", "Iterator End", .method),
                ("size", "size()", "Element Count", .method),
                ("empty", "empty()", "Bool", .method),
                ("clear", "clear()", "Remove All", .method),
                ("find", "find($0)", "Lookup Key", .method),
                ("insert", "insert($0)", "Insert Item", .method),
                ("erase", "erase($0)", "Remove Item", .method),
                ("substr", "substr($0)", "Substring", .method),
                ("first", "first", "Pair First", .property),
                ("second", "second", "Pair Second", .property)
            ]
        case .python:
            return [
                ("append", "append($0)", "list.append", .method),
                ("extend", "extend($0)", "list.extend", .method),
                ("pop", "pop()", "Remove & Return", .method),
                ("items", "items()", "dict (k, v)", .method),
                ("keys", "keys()", "dict keys", .method),
                ("values", "values()", "dict values", .method),
                ("get", "get($0)", "dict safe lookup", .method),
                ("split", "split($0)", "str.split", .method),
                ("join", "join($0)", "str.join", .method),
                ("strip", "strip()", "str.strip", .method),
                ("replace", "replace($0)", "str.replace", .method)
            ]
        case .javascript, .typescript, .tsx, .vue, .svelte, .astro:
            return [
                ("map", "map(($0) => )", "Array.map", .method),
                ("filter", "filter(($0) => )", "Array.filter", .method),
                ("reduce", "reduce((acc, $0) => acc, 0)", "Array.reduce", .method),
                ("forEach", "forEach(($0) => {\n  \n})", "Array.forEach", .method),
                ("find", "find(($0) => )", "Array.find", .method),
                ("includes", "includes($0)", "Contains", .method),
                ("push", "push($0)", "Array.push", .method),
                ("slice", "slice($0)", "Subarray/Str", .method),
                ("length", "length", "Count", .property),
                ("addEventListener", "addEventListener('$0', (e) => {})", "EventTarget", .method)
            ]
        case .rust:
            return [
                ("unwrap", "unwrap()", "Unwrap Option/Result", .method),
                ("expect", "expect(\"$0\")", "Unwrap with Message", .method),
                ("iter", "iter()", "Slice Iterator", .method),
                ("map", "map(|$0| )", "Iterator.map", .method),
                ("collect", "collect::<Vec<_>>()", "Collect Iterator", .method),
                ("clone", "clone()", "Clone Value", .method),
                ("len", "len()", "Length", .method),
                ("is_empty", "is_empty()", "Bool", .method),
                ("push", "push($0)", "Vec/String push", .method)
            ]
        case .swift:
            return [
                ("map", "map { $0 }", "Sequence.map", .method),
                ("filter", "filter { $0 }", "Sequence.filter", .method),
                ("compactMap", "compactMap { $0 }", "Non-nil map", .method),
                ("append", "append($0)", "Array.append", .method),
                ("count", "count", "Element Count", .property),
                ("isEmpty", "isEmpty", "Bool", .property),
                ("first", "first", "Optional First", .property)
            ]
        default:
            return []
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
        self.symbols = Self.extractSymbols(from: code, language: language)
        updateActiveBreadcrumb(cursorLocation: cursorLocation, in: code)

        diagnosticsTask?.cancel()
        guard diagnosticsEnabled else {
            if !diagnostics.isEmpty { diagnostics = [] }
            return
        }

        diagnosticsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }

            var found = Self.runFastOfflineDiagnostics(code: code, language: language)

            if let ssh = sshService, ssh.isConnected,
               [.c, .cpp, .python, .rust, .php, .ruby, .shell].contains(language) {
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

    // MARK: - Offline Real-Time Syntax & Lint Analyzer Across Languages
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

        if language == .javascript {
            if let ctx = JSContext() {
                var jsSyntaxDiag: EditorDiagnostic?
                ctx.exceptionHandler = { _, exc in
                    guard let exc else { return }
                    let msg = exc.toString() ?? "JavaScript Syntax Error"
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

        if language == .html || language == .xml || language == .vue {
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
                        if rawTag.hasPrefix("!") || rawTag.hasPrefix("?") || voidTags.contains(rawTag) || selfClosing { continue }
                        if isClosing {
                            if let lastIdx = tagStack.lastIndex(where: { $0.name == rawTag }) {
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
                                    message: "Thẻ đóng </\(rawTag)> dư thừa.",
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

        let proseLanguages: Set<CodeLanguage> = [.markdown, .plainText, .diff, .ini, .regex]
        if !proseLanguages.contains(language) {
            var stack: [(ch: Character, line: Int, col: Int)] = []
            let matchingOpen: [Character: Character] = [")": "(", "}": "{", "]": "["]
            let matchingClose: [Character: Character] = ["(": ")", "{": "}", "[": "]"]
            var inBlockComment = false
            let hashCommentLangs: Set<CodeLanguage> = [.python, .ruby, .perl, .r, .julia, .elixir, .yaml, .toml, .shell, .fish, .powershell, .dockerfile, .makefile, .cmake, .hcl, .nix]

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

                    if hashCommentLangs.contains(language) && c == "#" { break }
                    if (language == .lua || language == .sql || language == .haskell) && c == "-" && cIdx + 1 < chars.count && chars[cIdx + 1] == "-" { break }

                    if c == "/" && cIdx + 1 < chars.count {
                        if chars[cIdx + 1] == "/" { break }
                        if chars[cIdx + 1] == "*" {
                            inBlockComment = true
                            cIdx += 2
                            continue
                        }
                    }

                    if c == "\"" || c == "'" || c == "`" {
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

                if let q = inStringQuote, q != "`" && !(language == .rust && q == "'") {
                    issues.append(EditorDiagnostic(
                        line: lineNo,
                        severity: .error,
                        message: "Chuỗi ký tự mở bằng \(q) chưa được đóng trên dòng \(lineNo).",
                        range: lineNSRange(lineNo)
                    ))
                }

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

        if language == .yaml {
            for (index, rawLine) in lines.enumerated() {
                if rawLine.hasPrefix("\t") || rawLine.contains(":\t") {
                    let lineNum = index + 1
                    issues.append(EditorDiagnostic(
                        line: lineNum,
                        column: 1,
                        severity: .error,
                        message: "YAML không cho phép thụt lề bằng phím Tab; hãy dùng dấu cách (Spaces).",
                        range: lineNSRange(lineNum)
                    ))
                    if issues.count >= 25 { break }
                }
            }
        }

        return Array(issues.prefix(25))
    }

    // MARK: - Remote VPS Compiler Diagnostics Parser
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
        case .php:
            cmd = "echo '\(b64)' | base64 -d | php -l 2>&1"
        case .ruby:
            cmd = "echo '\(b64)' | base64 -d | ruby -c 2>&1"
        case .shell:
            cmd = "echo '\(b64)' | base64 -d | bash -n 2>&1"
        default:
            return []
        }

        let raw = await sshService.executeCommandOnVPS(cmd)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("Syntax OK"), !trimmed.hasPrefix("No syntax errors") else { return [] }

        let lines = code.components(separatedBy: "\n")
        let offsets = computeLineUTF16Offsets(lines: lines)
        func rangeForLine(_ l: Int) -> NSRange {
            let idx = min(max(0, l - 1), max(0, lines.count - 1))
            guard idx < offsets.count else { return NSRange(location: 0, length: 0) }
            return NSRange(location: offsets[idx], length: max((lines[idx] as NSString).length, 1))
        }

        var parsed: [EditorDiagnostic] = []
        let gccRegex = try? NSRegularExpression(pattern: #":(\d+):(\d+):\s*(fatal error|error|warning):\s*(.+)$"#)
        let genericLineRegex = try? NSRegularExpression(pattern: #"line\s+(\d+)"#, options: [.caseInsensitive])

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
            } else if let pm = genericLineRegex?.firstMatch(in: outLine, range: NSRange(location: 0, length: ns.length)) {
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

    // MARK: - Universal Symbol & Signature Extractor (Across Languages)
    nonisolated public static func extractSymbols(from code: String, language: CodeLanguage) -> [DocumentSymbolItem] {
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
        case .rust:
            patterns = [
                (#"\b(struct|enum|trait|impl|mod)\s+([A-Za-z_][A-Za-z0-9_]*)"#, 2, "Type", "cube"),
                (#"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<(]"#, 1, "Function", "function")
            ]
        case .go:
            patterns = [
                (#"\btype\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:struct|interface)"#, 1, "Type", "cube"),
                (#"\bfunc\s+(?:\([^)]+\)\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\("#, 1, "Function", "function")
            ]
        case .java, .csharp, .dart, .groovy, .solidity:
            patterns = [
                (#"\b(class|interface|enum|record|struct|contract)\s+([A-Za-z_][A-Za-z0-9_]*)"#, 2, "Type", "cube"),
                (#"^\s*(?:public|private|protected|static|async|virtual|override|\s)+[A-Za-z0-9_<>\[\]?]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, 1, "Method", "function")
            ]
        case .kotlin, .scala:
            patterns = [
                (#"\b(class|interface|object|trait)\s+([A-Za-z_][A-Za-z0-9_]*)"#, 2, "Type", "cube"),
                (#"\b(?:fun|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[<(]"#, 1, "Function", "function")
            ]
        case .c, .cpp, .objectiveC, .zig, .dlang:
            patterns = [
                (#"^\s*%hook\s+([A-Za-z_][A-Za-z0-9_]*)"#, 1, "%hook", "cube"),
                (#"^\s*[-+]\s*\([^)]+\)\s*([A-Za-z_][A-Za-z0-9_:]*)"#, 1, "Method", "function"),
                (#"\b(class|struct|namespace|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#, 2, "Type", "cube"),
                (#"^\s*(?:[A-Za-z_][A-Za-z0-9_:<>\*\s&]+)\s+([A-Za-z_~][A-Za-z0-9_:]*)\s*\([^;]*\)\s*(?:const)?\s*\{"#, 1, "Function", "function")
            ]
        case .python:
            patterns = [
                (#"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#, 1, "Class", "cube"),
                (#"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#, 1, "Function", "function")
            ]
        case .php, .ruby, .elixir, .lua, .julia:
            patterns = [
                (#"\b(class|module|defmodule)\s+([A-Za-z_][A-Za-z0-9_.:]*)"#, 2, "Type", "cube"),
                (#"\b(?:function|def|defp)\s+([A-Za-z_][A-Za-z0-9_?!.]*)"#, 1, "Function", "function")
            ]
        case .javascript, .typescript, .tsx:
            patterns = [
                (#"\b(class|interface|type|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, 2, "Type", "cube"),
                (#"\b(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\("#, 1, "Function", "function"),
                (#"\b(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>"#, 1, "Function", "function")
            ]
        case .html, .vue, .svelte, .astro:
            patterns = [
                (#"<(header|nav|main|section|article|footer|form|script|style|template)[^>]*>"#, 1, "Section", "chevron.left.forwardslash.chevron.right"),
                (#"id\s*=\s*["']([^"']+)["']"#, 1, "#id", "number")
            ]
        case .css, .scss:
            patterns = [(#"^\s*([.#@a-zA-Z][^{]+)\s*\{"#, 1, "Selector", "curlybraces")]
        case .sql:
            patterns = [(#"(?i)\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:TABLE|VIEW|FUNCTION|PROCEDURE|INDEX)\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_.]+)"#, 1, "Schema", "cylinder.split.1x2")]
        case .markdown:
            patterns = [(#"^(#{1,4}\s+.+)$"#, 1, "Heading", "list.bullet.indent")]
        case .shell, .fish:
            patterns = [(#"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)"#, 1, "Function", "apple.terminal")]
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
                    let disallowed: Set<String> = ["if", "for", "while", "switch", "catch", "else", "return"]
                    guard !rawName.isEmpty, !disallowed.contains(rawName) else { continue }
                    let sig = line.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"\s*\{$"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)
                    let docRange = NSRange(location: offsets[i], length: nsLine.length)
                    items.append(DocumentSymbolItem(
                        name: rawName,
                        signature: String(sig.prefix(90)),
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

    // MARK: - Helpers & Comprehensive Multi-Language Smart Catalog
    nonisolated private static func computeLineUTF16Offsets(lines: [String]) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(lines.count)
        var running = 0
        for line in lines {
            offsets.append(running)
            running += (line as NSString).length + 1
        }
        return offsets
    }

    private static func extractFirstInt(in text: String, after marker: String) -> Int? {
        guard let r = text.range(of: marker, options: .caseInsensitive) else { return nil }
        let tail = text[r.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func smartLanguageCatalog(for language: CodeLanguage) -> [(label: String, template: String, detail: String, kind: CompletionKind)] {
        switch language {
        case .cpp, .c, .objectiveC:
            return [
                ("for (int i...)", "for (int i = 0; i < $0; ++i) {\n    \n}", "Indexed Loop", .snippet),
                ("for (auto&...)", "for (const auto& item : $0) {\n    \n}", "Range-Based Loop", .snippet),
                ("if (...)", "if ($0) {\n    \n}", "Conditional Block", .snippet),
                ("while (...)", "while ($0) {\n    \n}", "While Loop", .snippet),
                ("main", "int main() {\n    $0\n    return 0;\n}", "Entry Point", .snippet),
                ("#include <>", "#include <$0>", "System Header", .module),
                ("std::cout", "std::cout << $0 << '\\n';", "Standard Output", .function),
                ("std::cin", "std::cin >> $0;", "Standard Input", .function),
                ("std::vector", "std::vector<$0>", "Dynamic Array", .type),
                ("std::string", "std::string", "String Type", .type),
                ("std::unordered_map", "std::unordered_map<$0>", "Hash Map", .type),
                ("std::sort", "std::sort($0.begin(), .end());", "Sort Container", .function),
                ("std::pair", "std::pair<$0>", "Tuple Pair", .type),
                ("push_back", "push_back($0)", "Append Item", .method),
                ("printf", "printf(\"$0\\n\");", "C Printf", .function),
                ("scanf", "scanf(\"$0\", );", "C Scanf", .function),
                ("constexpr", "constexpr ", "Compile-Time", .keyword),
                ("nullptr", "nullptr", "Null Pointer", .keyword),
                ("struct", "struct $0 {\n    \n};", "Struct Definition", .keyword),
                ("class", "class $0 {\npublic:\n    \n};", "Class Definition", .keyword),
                ("return", "return $0;", "Return Statement", .keyword),
                ("%hook", "%hook $0\n\n%end", "Logos Hook Class", .snippet),
                ("%orig", "%orig($0);", "Call Original IMP", .function),
                ("%ctor", "%ctor {\n    $0\n}", "Tweak Constructor", .snippet),
                ("%dtor", "%dtor {\n    $0\n}", "Tweak Destructor", .snippet),
                ("%group", "%group $0\n\n%end", "Logos Hook Group", .snippet),
                ("%init", "%init($0);", "Initialize Group", .function),
                ("%property", "%property (nonatomic, strong) $0;", "Logos Dynamic Property", .keyword),
                ("%new", "%new\n- (void)$0 {\n    \n}", "Add Method to Class", .snippet),
                ("%c()", "%c($0)", "Runtime Class Lookup", .function),
                ("MSHookFunction", "MSHookFunction((void *)$0, (void *)new_fn, (void **)&orig_fn);", "CydiaSubstrate Hook C", .function),
                ("MSHookMessageEx", "MSHookMessageEx(objc_getClass(\"$0\"), @selector(), (IMP)new_imp, (IMP *)&orig_imp);", "Substrate Hook ObjC", .function)
            ]

        case .python:
            return [
                ("def", "def $0():\n    pass", "Function Definition", .snippet),
                ("class", "class $0:\n    def __init__(self):\n        pass", "Class Definition", .snippet),
                ("for in range", "for i in range($0):\n    ", "Range Loop", .snippet),
                ("ifmain", "if __name__ == \"__main__\":\n    $0", "Main Guard", .snippet),
                ("try/except", "try:\n    $0\nexcept Exception as err:\n    print(err)", "Error Handler", .snippet),
                ("with open", "with open(\"$0\", \"r\", encoding=\"utf-8\") as f:\n    data = f.read()", "Read File", .snippet),
                ("print", "print($0)", "Built-in Output", .function),
                ("input", "input($0)", "Built-in Input", .function),
                ("enumerate", "enumerate($0)", "Indexed Iterable", .function),
                ("isinstance", "isinstance($0, )", "Type Check", .function),
                ("sorted", "sorted($0)", "Sorted List", .function),
                ("len", "len($0)", "Length", .function),
                ("async def", "async def $0():\n    ", "Async Coroutine", .keyword),
                ("import", "import $0", "Import Module", .keyword),
                ("from import", "from $0 import ", "Named Import", .keyword),
                ("return", "return $0", "Return Value", .keyword)
            ]

        case .javascript, .typescript, .tsx:
            return [
                ("const", "const $0 = ", "Constant Binding", .keyword),
                ("let", "let $0 = ", "Mutable Binding", .keyword),
                ("return", "return $0;", "Return Value", .keyword),
                ("if (...)", "if ($0) {\n  \n}", "Conditional Block", .snippet),
                ("for (...)", "for (let i = 0; i < $0; i++) {\n  \n}", "For Loop", .snippet),
                ("console.log", "console.log($0);", "Log Output", .method),
                ("console.error", "console.error($0);", "Log Error", .method),
                ("function", "function $0() {\n  \n}", "Function Declaration", .snippet),
                ("async function", "async function $0() {\n  \n}", "Async Function", .snippet),
                ("arrow fn", "const $0 = () => {\n  \n};", "Arrow Function", .snippet),
                ("fetch", "const res = await fetch('$0');\nconst data = await res.json();", "Fetch JSON", .snippet),
                ("try/catch", "try {\n  $0\n} catch (err) {\n  console.error(err);\n}", "Try/Catch Block", .snippet),
                ("interface", "interface $0 {\n  \n}", "TS Interface", .type),
                ("type", "type $0 = ", "TS Type Alias", .type),
                ("document.querySelector", "document.querySelector('$0')", "DOM Query", .method),
                ("document.getElementById", "document.getElementById('$0')", "DOM by ID", .method),
                ("addEventListener", "addEventListener('$0', (e) => {\n  \n});", "Event Listener", .method),
                ("Promise.all", "await Promise.all([$0])", "Concurrent Promises", .method),
                ("setTimeout", "setTimeout(() => {\n  $0\n}, 300);", "Timer", .function),
                ("export default", "export default $0", "ES Module Export", .keyword),
                ("import from", "import { $0 } from '';", "ES Module Import", .keyword)
            ]

        case .rust:
            return [
                ("fn main", "fn main() {\n    $0\n}", "Entry Point", .snippet),
                ("println!", "println!(\"$0\");", "Stdout Macro", .function),
                ("eprintln!", "eprintln!(\"$0\");", "Stderr Macro", .function),
                ("format!", "format!(\"$0\")", "String Macro", .function),
                ("vec!", "vec![$0]", "Vec Macro", .function),
                ("struct", "#[derive(Debug, Clone)]\nstruct $0 {\n    \n}", "Struct + Derive", .snippet),
                ("enum", "#[derive(Debug, Clone)]\nenum $0 {\n    \n}", "Enum + Derive", .snippet),
                ("impl", "impl $0 {\n    \n}", "Implementation", .snippet),
                ("match", "match $0 {\n    _ => {}\n}", "Pattern Match", .snippet),
                ("let mut", "let mut $0 = ", "Mutable Binding", .keyword),
                ("Result", "Result<$0, Box<dyn std::error::Error>>", "Result Type", .type),
                ("Option", "Option<$0>", "Option Type", .type),
                ("HashMap", "std::collections::HashMap<$0>", "HashMap", .type)
            ]

        case .go:
            return [
                ("func main", "func main() {\n\t$0\n}", "Entry Point", .snippet),
                ("fmt.Println", "fmt.Println($0)", "Print Line", .function),
                ("fmt.Printf", "fmt.Printf(\"$0\\n\", )", "Formatted Print", .function),
                ("iferr", "if err != nil {\n\treturn $0err\n}", "Go Error Guard", .snippet),
                ("for range", "for i, v := range $0 {\n\t\n}", "Range Loop", .snippet),
                ("struct", "type $0 struct {\n\t\n}", "Struct Type", .snippet),
                ("interface", "type $0 interface {\n\t\n}", "Interface Type", .snippet),
                ("make slice", "make([]$0, 0)", "Allocate Slice", .function),
                ("make map", "make(map[string]$0)", "Allocate Map", .function),
                ("go func", "go func() {\n\t$0\n}()", "Goroutine", .snippet)
            ]

        case .java, .kotlin, .csharp, .dart:
            return [
                ("main", language == .kotlin ? "fun main() {\n    $0\n}" : (language == .csharp ? "static void Main(string[] args) {\n    $0\n}" : "public static void main(String[] args) {\n    $0\n}"), "Entry Point", .snippet),
                ("println", language == .csharp ? "Console.WriteLine($0);" : (language == .java ? "System.out.println($0);" : "println($0)"), "Print Output", .function),
                ("for", "for (int i = 0; i < $0; i++) {\n    \n}", "For Loop", .snippet),
                ("class", "public class $0 {\n    \n}", "Class Declaration", .type),
                ("interface", "public interface $0 {\n    \n}", "Interface", .type),
                ("try/catch", "try {\n    $0\n} catch (Exception e) {\n    \n}", "Exception Handler", .snippet)
            ]

        case .swift:
            return [
                ("struct View", "struct $0: View {\n    var body: some View {\n        Text(\"Hello\")\n    }\n}", "SwiftUI View", .snippet),
                ("@main App", "@main\nstruct $0App: App {\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n        }\n    }\n}", "SwiftUI @main App Entry", .snippet),
                ("Package(xtool)", "// swift-tools-version: 5.10\nimport PackageDescription\n\nlet package = Package(\n    name: \"$0\",\n    platforms: [.iOS(.v17)],\n    products: [\n        .library(name: \"$0\", targets: [\"$0\"])\n    ],\n    targets: [\n        .target(name: \"$0\")\n    ]\n)", "xtool Package.swift Manifest", .snippet),
                (".library", ".library(name: \"$0\", targets: [\"$0\"])", "SwiftPM Library Product (xtool App)", .function),
                (".target", ".target(name: \"$0\")", "SwiftPM Source Target", .function),
                (".package(url:)", ".package(url: \"$0\", from: \"1.0.0\")", "SwiftPM Remote Dependency", .function),
                ("func", "func $0() {\n    \n}", "Function", .snippet),
                ("guard let", "guard let $0 else { return }", "Unwrap Guard", .snippet),
                ("Task", "Task {\n    $0\n}", "Async Task", .snippet),
                ("@Published", "@Published var $0", "Combine Property", .property),
                ("@State", "@State private var $0", "SwiftUI State", .property),
                ("print", "print($0)", "Console Output", .function)
            ]

        case .html, .vue, .svelte, .astro:
            return [
                ("!", "<!DOCTYPE html>\n<html lang=\"vi\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <title>$0</title>\n</head>\n<body>\n  \n</body>\n</html>", "HTML5 Skeleton", .emmet),
                ("div", "<div class=\"$0\"></div>", "HTML Container", .emmet),
                ("p", "<p>$0</p>", "Paragraph", .emmet),
                ("span", "<span>$0</span>", "Inline Span", .emmet),
                ("h1", "<h1>$0</h1>", "Heading 1", .emmet),
                ("h2", "<h2>$0</h2>", "Heading 2", .emmet),
                ("section", "<section>$0</section>", "HTML Section", .emmet),
                ("main", "<main>$0</main>", "HTML Main", .emmet),
                ("header", "<header>$0</header>", "HTML Header", .emmet),
                ("nav", "<nav>$0</nav>", "Navigation", .emmet),
                ("footer", "<footer>$0</footer>", "HTML Footer", .emmet),
                ("button", "<button type=\"button\">$0</button>", "HTML Button", .emmet),
                ("input", "<input type=\"text\" placeholder=\"$0\" />", "HTML Input", .emmet),
                ("form", "<form action=\"$0\" method=\"POST\">\n  \n</form>", "HTML Form", .emmet),
                ("label", "<label for=\"$0\"></label>", "Form Label", .emmet),
                ("ul", "<ul>\n  <li>$0</li>\n</ul>", "Unordered List", .emmet),
                ("li", "<li>$0</li>", "List Item", .emmet),
                ("a href", "<a href=\"$0\"></a>", "Anchor Link", .emmet),
                ("img", "<img src=\"$0\" alt=\"\" />", "Image Element", .emmet),
                ("script", "<script>\n  $0\n</script>", "Inline Script", .emmet),
                ("style", "<style>\n  $0\n</style>", "Inline CSS", .emmet),
                ("link css", "<link rel=\"stylesheet\" href=\"$0style.css\" />", "Stylesheet Link", .emmet)
            ]

        case .css, .scss:
            return [
                ("display: flex", "display: flex;\nalign-items: center;\njustify-content: $0center;", "Flexbox Center", .snippet),
                ("display: grid", "display: grid;\ngrid-template-columns: repeat($0, 1fr);\ngap: 16px;", "CSS Grid", .snippet),
                ("background", "background: $0;", "Background", .property),
                ("background-color", "background-color: $0;", "Background Color", .property),
                ("color", "color: $0;", "Text Color", .property),
                ("padding", "padding: $0px;", "Inner Spacing", .property),
                ("margin", "margin: $0px;", "Outer Spacing", .property),
                ("gap", "gap: $0px;", "Flex/Grid Gap", .property),
                ("width", "width: $0;", "Width", .property),
                ("height", "height: $0;", "Height", .property),
                ("border", "border: 1px solid $0;", "Border", .property),
                ("border-radius", "border-radius: $0px;", "Rounded Corners", .property),
                ("box-shadow", "box-shadow: 0 10px 30px rgba(0, 0, 0, $00.25);", "Drop Shadow", .property),
                ("font-size", "font-size: $0px;", "Font Size", .property),
                ("font-weight", "font-weight: $0600;", "Font Weight", .property),
                ("position", "position: $0relative;", "CSS Position", .property),
                ("transition", "transition: all $00.2s ease;", "Smooth Transition", .property),
                ("transform", "transform: $0;", "Transform", .property),
                ("cursor", "cursor: $0pointer;", "Cursor Style", .property),
                ("justify-content", "justify-content: $0center;", "Main Axis Align", .property),
                ("align-items", "align-items: $0center;", "Cross Axis Align", .property),
                ("@media", "@media (max-width: $0768px) {\n  \n}", "Responsive Breakpoint", .snippet),
                ("@keyframes", "@keyframes $0fadeIn {\n  from { opacity: 0; }\n  to { opacity: 1; }\n}", "CSS Animation", .snippet)
            ]

        case .sql:
            return [
                ("SELECT", "SELECT $0 FROM ;", "Query Rows", .keyword),
                ("CREATE TABLE", "CREATE TABLE $0 (\n  id INTEGER PRIMARY KEY,\n  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP\n);", "Table DDL", .snippet),
                ("INSERT INTO", "INSERT INTO $0 () VALUES ();", "Insert Row", .snippet),
                ("UPDATE", "UPDATE $0 SET  WHERE id = ;", "Update Row", .snippet),
                ("LEFT JOIN", "LEFT JOIN $0 ON ", "Join Clause", .keyword),
                ("GROUP BY", "GROUP BY $0 ORDER BY ", "Aggregation", .keyword)
            ]

        case .yaml:
            return [
                ("xtool.yml", "version: 1\nbundleID: com.dev.$0\nproduct: $0\ninfoPath: Info.plist", "xtool Manifest Skeleton", .snippet),
                ("version: 1", "version: 1", "xtool Schema Version", .property),
                ("bundleID:", "bundleID: com.dev.$0", "iOS App Bundle Identifier", .property),
                ("product:", "product: $0", "Primary .library Product in Package.swift", .property),
                ("infoPath:", "infoPath: Info.plist", "Custom Info.plist Path", .property),
                ("entitlementsPath:", "entitlementsPath: $0.entitlements", "App Entitlements Path", .property),
                ("resources:", "resources:\n  - path: $0", "Bundle Resources", .snippet),
                ("extensions:", "extensions:\n  - product: $0Extension\n    infoPath: $0Extension-Info.plist", "App Extension (Widget/Share)", .snippet)
            ]

        case .php, .ruby, .lua, .shell, .dockerfile, .hcl:
            return [
                ("function", language == .ruby ? "def $0\n  \nend" : "function $0()\n  \nend", "Function Block", .snippet),
                ("if", "if $0\n  \nend", "Conditional", .keyword),
                ("echo", "echo \"$0\"", "Print Output", .function)
            ]

        default:
            return [
                ("function", "function $0() {\n  \n}", "Function", .snippet),
                ("return", "return $0", "Return", .keyword)
            ]
        }
    }
}
