import Foundation

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
    public var isStreaming: Bool
    public var modelLabel: String?
    public let timestamp: Date

    public init(
        role: Role,
        text: String,
        proposedEdits: [AgentProposedEdit] = [],
        isStreaming: Bool = false,
        modelLabel: String? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.proposedEdits = proposedEdits
        self.isStreaming = isStreaming
        self.modelLabel = modelLabel
        self.timestamp = Date()
    }
}

/// Generic, user-configurable AI agent: any number of provider profiles, live model discovery
/// (always tracks the provider's newest model), realtime streaming, online + offline backends.
@MainActor
public final class AIAgentService: ObservableObject {
    private static let profilesKey = "3012.ai.profiles.v2"
    private static let activeProfileKey = "3012.ai.activeProfileID"
    /// How often the model catalogue is re-fetched to pick up newly released models.
    private static let modelRefreshInterval: TimeInterval = 6 * 3600

    @Published public private(set) var profiles: [AIProviderProfile] = []
    @Published public var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString, forKey: Self.activeProfileKey) }
    }
    @Published public var messages: [AIChatMessage] = [
        AIChatMessage(
            role: .assistant,
            text: "Xin chào! Mình là **3012 Coding Agent**.\n\nMình đọc được toàn bộ file trong Workspace, sửa lỗi biên dịch và tạo/sửa file trực tiếp kèm bảng **Diff (Accept / Reject)**. Bạn có thể tự kết nối bất kỳ nhà cung cấp AI nào (online hoặc offline) trong phần cấu hình."
        )
    ]
    @Published public private(set) var isThinking: Bool = false
    @Published public private(set) var refreshingProfileIDs: Set<UUID> = []
    @Published public var lastRefreshMessage: [UUID: String] = [:]
    /// Bumped while streaming so the chat view can keep scrolled to the bottom.
    @Published public private(set) var streamRevision: Int = 0

    private var generationTask: Task<Void, Never>?

    public init() {
        loadProfiles()
    }

    // MARK: - Profile Accessors

    public var activeProfile: AIProviderProfile? {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles.first
    }

    public var modelName: String {
        guard let profile = activeProfile else { return "Chưa cấu hình" }
        let model = profile.resolvedModelID
        return model.isEmpty ? "Chọn model" : model
    }

    public func profile(id: UUID) -> AIProviderProfile? {
        profiles.first(where: { $0.id == id })
    }

    public func isRefreshing(_ profileID: UUID) -> Bool {
        refreshingProfileIDs.contains(profileID)
    }

    public func apiKey(for profile: AIProviderProfile) -> String {
        KeychainVault.loadString(forKey: profile.keychainAccount) ?? ""
    }

    public func setAPIKey(_ key: String, for profileID: UUID) {
        guard let profile = self.profile(id: profileID) else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainVault.delete(forKey: profile.keychainAccount)
        } else {
            KeychainVault.saveString(trimmed, forKey: profile.keychainAccount)
        }
    }

    // MARK: - Profile Management

    @discardableResult
    public func addProfile(preset: AIProviderPreset) -> UUID {
        var profile = AIProviderProfile(preset: preset)
        let sameCount = profiles.filter { $0.presetID == preset.id }.count
        if sameCount > 0 { profile.name = "\(preset.name) \(sameCount + 1)" }
        profiles.append(profile)
        persistProfiles()
        activeProfileID = profile.id
        return profile.id
    }

    public func updateProfile(_ updated: AIProviderProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == updated.id }), profiles[idx] != updated else { return }
        profiles[idx] = updated
        persistProfiles()
    }

    public func deleteProfile(id: UUID) {
        if let profile = self.profile(id: id) {
            KeychainVault.delete(forKey: profile.keychainAccount)
        }
        profiles.removeAll { $0.id == id }
        lastRefreshMessage[id] = nil
        persistProfiles()
        if activeProfileID == id || !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles.first?.id
        }
    }

    public func setActiveProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    public func selectFixedModel(_ modelID: String, for profileID: UUID) {
        guard var profile = self.profile(id: profileID) else { return }
        profile.selectionMode = .fixed
        profile.fixedModelID = modelID
        updateProfile(profile)
    }

    // MARK: - Live Model Discovery (auto-tracks newest releases)

    @discardableResult
    public func refreshModels(for profileID: UUID, announceChanges: Bool = true) async -> Bool {
        guard let profile = self.profile(id: profileID), !refreshingProfileIDs.contains(profileID) else { return false }
        let key = apiKey(for: profile)
        if profile.requiresAPIKey && key.isEmpty {
            lastRefreshMessage[profileID] = "Chưa nhập API Key."
            return false
        }

        refreshingProfileIDs.insert(profileID)
        defer { refreshingProfileIDs.remove(profileID) }
        let previousModel = profile.resolvedModelID

        do {
            let models = try await AIProviderClient.listModels(format: profile.format, baseURL: profile.baseURL, apiKey: key)
            guard var latest = self.profile(id: profileID) else { return false }
            latest.cachedModels = models
            latest.lastModelRefresh = Date()
            updateProfile(latest)

            let resolved = latest.resolvedModelID
            let chatCount = AIModelRanker.rankedCandidates(from: models, presetID: latest.presetID, filter: latest.modelFilter).count
            lastRefreshMessage[profileID] = "Đã tải \(models.count) model (\(chatCount) model chat). Đang dùng: \(resolved.isEmpty ? "chưa chọn" : resolved)"

            if announceChanges, latest.selectionMode != .fixed, !previousModel.isEmpty,
               previousModel != resolved, !resolved.isEmpty, profileID == activeProfile?.id {
                messages.append(AIChatMessage(
                    role: .system,
                    text: "\(latest.name) có model mới hơn: \(resolved) — đã tự động chuyển từ \(previousModel)."
                ))
            }
            return true
        } catch {
            lastRefreshMessage[profileID] = "Không tải được danh sách model: \(error.localizedDescription)"
            return false
        }
    }

    /// Called when the agent panel appears; re-fetches the catalogue if it is older than the refresh interval.
    public func refreshStaleModelsIfNeeded() async {
        guard let profile = activeProfile else { return }
        let isStale = profile.lastModelRefresh.map { Date().timeIntervalSince($0) > Self.modelRefreshInterval } ?? true
        if isStale {
            await refreshModels(for: profile.id)
        }
    }

    // MARK: - Conversation

    public func clearConversation() {
        stopGenerating()
        messages = [
            AIChatMessage(role: .assistant, text: "Đã làm mới phiên trò chuyện. Hãy giao yêu cầu mới cho mình nhé!")
        ]
    }

    public func stopGenerating() {
        generationTask?.cancel()
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
        existingFileReader: @escaping (String) -> String?
    ) async {
        let cleanPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty, !isThinking else { return }

        messages.append(AIChatMessage(role: .user, text: cleanPrompt))

        guard let profile = activeProfile else {
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Chưa có nhà cung cấp AI nào. Bấm vào tên model ở đầu khung Agent > **Cấu hình AI** để thêm OpenAI, Claude, Gemini, DeepSeek, OpenRouter, Ollama, Apple On-Device hoặc endpoint riêng của bạn."
            ))
            return
        }
        let key = apiKey(for: profile)
        if profile.requiresAPIKey && key.isEmpty {
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Cấu hình **\(profile.name)** chưa có API Key. Mở **Cấu hình AI** để nhập key (được lưu an toàn trong iOS Keychain)."
            ))
            return
        }

        isThinking = true
        let context = PromptContext(
            workspaceTree: workspaceTree,
            activeFilePath: activeFilePath,
            activeFileContent: activeFileContent,
            selectedSnippet: selectedSnippet,
            lastConsoleOutput: lastConsoleOutput
        )
        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            await self.runGeneration(profileID: profile.id, apiKey: key, context: context, existingFileReader: existingFileReader)
        }
        generationTask = task
        await task.value
        generationTask = nil
        isThinking = false
    }

    // MARK: - Generation Pipeline

    private struct PromptContext {
        let workspaceTree: String
        let activeFilePath: String?
        let activeFileContent: String?
        let selectedSnippet: String?
        let lastConsoleOutput: String
    }

    private func runGeneration(
        profileID: UUID,
        apiKey: String,
        context: PromptContext,
        existingFileReader: @escaping (String) -> String?
    ) async {
        guard var profile = self.profile(id: profileID) else { return }

        var model = profile.resolvedModelID
        if model.isEmpty {
            await refreshModels(for: profileID, announceChanges: false)
            if let refreshed = self.profile(id: profileID) {
                profile = refreshed
                model = refreshed.resolvedModelID
            }
        }
        guard !model.isEmpty else {
            let detail = lastRefreshMessage[profileID].map { "\n\n\($0)" } ?? ""
            messages.append(AIChatMessage(
                role: .assistant,
                text: "Chưa xác định được model cho **\(profile.name)**. Mở **Cấu hình AI** để làm mới danh sách model hoặc nhập tay model ID.\(detail)"
            ))
            return
        }

        let systemPrompt = profile.format == .appleOnDevice
            ? buildCompactSystemPrompt(context)
            : buildSystemPrompt(context)
        let history = buildHistory()

        let placeholder = AIChatMessage(role: .assistant, text: "", isStreaming: true, modelLabel: model)
        messages.append(placeholder)
        let messageID = placeholder.id

        let stream = AIProviderClient.streamChat(
            format: profile.format,
            baseURL: profile.baseURL,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            history: history,
            temperature: profile.useCustomTemperature ? profile.temperature : nil,
            maxOutputTokens: profile.maxOutputTokens
        )

        var accumulated = ""
        var lastFlush = Date.distantPast
        do {
            for try await chunk in stream {
                accumulated += chunk
                let now = Date()
                if now.timeIntervalSince(lastFlush) > 0.05 {
                    updateMessage(messageID) { $0.text = accumulated }
                    streamRevision &+= 1
                    lastFlush = now
                }
            }
            if Task.isCancelled {
                finishStopped(messageID, accumulated: accumulated)
            } else {
                let (cleaned, edits) = Self.extractFileEdits(from: accumulated, existingFileReader: existingFileReader)
                updateMessage(messageID) {
                    $0.text = cleaned.isEmpty ? "(Model không trả về nội dung.)" : cleaned
                    $0.proposedEdits = edits
                    $0.isStreaming = false
                }
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                finishStopped(messageID, accumulated: accumulated)
            } else {
                let errorText = friendlyErrorText(error, profile: profile, model: model)
                updateMessage(messageID) {
                    $0.text = accumulated.isEmpty ? errorText : accumulated + "\n\n" + errorText
                    $0.isStreaming = false
                }
            }
        }
        streamRevision &+= 1
    }

    private func finishStopped(_ id: UUID, accumulated: String) {
        updateMessage(id) {
            $0.text = (accumulated.isEmpty ? "" : accumulated + "\n\n") + "_(Đã dừng)_"
            $0.isStreaming = false
        }
    }

    private func updateMessage(_ id: UUID, _ mutate: (inout AIChatMessage) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[idx])
    }

    private func friendlyErrorText(_ error: Error, profile: AIProviderProfile, model: String) -> String {
        let raw = error.localizedDescription
        switch (error as? AIProviderError)?.statusCode {
        case 401, 403:
            return "Lỗi xác thực với \(profile.name): API Key không hợp lệ hoặc không có quyền dùng model `\(model)`.\n\n\(raw)"
        case 404:
            return "Model `\(model)` không tồn tại hoặc không hỗ trợ endpoint này. Hãy làm mới danh sách model hoặc chọn model khác.\n\n\(raw)"
        case 429:
            return "\(profile.name) báo vượt hạn mức (rate limit / hết credit). Thử lại sau hoặc chuyển sang cấu hình khác.\n\n\(raw)"
        default:
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return "Không có kết nối mạng. Bạn có thể chuyển sang Apple On-Device hoặc Ollama/LM Studio trong mạng LAN để dùng offline."
                case .cannotConnectToHost, .cannotFindHost, .timedOut:
                    return "Không kết nối được tới \(profile.baseURL). Kiểm tra Base URL" + (profile.isLocal ? ", máy chủ local đang chạy và iPhone cùng mạng Wi-Fi." : ".")
                default:
                    break
                }
            }
            return "Lỗi khi gọi \(profile.name): \(raw)"
        }
    }

    private func buildHistory() -> [AIChatTurn] {
        var turns: [AIChatTurn] = []
        for msg in messages where msg.role != .system && !msg.isStreaming {
            let text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role: AIChatTurn.Role = msg.role == .user ? .user : .assistant
            if let last = turns.last, last.role == role {
                turns[turns.count - 1] = AIChatTurn(role: role, text: last.text + "\n\n" + text)
            } else {
                turns.append(AIChatTurn(role: role, text: text))
            }
        }
        var recent = Array(turns.suffix(12))
        while let first = recent.first, first.role == .assistant {
            recent.removeFirst()
        }
        return recent
    }

    private func buildSystemPrompt(_ ctx: PromptContext) -> String {
        """
        You are the built-in Coding Agent inside '3012', a native iOS / iPadOS code editor (similar to Cursor, VS Code Copilot and Antigravity).
        Reply in the user's language. Keep explanations concise and mobile-friendly.
        Whenever you create a new file or modify an existing file in the user's project, you MUST output the COMPLETE updated file content wrapped in this exact XML block:
        <file_edit path="relative/path/to/file.ext">
        ...full file content...
        </file_edit>
        Do NOT wrap <file_edit> inside markdown code fences. You may output multiple <file_edit> blocks in one reply.

        Workspace files:
        \(ctx.workspaceTree)

        Active file: \(ctx.activeFilePath ?? "None")
        \(ctx.selectedSnippet.map { "Selected snippet:\n\($0)\n" } ?? "")
        Active file content:
        \(ctx.activeFileContent ?? "(No open file)")

        Latest console / compiler output:
        \(String(ctx.lastConsoleOutput.suffix(1500)))
        """
    }

    /// The on-device model has a small context window, so the context is trimmed aggressively.
    private func buildCompactSystemPrompt(_ ctx: PromptContext) -> String {
        let file = ctx.activeFileContent.map { String($0.prefix(4000)) } ?? "(No open file)"
        return """
        You are a concise coding assistant inside the 3012 iOS code editor. Reply in the user's language.
        To change a file, output the complete file inside <file_edit path="relative/path">...</file_edit>.
        Active file: \(ctx.activeFilePath ?? "None")
        \(ctx.selectedSnippet.map { "Selection:\n\(String($0.prefix(1200)))\n" } ?? "")
        File content:
        \(file)
        Console: \(String(ctx.lastConsoleOutput.suffix(500)))
        """
    }

    // MARK: - Persistence & Migration

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
    }

    private func loadProfiles() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([AIProviderProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = migrateLegacyConfiguration()
            persistProfiles()
        }
        if let raw = defaults.string(forKey: Self.activeProfileKey),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    /// Converts the single-provider settings of v3.3 and earlier into a profile and moves
    /// the API key out of UserDefaults into the Keychain.
    private func migrateLegacyConfiguration() -> [AIProviderProfile] {
        let defaults = UserDefaults.standard
        let legacyKeys = ["3012.aiProvider", "3012.aiApiKey", "3012.aiModel", "3012.aiBaseURL"]
        let apiKey = (defaults.string(forKey: "3012.aiApiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let providerRaw = defaults.string(forKey: "3012.aiProvider") ?? ""
        let model = (defaults.string(forKey: "3012.aiModel") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = (defaults.string(forKey: "3012.aiBaseURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        defer { legacyKeys.forEach { defaults.removeObject(forKey: $0) } }

        guard !apiKey.isEmpty else { return [] }

        let presetID: String
        switch providerRaw {
        case "Google Gemini":
            presetID = "gemini"
        case "Anthropic Claude":
            presetID = "anthropic"
        default:
            let host = baseURL.lowercased()
            if host.contains("deepseek") {
                presetID = "deepseek"
            } else if host.contains("openrouter") {
                presetID = "openrouter"
            } else if host.isEmpty || host.contains("api.openai.com") {
                presetID = "openai"
            } else {
                presetID = "custom"
            }
        }
        guard let preset = AIProviderPreset.preset(id: presetID) else { return [] }

        var profile = AIProviderProfile(preset: preset)
        if !baseURL.isEmpty { profile.baseURL = baseURL }
        let oldBuiltInDefaults: Set<String> = ["gemini-2.5-flash", "gpt-4o-mini", "claude-3-5-sonnet-latest"]
        if !model.isEmpty && !oldBuiltInDefaults.contains(model) {
            profile.selectionMode = .fixed
            profile.fixedModelID = model
        }
        KeychainVault.saveString(apiKey, forKey: profile.keychainAccount)
        return [profile]
    }

    // MARK: - File Edit Extraction

    private static func extractFileEdits(
        from rawText: String,
        existingFileReader: (String) -> String?
    ) -> (String, [AgentProposedEdit]) {
        let pattern = #"<file_edit\s+path="([^"]+)"\s*>\s*([\s\S]*?)\s*</file_edit>"#
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
                stripped.replaceSubrange(swiftRange, with: "\n*Đề xuất cập nhật file `\(path)` (xem bảng Diff bên dưới)*\n")
            }
        }

        return (stripped.trimmingCharacters(in: .whitespacesAndNewlines), edits)
    }
}
