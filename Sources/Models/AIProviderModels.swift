import Foundation

// MARK: - API Wire Formats

/// Wire protocol spoken by an AI provider. Almost every vendor today exposes an
/// OpenAI-compatible Chat Completions endpoint, so most presets map to `.openAICompatible`.
public enum AIAPIFormat: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case openAIResponses
    case anthropic
    case gemini
    case customPost
    case appleOnDevice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .openAIResponses: return "OpenAI Responses (/responses)"
        case .anthropic: return "Anthropic Messages"
        case .gemini: return "Google Gemini"
        case .customPost: return "Custom POST API"
        case .appleOnDevice: return "Apple On-Device"
        }
    }
}

/// Custom HTTP header item for Custom POST API configs.
/// Secret values (`isSecret == true`) are never written in plaintext by `Codable` —
/// `AIAgentService` persists them separately inside iOS Keychain.
public struct AICustomHeaderItem: Codable, Identifiable, Hashable {
    public var id: UUID
    public var key: String
    public var value: String
    public var isSecret: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isSecret: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, key, value, isSecret, isEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        isSecret = try c.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(key, forKey: .key)
        // Scrub secret header values whenever encoded to UserDefaults or JSON exports.
        try c.encode(isSecret ? "" : value, forKey: .value)
        try c.encode(isSecret, forKey: .isSecret)
        try c.encode(isEnabled, forKey: .isEnabled)
    }

    public static func looksSensitive(headerName: String, value: String) -> Bool {
        let lowKey = headerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowVal = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowVal.contains("{{api_key}}") || lowVal.isEmpty { return false }
        let sensitiveNames = ["authorization", "x-api-key", "api-key", "x-auth-token", "cookie", "set-cookie", "proxy-authorization"]
        if sensitiveNames.contains(lowKey) || lowKey.contains("secret") || lowKey.contains("token") {
            return true
        }
        return lowVal.hasPrefix("bearer ") || lowVal.contains("sk-")
    }
}

/// User-defined HTTP POST API template configuration (no third-party client spoofing).
public struct AICustomPostConfig: Codable, Hashable {
    public var endpointURL: String
    public var headers: [AICustomHeaderItem]
    public var bodyTemplate: String
    public var responsePath: String
    public var streamDeltaPath: String
    public var streamEventTextFallback: String
    public var defaultModel: String
    public var useSSEResponse: Bool
    public var allowEmptyModel: Bool

    public static let defaultBodyTemplate = """
{
  "model": "{{model}}",
  "messages": {{messages}},
  "stream": {{stream}}
}
"""

    public init(
        endpointURL: String = "https://api.example.com/v1/chat/completions",
        headers: [AICustomHeaderItem] = [
            AICustomHeaderItem(key: "Content-Type", value: "application/json", isSecret: false, isEnabled: true),
            AICustomHeaderItem(key: "Authorization", value: "Bearer {{api_key}}", isSecret: false, isEnabled: true)
        ],
        bodyTemplate: String = AICustomPostConfig.defaultBodyTemplate,
        responsePath: String = "choices.0.message.content",
        streamDeltaPath: String = "choices.0.delta.content",
        streamEventTextFallback: String = "delta",
        defaultModel: String = "gpt-4o",
        useSSEResponse: Bool = true,
        allowEmptyModel: Bool = true
    ) {
        self.endpointURL = endpointURL
        self.headers = headers
        self.bodyTemplate = bodyTemplate
        self.responsePath = responsePath
        self.streamDeltaPath = streamDeltaPath
        self.streamEventTextFallback = streamEventTextFallback
        self.defaultModel = defaultModel
        self.useSSEResponse = useSSEResponse
        self.allowEmptyModel = allowEmptyModel
    }

    private enum CodingKeys: String, CodingKey {
        case endpointURL, headers, bodyTemplate, responsePath
        case streamDeltaPath, streamEventTextFallback, defaultModel
        case useSSEResponse, allowEmptyModel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        endpointURL = try c.decodeIfPresent(String.self, forKey: .endpointURL) ?? "https://api.example.com/v1/chat/completions"
        headers = try c.decodeIfPresent([AICustomHeaderItem].self, forKey: .headers) ?? []
        bodyTemplate = try c.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? AICustomPostConfig.defaultBodyTemplate
        responsePath = try c.decodeIfPresent(String.self, forKey: .responsePath) ?? "choices.0.message.content"
        streamDeltaPath = try c.decodeIfPresent(String.self, forKey: .streamDeltaPath) ?? "choices.0.delta.content"
        streamEventTextFallback = try c.decodeIfPresent(String.self, forKey: .streamEventTextFallback) ?? "delta"
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
        useSSEResponse = try c.decodeIfPresent(Bool.self, forKey: .useSSEResponse) ?? true
        allowEmptyModel = try c.decodeIfPresent(Bool.self, forKey: .allowEmptyModel) ?? true
    }

    public func scrubbingSecrets() -> AICustomPostConfig {
        var copy = self
        copy.headers = headers.map { item in
            var cleaned = item
            if cleaned.isSecret { cleaned.value = "" }
            return cleaned
        }
        return copy
    }
}

/// Parses captured `curl` commands or raw HTTP POST requests into `AICustomPostConfig`.
public enum AICurlAndRawRequestParser {
    public struct ParsedResult {
        public let config: AICustomPostConfig
        public let detectedModel: String
    }

    public static func parse(_ rawInput: String, injectPlaceholders: Bool = true) -> ParsedResult? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        if looksLikeRawHTTP(normalized) {
            return parseRawHTTP(normalized, injectPlaceholders: injectPlaceholders)
        }
        return parseCurl(normalized, injectPlaceholders: injectPlaceholders)
    }

    private static func looksLikeRawHTTP(_ text: String) -> Bool {
        let firstLine = text.components(separatedBy: "\n").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        let prefixes = ["POST ", "PUT ", "PATCH ", "GET "]
        return prefixes.contains(where: { firstLine.hasPrefix($0) }) && firstLine.contains("HTTP/")
    }

    private static func parseRawHTTP(_ text: String, injectPlaceholders: Bool) -> ParsedResult? {
        let splitParts = text.components(separatedBy: "\n\n")
        let headSection = splitParts.first ?? ""
        let rawBody = splitParts.count > 1 ? splitParts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let lines = headSection.components(separatedBy: "\n")
        guard let requestLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let reqTokens = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard reqTokens.count >= 2 else { return nil }
        let targetPath = reqTokens[1]

        var host = ""
        var scheme = "https"
        var authorityPath = ""
        var headers: [AICustomHeaderItem] = []

        for line in lines.dropFirst() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, let colonIdx = trimmedLine.firstIndex(of: ":") else { continue }
            let k: String
            let v: String
            if trimmedLine.hasPrefix(":") {
                // HTTP/2 pseudo-header like `:authority: api.example.com`
                let afterLeading = trimmedLine.index(after: trimmedLine.startIndex)
                if let secondColon = trimmedLine[afterLeading...].firstIndex(of: ":") {
                    k = String(trimmedLine[..<secondColon]).lowercased()
                    v = String(trimmedLine[trimmedLine.index(after: secondColon)...]).trimmingCharacters(in: .whitespaces)
                    if k == ":authority" { host = v }
                    if k == ":scheme" { scheme = v }
                    if k == ":path" { authorityPath = v }
                }
                continue
            } else {
                k = String(trimmedLine[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                v = String(trimmedLine[trimmedLine.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
            let lowerK = k.lowercased()
            if lowerK == "host" { host = v; continue }
            if lowerK == "content-length" || lowerK == "accept-encoding" || lowerK == "connection" { continue }
            headers.append(AICustomHeaderItem(
                key: k,
                value: v,
                isSecret: AICustomHeaderItem.looksSensitive(headerName: k, value: v),
                isEnabled: true
            ))
        }

        let effectivePath = authorityPath.isEmpty ? targetPath : authorityPath
        let endpoint: String
        if effectivePath.lowercased().hasPrefix("http://") || effectivePath.lowercased().hasPrefix("https://") {
            endpoint = effectivePath
        } else if !host.isEmpty {
            let cleanHost = host.hasPrefix("localhost") || host.hasPrefix("127.") ? "http://\(host)" : "\(scheme)://\(host)"
            let pathWithSlash = effectivePath.hasPrefix("/") ? effectivePath : "/\(effectivePath)"
            endpoint = cleanHost + pathWithSlash
        } else {
            endpoint = effectivePath
        }

        return buildParsedResult(
            endpointURL: endpoint,
            headers: headers,
            rawBody: rawBody,
            injectPlaceholders: injectPlaceholders
        )
    }

    private static func parseCurl(_ text: String, injectPlaceholders: Bool) -> ParsedResult? {
        let joined = text
            .replacingOccurrences(of: "\\\n", with: " ")
            .replacingOccurrences(of: "^\n", with: " ")
        let tokens = tokenizeShellWords(joined)
        guard !tokens.isEmpty else { return nil }

        var urlCandidate = ""
        var headers: [AICustomHeaderItem] = []
        var bodyParts: [String] = []
        var hasExplicitContentType = false
        var i = 0
        if tokens[0].lowercased() == "curl" || tokens[0].lowercased() == "curl.exe" {
            i = 1
        }

        while i < tokens.count {
            let tok = tokens[i]
            switch tok {
            case "-H", "--header":
                if i + 1 < tokens.count {
                    let h = tokens[i + 1]
                    if let colon = h.firstIndex(of: ":") {
                        let k = String(h[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = String(h[h.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        if k.lowercased() == "content-type" { hasExplicitContentType = true }
                        let lowerK = k.lowercased()
                        if lowerK != "content-length" && lowerK != "accept-encoding" {
                            headers.append(AICustomHeaderItem(
                                key: k,
                                value: v,
                                isSecret: AICustomHeaderItem.looksSensitive(headerName: k, value: v),
                                isEnabled: true
                            ))
                        }
                    }
                    i += 2
                    continue
                }
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii":
                if i + 1 < tokens.count {
                    bodyParts.append(tokens[i + 1])
                    i += 2
                    continue
                }
            case "--json":
                if i + 1 < tokens.count {
                    bodyParts.append(tokens[i + 1])
                    if !hasExplicitContentType {
                        headers.append(AICustomHeaderItem(key: "Content-Type", value: "application/json", isSecret: false, isEnabled: true))
                        hasExplicitContentType = true
                    }
                    i += 2
                    continue
                }
            case "--url":
                if i + 1 < tokens.count {
                    urlCandidate = tokens[i + 1]
                    i += 2
                    continue
                }
            case "-A", "--user-agent":
                if i + 1 < tokens.count {
                    headers.append(AICustomHeaderItem(key: "User-Agent", value: tokens[i + 1], isSecret: false, isEnabled: true))
                    i += 2
                    continue
                }
            case "-X", "--request", "-o", "--output", "--connect-timeout", "-m", "--max-time", "-u", "--user":
                i += 2
                continue
            default:
                if !tok.hasPrefix("-") {
                    if tok.lowercased().hasPrefix("http://") || tok.lowercased().hasPrefix("https://") {
                        urlCandidate = tok
                    }
                } else if tok.hasPrefix("--url=") {
                    urlCandidate = String(tok.dropFirst("--url=".count))
                } else if tok.hasPrefix("--header=") {
                    let h = String(tok.dropFirst("--header=".count))
                    if let colon = h.firstIndex(of: ":") {
                        let k = String(h[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = String(h[h.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        headers.append(AICustomHeaderItem(
                            key: k,
                            value: v,
                            isSecret: AICustomHeaderItem.looksSensitive(headerName: k, value: v),
                            isEnabled: true
                        ))
                    }
                }
            }
            i += 1
        }

        guard !urlCandidate.isEmpty || !bodyParts.isEmpty else { return nil }
        let rawBody = bodyParts.joined(separator: "&")
        return buildParsedResult(
            endpointURL: urlCandidate.isEmpty ? "https://api.example.com/v1/chat/completions" : urlCandidate,
            headers: headers,
            rawBody: rawBody,
            injectPlaceholders: injectPlaceholders
        )
    }

    private static func buildParsedResult(
        endpointURL: String,
        headers: [AICustomHeaderItem],
        rawBody: String,
        injectPlaceholders: Bool
    ) -> ParsedResult {
        var finalHeaders = headers
        if !finalHeaders.contains(where: { $0.key.lowercased() == "content-type" }) {
            finalHeaders.insert(AICustomHeaderItem(key: "Content-Type", value: "application/json", isSecret: false, isEnabled: true), at: 0)
        }

        let trimmedBody = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        var detectedModel = ""
        var finalBody = trimmedBody
        if injectPlaceholders && !trimmedBody.isEmpty {
            finalBody = injectTemplatePlaceholders(in: trimmedBody, detectedModel: &detectedModel)
        } else {
            detectedModel = extractModelString(fromJSONText: trimmedBody)
        }

        let lowerURL = endpointURL.lowercased()
        let isResponsesStyle = lowerURL.contains("/responses") || finalBody.contains("\"responses_input\"") || finalBody.contains("{{responses_input}}")
        let isGeminiStyle = finalBody.contains("{{gemini_contents}}") || lowerURL.contains("generatecontent")
        let isAnthropicStyle = lowerURL.contains("/messages") && !lowerURL.contains("chat/completions")

        let sseFlag = !trimmedBody.contains("\"stream\":false") && !trimmedBody.contains("\"stream\": false")
        let responsePath: String
        let streamDeltaPath: String
        let fallbackPath: String

        if isResponsesStyle {
            responsePath = "output_text"
            streamDeltaPath = "delta"
            fallbackPath = "output.0.content.0.text"
        } else if isGeminiStyle {
            responsePath = "candidates.0.content.parts.0.text"
            streamDeltaPath = "candidates.0.content.parts.0.text"
            fallbackPath = "delta"
        } else if isAnthropicStyle {
            responsePath = "content.0.text"
            streamDeltaPath = "delta.text"
            fallbackPath = "delta"
        } else {
            responsePath = "choices.0.message.content"
            streamDeltaPath = "choices.0.delta.content"
            fallbackPath = "delta"
        }

        let cfg = AICustomPostConfig(
            endpointURL: endpointURL,
            headers: finalHeaders,
            bodyTemplate: finalBody.isEmpty ? AICustomPostConfig.defaultBodyTemplate : finalBody,
            responsePath: responsePath,
            streamDeltaPath: streamDeltaPath,
            streamEventTextFallback: fallbackPath,
            defaultModel: detectedModel,
            useSSEResponse: sseFlag,
            allowEmptyModel: true
        )
        return ParsedResult(config: cfg, detectedModel: detectedModel)
    }

    private static func extractModelString(fromJSONText text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let m = obj["model"] as? String else {
            return ""
        }
        return m.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces literal top-level JSON fields (`model`, `messages`, `input`, `contents`, `prompt`, `stream`)
    /// with 3012 placeholders so imported requests immediately work dynamically in AI Agent chats.
    public static func injectTemplatePlaceholders(in body: String, detectedModel: inout String) -> String {
        var result = body
        if let extracted = extractJSONStringFieldValue(named: "model", in: result) {
            if !extracted.contains("{{") {
                detectedModel = extracted
                result = replaceTopLevelJSONFieldValue(named: "model", in: result, withRawLiteral: "\"{{model}}\"")
            }
        }
        result = replaceTopLevelJSONFieldValue(named: "messages", in: result, withRawLiteral: "{{messages}}")
        result = replaceTopLevelJSONFieldValue(named: "input", in: result, withRawLiteral: "{{responses_input}}")
        result = replaceTopLevelJSONFieldValue(named: "contents", in: result, withRawLiteral: "{{gemini_contents}}")
        result = replaceTopLevelJSONFieldValue(named: "prompt", in: result, withRawLiteral: "\"{{prompt}}\"")
        result = replaceTopLevelJSONFieldValue(named: "stream", in: result, withRawLiteral: "{{stream}}")
        return result
    }

    private static func extractJSONStringFieldValue(named key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj[key] as? String
    }

    /// Replaces the raw JSON value token of a top-level key at brace depth 1 while preserving JSON formatting.
    private static func replaceTopLevelJSONFieldValue(named targetKey: String, in text: String, withRawLiteral replacement: String) -> String {
        let chars = Array(text)
        let n = chars.count
        var i = 0
        var depth = 0
        var inString = false
        var escaped = false

        while i < n {
            let c = chars[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            if c == "\"" {
                // Only inspect top-level object keys (`depth == 1`).
                if depth == 1 {
                    let keyStart = i + 1
                    var j = keyStart
                    var esc = false
                    while j < n {
                        let kc = chars[j]
                        if esc { esc = false }
                        else if kc == "\\" { esc = true }
                        else if kc == "\"" { break }
                        j += 1
                    }
                    if j < n {
                        let keyName = String(chars[keyStart..<j])
                        var k = j + 1
                        while k < n && (chars[k] == " " || chars[k] == "\t" || chars[k] == "\n" || chars[k] == "\r") { k += 1 }
                        if k < n && chars[k] == ":" && keyName == targetKey {
                            var valStart = k + 1
                            while valStart < n && (chars[valStart] == " " || chars[valStart] == "\t" || chars[valStart] == "\n" || chars[valStart] == "\r") {
                                valStart += 1
                            }
                            if let valEnd = scanJSONValueEnd(chars: chars, from: valStart) {
                                let prefix = String(chars[0..<valStart])
                                let suffix = String(chars[valEnd..<n])
                                return prefix + replacement + suffix
                            }
                        }
                        i = j + 1
                        continue
                    }
                }
                inString = true
            } else if c == "{" || c == "[" {
                depth += 1
            } else if c == "}" || c == "]" {
                depth = max(0, depth - 1)
            }
            i += 1
        }
        return text
    }

    private static func scanJSONValueEnd(chars: [Character], from start: Int) -> Int? {
        let n = chars.count
        guard start < n else { return nil }
        let first = chars[start]
        if first == "\"" {
            var i = start + 1
            var esc = false
            while i < n {
                if esc { esc = false }
                else if chars[i] == "\\" { esc = true }
                else if chars[i] == "\"" { return i + 1 }
                i += 1
            }
            return nil
        }
        if first == "{" || first == "[" {
            var depth = 0
            var inStr = false
            var esc = false
            var i = start
            while i < n {
                let c = chars[i]
                if inStr {
                    if esc { esc = false }
                    else if c == "\\" { esc = true }
                    else if c == "\"" { inStr = false }
                } else {
                    if c == "\"" { inStr = true }
                    else if c == "{" || c == "[" { depth += 1 }
                    else if c == "}" || c == "]" {
                        depth -= 1
                        if depth == 0 { return i + 1 }
                    }
                }
                i += 1
            }
            return nil
        }
        var i = start
        while i < n && ![",", "}", "]", "\n", "\r", " ", "\t"].contains(chars[i]) {
            i += 1
        }
        return i > start ? i : nil
    }

    private static func tokenizeShellWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var hasCurrent = false
        var quote: Character? = nil
        var escaped = false
        var ansiDollar = false

        let chars = Array(command)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped {
                if quote != nil && ansiDollar {
                    switch c {
                    case "n": current.append("\n")
                    case "r": current.append("\r")
                    case "t": current.append("\t")
                    default: current.append(c)
                    }
                } else {
                    current.append(c)
                }
                escaped = false
                hasCurrent = true
                i += 1
                continue
            }

            if let q = quote {
                if c == q {
                    quote = nil
                    ansiDollar = false
                    hasCurrent = true
                } else if c == "\\" && (q == "\"" || ansiDollar) {
                    escaped = true
                } else {
                    current.append(c)
                }
                i += 1
                continue
            }

            if c == "$" && i + 1 < chars.count && chars[i + 1] == "'" {
                quote = "'"
                ansiDollar = true
                hasCurrent = true
                i += 2
                continue
            }
            if c == "'" || c == "\"" {
                quote = c
                hasCurrent = true
                i += 1
                continue
            }
            if c == "\\" {
                escaped = true
                hasCurrent = true
                i += 1
                continue
            }
            if c.isWhitespace {
                if hasCurrent {
                    words.append(current)
                    current = ""
                    hasCurrent = false
                }
                i += 1
                continue
            }
            current.append(c)
            hasCurrent = true
            i += 1
        }
        if hasCurrent {
            words.append(current)
        }
        return words
    }
}

// MARK: - Model Selection Strategy

public enum AIModelSelectionMode: String, Codable, CaseIterable, Identifiable {
    /// Always use the newest flagship model published by the provider (auto-updated).
    case latestFlagship
    /// Always use the newest fast / low-cost model (mini, flash, haiku, nano...).
    case latestFast
    /// Pin an explicit model ID chosen by the user.
    case fixed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .latestFlagship: return "Mới nhất"
        case .latestFast: return "Mới nhất (nhanh)"
        case .fixed: return "Cố định"
        }
    }
}

// MARK: - Model Metadata (fetched live from the provider)

public struct AIModelInfo: Codable, Identifiable, Hashable {
    public var id: String
    public var displayName: String
    public var createdAt: Date?
    public var contextWindow: Int?

    public init(id: String, displayName: String? = nil, createdAt: Date? = nil, contextWindow: Int? = nil) {
        self.id = id
        self.displayName = (displayName?.isEmpty == false) ? displayName! : id
        self.createdAt = createdAt
        self.contextWindow = contextWindow
    }
}

// MARK: - Provider Presets (templates only — no hard-coded model names)

public struct AIProviderPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let format: AIAPIFormat
    public let baseURL: String
    public let requiresAPIKey: Bool
    public let isLocal: Bool
    public let symbol: String
    public let defaultModelFilter: String
    public let note: String

    public static let all: [AIProviderPreset] = [
        AIProviderPreset(id: "openai", name: "OpenAI", format: .openAICompatible,
                         baseURL: "https://api.openai.com/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "GPT / o-series"),
        AIProviderPreset(id: "openai_responses", name: "OpenAI Responses (/responses)", format: .openAIResponses,
                         baseURL: "https://api.openai.com/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "bolt.horizontal.circle", defaultModelFilter: "",
                         note: "Hỗ trợ o1-pro / o3-pro / GPT Responses API"),
        AIProviderPreset(id: "anthropic", name: "Anthropic Claude", format: .anthropic,
                         baseURL: "https://api.anthropic.com/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Claude Opus / Sonnet / Haiku"),
        AIProviderPreset(id: "gemini", name: "Google Gemini", format: .gemini,
                         baseURL: "https://generativelanguage.googleapis.com/v1beta", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "gemini", note: "Gemini Pro / Flash"),
        AIProviderPreset(id: "deepseek", name: "DeepSeek", format: .openAICompatible,
                         baseURL: "https://api.deepseek.com/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "DeepSeek Chat / Reasoner"),
        AIProviderPreset(id: "openrouter", name: "OpenRouter", format: .openAICompatible,
                         baseURL: "https://openrouter.ai/api/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "point.3.connected.trianglepath.dotted", defaultModelFilter: "openai/, anthropic/, google/",
                         note: "Hàng trăm model qua 1 API key"),
        AIProviderPreset(id: "xai", name: "xAI Grok", format: .openAICompatible,
                         baseURL: "https://api.x.ai/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Grok"),
        AIProviderPreset(id: "mistral", name: "Mistral AI", format: .openAICompatible,
                         baseURL: "https://api.mistral.ai/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Mistral / Codestral"),
        AIProviderPreset(id: "groq", name: "Groq", format: .openAICompatible,
                         baseURL: "https://api.groq.com/openai/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "bolt", defaultModelFilter: "", note: "Suy luận tốc độ cao"),
        AIProviderPreset(id: "together", name: "Together AI", format: .openAICompatible,
                         baseURL: "https://api.together.xyz/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Model mã nguồn mở"),
        AIProviderPreset(id: "fireworks", name: "Fireworks AI", format: .openAICompatible,
                         baseURL: "https://api.fireworks.ai/inference/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Model mã nguồn mở"),
        AIProviderPreset(id: "moonshot", name: "Moonshot Kimi", format: .openAICompatible,
                         baseURL: "https://api.moonshot.ai/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "Kimi"),
        AIProviderPreset(id: "qwen", name: "Alibaba Qwen", format: .openAICompatible,
                         baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "qwen", note: "Qwen (DashScope)"),
        AIProviderPreset(id: "zai", name: "Z.ai GLM", format: .openAICompatible,
                         baseURL: "https://api.z.ai/api/paas/v4", requiresAPIKey: true, isLocal: false,
                         symbol: "cloud", defaultModelFilter: "", note: "GLM"),
        AIProviderPreset(id: "custom", name: "Tuỳ chỉnh (OpenAI-compatible)", format: .openAICompatible,
                         baseURL: "https://", requiresAPIKey: false, isLocal: false,
                         symbol: "server.rack", defaultModelFilter: "", note: "Proxy riêng, VPS, vLLM, LiteLLM..."),
        AIProviderPreset(id: "custom_post", name: "Custom POST API (Tự cấu hình)", format: .customPost,
                         baseURL: "https://api.example.com/v1/chat/completions", requiresAPIKey: false, isLocal: false,
                         symbol: "paperplane.fill", defaultModelFilter: "",
                         note: "Tự cấu hình URL, Header, Body JSON, Import cURL / Raw HTTP & Live Inspector"),

        // Offline / Local
        AIProviderPreset(id: "apple", name: "Apple On-Device", format: .appleOnDevice,
                         baseURL: "", requiresAPIKey: false, isLocal: true,
                         symbol: "iphone", defaultModelFilter: "", note: "Offline 100% trên iPhone (iOS 26+)"),
        AIProviderPreset(id: "ollama", name: "Ollama (LAN)", format: .openAICompatible,
                         baseURL: "http://192.168.1.10:11434/v1", requiresAPIKey: false, isLocal: true,
                         symbol: "desktopcomputer", defaultModelFilter: "", note: "Máy tính / server trong mạng Wi-Fi"),
        AIProviderPreset(id: "lmstudio", name: "LM Studio (LAN)", format: .openAICompatible,
                         baseURL: "http://192.168.1.10:1234/v1", requiresAPIKey: false, isLocal: true,
                         symbol: "desktopcomputer", defaultModelFilter: "", note: "Máy tính trong mạng Wi-Fi")
    ]

    public static func preset(id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}

// MARK: - User Provider Profile (persisted; API key lives in the Keychain)

public struct AIProviderProfile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var presetID: String
    public var format: AIAPIFormat
    public var baseURL: String
    public var selectionMode: AIModelSelectionMode
    public var fixedModelID: String
    public var modelFilter: String
    public var cachedModels: [AIModelInfo]
    public var lastModelRefresh: Date?
    public var useCustomTemperature: Bool
    public var temperature: Double
    public var maxOutputTokens: Int
    public var customPostConfig: AICustomPostConfig?

    public init(preset: AIProviderPreset) {
        self.id = UUID()
        self.name = preset.name
        self.presetID = preset.id
        self.format = preset.format
        self.baseURL = preset.baseURL
        if preset.format == .customPost {
            self.selectionMode = .fixed
            self.fixedModelID = "gpt-4o"
            self.customPostConfig = AICustomPostConfig(endpointURL: preset.baseURL)
        } else {
            self.selectionMode = .latestFlagship
            self.fixedModelID = ""
            self.customPostConfig = nil
        }
        self.modelFilter = preset.defaultModelFilter
        self.cachedModels = []
        self.lastModelRefresh = nil
        self.useCustomTemperature = false
        self.temperature = 0.2
        self.maxOutputTokens = 8192
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, presetID, format, baseURL, selectionMode, fixedModelID, modelFilter
        case cachedModels, lastModelRefresh, useCustomTemperature, temperature, maxOutputTokens
        case customPostConfig
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "AI"
        presetID = try c.decodeIfPresent(String.self, forKey: .presetID) ?? "custom"
        format = try c.decodeIfPresent(AIAPIFormat.self, forKey: .format) ?? .openAICompatible
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        selectionMode = try c.decodeIfPresent(AIModelSelectionMode.self, forKey: .selectionMode) ?? .latestFlagship
        fixedModelID = try c.decodeIfPresent(String.self, forKey: .fixedModelID) ?? ""
        modelFilter = try c.decodeIfPresent(String.self, forKey: .modelFilter) ?? ""
        cachedModels = try c.decodeIfPresent([AIModelInfo].self, forKey: .cachedModels) ?? []
        lastModelRefresh = try c.decodeIfPresent(Date.self, forKey: .lastModelRefresh)
        useCustomTemperature = try c.decodeIfPresent(Bool.self, forKey: .useCustomTemperature) ?? false
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.2
        maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens) ?? 8192
        customPostConfig = try c.decodeIfPresent(AICustomPostConfig.self, forKey: .customPostConfig)
    }

    public var keychainAccount: String { "ai.apikey.\(id.uuidString)" }
    public var customHeadersKeychainAccount: String { "ai.customheaders.\(id.uuidString)" }
    public var preset: AIProviderPreset? { AIProviderPreset.preset(id: presetID) }
    public var requiresAPIKey: Bool {
        if format == .customPost {
            let cfg = customPostConfig ?? AICustomPostConfig(endpointURL: baseURL)
            if cfg.bodyTemplate.contains("{{api_key}}") || cfg.endpointURL.contains("{{api_key}}") {
                return true
            }
            return cfg.headers.contains { $0.isEnabled && $0.value.contains("{{api_key}}") }
        }
        return preset?.requiresAPIKey ?? (format != .appleOnDevice)
    }
    public var isLocal: Bool { preset?.isLocal ?? false }

    /// The model actually used for the next request.
    public var resolvedModelID: String {
        if format == .appleOnDevice { return "apple-on-device" }
        let fixed = fixedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if format == .customPost {
            if !fixed.isEmpty { return fixed }
            let cfgDefault = customPostConfig?.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cfgDefault.isEmpty { return cfgDefault }
            if !cachedModels.isEmpty, selectionMode != .fixed {
                return AIModelRanker.pickLatest(
                    from: cachedModels,
                    mode: selectionMode,
                    presetID: presetID,
                    filter: modelFilter,
                    format: format
                )?.id ?? ""
            }
            return ""
        }
        if selectionMode == .fixed { return fixed }
        return AIModelRanker.pickLatest(
            from: cachedModels,
            mode: selectionMode,
            presetID: presetID,
            filter: modelFilter,
            format: format
        )?.id ?? fixed
    }
}

// MARK: - Latest-Model Ranking (vendor-agnostic heuristics)

public enum AIModelRanker {
    /// Non-chat endpoints that would fail on a chat request.
    private static let excludedSubstrings: [String] = [
        "embed", "whisper", "tts", "transcribe", "dall-e", "moderation", "image", "imagen",
        "veo", "sora", "audio", "realtime", "davinci", "babbage", "rerank", "aqa",
        "deep-research", "computer-use", "native-audio", "lyria"
    ]
    private static let excludedTokens: Set<String> = ["live", "search", "guard", "ocr", "speech", "vl-embedding"]
    private static let fastTokens: Set<String> = [
        "mini", "nano", "flash", "haiku", "lite", "small", "fast", "instant", "tiny", "1b", "3b", "7b", "8b"
    ]

    static func tokens(_ id: String) -> [String] {
        id.lowercased()
            .split(whereSeparator: { "-_/:. ".contains($0) })
            .map(String.init)
    }

    public static func isChatCandidate(_ id: String, presetID: String, format: AIAPIFormat = .openAICompatible) -> Bool {
        let lower = id.lowercased()
        if excludedSubstrings.contains(where: { lower.contains($0) }) { return false }
        let toks = tokens(id)
        if toks.contains(where: { excludedTokens.contains($0) }) { return false }
        // Legacy completion/instruct models across all presets.
        if lower.contains("-instruct") || toks.contains("instruct") {
            return false
        }
        // Only filter Responses-API `-pro` models when using Chat Completions endpoints.
        if format != .openAIResponses && format != .customPost {
            if lower == "o1-pro" || lower.hasSuffix("/o1-pro") {
                return false
            }
            if (presetID == "openai" || lower.hasPrefix("openai/")) && toks.last == "pro" {
                return false
            }
        }
        if presetID == "openai" || lower.hasPrefix("openai/") {
            if lower.hasPrefix("text-") || lower.hasPrefix("ada") || lower.hasPrefix("curie") { return false }
        }
        return true
    }

    public static func isFast(_ id: String) -> Bool {
        tokens(id).contains(where: { fastTokens.contains($0) })
    }

    public static func isSnapshotOrPreview(_ id: String) -> Bool {
        let lower = id.lowercased()
        if lower.contains("preview") || lower.contains("-exp") || lower.contains("experimental") { return true }
        if lower.range(of: #"\d{4}-?\d{2}-?\d{2}"#, options: .regularExpression) != nil { return true }
        return lower.range(of: #"-\d{3,4}$"#, options: .regularExpression) != nil
    }

    /// Extracts the weighted model generation score: `4.10` (41000) > `4.5` (40500) > `4.1` (40100).
    public static func versionScore(_ id: String) -> Double {
        let lower = id.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)(?:\.(\d+)(?:\.(\d+))?)?"#) else { return 0 }
        let ns = lower as NSString
        let matches = regex.matches(in: lower, range: NSRange(location: 0, length: ns.length))
        var idx = 0
        while idx < matches.count {
            let m = matches[idx]
            let major = ns.substring(with: m.range(at: 1))
            let end = m.range.location + m.range.length
            if major.count >= 4 { idx += 1; continue } // dates / build numbers
            if end < ns.length {
                let next = ns.substring(with: NSRange(location: end, length: 1))
                if next == "b" || next == "k" || next == "x" || next == "m" { idx += 1; continue } // param sizes
            }
            let majorInt = Int(major) ?? 0
            var minorInt = 0
            var patchInt = 0
            if m.range(at: 2).location != NSNotFound {
                minorInt = Int(ns.substring(with: m.range(at: 2))) ?? 0
                if m.range(at: 3).location != NSNotFound {
                    patchInt = Int(ns.substring(with: m.range(at: 3))) ?? 0
                }
            } else if idx + 1 < matches.count, end < ns.length {
                let n = matches[idx + 1]
                let minorStr = ns.substring(with: n.range(at: 1))
                let separator = ns.substring(with: NSRange(location: end, length: 1))
                let nEnd = n.range.location + n.range.length
                let followedBySize = nEnd < ns.length && ["b", "k", "x", "m"].contains(ns.substring(with: NSRange(location: nEnd, length: 1)))
                if separator == "-", n.range.location == end + 1, minorStr.count <= 2,
                   n.range(at: 2).location == NSNotFound, !followedBySize {
                    minorInt = Int(minorStr) ?? 0
                }
            }
            return Double(majorInt * 10_000 + minorInt * 100 + patchInt)
        }
        return 0
    }

    static func isNewer(_ a: AIModelInfo, than b: AIModelInfo) -> Bool {
        if let da = a.createdAt, let db = b.createdAt, abs(da.timeIntervalSince(db)) > 2 * 86_400 {
            return da > db
        }
        let va = versionScore(a.id), vb = versionScore(b.id)
        if va != vb { return va > vb }
        let sa = isSnapshotOrPreview(a.id), sb = isSnapshotOrPreview(b.id)
        if sa != sb { return !sa }
        if let da = a.createdAt, let db = b.createdAt, da != db { return da > db }
        if a.id.count != b.id.count { return a.id.count < b.id.count }
        return a.id < b.id
    }

    public static func rankedCandidates(
        from models: [AIModelInfo],
        presetID: String,
        filter: String,
        format: AIAPIFormat = .openAICompatible
    ) -> [AIModelInfo] {
        let filterTokens = filter
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var candidates = models.filter { isChatCandidate($0.id, presetID: presetID, format: format) }
        if !filterTokens.isEmpty {
            candidates = candidates.filter { model in
                let hay = (model.id + " " + model.displayName).lowercased()
                return filterTokens.contains { hay.contains($0) }
            }
        }
        return candidates.sorted { isNewer($0, than: $1) }
    }

    public static func pickLatest(
        from models: [AIModelInfo],
        mode: AIModelSelectionMode,
        presetID: String,
        filter: String,
        format: AIAPIFormat = .openAICompatible
    ) -> AIModelInfo? {
        let ranked = rankedCandidates(from: models, presetID: presetID, filter: filter, format: format)
        guard !ranked.isEmpty else { return nil }
        switch mode {
        case .latestFast:
            return ranked.first(where: { isFast($0.id) }) ?? ranked.first
        case .latestFlagship, .fixed:
            return ranked.first(where: { !isFast($0.id) }) ?? ranked.first
        }
    }
}
