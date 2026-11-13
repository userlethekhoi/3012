import Foundation

// MARK: - API Wire Formats

/// Wire protocol spoken by an AI provider. Almost every vendor today exposes an
/// OpenAI-compatible Chat Completions endpoint, so most presets map to `.openAICompatible`.
public enum AIAPIFormat: String, Codable, CaseIterable, Identifiable {
    case openAICompatible
    case anthropic
    case gemini
    case appleOnDevice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .anthropic: return "Anthropic Messages"
        case .gemini: return "Google Gemini"
        case .appleOnDevice: return "Apple On-Device"
        }
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

    public init(preset: AIProviderPreset) {
        self.id = UUID()
        self.name = preset.name
        self.presetID = preset.id
        self.format = preset.format
        self.baseURL = preset.baseURL
        self.selectionMode = .latestFlagship
        self.fixedModelID = ""
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
    }

    public var keychainAccount: String { "ai.apikey.\(id.uuidString)" }
    public var preset: AIProviderPreset? { AIProviderPreset.preset(id: presetID) }
    public var requiresAPIKey: Bool { preset?.requiresAPIKey ?? (format != .appleOnDevice) }
    public var isLocal: Bool { preset?.isLocal ?? false }

    /// The model actually used for the next request.
    public var resolvedModelID: String {
        if format == .appleOnDevice { return "apple-on-device" }
        let fixed = fixedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectionMode == .fixed { return fixed }
        return AIModelRanker.pickLatest(
            from: cachedModels,
            mode: selectionMode,
            presetID: presetID,
            filter: modelFilter
        )?.id ?? fixed
    }
}

// MARK: - Latest-Model Ranking (vendor-agnostic heuristics)

public enum AIModelRanker {
    /// Non-chat endpoints that would fail on a chat request.
    private static let excludedSubstrings: [String] = [
        "embed", "whisper", "tts", "transcribe", "dall-e", "moderation", "image", "imagen",
        "veo", "sora", "audio", "realtime", "davinci", "babbage", "rerank", "aqa",
        "deep-research", "computer-use", "codex", "native-audio", "lyria"
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

    public static func isChatCandidate(_ id: String, presetID: String) -> Bool {
        let lower = id.lowercased()
        if excludedSubstrings.contains(where: { lower.contains($0) }) { return false }
        let toks = tokens(id)
        if toks.contains(where: { excludedTokens.contains($0) }) { return false }
        if presetID == "openai" {
            // Responses-API-only or legacy completion models.
            if toks.last == "pro" || lower.contains("instruct") { return false }
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

    /// Extracts the model generation number: `gpt-5.1` -> 5.1, `claude-sonnet-4-5` -> 4.5, `gemini-2.5-pro` -> 2.5.
    public static func versionScore(_ id: String) -> Double {
        let lower = id.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)(?:\.(\d+))?"#) else { return 0 }
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
            var value = Double(major) ?? 0
            if m.range(at: 2).location != NSNotFound {
                let minor = ns.substring(with: m.range(at: 2))
                value += (Double(minor) ?? 0) / pow(10, Double(minor.count))
            } else if idx + 1 < matches.count, end < ns.length {
                let n = matches[idx + 1]
                let minorStr = ns.substring(with: n.range(at: 1))
                let separator = ns.substring(with: NSRange(location: end, length: 1))
                let nEnd = n.range.location + n.range.length
                let followedBySize = nEnd < ns.length && ["b", "k", "x", "m"].contains(ns.substring(with: NSRange(location: nEnd, length: 1)))
                if separator == "-", n.range.location == end + 1, minorStr.count == 1,
                   n.range(at: 2).location == NSNotFound, !followedBySize {
                    value += (Double(minorStr) ?? 0) / 10
                }
            }
            return value
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

    public static func rankedCandidates(from models: [AIModelInfo], presetID: String, filter: String) -> [AIModelInfo] {
        let filterTokens = filter
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var candidates = models.filter { isChatCandidate($0.id, presetID: presetID) }
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
        filter: String
    ) -> AIModelInfo? {
        let ranked = rankedCandidates(from: models, presetID: presetID, filter: filter)
        guard !ranked.isEmpty else { return nil }
        switch mode {
        case .latestFast:
            return ranked.first(where: { isFast($0.id) }) ?? ranked.first
        case .latestFlagship, .fixed:
            return ranked.first(where: { !isFast($0.id) }) ?? ranked.first
        }
    }
}
