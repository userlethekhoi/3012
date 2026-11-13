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

public struct AIChatTurn: Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
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

    static func normalizedBase(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: Model Discovery

    public static func listModels(format: AIAPIFormat, baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        let base = normalizedBase(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {
        case .openAICompatible:
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
        guard let url = URL(string: base + "/models") else { throw AIProviderError.invalidURL(base) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
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
        guard let url = URL(string: base + "/models?limit=1000") else { throw AIProviderError.invalidURL(base) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
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
        maxOutputTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let base = normalizedBase(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let emit: (String) -> Void = { continuation.yield($0) }
                    switch format {
                    case .openAICompatible:
                        try await streamOpenAICompatible(base: base, key: key, model: model, system: systemPrompt,
                                                         history: history, temperature: temperature, emit: emit)
                    case .anthropic:
                        try await streamAnthropic(base: base, key: key, model: model, system: systemPrompt,
                                                  history: history, temperature: temperature,
                                                  maxTokens: maxOutputTokens, emit: emit)
                    case .gemini:
                        try await streamGemini(base: base, key: key, model: model, system: systemPrompt,
                                               history: history, temperature: temperature, emit: emit)
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

    private static func streamOpenAICompatible(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, emit: (String) -> Void
    ) async throws {
        guard let url = URL(string: base + "/chat/completions") else { throw AIProviderError.invalidURL(base) }
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { ["role": $0.role.rawValue, "content": $0.text] }
        var payload: [String: Any] = ["model": model, "messages": messages, "stream": true]
        if let temperature { payload["temperature"] = temperature }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
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

    private static func streamAnthropic(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, maxTokens: Int, emit: (String) -> Void
    ) async throws {
        guard let url = URL(string: base + "/messages") else { throw AIProviderError.invalidURL(base) }
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": max(1024, maxTokens),
            "system": system,
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.text] },
            "stream": true
        ]
        if let temperature { payload["temperature"] = min(1.0, temperature) }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        _ = try await consumeSSE(req) { event in
            guard (event["type"] as? String) == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta",
                  let text = delta["text"] as? String else { return }
            emit(text)
        }
    }

    private static func streamGemini(
        base: String, key: String, model: String, system: String,
        history: [AIChatTurn], temperature: Double?, emit: (String) -> Void
    ) async throws {
        let modelPath = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        guard let url = URL(string: "\(base)/models/\(modelPath):streamGenerateContent?alt=sse") else {
            throw AIProviderError.invalidURL(base)
        }
        var payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": history.map { turn in
                ["role": turn.role == .user ? "user" : "model", "parts": [["text": turn.text]]]
            }
        ]
        if let temperature { payload["generationConfig"] = ["temperature": temperature] }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        _ = try await consumeSSE(req) { event in
            if let feedback = event["promptFeedback"] as? [String: Any],
               let reason = feedback["blockReason"] as? String {
                throw AIProviderError.unavailable("Gemini đã chặn yêu cầu: \(reason)")
            }
            guard let candidates = event["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return }
            for part in parts where (part["thought"] as? Bool) != true {
                if let text = part["text"] as? String, !text.isEmpty { emit(text) }
            }
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
                let clipped = turn.text.count > 1800 ? String(turn.text.suffix(1800)) : turn.text
                transcript += (turn.role == .user ? "User: " : "Assistant: ") + clipped + "\n\n"
            }
            var prompt = system + "\n\n" + transcript + "Assistant:"
            if prompt.count > 11_000 { prompt = String(prompt.suffix(11_000)) }
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            emit(response.content)
            return
        }
        #endif
        throw AIProviderError.unavailable(appleOnDeviceStatus().detail)
    }

    // MARK: Networking Helpers

    /// Reads a Server-Sent-Events stream line by line in realtime. Returns any non-SSE body text
    /// (used as a fallback when a server ignores streaming).
    private static func consumeSSE(
        _ request: URLRequest,
        onEvent: ([String: Any]) throws -> Void
    ) async throws -> String {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 32_000 { break }
            }
            throw AIProviderError.http(http.statusCode, extractErrorMessage(body))
        }

        var leftover = ""
        for try await rawLine in bytes.lines {
            try Task.checkCancellation()
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("data:") else {
                if !line.isEmpty, !line.hasPrefix("event:"), !line.hasPrefix(":"),
                   !line.hasPrefix("id:"), !line.hasPrefix("retry:") {
                    leftover += line
                }
                continue
            }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let event = jsonObject(payload) else { continue }
            if let err = event["error"] {
                throw AIProviderError.http(0, messageText(from: err))
            }
            try onEvent(event)
        }
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
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}
