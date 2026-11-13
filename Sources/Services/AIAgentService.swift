import Foundation

public enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case gemini = "Google Gemini"
    case openAICompatible = "OpenAI / DeepSeek / OpenRouter / VPS"
    case anthropic = "Anthropic Claude"

    public var id: String { rawValue }

    public var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .openAICompatible: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-sonnet-latest"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openAICompatible: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }
}

public struct AgentProposedEdit: Identifiable, Equatable {
    public enum DecisionState: String, Equatable {
        case pending
        case applied
        case rejected
    }

    public let id: UUID
    public let relativePath: String
    public let newContent: String
    public let diffPreviewLines: [String]
    public var state: DecisionState

    public init(relativePath: String, oldContent: String?, newContent: String) {
        self.id = UUID()
        self.relativePath = relativePath
        self.newContent = newContent
        self.diffPreviewLines = Self.computeSimpleDiff(oldText: oldContent ?? "", newText: newContent)
        self.state = .pending
    }

    private static func computeSimpleDiff(oldText: String, newText: String) -> [String] {
        let oldLines = oldText.isEmpty ? [] : oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")
        let oldSet = Set(oldLines)
        let newSet = Set(newLines)
        var preview: [String] = []

        for line in oldLines where !newSet.contains(line) {
            preview.append("- " + line)
            if preview.count >= 18 { break }
        }
        for line in newLines where !oldSet.contains(line) {
            preview.append("+ " + line)
            if preview.count >= 40 { break }
        }
        if preview.isEmpty {
            preview = newLines.prefix(12).map { "  " + $0 }
        }
        return preview
    }
}

public struct AIChatMessage: Identifiable, Equatable {
    public enum Role: String, Equatable {
        case user
        case assistant
        case system
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public var proposedEdits: [AgentProposedEdit]
    public let timestamp: Date

    public init(role: Role, text: String, proposedEdits: [AgentProposedEdit] = []) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.proposedEdits = proposedEdits
        self.timestamp = Date()
    }
}

@MainActor
public final class AIAgentService: ObservableObject {
    @Published public var provider: AIProviderType {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "3012.aiProvider")
            if modelName.isEmpty { modelName = provider.defaultModel }
            if customBaseURL.isEmpty { customBaseURL = provider.defaultBaseURL }
        }
    }
    @Published public var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "3012.aiApiKey") }
    }
    @Published public var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "3012.aiModel") }
    }
    @Published public var customBaseURL: String {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: "3012.aiBaseURL") }
    }

    @Published public var messages: [AIChatMessage] = [
        AIChatMessage(
            role: .assistant,
            text: "Xin chào! Mình là **3012 AI Coding Agent**.\n\nMình có thể đọc toàn bộ file trong Workspace của bạn, sửa lỗi biên dịch và tạo/sửa file trực tiếp kèm bảng **Diff (Accept / Reject)** ngay bên cạnh cửa sổ code."
        )
    ]
    @Published public private(set) var isThinking: Bool = false

    public init() {
        let rawProv = UserDefaults.standard.string(forKey: "3012.aiProvider") ?? AIProviderType.gemini.rawValue
        let resolvedProv = AIProviderType(rawValue: rawProv) ?? .gemini
        self.provider = resolvedProv
        self.apiKey = UserDefaults.standard.string(forKey: "3012.aiApiKey") ?? ""
        self.modelName = UserDefaults.standard.string(forKey: "3012.aiModel") ?? resolvedProv.defaultModel
        self.customBaseURL = UserDefaults.standard.string(forKey: "3012.aiBaseURL") ?? resolvedProv.defaultBaseURL
    }

    public func clearConversation() {
        messages = [
            AIChatMessage(
                role: .assistant,
                text: "Đã làm mới phiên trò chuyện. Hãy giao yêu cầu mới cho mình nhé!"
            )
        ]
    }

    public func markEditState(messageID: UUID, editID: UUID, newState: AgentProposedEdit.DecisionState) {
        guard let mIdx = messages.firstIndex(where: { $0.id == messageID }),
              let eIdx = messages[mIdx].proposedEdits.firstIndex(where: { $0.id == editID }) else { return }
        messages[mIdx].proposedEdits[eIdx].state = newState
    }

    public func sendPrompt(
        userPrompt: String,
        workspaceTree: String,
        activeFilePath: String?,
        activeFileContent: String?,
        selectedSnippet: String?,
        lastConsoleOutput: String,
        existingFileReader: (String) -> String?
    ) async {
        let cleanPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        messages.append(AIChatMessage(role: .user, text: cleanPrompt))

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Chưa cấu hình API Key cho \(provider.rawValue). Bấm nút tuỳ chỉnh ở góc trên khung Agent để nhập API Key (Gemini / OpenAI / DeepSeek / OpenRouter / Claude)."
            ))
            return
        }

        isThinking = true
        defer { isThinking = false }

        let systemInstruction = """
        You are the built-in AI Coding Agent inside '3012', a native iOS Mobile IDE similar to Cursor, Antigravity, and VS Code Copilot.
        Keep explanations concise and mobile-friendly.
        Whenever you create a new file or modify an existing file in the user's project, you MUST output the COMPLETE updated file content wrapped inside an XML block with the exact format:
        <file_edit path="relative/path/to/file.ext">
        ...full file code here...
        </file_edit>
        Do NOT wrap <file_edit> inside markdown triple backticks. You may propose multiple <file_edit> blocks in one reply if needed.

        Current Workspace Files:
        \(workspaceTree)

        Active File: \(activeFilePath ?? "None")
        \(selectedSnippet != nil ? "Selected Snippet:\n\(selectedSnippet!)\n" : "")
        Active File Content:
        \(activeFileContent ?? "(No open file)")

        Latest Console / Compiler Output:
        \(String(lastConsoleOutput.suffix(1200)))
        """

        do {
            let rawReply: String
            switch provider {
            case .gemini:
                rawReply = try await callGemini(systemPrompt: systemInstruction, userPrompt: cleanPrompt)
            case .openAICompatible:
                rawReply = try await callOpenAICompatible(systemPrompt: systemInstruction, userPrompt: cleanPrompt)
            case .anthropic:
                rawReply = try await callAnthropic(systemPrompt: systemInstruction, userPrompt: cleanPrompt)
            }

            let (cleanedText, edits) = Self.extractFileEdits(from: rawReply, existingFileReader: existingFileReader)
            messages.append(AIChatMessage(role: .assistant, text: cleanedText, proposedEdits: edits))
        } catch {
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Lỗi kết nối API: \(error.localizedDescription)"
            ))
        }
    }

    private func callGemini(systemPrompt: String, userPrompt: String) async throws -> String {
        let base = customBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = "\(base)/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }

        let historyTurns: [[String: Any]] = messages.suffix(8).compactMap { msg in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            return [
                "role": msg.role == .user ? "user" : "model",
                "parts": [["text": msg.text]]
            ]
        }

        var contents = historyTurns
        if contents.isEmpty {
            contents = [["role": "user", "parts": [["text": userPrompt]]]]
        }

        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": contents
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        return String(data: data, encoding: .utf8) ?? "Empty response."
    }

    private func callOpenAICompatible(systemPrompt: String, userPrompt: String) async throws -> String {
        let base = customBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/chat/completions") else { throw URLError(.badURL) }

        var chatMessages: [[String: String]] = [
            ["role": "system", "content": systemInstructionSafe(systemPrompt)]
        ]
        for msg in messages.suffix(8) where (msg.role == .user || msg.role == .assistant) {
            chatMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text
            ])
        }

        let payload: [String: Any] = [
            "model": modelName,
            "messages": chatMessages,
            "temperature": 0.2
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        return String(data: data, encoding: .utf8) ?? "Empty response."
    }

    private func callAnthropic(systemPrompt: String, userPrompt: String) async throws -> String {
        let base = customBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/messages") else { throw URLError(.badURL) }

        var chatMessages: [[String: String]] = []
        for msg in messages.suffix(8) where (msg.role == .user || msg.role == .assistant) {
            chatMessages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text
            ])
        }

        let payload: [String: Any] = [
            "model": modelName,
            "max_tokens": 4096,
            "system": systemInstructionSafe(systemPrompt),
            "messages": chatMessages
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let contentArr = json["content"] as? [[String: Any]] {
                let text = contentArr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                throw NSError(domain: "AnthropicAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        return String(data: data, encoding: .utf8) ?? "Empty response."
    }

    private func systemInstructionSafe(_ s: String) -> String { s }

    private static func extractFileEdits(
        from rawText: String,
        existingFileReader: (String) -> String?
    ) -> (String, [AgentProposedEdit]) {
        let pattern = #"<file_edit\s+path="([^"]+)">\s*([\s\S]*?)\s*</file_edit>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (rawText, [])
        }
        let nsText = rawText as NSString
        let matches = regex.matches(in: rawText, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return (rawText, [])
        }

        var edits: [AgentProposedEdit] = []
        var stripped = rawText

        for match in matches.reversed() {
            let path = nsText.substring(with: match.range(at: 1))
            let code = nsText.substring(with: match.range(at: 2))
            let existing = existingFileReader(path)
            edits.insert(AgentProposedEdit(relativePath: path, oldContent: existing, newContent: code), at: 0)
            if let swiftRange = Range(match.range, in: stripped) {
                stripped.replaceSubrange(swiftRange, with: "\n*Đề xuất cập nhật file `\(path)` (Xem bảng Diff bên dưới)*\n")
            }
        }

        return (stripped.trimmingCharacters(in: .whitespacesAndNewlines), edits)
    }
}
