import SwiftUI
import UIKit

public struct AIAgentSidePanel: View {
    @ObservedObject var aiService: AIAgentService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var preferences: EditorPreferences
    var intelligence: CodeIntelligenceService?
    var gitService: GitService?
    var onClose: () -> Void

    @State private var promptInput: String = ""
    @State private var pendingImages: [AIAttachmentImage] = []
    @State private var attachmentNotice: String? = nil
    @State private var showConfigSheet: Bool = false
    @State private var showSkillCreatorSheet: Bool = false
    @State private var newSkillCmd: String = ""
    @State private var newSkillTitle: String = ""
    @State private var newSkillInstruction: String = ""

    public init(
        aiService: AIAgentService,
        workspace: WorkspaceManager,
        runner: CodeRunnerService,
        preferences: EditorPreferences,
        intelligence: CodeIntelligenceService? = nil,
        gitService: GitService? = nil,
        onClose: @escaping () -> Void
    ) {
        self.aiService = aiService
        self.workspace = workspace
        self.runner = runner
        self.preferences = preferences
        self.intelligence = intelligence
        self.gitService = gitService
        self.onClose = onClose
    }

    private enum TriggerMatch {
        case slash(query: String, tokenRange: Range<String.Index>)
        case mention(query: String, tokenRange: Range<String.Index>)
    }

    private var activeTrigger: TriggerMatch? {
        let s = promptInput
        guard !s.isEmpty else { return nil }
        let start = s.lastIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { s.index(after: $0) } ?? s.startIndex
        let token = String(s[start..<s.endIndex])
        if token.hasPrefix("/") {
            return .slash(query: String(token.dropFirst()).lowercased(), tokenRange: start..<s.endIndex)
        }
        if token.hasPrefix("@") {
            return .mention(query: String(token.dropFirst()).lowercased(), tokenRange: start..<s.endIndex)
        }
        return nil
    }

    private var canSend: Bool {
        !promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Top Header Bar
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: palette.accent))
                Text("Agent")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: palette.foreground))

                // Provider & Model Menu
                Menu {
                    if !aiService.profiles.isEmpty {
                        Section(preferences.tr("Nhà cung cấp", "Providers")) {
                            ForEach(aiService.profiles) { profile in
                                Button {
                                    aiService.setActiveProfile(profile.id)
                                } label: {
                                    if aiService.activeProfile?.id == profile.id {
                                        Label(profile.name, systemImage: "checkmark")
                                    } else {
                                        Text(profile.name)
                                    }
                                }
                            }
                        }
                    }
                    if let active = aiService.activeProfile {
                        Button {
                            Task { await aiService.refreshModels(for: active.id) }
                        } label: {
                            Label(preferences.tr("Kiểm tra model mới nhất", "Check Latest Models"), systemImage: "arrow.clockwise")
                        }
                    }
                    Button {
                        showConfigSheet = true
                    } label: {
                        Label(preferences.tr("Cấu hình AI...", "Configure AI..."), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 3) {
                        if let active = aiService.activeProfile, active.isLocal {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        Text(aiService.modelName)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(4)
                    .foregroundColor(Color(hex: palette.gutterForeground))
                }

                // Multi-session Thread Switcher
                Menu {
                    Button {
                        aiService.createNewSession()
                    } label: {
                        Label(preferences.tr("Phiên chat mới", "New Chat Thread"), systemImage: "plus.bubble")
                    }
                    if !aiService.sessions.isEmpty {
                        Section(preferences.tr("Lịch sử phiên chat", "Chat Sessions")) {
                            ForEach(aiService.sessions) { session in
                                Button {
                                    aiService.switchSession(to: session.id)
                                } label: {
                                    if session.id == aiService.activeSessionID {
                                        Label(session.title, systemImage: "checkmark")
                                    } else {
                                        Text(session.title)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showSkillCreatorSheet = true
                    } label: {
                        Label(preferences.tr("Quản lý '/' Skills...", "Manage '/' Skills..."), systemImage: "slash.circle")
                    }
                    if let currentID = aiService.activeSessionID, aiService.sessions.count > 1 {
                        Button(role: .destructive) {
                            aiService.deleteSession(id: currentID)
                        } label: {
                            Label(preferences.tr("Xóa phiên hiện tại", "Delete This Thread"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }

                Spacer(minLength: 4)

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

            // Active Context & Quick /Skill + @Mention Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let active = workspace.activeTab {
                        Button {
                            insertAtEnd("@\(workspace.relativePath(for: active.fileURL)) ")
                        } label: {
                            Label(active.title, systemImage: "doc.text.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color(hex: palette.accent).opacity(0.2))
                                .foregroundColor(Color(hex: palette.accent))
                                .cornerRadius(6)
                        }
                    }
                    if workspace.selectedSnippetInActiveTab() != nil {
                        Button {
                            insertAtEnd("@selection ")
                        } label: {
                            Label("@selection", systemImage: "selection.pin.in.out")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.22))
                                .foregroundColor(.purple)
                                .cornerRadius(6)
                        }
                    }

                    ForEach([
                        ("/fix", preferences.tr("Sửa lỗi file đang mở với /fix", "/fix active file bugs")),
                        ("/ui", preferences.tr("Thiết kế / sửa UI với /ui", "/ui design & polish")),
                        ("/refactor", preferences.tr("Làm sạch & tối ưu với /refactor", "/refactor cleanly")),
                        ("@problems", nil),
                        ("@git", nil)
                    ], id: \.0) { chip, instantPrompt in
                        Button {
                            if let instantPrompt, promptInput.trimmingCharacters(in: .whitespaces).isEmpty {
                                promptInput = "\(chip) \(instantPrompt)"
                            } else {
                                insertAtEnd("\(chip) ")
                            }
                        } label: {
                            Text(chip)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color(hex: palette.currentLineBackground))
                                .foregroundColor(chip.hasPrefix("/") ? Color.orange : Color.cyan)
                                .cornerRadius(6)
                        }
                    }

                    Button {
                        showSkillCreatorSheet = true
                    } label: {
                        Label("+ /Skill", systemImage: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .cornerRadius(6)
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
                        if aiService.isThinking && !(aiService.messages.last?.isStreaming ?? false) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(preferences.tr("Đang chuẩn bị model...", "Preparing model..."))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                            }
                            .padding(.horizontal, 10)
                            .id("thinking-indicator")
                        }
                    }
                    .padding(10)
                }
                .onChange(of: aiService.messages.count) { _ in
                    if let lastID = aiService.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
                .onChange(of: aiService.streamRevision) { _ in
                    if let lastID = aiService.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            // Live /Skill and @Mention Autocomplete Popover
            if let trigger = activeTrigger {
                triggerAutocompleteBar(trigger: trigger, palette: palette)
            }

            // Pending Multimodal Image Strip
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages) { img in
                            ZStack(alignment: .topTrailing) {
                                if let uiImg = UIImage(data: img.jpegData) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(hex: palette.accent).opacity(0.6), lineWidth: 1)
                                        )
                                }
                                Button {
                                    pendingImages.removeAll { $0.id == img.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.7).clipShape(Circle()))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(Color(hex: palette.headerBackground).opacity(0.85))
            }

            if let attachmentNotice {
                Text(attachmentNotice)
                    .font(.system(size: 10.5))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: palette.headerBackground))
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Composer Input Row
            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    Button {
                        NativeDocumentPickerPresenter.shared.presentPhotoLibraryPicker(maxCount: 4) { images in
                            for image in images {
                                attachUIImage(image)
                            }
                        }
                    } label: {
                        Label(preferences.tr("Chọn ảnh từ Thư viện", "Choose Photo from Library"), systemImage: "photo.on.rectangle")
                    }

                    Button {
                        NativeDocumentPickerPresenter.shared.presentCameraPicker { image in
                            attachUIImage(image)
                        }
                    } label: {
                        Label(preferences.tr("Chụp ảnh bằng Camera", "Take Photo with Camera"), systemImage: "camera")
                    }

                    Button {
                        if let clipImg = UIPasteboard.general.image {
                            attachUIImage(clipImg)
                        } else {
                            attachmentNotice = preferences.tr("Clipboard hiện chưa có hình ảnh.", "No image found in clipboard.")
                        }
                    } label: {
                        Label(preferences.tr("Dán ảnh từ Clipboard", "Paste Image from Clipboard"), systemImage: "doc.on.clipboard")
                    }

                    Divider()

                    Button {
                        insertAtEnd("/")
                    } label: {
                        Label(preferences.tr("Gắn Skill ('/')", "Insert '/' Skill"), systemImage: "slash.circle")
                    }

                    Button {
                        insertAtEnd("@")
                    } label: {
                        Label(preferences.tr("Tag File / Context ('@')", "Tag File / Context ('@')"), systemImage: "at")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: palette.accent))
                        .frame(width: 28, height: 32)
                }

                Group {
                    if #available(iOS 16.0, *) {
                        TextField(
                            preferences.tr("Gõ / (Skill), @ (File) hoặc đính ảnh...", "Type / (Skill), @ (File) or attach image..."),
                            text: $promptInput,
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                    } else {
                        TextField(
                            preferences.tr("Gõ / (Skill), @ (File) hoặc đính ảnh...", "Type / (Skill), @ (File) or attach image..."),
                            text: $promptInput
                        )
                    }
                }
                .font(.system(size: 13))
                .padding(8)
                .background(Color(hex: palette.editorBackground))
                .foregroundColor(Color(hex: palette.foreground))
                .cornerRadius(8)

                if aiService.isThinking {
                    Button {
                        aiService.stopGenerating()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.red.opacity(0.85))
                    }
                } else {
                    Button {
                        let current = promptInput
                        let imgs = pendingImages
                        promptInput = ""
                        pendingImages = []
                        attachmentNotice = nil
                        submitPrompt(current, images: imgs)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(!canSend ? .gray : Color(hex: palette.accent))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(8)
            .background(Color(hex: palette.headerBackground))
        }
        .background(Color(hex: palette.sidebarBackground))
        .task {
            await aiService.refreshStaleModelsIfNeeded()
        }
        .sheet(isPresented: $showConfigSheet) {
            AIProviderSettingsSheet(aiService: aiService)
        }
        .sheet(isPresented: $showSkillCreatorSheet) {
            skillCreatorSheet
        }
    }

    // MARK: - Trigger Popover View
    @ViewBuilder
    private func triggerAutocompleteBar(trigger: TriggerMatch, palette: IDEColorPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                switch trigger {
                case .slash(let query, let range):
                    let matched = aiService.allSkills.filter {
                        query.isEmpty || $0.slashCommand.lowercased().contains(query) || $0.title.lowercased().contains(query)
                    }
                    ForEach(matched) { skill in
                        Button {
                            promptInput.replaceSubrange(range, with: "\(skill.slashCommand) ")
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(skill.slashCommand)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text(skill.title)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(hex: palette.currentLineBackground))
                            .cornerRadius(7)
                        }
                    }
                    Button {
                        showSkillCreatorSheet = true
                    } label: {
                        Label(preferences.tr("Tạo Skill mới", "New Skill"), systemImage: "plus.circle")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(7)
                    }

                case .mention(let query, let range):
                    let builtins = ["@active", "@selection", "@problems", "@terminal", "@git"]
                    let files = workspace.flattenFiles(in: workspace.fileTree).map { "@\(workspace.relativePath(for: $0))" }
                    let candidates = (builtins + files).filter {
                        query.isEmpty || $0.lowercased().contains(query)
                    }
                    ForEach(Array(candidates.prefix(14)), id: \.self) { item in
                        Button {
                            promptInput.replaceSubrange(range, with: "\(item) ")
                        } label: {
                            Text(item)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(hex: palette.currentLineBackground))
                                .foregroundColor(builtins.contains(item) ? .cyan : Color(hex: palette.foreground))
                                .cornerRadius(7)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(hex: palette.headerBackground))
    }

    // MARK: - Custom Slash Skill Manager Sheet
    private var skillCreatorSheet: some View {
        CompatibleNavigationContainer {
            Form {
                Section(preferences.tr("Tạo '/' Skill mới cho AI Agent", "Create New '/' Agent Skill")) {
                    TextField("/command (vd: /api, /clean)", text: $newSkillCmd)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(preferences.tr("Tên ngắn gọn", "Short Title"), text: $newSkillTitle)
                    TextField(preferences.tr("Chỉ dẫn chi tiết cho AI khi gọi skill này...", "Instruction injected when calling this skill..."), text: $newSkillInstruction)
                    Button {
                        aiService.addCustomSkill(slashCommand: newSkillCmd, title: newSkillTitle, instruction: newSkillInstruction)
                        newSkillCmd = ""
                        newSkillTitle = ""
                        newSkillInstruction = ""
                    } label: {
                        Label(preferences.tr("Lưu Slash Skill", "Save Slash Skill"), systemImage: "checkmark.circle.fill")
                    }
                    .disabled(newSkillCmd.trimmingCharacters(in: .whitespaces).isEmpty || newSkillInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section(preferences.tr("Tất cả Skills (/cmd)", "Available Slash Skills")) {
                    ForEach(aiService.allSkills) { skill in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(skill.slashCommand) — \(skill.title)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.orange)
                                Text(skill.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !skill.isBuiltIn {
                                Button(role: .destructive) {
                                    aiService.deleteCustomSkill(id: skill.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(preferences.tr("Slash Skills (/)", "Agent '/' Skills"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { showSkillCreatorSheet = false }
                }
            }
        }
    }

    // MARK: - Helpers
    private func insertAtEnd(_ token: String) {
        if !promptInput.isEmpty && !promptInput.hasSuffix(" ") && !promptInput.hasSuffix("\n") && token != "/" && token != "@" {
            promptInput += " "
        }
        promptInput += token
    }

    private func attachUIImage(_ image: UIImage) {
        guard let compressed = NativeDocumentPickerPresenter.downscaleAndCompress(image) else { return }
        pendingImages.append(AIAttachmentImage(
            jpegData: compressed.data,
            width: compressed.width,
            height: compressed.height
        ))
        attachmentNotice = nil
    }

    // MARK: - Message Bubbles & Diff Cards
    @ViewBuilder
    private func messageBubble(_ msg: AIChatMessage, palette: IDEColorPalette) -> some View {
        if msg.role == .system {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text(msg.text)
                    .font(.system(size: 11))
                    .textSelection(.enabled)
            }
            .foregroundColor(Color(hex: palette.gutterForeground))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: palette.currentLineBackground).opacity(0.6))
            .cornerRadius(8)
        } else {
            chatBubble(msg, palette: palette)
        }
    }

    private func renderedMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    @ViewBuilder
    private func chatBubble(_ msg: AIChatMessage, palette: IDEColorPalette) -> some View {
        let pendingEditsCount = msg.proposedEdits.filter { $0.state == .pending }.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: msg.role == .user ? "person" : "cpu")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(msg.role == .user ? "Bạn" : "3012 Agent")
                    .font(.system(size: 10, weight: .bold))
                if let model = msg.modelLabel, msg.role == .assistant {
                    Text(model)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .lineLimit(1)
                }
                Spacer()
            }
            .foregroundColor(msg.role == .user ? Color(hex: palette.accent) : .green)

            if !msg.attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(msg.attachedImages) { img in
                            if let uiImg = UIImage(data: img.jpegData) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            if msg.isStreaming && msg.text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Đang kết nối model...")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }
            } else {
                Text(renderedMarkdown(msg.isStreaming ? msg.text + " ▍" : msg.text))
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: palette.foreground))
                    .textSelection(.enabled)
            }

            if pendingEditsCount > 1 {
                HStack(spacing: 8) {
                    Button {
                        aiService.acceptAllEdits(in: msg.id) { rel, body in
                            workspace.applyAgentFileEdit(relativePath: rel, newContent: body)
                        }
                    } label: {
                        Label(preferences.tr("Accept All (\(pendingEditsCount))", "Accept All (\(pendingEditsCount))"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                    }

                    Button {
                        aiService.rejectAllEdits(in: msg.id)
                    } label: {
                        Label(preferences.tr("Reject All", "Reject All"), systemImage: "xmark.circle")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.18))
                            .foregroundColor(.red)
                            .cornerRadius(6)
                    }
                }
            }

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
                    .lineLimit(1)
                Text("+\(edit.addedCount) -\(edit.removedCount)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: palette.gutterForeground))
                Spacer()
                switch edit.state {
                case .applied:
                    HStack(spacing: 6) {
                        Label("Đã áp dụng", systemImage: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                        if edit.previousContent != nil || !edit.existedBeforeEdit {
                            Button {
                                aiService.revertAppliedEdit(
                                    messageID: messageID,
                                    editID: edit.id,
                                    restoreHandler: { rel, prev in
                                        workspace.applyAgentFileEdit(relativePath: rel, newContent: prev)
                                    },
                                    deleteHandler: { rel in
                                        let rootCanon = WorkspaceManager.canonicalPath(workspace.rootURL)
                                        let rootPrefix = rootCanon.hasSuffix("/") ? rootCanon : rootCanon + "/"
                                        let targetURL = workspace.rootURL.appendingPathComponent(rel)
                                        if WorkspaceManager.canonicalPath(targetURL).hasPrefix(rootPrefix) {
                                            workspace.deleteItem(at: targetURL)
                                        }
                                    }
                                )
                            } label: {
                                Text("Undo")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.22))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }
                    }
                case .rejected:
                    Label("Đã bỏ qua", systemImage: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                case .pending:
                    EmptyView()
                }
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
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

    private func submitPrompt(_ text: String, images: [AIAttachmentImage] = []) {
        let activePath = workspace.activeTab.map { workspace.relativePath(for: $0.fileURL) }
        let activeCode = workspace.activeTab?.content
        let snippet = workspace.selectedSnippetInActiveTab()
        let tree = workspace.workspaceSummaryTree()
        let lastOut = runner.consoleOutput

        let diagText: String = {
            guard let intel = intelligence, !intel.diagnostics.isEmpty else { return "" }
            return intel.diagnostics.prefix(20).map { "Line \($0.line) [\($0.severity)]: \($0.message)" }.joined(separator: "\n")
        }()

        let gitText: String = {
            guard let git = gitService, !git.changedFiles.isEmpty else { return "" }
            return "Branch: \(git.currentBranch)\n" + git.changedFiles.prefix(15).map { "[\($0.statusBadge)] \($0.relativePath) (+\($0.addedLines)/-\($0.removedLines))" }.joined(separator: "\n")
        }()

        Task {
            await aiService.sendPrompt(
                userPrompt: text,
                workspaceTree: tree,
                activeFilePath: activePath,
                activeFileContent: activeCode,
                selectedSnippet: snippet,
                lastConsoleOutput: lastOut,
                attachedImages: images,
                diagnosticsSummary: diagText,
                gitDiffSummary: gitText,
                existingFileReader: { relPath in
                    let clean = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                    let url = workspace.rootURL.appendingPathComponent(clean)
                    if let tab = workspace.openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
                        return tab.content
                    }
                    return try? String(contentsOf: url, encoding: .utf8)
                }
            )
        }
    }
}
