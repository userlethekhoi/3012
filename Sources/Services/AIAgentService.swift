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

    // MARK: - Terminal Coding Agent CLI (claude / opencode / ai)
    public func runTerminalAgentCLI(
        cliName: String,
        rawArgs: String,
        cwd: URL,
        workspace: WorkspaceManager,
        lastConsoleOutput: String,
        onPrint: @escaping @MainActor (String) -> Void
    ) async {
        let trimmed = rawArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let firstCmd = tokens.first.map { String($0).lowercased() } ?? ""
        let restArg = tokens.count > 1 ? String(tokens[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if firstCmd == "help" || firstCmd == "--help" || firstCmd == "-h" {
            onPrint("""
            \(cliName) — 3012 On-Device AI Coding CLI (Full Workspace Sandbox Access)
            Usage:
              \(cliName) "<prompt>"        Run AI task reading/writing files directly in current folder
              \(cliName)                   Enter interactive \(cliName) REPL mode
              \(cliName) auth <API_KEY>    Save API key to iOS Keychain (auto-detects Claude/OpenAI/Gemini/OpenRouter/DeepSeek)
              \(cliName) models            List configured AI provider profiles & active model
              \(cliName) model <model_id>  Pin specific model ID (or switch profile by name)
              \(cliName) clear             Reset conversation context
            \n
            """)
            return
        }

        if firstCmd == "clear" || firstCmd == "/clear" {
            clearConversation()
            onPrint("\u{001B}[32m[\(cliName.uppercased())]\u{001B}[0m Cleared conversation history.\n")
            return
        }

        if firstCmd == "models" || firstCmd == "/models" {
            if profiles.isEmpty {
                onPrint("No AI profiles configured yet. Run: \(cliName) auth <YOUR_API_KEY>\n")
                return
            }
            onPrint("Configured AI Profiles (active: *):\n")
            for p in profiles {
                let mark = (p.id == activeProfile?.id) ? "*" : " "
                let mod = p.resolvedModelID.isEmpty ? "(auto-latest)" : p.resolvedModelID
                let hasKey = !p.requiresAPIKey || !apiKey(for: p).isEmpty
                onPrint("  \(mark) \(p.name) | model: \(mod) | key: \(hasKey ? "OK" : "MISSING")\n")
            }
            return
        }

        if firstCmd == "model" || firstCmd == "/model" {
            if restArg.isEmpty {
                onPrint("Active: \(activeProfile?.name ?? "None") -> \(modelName)\n")
                return
            }
            if let matchedProfile = profiles.first(where: { $0.name.localizedCaseInsensitiveContains(restArg) || $0.presetID.localizedCaseInsensitiveContains(restArg) }) {
                setActiveProfile(matchedProfile.id)
                onPrint("\u{001B}[32m[\(cliName.uppercased())]\u{001B}[0m Switched profile to \(matchedProfile.name) (\(modelName)).\n")
            } else if let current = activeProfile {
                selectFixedModel(restArg, for: current.id)
                onPrint("\u{001B}[32m[\(cliName.uppercased())]\u{001B}[0m Pinned model to \(restArg) on \(current.name).\n")
            } else {
                onPrint("No active profile. Run: \(cliName) auth <YOUR_API_KEY>\n")
            }
            return
        }

        if firstCmd == "auth" || firstCmd == "/key" || firstCmd == "login" {
            guard !restArg.isEmpty else {
                onPrint("Usage: \(cliName) auth <YOUR_API_KEY>\n")
                return
            }
            var targetID = activeProfile?.id
            if targetID == nil {
                let detectedPresetID: String = {
                    if restArg.hasPrefix("sk-ant-") { return "anthropic" }
                    if restArg.hasPrefix("AIza") { return "gemini" }
                    if restArg.hasPrefix("sk-or-") { return "openrouter" }
                    if restArg.hasPrefix("gsk_") { return "groq" }
                    if cliName == "claude" { return "anthropic" }
                    return "openai"
                }()
                if let preset = AIProviderPreset.preset(id: detectedPresetID) {
                    targetID = addProfile(preset: preset)
                }
            }
            if let id = targetID, let p = profile(id: id) {
                setAPIKey(restArg, for: id)
                onPrint("\u{001B}[32m[\(cliName.uppercased())]\u{001B}[0m Saved API key securely in iOS Keychain for \(p.name).\n")
                let ok = await refreshModels(for: id, announceChanges: false)
                if ok {
                    onPrint("\u{001B}[32m[\(cliName.uppercased())]\u{001B}[0m Active model ready: \(modelName)\n")
                }
            }
            return
        }

        let promptText = stripSurroundingQuotes(trimmed)
        guard !promptText.isEmpty else { return }

        let relCWD = workspace.relativePath(for: cwd)
        let displayDir = (cwd.standardizedFileURL == workspace.rootURL.standardizedFileURL) ? "." : relCWD
        onPrint("\u{001B}[36m[SCAN]\u{001B}[0m Reading files in \(displayDir) (Full Sandbox Access)...\n")

        let (scannedTree, scannedSnapshot) = collectDirectoryContext(cwd: cwd, workspace: workspace)

        guard var active = activeProfile, (!active.requiresAPIKey || !apiKey(for: active).isEmpty) else {
            await offlineSynthesizeCLIResponse(cliName: cliName, prompt: promptText, cwd: cwd, workspace: workspace, scannedTree: scannedTree, onPrint: onPrint)
            return
        }

        let key = apiKey(for: active)
        var model = active.resolvedModelID
        if model.isEmpty {
            _ = await refreshModels(for: active.id, announceChanges: false)
            if let refreshed = profile(id: active.id) {
                active = refreshed
                model = refreshed.resolvedModelID
            }
        }
        guard !model.isEmpty else {
            onPrint("\u{001B}[33m[\(cliName.uppercased())]\u{001B}[0m Could not resolve model ID. Switching to built-in offline scaffolder...\n")
            await offlineSynthesizeCLIResponse(cliName: cliName, prompt: promptText, cwd: cwd, workspace: workspace, scannedTree: scannedTree, onPrint: onPrint)
            return
        }

        onPrint("\u{001B}[1;35m[\(cliName.uppercased()) • \(model)]\u{001B}[0m Thinking & editing files...\n")
        messages.append(AIChatMessage(role: .user, text: "[\(cliName) CLI @ \(displayDir)] \(promptText)"))

        let cliContext = PromptContext(
            workspaceTree: scannedTree,
            activeFilePath: workspace.activeTab.map { workspace.relativePath(for: $0.fileURL) },
            activeFileContent: scannedSnapshot + (workspace.activeTab.map { "\n--- ACTIVE TAB ---\n\($0.content)" } ?? ""),
            selectedSnippet: nil,
            lastConsoleOutput: lastConsoleOutput
        )
        let systemPrompt = active.format == .appleOnDevice
            ? buildCompactSystemPrompt(cliContext)
            : buildSystemPrompt(cliContext)

        isThinking = true
        defer { isThinking = false }

        let stream = AIProviderClient.streamChat(
            format: active.format,
            baseURL: active.baseURL,
            apiKey: key,
            model: model,
            systemPrompt: systemPrompt,
            history: [AIChatTurn(role: .user, text: promptText)],
            temperature: active.useCustomTemperature ? active.temperature : nil,
            maxOutputTokens: active.maxOutputTokens
        )

        var accumulated = ""
        do {
            for try await chunk in stream {
                accumulated += chunk
                onPrint(chunk)
            }
            let (cleaned, edits) = Self.extractFileEdits(from: accumulated) { rel in
                let targetURL = workspace.rootURL.appendingPathComponent(rel)
                return try? String(contentsOf: targetURL, encoding: .utf8)
            }
            messages.append(AIChatMessage(role: .assistant, text: cleaned.isEmpty ? accumulated : cleaned, proposedEdits: edits, modelLabel: model))

            if !edits.isEmpty {
                onPrint("\n")
                for edit in edits {
                    let finalRel = resolveWorkspaceRelativePath(edit.relativePath, cwd: cwd, workspace: workspace)
                    workspace.applyAgentFileEdit(relativePath: finalRel, newContent: edit.newContent)
                    let lines = edit.newContent.components(separatedBy: "\n").count
                    onPrint("\u{001B}[1;32m[WRITE]\u{001B}[0m \(finalRel) (\(lines) lines) -> opened in Editor.\n")
                }
            } else {
                onPrint("\n")
            }
        } catch {
            onPrint("\n\u{001B}[31m[\(cliName.uppercased()) ERROR]\u{001B}[0m \(error.localizedDescription)\n")
        }
    }

    private func collectDirectoryContext(cwd: URL, workspace: WorkspaceManager) -> (tree: String, contents: String) {
        let tree = workspace.workspaceSummaryTree()
        var urls: [URL] = []
        if let items = try? FileManager.default.contentsOfDirectory(
            at: cwd,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for u in items {
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !isDir { urls.append(u) }
            }
        }
        if urls.count < 8 {
            for u in workspace.flattenFiles(in: workspace.fileTree) where !urls.contains(u) {
                urls.append(u)
            }
        }
        var budget = 22_000
        var blocks: [String] = []
        for url in urls.prefix(12) {
            guard budget > 0,
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.isEmpty else { continue }
            let rel = workspace.relativePath(for: url)
            let clipped = String(text.prefix(min(budget, 4_000)))
            budget -= clipped.count
            blocks.append("=== FILE: \(rel) ===\n\(clipped)")
        }
        return (tree, blocks.joined(separator: "\n\n"))
    }

    private func resolveWorkspaceRelativePath(_ rawPath: String, cwd: URL, workspace: WorkspaceManager) -> String {
        let cleaned = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if cwd.standardizedFileURL == workspace.rootURL.standardizedFileURL {
            return cleaned
        }
        let relCWD = workspace.relativePath(for: cwd)
        let rootCandidate = workspace.rootURL.appendingPathComponent(cleaned)
        if cleaned.hasPrefix(relCWD + "/") || FileManager.default.fileExists(atPath: rootCandidate.path) {
            return cleaned
        }
        return "\(relCWD)/\(cleaned)"
    }

    private func stripSurroundingQuotes(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, ((t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'"))) {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    private func offlineSynthesizeCLIResponse(
        cliName: String,
        prompt: String,
        cwd: URL,
        workspace: WorkspaceManager,
        scannedTree: String,
        onPrint: @escaping @MainActor (String) -> Void
    ) async {
        let lower = prompt.lowercased()
        let explicitFile = extractFilename(from: prompt)
        onPrint("\u{001B}[1;33m[\(cliName.uppercased()) LOCAL]\u{001B}[0m Running offline workspace assistant (no API key required)...\n")

        if let fileName = explicitFile {
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let codeBody: String = {
                switch ext {
                case "html", "htm":
                    return "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\n  <title>\(fileName)</title>\n</head>\n<body>\n  <h1>Generated by 3012 \(cliName) CLI</h1>\n  <p>Prompt: \(prompt)</p>\n</body>\n</html>\n"
                case "js", "mjs":
                    if lower.contains("bot") || lower.contains("telegram") {
                        return "const token = process.env.TELEGRAM_BOT_TOKEN || '';\nconst bot = new TelegramBot(token);\nbot.onCommand('start', async (msg) => {\n  await bot.sendMessage(msg.chat.id, 'Hello from 3012 \(cliName) CLI!');\n});\nbot.startPolling(1200);\n"
                    }
                    return "// Generated by 3012 \(cliName) CLI\nconsole.log('Running \(fileName) on 3012!');\n"
                case "py":
                    return "# Generated by 3012 \(cliName) CLI\ndef main():\n    print(\"Hello from \(fileName)!\")\n\nif __name__ == \"__main__\":\n    main()\n"
                case "cpp", "cc":
                    return "#include <iostream>\nusing namespace std;\nint main() {\n    cout << \"Hello from \(fileName)!\" << endl;\n    return 0;\n}\n"
                case "c":
                    return "#include <stdio.h>\nint main(void) {\n    printf(\"Hello from \(fileName)!\\n\");\n    return 0;\n}\n"
                default:
                    return "// \(fileName) — generated by 3012 \(cliName) CLI\n// Task: \(prompt)\n"
                }
            }()
            let finalRel = resolveWorkspaceRelativePath(fileName, cwd: cwd, workspace: workspace)
            workspace.applyAgentFileEdit(relativePath: finalRel, newContent: codeBody)
            onPrint("\u{001B}[1;32m[WRITE]\u{001B}[0m Created \(finalRel) and opened it in 3012 Editor.\n")
        } else {
            onPrint("Workspace files scanned:\n\(scannedTree)\n")
        }
        onPrint("\u{001B}[36m[TIP]\u{001B}[0m Run '\(cliName) auth <YOUR_API_KEY>' or configure Agent Settings to enable full LLM coding streaming.\n")
    }

    private func extractFilename(from text: String) -> String? {
        let pattern = #"\b([A-Za-z0-9_\-./]+\.(?:html|htm|css|js|ts|py|c|cpp|h|hpp|swift|json|md|txt|sh|xm|x|lua|go|rs))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
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
