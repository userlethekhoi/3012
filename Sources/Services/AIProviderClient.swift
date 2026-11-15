import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Errors

public enum AIProviderError: LocalizedError {
    case invalidURL(String)
    case http(Int, String)
    case unavailable(String)
    case emptyResponse

    public var statusCode: Int? {
        if case .http(let code, _) = self { return code }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let raw): return "Base URL không hợp lệ: \(raw)"
        case .http(let code, let message): return code > 0 ? "HTTP \(code): \(message)" : message
        case .unavailable(let reason): return reason
        case .emptyResponse: return "Model không trả về nội dung."
        }
    }
}

public struct AIAttachmentImage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let jpegData: Data
    public let width: Int
    public let height: Int

    public init(id: UUID = UUID(), jpegData: Data, width: Int, height: Int) {
        self.id = id
        self.jpegData = jpegData
        self.width = width
        self.height = height
    }

    public var base64JPEG: String {
        jpegData.base64EncodedString()
    }
}

public struct AIChatTurn: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String
    public let attachments: [AIAttachmentImage]

    public init(role: Role, text: String, attachments: [AIAttachmentImage] = []) {
        self.role = role
        self.text = text
        self.attachments = attachments
    }
}

// MARK: - URL Normalization (prevents duplicate /v1/v1 or endpoint suffix duplication)

public enum AIURLBuilder {
    static func normalize(_ raw: String) -> (url: String, isExactEndpoint: Bool) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("#") {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("/") { s.removeLast() }
            return (s, true)
        }
        while s.hasSuffix("/") { s.removeLast() }
        return (collapseDuplicateV1(in: s), false)
    }

    static func collapseDuplicateV1(in raw: String) -> String {
        var result = raw
        while result.contains("/v1/v1") {
            result = result.replacingOccurrences(of: "/v1/v1", with: "/v1")
        }
        return result
    }

    public static func modelsURL(base raw: String) -> URL? {
        let (clean, _) = normalize(raw)
        guard !clean.isEmpty else { return nil }
        let stripped: String
        if clean.hasSuffix("/chat/completions") {
            stripped = String(clean.dropLast("/chat/completions".count))
        } else if clean.hasSuffix("/responses") {
            stripped = String(clean.dropLast("/responses".count))
        } else if clean.hasSuffix("/messages") {
            stripped = String(clean.dropLast("/messages".count))
        } else if clean.hasSuffix("/models") {
            return URL(string: clean)
        } else {
            stripped = clean
        }
        return URL(string: collapseDuplicateV1(in: stripped + "/models"))
    }

    public static func chatCompletionsURL(base raw: String) -> URL? {
        let (clean, isExact) = normalize(raw)
        guard !clean.isEmpty else { return nil }
        if isExact || clean.hasSuffix("/chat/completions") {
            return URL(string: clean)
        }
        if clean.hasSuffix("/v1/chat") {
            return URL(string: clean + "/completions")
        }
        return URL(string: collapseDuplicateV1(in: clean + "/chat/completions"))
    }

    public static func responsesURL(base raw: String) -> URL? {
        let (clean, isExact) = normalize(raw)
        guard !clean.isEmpty else { return nil }
        if isExact || clean.hasSuffix("/responses") {
            return URL(string: clean)
        }
        if clean.hasSuffix("/chat/completions") {
            let root = String(clean.dropLast("/chat/completions".count))
            return URL(string: collapseDuplicateV1(in: root + "/responses"))
        }
        return URL(string: collapseDuplicateV1(in: clean + "/responses"))
    }

    public static func anthropicMessagesURL(base raw: String) -> URL? {
        let (clean, isExact) = normalize(raw)
        guard !clean.isEmpty else { return nil }
        if isExact || clean.hasSuffix("/messages") {
            return URL(string: clean)
        }
        return URL(string: collapseDuplicateV1(in: clean + "/messages"))
    }

    public static func geminiStreamURL(base raw: String, model: String) -> URL? {
        let (clean, isExact) = normalize(raw)
        guard !clean.isEmpty else { return nil }
        if isExact || clean.contains(":streamGenerateContent") {
            return URL(string: clean)
        }
        let modelPath = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let encodedModelPath = modelPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelPath
        return URL(string: "\(clean)/models/\(encodedModelPath):streamGenerateContent?alt=sse")
    }
}

// MARK: - Live Custom POST Inspection Result

public struct AICustomPostInspectionResult: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let endpointURL: String
    public let httpMethod: String
    public let statusCode: Int?
    public let durationSeconds: Double
    public let responseByteCount: Int
    public let renderedRequestText: String
    public let rawResponseText: String
    public let extractedAssistantText: String
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        endpointURL: String,
        httpMethod: String = "POST",
        statusCode: Int?,
        durationSeconds: Double,
        responseByteCount: Int,
        renderedRequestText: String,
        rawResponseText: String,
        extractedAssistantText: String,
        errorMessage: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endpointURL = endpointURL
        self.httpMethod = httpMethod
        self.statusCode = statusCode
        self.durationSeconds = durationSeconds
        self.responseByteCount = responseByteCount
        self.renderedRequestText = renderedRequestText
        self.rawResponseText = rawResponseText
        self.extractedAssistantText = extractedAssistantText
        self.errorMessage = errorMessage
    }

    public var formattedDuration: String {
        String(format: "%.2fs", durationSeconds)
    }

    public var formattedBytes: String {
        if responseByteCount < 1024 {
            return "\(responseByteCount) B"
        }
        return String(format: "%.1fkb", Double(responseByteCount) / 1024.0)
    }
}

// MARK: - Generic Provider Client (model discovery + realtime streaming)

public enum AIProviderClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 180
        cfg.timeoutIntervalForResource = 900
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private static func makeStreamingSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 900
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    public static func defaultUserAgentString() -> String {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "5.3.0"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "3012/\(appVersion) (iOS \(os.majorVersion).\(os.minorVersion))"
    }

    private static func applyStandardHeaders(to req: inout URLRequest) {
        let hasUA = req.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) ?? false
        if !hasUA {
            req.setValue(defaultUserAgentString(), forHTTPHeaderField: "User-Agent")
        }
    }

    private static let isoLock = NSLock()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoStandardFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func normalizedBase(_ raw: String) -> String {
        AIURLBuilder.normalize(raw).url
    }

    // MARK: Model Discovery

    public static func listModels(format: AIAPIFormat, baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        let base = normalizedBase(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .openAICompatible, .openAIResponses, .customPost:
            return try await listOpenAICompatibleModels(base: base, key: key)
        case .anthropic:
            return try await listAnthropicModels(base: base, key: key)
        case .gemini:
            return try await listGeminiModels(base: base, key: key)
        case .appleOnDevice:
            let status = appleOnDeviceStatus()
            guard status.available else { throw AIProviderError.unavailable(status.detail) }
            return [AIModelInfo(id: "apple-on-device", displayName: "Apple Intelligence On-Device")]
        }
    }

    private static func listOpenAICompatibleModels(base: String, key: String) async throws -> [AIModelInfo] {
        guard let url = AIURLBuilder.modelsURL(base: base) else { throw AIProviderError.invalidURL(base) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        applyStandardHeaders(to: &req)
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let json = try await fetchJSON(req)

        let items: [[String: Any]]
        if let dict = json as? [String: Any], let data = dict["data"] as? [[String: Any]] {
            items = data
        } else if let dict = json as? [String: Any], let models = dict["models"] as? [[String: Any]] {
            items = models
        } else if let arr = json as? [[String: Any]] {
            items = arr
        } else {
            items = []
        }

        return items.compactMap { item in
            guard let id = (item["id"] as? String) ?? (item["model"] as? String) ?? (item["name"] as? String) else { return nil }
            let created = unixDate(item["created"]) ?? isoDate(item["created_at"] as? String)
            let ctx = intValue(item["context_length"]) ?? intValue(item["context_window"]) ?? intValue(item["max_context_length"])
            let name = (item["name"] as? String) ?? (item["display_name"] as? String) ?? id
            return AIModelInfo(id: id, displayName: name, createdAt: created, contextWindow: ctx)
        }
    }

    private static func listAnthropicModels(base: String, key: String) async throws -> [AIModelInfo] {
        guard let modelsURL = AIURLBuilder.modelsURL(base: base),
              var comps = URLComponents(url: modelsURL, resolvingAgainstBaseURL: false) else {
            throw AIProviderError.invalidURL(base)
        }
        comps.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        guard let url = comps.url else { throw AIProviderError.invalidURL(base) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        applyStandardHeaders(to: &req)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let json = try await fetchJSON(req)
        guard let dict = json as? [String: Any], let data = dict["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return AIModelInfo(
                id: id,
                displayName: item["display_name"] as? String,
                createdAt: isoDate(item["created_at"] as? String)
            )
        }
    }

    private static func listGeminiModels(base: String, key: String) async throws -> [AIModelInfo] {
        var result: [AIModelInfo] = []
        var pageToken: String? = nil
        for _ in 0..<6 {
            guard var comps = URLComponents(string: base + "/models") else { throw AIProviderError.invalidURL(base) }
            var query = [URLQueryItem(name: "pageSize", value: "1000")]
            if let token = pageToken { query.append(URLQueryItem(name: "pageToken", value: token)) }
            comps.queryItems = query
            guard let url = comps.url else { throw AIProviderError.invalidURL(base) }
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            applyStandardHeaders(to: &req)
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let json = try await fetchJSON(req)
            guard let dict = json as? [String: Any] else { break }
            for item in (dict["models"] as? [[String: Any]]) ?? [] {
                guard let rawName = item["name"] as? String else { continue }
                let methods = (item["supportedGenerationMethods"] as? [String]) ?? []
                guard methods.isEmpty || methods.contains("generateContent") else { continue }
                let id = rawName.hasPrefix("models/") ? String(rawName.dropFirst(7)) : rawName
                result.append(AIModelInfo(
                    id: id,
                    displayName: item["displayName"] as? String,
                    contextWindow: intValue(item["inputTokenLimit"])
                ))
            }
            pageToken = dict["nextPageToken"] as? String
            if pageToken?.isEmpty ?? true { break }
        }
        return result
    }

    // MARK: Realtime Streaming Chat

    public static func streamChat(
        format: AIAPIFormat,
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        history: [AIChatTurn],
        temperature: Double?,
        maxOutputTokens: Int,
        customConfig: AICustomPostConfig? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let rawBase = baseURL
        let base = normalizedBase(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let emit: (String) -> Void = { continuation.yield($0) }
                    switch format {
                    case .openAICompatible:
                        try await streamOpenAICompatible(base: rawBase, key: key, model: model, system: systemPrompt,
                                                         history: history, temperature: temperature,
                                                         maxTokens: maxOutputTokens, emit: emit)
                    case .openAIResponses:
                        try await streamOpenAIResponses(base: rawBase, key: key, model: model, system: systemPrompt,
                                                        history: history, temperature: temperature,
                                                        maxTokens: maxOutputTokens, emit: emit)
                    case .anthropic:
                        try await streamAnthropic(base: rawBase, key: key, model: model, system: systemPrompt,
                                                  history: history, temperature: temperature,
                                                  maxTokens: maxOutputTokens, emit: emit)
                    case .gemini:
                        try await streamGemini(base: rawBase, key: key, model: model, system: systemPrompt,
                                               history: history, temperature: temperature,
                                               maxTokens: maxOutputTokens, emit: emit)
                    case .customPost:
                        let cfg = customConfig ?? AICustomPostConfig(endpointURL: base.isEmpty ? rawBase : base)
                        try await streamCustomPost(config: cfg, key: key, model: model, system: systemPrompt,
                                                   history: history, temperature: temperature,
                                                   maxTokens: maxOutputTokens, emit: emit)
                    case .appleOnDevice:
                        try await runAppleOnDevice(system: systemPrompt, history: history, emit: emit)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func buildOpenAIMessages(system: String, history: [AIChatTurn], includeSystem: Bool) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if includeSystem && !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for turn in history {
            if turn.attachments.isEmpty {
                messages.append(["role": turn.role.rawValue, "content": turn.text])
            } else {
                var parts: [[String: Any]] = []
                if !turn.text.isEmpty {
                    parts.append(["type": "text", "text": turn.text])
                }
                for img in turn.attachments {
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(img.base64JPEG)"]
                    ])
                }
                messages.append(["role": turn.role.rawValue, "content": parts])
            }
        }
        return messages
    }

    private static func buildResponsesInput(history: [AIChatTurn]) -> [[String: Any]] {
        history.map { turn in
            if turn.attachments.isEmpty || turn.role == .assistant {
                return ["role": turn.role.rawValue, "content": turn.text]
            }
            var parts: [[String: Any]] = []
            if !turn.text.isEmpty {
                parts.append(["type": "input_text", "text": turn.text])
            }
            for img in turn.attachments {
                parts.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(img.base64JPEG)"
                ])
            }
            return ["role": "user", "content": parts]
        }
    }

    private static func buildGeminiContents(history: [AIChatTurn]) -> [[String: Any]] {
        history.map { turn in
            var parts: [[String: Any]] = turn.attachments.map { img in
                ["inlineData": ["mimeType": "image/jpeg", "data": img.base64JPEG]]
            }
            if !turn.text.isEmpty || parts.isEmpty {
                parts.append(["text": turn.text])
            }
            return ["role": turn.role == .user ? "user" : "model", "parts": parts]
        }
    }

    private static func isReasoningModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        let lastSeg = lower.split(separator: "/").last.map(String.init) ?? lower
        return lastSeg.hasPrefix("o1") || lastSeg.hasPrefix("o3") || lastSeg.hasPrefix("o4")
            || lastSeg.hasSuffix("-pro") || lastSeg.contains("-pro-")
    }

    private static func streamOpenAICompatible(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, maxTokens: Int, emit: (String) -> Void
    ) async throws {
        guard let url = AIURLBuilder.chatCompletionsURL(base: base) else { throw AIProviderError.invalidURL(base) }
        let messages = buildOpenAIMessages(system: system, history: history, includeSystem: true)
        var payload: [String: Any] = ["model": model, "messages": messages, "stream": true]
        if let temperature, !isReasoningModel(model) { payload["temperature"] = temperature }
        if maxTokens > 0 { payload["max_tokens"] = maxTokens }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyStandardHeaders(to: &req)
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if base.contains("openrouter.ai") {
            req.setValue("https://github.com/userlethekhoi/3012", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("3012 Mobile IDE", forHTTPHeaderField: "X-Title")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var produced = false
        let leftover = try await consumeSSE(req) { event in
            if let choices = event["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                produced = true
                emit(content)
            }
        }
        // Some self-hosted servers ignore `stream: true` and return a single JSON body.
        if !produced, let obj = jsonObject(leftover),
           let choices = obj["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String, !content.isEmpty {
            emit(content)
        }
    }

    private static func streamOpenAIResponses(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, maxTokens: Int, emit: (String) -> Void
    ) async throws {
        guard let url = AIURLBuilder.responsesURL(base: base) else { throw AIProviderError.invalidURL(base) }
        var payload: [String: Any] = [
            "model": model,
            "input": buildResponsesInput(history: history),
            "stream": true
        ]
        if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["instructions"] = system
        }
        if let temperature, !isReasoningModel(model) {
            payload["temperature"] = temperature
        }
        if maxTokens > 0 {
            payload["max_output_tokens"] = maxTokens
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyStandardHeaders(to: &req)
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if base.contains("openrouter.ai") {
            req.setValue("https://github.com/userlethekhoi/3012", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("3012 Mobile IDE", forHTTPHeaderField: "X-Title")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var produced = false
        var completedFallbackText = ""

        func extractResponsesOutputText(from dict: [String: Any]) -> String? {
            if let t = dict["output_text"] as? String, !t.isEmpty { return t }
            let target = (dict["response"] as? [String: Any]) ?? dict
            if let t = target["output_text"] as? String, !t.isEmpty { return t }
            if let output = target["output"] as? [[String: Any]] {
                var joined = ""
                for item in output {
                    if let contents = item["content"] as? [[String: Any]] {
                        for part in contents {
                            if let txt = part["text"] as? String {
                                joined += txt
                            }
                        }
                    }
                }
                if !joined.isEmpty { return joined }
            }
            return nil
        }

        let leftover = try await consumeSSE(req) { event in
            let eventType = (event["type"] as? String) ?? ""
            if eventType == "response.failed" || eventType == "error" {
                let errObj = event["error"] ?? (event["response"] as? [String: Any])?["error"]
                throw AIProviderError.http(0, errObj.map { messageText(from: $0) } ?? "Responses API error")
            }
            if eventType == "response.output_text.delta",
               let delta = event["delta"] as? String, !delta.isEmpty {
                produced = true
                emit(delta)
                return
            }
            // Compatibility if proxy relays OpenAI Chat Completions deltas on /responses.
            if let choices = event["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                produced = true
                emit(content)
                return
            }
            if (eventType == "response.completed" || eventType == "response.done") && completedFallbackText.isEmpty {
                completedFallbackText = extractResponsesOutputText(from: event) ?? ""
            }
        }

        if !produced {
            if !completedFallbackText.isEmpty {
                emit(completedFallbackText)
            } else if let obj = jsonObject(leftover), let extracted = extractResponsesOutputText(from: obj) {
                emit(extracted)
            } else if let obj = jsonObject(leftover),
                      let choices = obj["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String, !content.isEmpty {
                emit(content)
            }
        }
    }

    private static func streamAnthropic(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, maxTokens: Int, emit: (String) -> Void
    ) async throws {
        guard let url = AIURLBuilder.anthropicMessagesURL(base: base) else { throw AIProviderError.invalidURL(base) }
        let formattedMessages: [[String: Any]] = history.map { turn in
            if turn.attachments.isEmpty {
                return ["role": turn.role.rawValue, "content": turn.text]
            }
            var blocks: [[String: Any]] = turn.attachments.map { img in
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": img.base64JPEG
                    ]
                ]
            }
            if !turn.text.isEmpty {
                blocks.append(["type": "text", "text": turn.text])
            }
            return ["role": turn.role.rawValue, "content": blocks]
        }
        let lowerModel = model.lowercased()
        let isLegacyClaude3 = lowerModel.contains("claude-3-")
            && !lowerModel.contains("3-5")
            && !lowerModel.contains("3.5")
            && !lowerModel.contains("3-7")
            && !lowerModel.contains("3.7")
        let effectiveMax = isLegacyClaude3 ? min(maxTokens, 4096) : maxTokens
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": max(1024, effectiveMax),
            "system": system,
            "messages": formattedMessages,
            "stream": true
        ]
        if let temperature { payload["temperature"] = min(1.0, temperature) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyStandardHeaders(to: &req)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var produced = false
        let leftover = try await consumeSSE(req) { event in
            guard (event["type"] as? String) == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta",
                  let text = delta["text"] as? String else { return }
            produced = true
            emit(text)
        }
        if !produced, let obj = jsonObject(leftover),
           let contentBlocks = obj["content"] as? [[String: Any]] {
            let text = contentBlocks.compactMap { ($0["type"] as? String) == "text" ? ($0["text"] as? String) : nil }.joined()
            if !text.isEmpty {
                emit(text)
            }
        }
    }

    private static func streamGemini(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, maxTokens: Int, emit: (String) -> Void
    ) async throws {
        guard let url = AIURLBuilder.geminiStreamURL(base: base, model: model) else {
            throw AIProviderError.invalidURL(base)
        }
        var payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": buildGeminiContents(history: history)
        ]
        var genConfig: [String: Any] = [:]
        if let temperature { genConfig["temperature"] = temperature }
        if maxTokens > 0 { genConfig["maxOutputTokens"] = maxTokens }
        if !genConfig.isEmpty { payload["generationConfig"] = genConfig }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyStandardHeaders(to: &req)
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        func emitGeminiEvent(_ event: [String: Any]) throws -> Bool {
            if let feedback = event["promptFeedback"] as? [String: Any],
               let reason = feedback["blockReason"] as? String {
                throw AIProviderError.unavailable("Gemini đã chặn yêu cầu: \(reason)")
            }
            guard let candidates = event["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return false }
            var emitted = false
            for part in parts where (part["thought"] as? Bool) != true {
                if let text = part["text"] as? String, !text.isEmpty {
                    emit(text)
                    emitted = true
                }
            }
            return emitted
        }

        var produced = false
        let leftover = try await consumeSSE(req) { event in
            if try emitGeminiEvent(event) {
                produced = true
            }
        }
        if !produced, !leftover.isEmpty {
            if let obj = jsonObject(leftover) {
                _ = try emitGeminiEvent(obj)
            } else if let data = leftover.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in arr {
                    if let err = item["error"] {
                        throw AIProviderError.http(0, messageText(from: err))
                    }
                    _ = try emitGeminiEvent(item)
                }
            }
        }
    }

    // MARK: - Custom POST API Engine & Live Request/Response Inspector

    public static func renderCustomPostBody(
        template: String,
        model: String,
        system: String,
        history: [AIChatTurn],
        apiKey: String,
        temperature: Double?,
        maxTokens: Int,
        stream: Bool
    ) -> String {
        let messagesJSON = jsonSerializedString(buildOpenAIMessages(system: system, history: history, includeSystem: true), fallback: "[]")
        let messagesNoSysJSON = jsonSerializedString(buildOpenAIMessages(system: system, history: history, includeSystem: false), fallback: "[]")
        let responsesInputJSON = jsonSerializedString(buildResponsesInput(history: history), fallback: "[]")
        let geminiContentsJSON = jsonSerializedString(buildGeminiContents(history: history), fallback: "[]")
        let lastUserPrompt = history.last(where: { $0.role == .user })?.text ?? history.last?.text ?? ""

        let tempNum = temperature.map { String(format: "%.2f", $0) } ?? "0.2"
        let maxTokStr = String(max(256, maxTokens))
        let streamStr = stream ? "true" : "false"

        var output = template
        output = output.replacingOccurrences(of: "{{messages_no_system}}", with: messagesNoSysJSON)
        output = output.replacingOccurrences(of: "{{messages}}", with: messagesJSON)
        output = output.replacingOccurrences(of: "{{responses_input}}", with: responsesInputJSON)
        output = output.replacingOccurrences(of: "{{gemini_contents}}", with: geminiContentsJSON)
        output = output.replacingOccurrences(of: "{{prompt_json}}", with: jsonQuotedString(lastUserPrompt))
        output = output.replacingOccurrences(of: "{{system_json}}", with: jsonQuotedString(system))
        output = output.replacingOccurrences(of: "{{model}}", with: jsonEscapedInnerString(model))
        output = output.replacingOccurrences(of: "{{system}}", with: jsonEscapedInnerString(system))
        output = output.replacingOccurrences(of: "{{prompt}}", with: jsonEscapedInnerString(lastUserPrompt))
        output = output.replacingOccurrences(of: "{{api_key}}", with: jsonEscapedInnerString(apiKey))
        output = output.replacingOccurrences(of: "{{temperature}}", with: tempNum)
        output = output.replacingOccurrences(of: "{{max_tokens}}", with: maxTokStr)
        output = output.replacingOccurrences(of: "{{stream}}", with: streamStr)
        return output
    }

    public static func buildCustomPostURLRequest(
        config: AICustomPostConfig,
        apiKey: String,
        model: String,
        system: String,
        history: [AIChatTurn],
        temperature: Double?,
        maxTokens: Int
    ) throws -> (request: URLRequest, renderedPreview: String) {
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? config.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        let rawURL = config.endpointURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{{model}}", with: effectiveModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? effectiveModel)
            .replacingOccurrences(of: "{{api_key}}", with: apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw AIProviderError.invalidURL(config.endpointURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        var hasContentType = false
        var hasAccept = false
        var previewHeaders: [(String, String)] = []

        for item in config.headers where item.isEnabled {
            let headerKey = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headerKey.isEmpty else { continue }
            let resolvedVal = item.value
                .replacingOccurrences(of: "{{api_key}}", with: apiKey)
                .replacingOccurrences(of: "{{model}}", with: effectiveModel)

            if headerKey.caseInsensitiveCompare("Content-Type") == .orderedSame { hasContentType = true }
            if headerKey.caseInsensitiveCompare("Accept") == .orderedSame { hasAccept = true }
            req.setValue(resolvedVal, forHTTPHeaderField: headerKey)

            let maskedVal: String
            if item.isSecret || (!apiKey.isEmpty && item.value.contains("{{api_key}}")) {
                maskedVal = maskSecretPreview(resolvedVal)
            } else {
                maskedVal = resolvedVal
            }
            previewHeaders.append((headerKey, maskedVal))
        }

        if !hasContentType {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            previewHeaders.append(("Content-Type", "application/json"))
        }
        if !hasAccept && config.useSSEResponse {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            previewHeaders.append(("Accept", "text/event-stream"))
        }

        applyStandardHeaders(to: &req)
        if !previewHeaders.contains(where: { $0.0.caseInsensitiveCompare("User-Agent") == .orderedSame }),
           let ua = req.value(forHTTPHeaderField: "User-Agent") {
            previewHeaders.append(("User-Agent", ua))
        }

        let bodyText = renderCustomPostBody(
            template: config.bodyTemplate,
            model: effectiveModel,
            system: system,
            history: history,
            apiKey: apiKey,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: config.useSSEResponse
        )
        req.httpBody = bodyText.data(using: .utf8)

        let pathWithQuery = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
        var lines: [String] = ["POST \(pathWithQuery) HTTP/1.1"]
        if let host = url.host {
            let portSuffix = url.port.map { ":\($0)" } ?? ""
            lines.append("Host: \(host)\(portSuffix)")
        }
        for (hk, hv) in previewHeaders {
            lines.append("\(hk): \(hv)")
        }
        lines.append("")
        lines.append(bodyText)

        return (req, lines.joined(separator: "\n"))
    }

    public static func extractValue(atDotPath path: String, from root: Any) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "[", with: ".")
            .replacingOccurrences(of: "]", with: "")
        let segments = normalized.split(separator: ".").map(String.init)
        guard !segments.isEmpty else { return nil }

        var current: Any = root
        for seg in segments {
            if let dict = current as? [String: Any] {
                guard let next = dict[seg] else { return nil }
                current = next
            } else if let arr = current as? [Any], let idx = Int(seg), arr.indices.contains(idx) {
                current = arr[idx]
            } else {
                return nil
            }
        }
        if let str = current as? String {
            return str
        }
        if let parts = current as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            return texts.isEmpty ? nil : texts.joined()
        }
        return nil
    }

    public static func extractDeltaOrFullText(
        from event: [String: Any],
        primaryPath: String,
        fallbackPath: String,
        isFinalPass: Bool = false
    ) -> String? {
        let eventType = (event["type"] as? String) ?? ""
        let isTerminalDoneEvent = [
            "response.output_text.done",
            "response.content_part.done",
            "response.output_item.done",
            "response.completed",
            "content_block_stop"
        ].contains(eventType)

        if !isFinalPass && isTerminalDoneEvent {
            return nil
        }

        if let s = extractValue(atDotPath: primaryPath, from: event), !s.isEmpty {
            return s
        }
        if let s = extractValue(atDotPath: fallbackPath, from: event), !s.isEmpty {
            return s
        }

        let candidates = isFinalPass
            ? [
                "choices.0.message.content",
                "output_text",
                "response.output_text",
                "output.0.content.0.text",
                "response.output.0.content.0.text",
                "candidates.0.content.parts.0.text",
                "content.0.text",
                "choices.0.delta.content",
                "delta.text",
                "delta",
                "text",
                "content"
            ]
            : [
                "choices.0.delta.content",
                "delta.text",
                "candidates.0.content.parts.0.text",
                "output_text",
                "choices.0.message.content"
            ]
        for candidate in candidates {
            if candidate == "delta" && !eventType.isEmpty && !eventType.contains("delta") {
                continue
            }
            if let s = extractValue(atDotPath: candidate, from: event), !s.isEmpty {
                return s
            }
        }
        if eventType == "response.output_text.delta", let d = event["delta"] as? String, !d.isEmpty {
            return d
        }
        return nil
    }

    private static func streamCustomPost(
        config: AICustomPostConfig,
        key: String,
        model: String,
        system: String,
        history: [AIChatTurn],
        temperature: Double?,
        maxTokens: Int,
        emit: (String) -> Void
    ) async throws {
        let built = try buildCustomPostURLRequest(
            config: config,
            apiKey: key,
            model: model,
            system: system,
            history: history,
            temperature: temperature,
            maxTokens: maxTokens
        )

        var produced = false
        var finalEvents: [[String: Any]] = []

        if config.useSSEResponse {
            let leftover = try await consumeSSE(built.request) { event in
                if finalEvents.count < 8 { finalEvents.append(event) }
                else { finalEvents[finalEvents.count - 1] = event }
                if let chunk = extractDeltaOrFullText(
                    from: event,
                    primaryPath: config.streamDeltaPath,
                    fallbackPath: config.streamEventTextFallback,
                    isFinalPass: false
                ), !chunk.isEmpty {
                    produced = true
                    emit(chunk)
                }
            }
            if !produced {
                if let obj = jsonObject(leftover),
                   let text = extractDeltaOrFullText(
                       from: obj,
                       primaryPath: config.responsePath,
                       fallbackPath: config.streamDeltaPath,
                       isFinalPass: true
                   ), !text.isEmpty {
                    produced = true
                    emit(text)
                } else {
                    for ev in finalEvents.reversed() {
                        if let text = extractDeltaOrFullText(
                            from: ev,
                            primaryPath: config.responsePath,
                            fallbackPath: config.streamEventTextFallback,
                            isFinalPass: true
                        ), !text.isEmpty {
                            produced = true
                            emit(text)
                            break
                        }
                    }
                }
            }
        } else {
            let streamSession = makeStreamingSession()
            defer { streamSession.finishTasksAndInvalidate() }
            let (data, response) = try await streamSession.data(for: built.request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AIProviderError.http(http.statusCode, extractErrorMessage(data))
            }
            if let json = try? JSONSerialization.jsonObject(with: data) {
                if let dict = json as? [String: Any] {
                    if let err = dict["error"] {
                        throw AIProviderError.http(0, messageText(from: err))
                    }
                    if let text = extractDeltaOrFullText(
                        from: dict,
                        primaryPath: config.responsePath,
                        fallbackPath: config.streamDeltaPath,
                        isFinalPass: true
                    ), !text.isEmpty {
                        emit(text)
                        return
                    }
                } else if let text = extractValue(atDotPath: config.responsePath, from: json), !text.isEmpty {
                    emit(text)
                    return
                }
            }
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !raw.isEmpty {
                emit(raw)
            } else {
                throw AIProviderError.emptyResponse
            }
        }
    }

    /// Executes a live Custom POST request and streams raw bytes + metrics for `AICustomPostInspectorSheet`.
    public static func inspectCustomPost(
        config: AICustomPostConfig,
        apiKey: String,
        model: String,
        prompt: String,
        systemPrompt: String = "You are a helpful coding assistant.",
        temperature: Double? = nil,
        maxOutputTokens: Int = 2048,
        onLiveUpdate: (@MainActor @Sendable (AICustomPostInspectionResult) -> Void)? = nil
    ) async -> AICustomPostInspectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let history = [AIChatTurn(role: .user, text: prompt.isEmpty ? "Hey" : prompt)]

        let built: (request: URLRequest, renderedPreview: String)
        do {
            built = try buildCustomPostURLRequest(
                config: config,
                apiKey: apiKey,
                model: model,
                system: systemPrompt,
                history: history,
                temperature: temperature,
                maxTokens: maxOutputTokens
            )
        } catch {
            return AICustomPostInspectionResult(
                endpointURL: config.endpointURL,
                statusCode: nil,
                durationSeconds: 0,
                responseByteCount: 0,
                renderedRequestText: config.bodyTemplate,
                rawResponseText: "",
                extractedAssistantText: "",
                errorMessage: error.localizedDescription
            )
        }

        let streamSession = makeStreamingSession()
        defer { streamSession.finishTasksAndInvalidate() }

        var capturedStatus: Int? = nil
        var rawData = Data()
        var extracted = ""
        var lineBuffer: [UInt8] = []
        var eventDataLines: [String] = []
        var lastPublishAt = CFAbsoluteTimeGetCurrent()

        func makeSnapshot(error: String? = nil) -> AICustomPostInspectionResult {
            let elapsed = max(0, CFAbsoluteTimeGetCurrent() - start)
            let rawText = String(data: rawData, encoding: .utf8) ?? "<binary \(rawData.count) bytes>"
            return AICustomPostInspectionResult(
                endpointURL: built.request.url?.absoluteString ?? config.endpointURL,
                statusCode: capturedStatus,
                durationSeconds: elapsed,
                responseByteCount: rawData.count,
                renderedRequestText: built.renderedPreview,
                rawResponseText: rawText,
                extractedAssistantText: extracted,
                errorMessage: error
            )
        }

        func consumeInspectorSSELine(_ bytesLine: [UInt8]) {
            var slice = bytesLine
            if slice.last == 0x0D { slice.removeLast() }
            guard let line = String(bytes: slice, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                let payload = eventDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                eventDataLines.removeAll(keepingCapacity: true)
                if !payload.isEmpty && payload != "[DONE]", let obj = jsonObject(payload) {
                    if let chunk = extractDeltaOrFullText(
                        from: obj,
                        primaryPath: config.streamDeltaPath,
                        fallbackPath: config.streamEventTextFallback,
                        isFinalPass: false
                    ) {
                        extracted += chunk
                    }
                }
            } else if trimmed.hasPrefix("data:") {
                var val = String(trimmed.dropFirst(5))
                if val.hasPrefix(" ") { val.removeFirst() }
                if val.trimmingCharacters(in: .whitespaces) != "[DONE]" {
                    if !eventDataLines.isEmpty, jsonObject(eventDataLines.joined(separator: "\n")) != nil {
                        let payload = eventDataLines.joined(separator: "\n")
                        eventDataLines.removeAll(keepingCapacity: true)
                        if let obj = jsonObject(payload),
                           let chunk = extractDeltaOrFullText(
                               from: obj,
                               primaryPath: config.streamDeltaPath,
                               fallbackPath: config.streamEventTextFallback,
                               isFinalPass: false
                           ) {
                            extracted += chunk
                        }
                    }
                    eventDataLines.append(val)
                }
            }
        }

        do {
            let (bytes, response) = try await streamSession.bytes(for: built.request)
            if let http = response as? HTTPURLResponse {
                capturedStatus = http.statusCode
            }
            if let onLiveUpdate {
                await onLiveUpdate(makeSnapshot())
            }

            for try await byte in bytes {
                try Task.checkCancellation()
                rawData.append(byte)
                if byte == 0x0A {
                    consumeInspectorSSELine(lineBuffer)
                    lineBuffer.removeAll(keepingCapacity: true)
                } else {
                    lineBuffer.append(byte)
                }
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastPublishAt >= 0.08, let onLiveUpdate {
                    lastPublishAt = now
                    await onLiveUpdate(makeSnapshot())
                }
                if rawData.count > 2_000_000 { break }
            }
            if !lineBuffer.isEmpty {
                consumeInspectorSSELine(lineBuffer)
            }
            consumeInspectorSSELine([])

            if extracted.isEmpty {
                let rawText = String(data: rawData, encoding: .utf8) ?? ""
                if let obj = jsonObject(rawText),
                   let full = extractDeltaOrFullText(
                       from: obj,
                       primaryPath: config.responsePath,
                       fallbackPath: config.streamDeltaPath,
                       isFinalPass: true
                   ) {
                    extracted = full
                }
            }

            let httpErr: String? = (capturedStatus.map { !(200..<300).contains($0) } ?? false)
                ? "HTTP \(capturedStatus ?? 0): \(extractErrorMessage(rawData))"
                : nil
            return makeSnapshot(error: httpErr)
        } catch {
            return makeSnapshot(error: error.localizedDescription)
        }
    }

    // MARK: Apple On-Device (Foundation Models, fully offline)

    public static func appleOnDeviceStatus() -> (available: Bool, detail: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "Sẵn sàng — chạy hoàn toàn offline trên thiết bị, không gửi dữ liệu ra ngoài.")
            case .unavailable(let reason):
                return (false, "Chưa khả dụng trên máy này (\(String(describing: reason))). Hãy bật Apple Intelligence trong Cài đặt.")
            @unknown default:
                return (false, "Apple Intelligence chưa khả dụng trên máy này.")
            }
        }
        #endif
        return (false, "Cần iOS 26 trở lên và thiết bị hỗ trợ Apple Intelligence (iPhone 15 Pro trở lên, iPad M1 trở lên).")
    }

    private static func runAppleOnDevice(system: String, history: [AIChatTurn], emit: (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let status = appleOnDeviceStatus()
            guard status.available else { throw AIProviderError.unavailable(status.detail) }
            var transcript = ""
            for turn in history.suffix(6) {
                let raw = turn.attachments.isEmpty ? turn.text : "\(turn.text)\n[Attached \(turn.attachments.count) image(s)]"
                let clipped = raw.count > 1800 ? String(raw.suffix(1800)) : raw
                transcript += (turn.role == .user ? "User: " : "Assistant: ") + clipped + "\n\n"
            }
            let sysPrefix = system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : String(system.prefix(3500)) + "\n\n"
            let remainingBudget = max(1000, 11_000 - sysPrefix.count)
            let tail = transcript + "Assistant:"
            let boundedTail = tail.count > remainingBudget ? String(tail.suffix(remainingBudget)) : tail
            let prompt = sysPrefix + boundedTail
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            emit(response.content)
            return
        }
        #endif
        throw AIProviderError.unavailable(appleOnDeviceStatus().detail)
    }

    // MARK: Networking Helpers

    /// Reads a Server-Sent-Events stream line by line in realtime using strict LF splitting
    /// (preserving multi-byte UTF-8 sequences that contain 0x85). Returns any non-SSE body text.
    private static func consumeSSE(
        _ request: URLRequest,
        onEvent: ([String: Any]) throws -> Void
    ) async throws -> String {
        let streamSession = makeStreamingSession()
        defer { streamSession.finishTasksAndInvalidate() }

        let (bytes, response) = try await streamSession.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 32_000 { break }
            }
            throw AIProviderError.http(http.statusCode, extractErrorMessage(body))
        }

        var lineBytes: [UInt8] = []
        var eventDataLines: [String] = []
        var leftoverBytes: [UInt8] = []

        func flushSSEEvent() throws -> Bool {
            guard !eventDataLines.isEmpty else { return false }
            let payload = eventDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            eventDataLines.removeAll(keepingCapacity: true)
            if payload.isEmpty { return false }
            if payload == "[DONE]" { return true }
            guard let event = jsonObject(payload) else { return false }
            if let err = event["error"] {
                throw AIProviderError.http(0, messageText(from: err))
            }
            try onEvent(event)
            return false
        }

        func processLineBytes(_ rawLineBytes: [UInt8]) throws -> Bool {
            var slice = rawLineBytes
            if slice.last == 0x0D {
                slice.removeLast()
            }
            guard let rawLine = String(bytes: slice, encoding: .utf8) else { return false }
            if rawLine.isEmpty {
                return try flushSSEEvent()
            }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":") {
                return false
            }
            if trimmed.hasPrefix("data:") {
                var value = String(trimmed.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                if value.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    _ = try flushSSEEvent()
                    return true
                }
                if !eventDataLines.isEmpty, jsonObject(eventDataLines.joined(separator: "\n")) != nil {
                    if try flushSSEEvent() { return true }
                }
                eventDataLines.append(value)
            } else if trimmed.hasPrefix("event:") || trimmed.hasPrefix("id:") || trimmed.hasPrefix("retry:") {
                // SSE control fields
            } else {
                leftoverBytes.append(contentsOf: slice)
                leftoverBytes.append(0x0A)
            }
            return false
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 0x0A {
                if try processLineBytes(lineBytes) {
                    lineBytes.removeAll(keepingCapacity: true)
                    break
                }
                lineBytes.removeAll(keepingCapacity: true)
            } else {
                lineBytes.append(byte)
            }
        }
        if !lineBytes.isEmpty {
            _ = try processLineBytes(lineBytes)
        }
        _ = try flushSSEEvent()

        let leftover = String(bytes: leftoverBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let obj = jsonObject(leftover), let err = obj["error"] {
            throw AIProviderError.http(0, messageText(from: err))
        }
        return leftover
    }

    private static func fetchJSON(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIProviderError.http(http.statusCode, extractErrorMessage(data))
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func jsonSerializedString(_ object: Any, fallback: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let str = String(data: data, encoding: .utf8) else {
            return fallback
        }
        return str
    }

    private static func jsonQuotedString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
           let arrStr = String(data: data, encoding: .utf8),
           arrStr.count >= 2 {
            return String(arrStr.dropFirst().dropLast())
        }
        return "\"\""
    }

    private static func jsonEscapedInnerString(_ value: String) -> String {
        let quoted = jsonQuotedString(value)
        if quoted.count >= 2 && quoted.hasPrefix("\"") && quoted.hasSuffix("\"") {
            return String(quoted.dropFirst().dropLast())
        }
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func maskSecretPreview(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("bearer ") {
            let token = String(trimmed.dropFirst(7))
            let tail = token.count > 4 ? String(token.suffix(4)) : ""
            return "Bearer ••••••••\(tail)"
        }
        let tail = trimmed.count > 4 ? String(trimmed.suffix(4)) : ""
        return "••••••••\(tail)"
    }

    private static func messageText(from error: Any) -> String {
        if let dict = error as? [String: Any] {
            if let msg = dict["message"] as? String { return msg }
            if let type = dict["type"] as? String { return type }
        }
        if let str = error as? String { return str }
        return String(describing: error)
    }

    static func extractErrorMessage(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                if let err = dict["error"] { return messageText(from: err) }
                if let msg = dict["message"] as? String { return msg }
                if let detail = dict["detail"] as? String { return detail }
            }
            if let arr = json as? [[String: Any]], let err = arr.first?["error"] {
                return messageText(from: err)
            }
        }
        let raw = String(data: data.prefix(400), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Máy chủ không trả về nội dung." : raw
    }

    private static func intValue(_ any: Any?) -> Int? {
        (any as? NSNumber)?.intValue
    }

    private static func unixDate(_ any: Any?) -> Date? {
        guard let value = (any as? NSNumber)?.doubleValue, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }

    private static func isoDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        isoLock.lock()
        defer { isoLock.unlock() }
        if let d = isoFractionalFormatter.date(from: string) { return d }
        return isoStandardFormatter.date(from: string)
    }
}
