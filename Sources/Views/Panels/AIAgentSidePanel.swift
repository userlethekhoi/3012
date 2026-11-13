import SwiftUI

public struct AIAgentSidePanel: View {
    @ObservedObject var aiService: AIAgentService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var preferences: EditorPreferences
    var onClose: () -> Void

    @State private var promptInput: String = ""
    @State private var showConfigSheet: Bool = false

    public init(
        aiService: AIAgentService,
        workspace: WorkspaceManager,
        runner: CodeRunnerService,
        preferences: EditorPreferences,
        onClose: @escaping () -> Void
    ) {
        self.aiService = aiService
        self.workspace = workspace
        self.runner = runner
        self.preferences = preferences
        self.onClose = onClose
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: palette.accent))
                Text("Coding Agent")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: palette.foreground))
                Text(aiService.modelName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(4)
                    .foregroundColor(Color(hex: palette.gutterForeground))
                    .lineLimit(1)

                Spacer()

                Button {
                    aiService.clearConversation()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }

                Button {
                    showConfigSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: palette.foreground))
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hex: palette.headerBackground))

            // Active Context Bar + Quick Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let active = workspace.activeTab {
                        Label(active.title, systemImage: "doc.text.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(hex: palette.accent).opacity(0.2))
                            .foregroundColor(Color(hex: palette.accent))
                            .cornerRadius(6)
                    }
                    if workspace.selectedSnippetInActiveTab() != nil {
                        Label("Selection", systemImage: "selection.pin.in.out")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.22))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                    }

                    ForEach([
                        ("Sửa lỗi", "Kiểm tra lỗi và sửa trực tiếp file đang mở giúp tôi."),
                        ("Tối ưu", "Tối ưu hiệu năng và làm sạch code của file đang mở."),
                        ("Giải thích", "Giải thích ngắn gọn logic của đoạn code đang mở.")
                    ], id: \.0) { label, fullPrompt in
                        Button {
                            submitPrompt(fullPrompt)
                        } label: {
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: palette.currentLineBackground))
                                .foregroundColor(Color(hex: palette.foreground))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(Color(hex: palette.sidebarBackground))

            Divider().overlay(Color.white.opacity(0.08))

            // Messages Stream
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(aiService.messages) { msg in
                            messageBubble(msg, palette: palette)
                                .id(msg.id)
                        }
                        if aiService.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Agent đang phân tích project & viết code...")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                            }
                            .padding(.horizontal, 10)
                            .id("thinking-indicator")
                        }
                    }
                    .padding(10)
                }
                .onChange(of: aiService.messages.count) { _, _ in
                    if let lastID = aiService.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Composer Input
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Giao việc cho AI (tạo/sửa file, fix bug)...", text: $promptInput, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(Color(hex: palette.editorBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(8)

                Button {
                    let current = promptInput
                    promptInput = ""
                    submitPrompt(current)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isThinking ? .gray : Color(hex: palette.accent))
                }
                .disabled(promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isThinking)
            }
            .padding(8)
            .background(Color(hex: palette.headerBackground))
        }
        .background(Color(hex: palette.sidebarBackground))
        .sheet(isPresented: $showConfigSheet) {
            NavigationStack {
                Form {
                    Section("Nhà cung cấp Model AI") {
                        Picker("Provider", selection: $aiService.provider) {
                            ForEach(AIProviderType.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .onChange(of: aiService.provider) { _, newValue in
                            aiService.modelName = newValue.defaultModel
                            aiService.customBaseURL = newValue.defaultBaseURL
                        }

                        TextField("Model Name (vd: gemini-2.5-flash, gpt-4o)", text: $aiService.modelName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        SecureField("API Key", text: $aiService.apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("API Base URL", text: $aiService.customBaseURL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Section("Mẹo kết nối DeepSeek / OpenRouter / VPS") {
                        Text("Chọn 'OpenAI / DeepSeek / OpenRouter / VPS' rồi đổi Base URL thành https://api.deepseek.com/v1 hoặc https://openrouter.ai/api/v1 hoặc AI Proxy trên VPS của bạn.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .navigationTitle("Cấu hình AI Agent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") { showConfigSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func messageBubble(_ msg: AIChatMessage, palette: IDEColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: msg.role == .user ? "person" : "cpu")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(msg.role == .user ? "Bạn" : "3012 Agent")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
            }
            .foregroundColor(msg.role == .user ? Color(hex: palette.accent) : .green)

            Text(msg.text)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: palette.foreground))
                .textSelection(.enabled)

            ForEach(msg.proposedEdits) { edit in
                diffCard(messageID: msg.id, edit: edit, palette: palette)
            }
        }
        .padding(9)
        .background(
            msg.role == .user
                ? Color(hex: palette.accent).opacity(0.14)
                : Color(hex: palette.editorBackground)
        )
        .cornerRadius(10)
    }

    @ViewBuilder
    private func diffCard(messageID: UUID, edit: AgentProposedEdit, palette: IDEColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.badge.gearshape.fill")
                    .foregroundColor(Color(hex: palette.accent))
                Text(edit.relativePath)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: palette.foreground))
                Spacer()
                switch edit.state {
                case .applied:
                    Label("Đã áp dụng", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                case .rejected:
                    Label("Đã bỏ qua", systemImage: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                case .pending:
                    EmptyView()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(edit.diffPreviewLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(
                                line.hasPrefix("+") ? Color.green :
                                (line.hasPrefix("-") ? Color.red : Color(hex: palette.gutterForeground))
                            )
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 150)
            .background(Color.black.opacity(0.28))
            .cornerRadius(6)

            if edit.state == .pending {
                HStack(spacing: 8) {
                    Button {
                        workspace.applyAgentFileEdit(relativePath: edit.relativePath, newContent: edit.newContent)
                        aiService.markEditState(messageID: messageID, editID: edit.id, newState: .applied)
                    } label: {
                        Label("Accept & Save", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                    }

                    Button {
                        aiService.markEditState(messageID: messageID, editID: edit.id, newState: .rejected)
                    } label: {
                        Label("Reject", systemImage: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(hex: palette.currentLineBackground))
        .cornerRadius(8)
    }

    private func submitPrompt(_ text: String) {
        let activePath = workspace.activeTab.map { workspace.relativePath(for: $0.fileURL) }
        let activeCode = workspace.activeTab?.content
        let snippet = workspace.selectedSnippetInActiveTab()
        let tree = workspace.workspaceSummaryTree()
        let lastOut = runner.consoleOutput

        Task {
            await aiService.sendPrompt(
                userPrompt: text,
                workspaceTree: tree,
                activeFilePath: activePath,
                activeFileContent: activeCode,
                selectedSnippet: snippet,
                lastConsoleOutput: lastOut,
                existingFileReader: { relPath in
                    let url = workspace.rootURL.appendingPathComponent(relPath)
                    return try? String(contentsOf: url, encoding: .utf8)
                }
            )
        }
    }
}
