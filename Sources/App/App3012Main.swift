import SwiftUI
import UIKit

public enum MarkdownDisplayMode: String, CaseIterable, Identifiable {
    case editor = "Code"
    case split = "Split"
    case preview = "Preview"

    public var id: String { rawValue }
}

@main
struct App3012Main: App {
    @StateObject private var preferences = EditorPreferences()
    @StateObject private var workspace = WorkspaceManager()
    @StateObject private var liveServer = LiveServerService()
    @StateObject private var runner = CodeRunnerService()
    @StateObject private var aiService = AIAgentService()
    @StateObject private var gitService = GitService()
    @StateObject private var sshService = SSHWorkspaceService()
    @StateObject private var extStore = ExtensionStoreService()
    @StateObject private var intelligence = CodeIntelligenceService()
    @StateObject private var timelineService = FileTimelineAndArchiveService()

    var body: some Scene {
        WindowGroup {
            MainIDEWorkspaceView(
                preferences: preferences,
                workspace: workspace,
                liveServer: liveServer,
                runner: runner,
                aiService: aiService,
                gitService: gitService,
                sshService: sshService,
                extStore: extStore,
                intelligence: intelligence,
                timelineService: timelineService
            )
            .preferredColorScheme(preferences.activePalette.isDark ? .dark : .light)
        }
    }
}

public struct MainIDEWorkspaceView: View {
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var aiService: AIAgentService
    @ObservedObject var gitService: GitService
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var extStore: ExtensionStoreService
    @ObservedObject var intelligence: CodeIntelligenceService
    @ObservedObject var timelineService: FileTimelineAndArchiveService

    @State private var showLeftExplorer: Bool = false
    @State private var showRightAIPanel: Bool = false
    @State private var showBottomPanel: Bool = false
    @State private var bottomTab: BottomPanelTab = .terminal
    @State private var bottomDetent: BottomPanelDetent = .half
    @State private var showSettingsSheet: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var showSymbolOutlineSheet: Bool = false
    @State private var showLanguagePickerSheet: Bool = false
    @State private var showTimelineSheet: Bool = false
    @State private var showThemeStudioDirect: Bool = false
    @State private var shareZipItem: ShareableZipFile? = nil

    @State private var markdownMode: MarkdownDisplayMode = .editor
    @State private var findTriggerToken: Int = 0
    @State private var toggleCommentToken: Int = 0
    @State private var completionRequest: CompletionReplacementRequest? = nil
    @State private var jumpRequest: JumpToLineRequest? = nil

    public var body: some View {
        let palette = preferences.activePalette

        GeometryReader { geo in
            let isWideLayout = geo.size.width >= 680

            ZStack(alignment: .leading) {
                // Hidden Hardware Bluetooth / Magic Keyboard Shortcuts Responder
                hardwareKeyboardShortcutsHost

                VStack(spacing: 0) {
                    // 1. Ultra-Slim 38pt Top Header Bar
                    topHeaderBar(palette: palette)

                    // 2. Slim 26pt Breadcrumb, Diagnostics, Quick Toggles & Markdown/Timeline Strip
                    if let activeTab = workspace.activeTab {
                        editorSubToolbar(activeTab: activeTab, palette: palette)
                    }

                    // 3. Central Workspace Area (Editor / Markdown Preview + Optional Side-by-Side Agent)
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if let activeTab = workspace.activeTab {
                                centralEditorAndPreviewArea(activeTab: activeTab, palette: palette, isWide: isWideLayout)
                            } else {
                                emptyEditorPlaceholder(palette: palette)
                            }

                            if showBottomPanel {
                                Divider().overlay(Color.white.opacity(0.12))
                                BottomConsolePreviewPanel(
                                    selectedTab: $bottomTab,
                                    detent: $bottomDetent,
                                    runner: runner,
                                    liveServer: liveServer,
                                    sshService: sshService,
                                    workspace: workspace,
                                    preferences: preferences,
                                    intelligence: intelligence,
                                    onJumpToLine: { line in
                                        triggerJumpToLine(line)
                                    },
                                    onFixDiagnosticWithAgent: { diag in
                                        fixDiagnosticWithAgent(diag)
                                    },
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showBottomPanel = false
                                        }
                                    }
                                )
                                .frame(height: bottomDetent.height(in: geo.size.height))
                            }
                        }

                        // Side-by-side Coding Agent Panel when screen is wide (Landscape iPhone / iPad)
                        if showRightAIPanel && isWideLayout {
                            Divider().overlay(Color.white.opacity(0.12))
                            AIAgentSidePanel(
                                aiService: aiService,
                                workspace: workspace,
                                runner: runner,
                                preferences: preferences,
                                onClose: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showRightAIPanel = false
                                    }
                                }
                            )
                            .frame(width: min(max(geo.size.width * 0.38, 300), 420))
                        }
                    }
                }
                .background(Color(hex: palette.editorBackground))

                // Dimming Backdrop for Portrait Drawers
                if showLeftExplorer || (showRightAIPanel && !isWideLayout) {
                    Color.black.opacity(0.42)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLeftExplorer = false
                                if !isWideLayout { showRightAIPanel = false }
                            }
                        }
                }

                // Full 5-Tab VS Code Activity Sidebar Drawer (Explorer, Search, Git, SSH/SFTP, OpenVSX)
                if showLeftExplorer {
                    LeftExplorerDrawer(
                        workspace: workspace,
                        preferences: preferences,
                        liveServer: liveServer,
                        gitService: gitService,
                        sshService: sshService,
                        extStore: extStore,
                        timelineService: timelineService,
                        onInsertSnippet: { snippetBody in
                            insertTextIntoActiveTab(snippetBody)
                        },
                        onOpenSettings: {
                            showLeftExplorer = false
                            showSettingsSheet = true
                        },
                        onCloseDrawer: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLeftExplorer = false
                            }
                        }
                    )
                    .frame(width: min(geo.size.width * 0.86, 350))
                    .transition(.move(edge: .leading))
                    .zIndex(10)
                }

                // Right Coding Agent Drawer (Portrait Overlay mode)
                if showRightAIPanel && !isWideLayout {
                    HStack(spacing: 0) {
                        Spacer()
                        AIAgentSidePanel(
                            aiService: aiService,
                            workspace: workspace,
                            runner: runner,
                            preferences: preferences,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showRightAIPanel = false
                                }
                            }
                        )
                        .frame(width: min(geo.size.width * 0.88, 360))
                        .shadow(color: .black.opacity(0.45), radius: 14, x: -4, y: 0)
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(11)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 22, coordinateSpace: .local)
                    .onEnded { value in
                        if value.startLocation.x < 24 && value.translation.width > 55 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                showLeftExplorer = true
                            }
                        } else if value.startLocation.x > geo.size.width - 24 && value.translation.width < -55 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                showRightAIPanel = true
                            }
                        }
                    }
            )
        }
        .onAppear {
            workspace.onFileSavedOrChanged = { [weak liveServer] in
                liveServer?.notifyFileChanged()
            }
            workspace.onAnyTabSavedWithURL = { [weak sshService, weak timelineService, weak intelligence, weak workspace] fileURL, updatedText in
                sshService?.syncSavedLocalMirrorIfNeeded(localURL: fileURL, content: updatedText)
                timelineService?.recordSnapshot(for: fileURL, content: updatedText, label: "Auto-Save")
                if let workspace {
                    intelligence?.reindexWorkspaceFiles(workspace.flattenFiles(in: workspace.fileTree))
                }
            }
            liveServer.start(
                serving: workspace.rootURL,
                keepAliveInBackground: preferences.keepServerInBackground
            )
            intelligence.reindexWorkspaceFiles(workspace.flattenFiles(in: workspace.fileTree))
            refreshIntelligenceForActiveTab()
        }
        .onChange(of: workspace.fileTree) { _, updatedTree in
            intelligence.reindexWorkspaceFiles(workspace.flattenFiles(in: updatedTree))
        }
        .onChange(of: workspace.activeTabID) { _, _ in
            intelligence.clearCompletions()
            if workspace.activeTab?.language != .markdown {
                markdownMode = .editor
            }
            refreshIntelligenceForActiveTab()
        }
        .onChange(of: preferences.enableLiveDiagnostics) { _, enabled in
            if enabled {
                refreshIntelligenceForActiveTab()
            } else {
                intelligence.diagnostics = []
            }
        }
        .onChange(of: preferences.enableCodeCompletion) { _, enabled in
            if !enabled {
                intelligence.clearCompletions()
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsAndThemesSheet(
                preferences: preferences,
                liveServer: liveServer,
                runner: runner
            )
        }
        .sheet(isPresented: $showThemeStudioDirect) {
            ThemeStudioEditorSheet(preferences: preferences)
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteSheet(
                workspace: workspace,
                preferences: preferences,
                commands: buildPaletteCommands()
            )
        }
        .sheet(isPresented: $showSymbolOutlineSheet) {
            if let activeTab = workspace.activeTab {
                SymbolOutlineSheet(
                    fileName: activeTab.title,
                    symbols: intelligence.symbols,
                    palette: palette,
                    onSelectLine: { line in
                        triggerJumpToLine(line)
                    }
                )
            }
        }
        .sheet(isPresented: $showLanguagePickerSheet) {
            if let activeTab = workspace.activeTab {
                LanguageModePickerSheet(
                    fileName: activeTab.title,
                    autoDetectedLanguage: CodeLanguage.detect(
                        from: activeTab.fileURL,
                        contentSample: String(activeTab.content.prefix(1200))
                    ),
                    currentOverride: activeTab.languageOverride,
                    palette: palette,
                    onSelectOverride: { overrideLang in
                        workspace.setLanguageOverrideForActiveTab(overrideLang)
                        refreshIntelligenceForActiveTab()
                    }
                )
            }
        }
        .sheet(isPresented: $showTimelineSheet) {
            if let activeTab = workspace.activeTab {
                FileTimelineSheet(
                    fileURL: activeTab.fileURL,
                    currentContent: activeTab.content,
                    timelineService: timelineService,
                    onRestoreContent: { restored in
                        workspace.updateActiveContent(restored, autoSave: true)
                        timelineService.recordSnapshot(for: activeTab.fileURL, content: restored, label: "Restored Snapshot")
                        refreshIntelligenceForActiveTab()
                    }
                )
            }
        }
        .sheet(item: $shareZipItem) { item in
            ZipActivityShareSheet(fileURL: item.url)
        }
    }

    // MARK: - Central Editor + Floating Live Autocomplete + Markdown/Mermaid View
    @ViewBuilder
    private func centralEditorAndPreviewArea(activeTab: OpenTab, palette: IDEColorPalette, isWide: Bool) -> some View {
        let showMarkdownSplit = (activeTab.language == .markdown && markdownMode == .split)
        let showMarkdownOnly = (activeTab.language == .markdown && markdownMode == .preview)

        if showMarkdownOnly {
            MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette)
        } else if showMarkdownSplit {
            if isWide {
                HStack(spacing: 0) {
                    editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
                    Divider().overlay(Color.white.opacity(0.12))
                    MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette)
                }
            } else {
                VStack(spacing: 0) {
                    editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
                    Divider().overlay(Color.white.opacity(0.12))
                    MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette)
                }
            }
        } else {
            editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
        }
    }

    @ViewBuilder
    private func editorWithAutocompleteOverlay(activeTab: OpenTab, palette: IDEColorPalette) -> some View {
        ZStack(alignment: .bottomLeading) {
            RunestoneEditorView(
                fileURL: activeTab.fileURL,
                text: activeTab.content,
                language: activeTab.language,
                preferences: preferences,
                highlightedRanges: intelligence.makeRunestoneHighlightedRanges(enabled: preferences.enableLiveDiagnostics),
                completionRequest: completionRequest,
                jumpRequest: jumpRequest,
                findTriggerToken: findTriggerToken,
                toggleCommentToken: toggleCommentToken,
                onAcceptPrimaryCompletion: {
                    guard preferences.enableCodeCompletion, let top = intelligence.completions.first else {
                        return false
                    }
                    applyCompletionCandidate(top)
                    return true
                },
                onTextChange: { updatedCode, range in
                    workspace.updateActiveContent(updatedCode, selectedRange: range, autoSave: preferences.enableAutoSave)
                    let allSnips = extStore.snippets
                    intelligence.updateCompletions(
                        in: updatedCode,
                        selectedRange: range,
                        language: activeTab.language,
                        snippets: allSnips,
                        enabled: preferences.enableCodeCompletion
                    )
                    intelligence.scheduleAnalysis(
                        code: updatedCode,
                        language: activeTab.language,
                        fileName: activeTab.title,
                        cursorLocation: range.location,
                        diagnosticsEnabled: preferences.enableLiveDiagnostics,
                        sshService: sshService
                    )
                },
                onSelectionChange: { range in
                    workspace.updateSelectionOnly(range)
                    intelligence.updateActiveBreadcrumb(cursorLocation: range.location, in: activeTab.content)
                    if range.length > 0 {
                        intelligence.clearCompletions()
                    }
                },
                onToggleAI: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        showRightAIPanel.toggle()
                    }
                }
            )

            // Floating VS Code Smart IntelliSense & Parameter Signature Widget
            if preferences.enableCodeCompletion && (!intelligence.completions.isEmpty || intelligence.activeSignatureHint != nil) {
                liveAutocompleteFloatingBar(palette: palette)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func completionKindColor(_ kind: CompletionKind, palette: IDEColorPalette) -> Color {
        switch kind {
        case .emmet: return .orange
        case .snippet: return Color(hex: palette.accent)
        case .method, .function: return Color(hex: palette.function)
        case .type: return Color(hex: palette.typeName)
        case .property: return Color(hex: palette.property)
        case .variable: return Color(hex: palette.variable)
        case .keyword: return Color(hex: palette.keyword)
        case .module: return Color(hex: palette.string)
        }
    }

    @ViewBuilder
    private func liveAutocompleteFloatingBar(palette: IDEColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // 1. Live Function Parameter Signature Callout (when typing inside fn(...))
            if let sig = intelligence.activeSignatureHint {
                HStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: palette.function))
                    Text(sig)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if intelligence.completions.isEmpty {
                        Button {
                            intelligence.clearCompletions()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(Color(hex: palette.gutterForeground))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: palette.editorBackground).opacity(0.9))
                .cornerRadius(6)
            }

            // 2. Fuzzy / CamelCase / Member Dot / Emmet Completion Strip
            if !intelligence.completions.isEmpty {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(intelligence.completions.enumerated()), id: \.element.id) { idx, item in
                                Button {
                                    applyCompletionCandidate(item)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: item.kind.systemIcon)
                                            .symbolRenderingMode(.hierarchical)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(completionKindColor(item.kind, palette: palette))

                                        Text(item.label)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: palette.foreground))

                                        Text(item.detail)
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(hex: palette.gutterForeground))
                                            .lineLimit(1)

                                        if idx == 0 {
                                            Text("Tab")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(hex: palette.accent).opacity(0.22))
                                                .foregroundColor(Color(hex: palette.accent))
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: palette.editorBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(idx == 0 ? Color(hex: palette.accent).opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    .cornerRadius(7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        intelligence.clearCompletions()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: palette.headerBackground).opacity(0.97))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(hex: palette.currentLineBackground), lineWidth: 1)
        )
        .cornerRadius(9)
        .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 3)
    }

    // MARK: - Slim Sub-Toolbar (Breadcrumbs + Language Mode + Format + Quick Toggles + Diagnostics + Timeline)
    @ViewBuilder
    private func editorSubToolbar(activeTab: OpenTab, palette: IDEColorPalette) -> some View {
        HStack(spacing: 6) {
            // 1. Breadcrumb & Symbol Outline Trigger
            if preferences.showBreadcrumbs {
                Button {
                    showSymbolOutlineSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(workspace.relativePath(for: activeTab.fileURL))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .lineLimit(1)

                        if let activeSym = intelligence.activeBreadcrumbSymbol {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(Color(hex: palette.gutterForeground))
                            Text(activeSym)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: palette.accent))
                                .lineLimit(1)
                        } else if !intelligence.symbols.isEmpty {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color(hex: palette.gutterForeground))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            // 2. Markdown & Mermaid Live Preview Mode Picker
            if activeTab.language == .markdown {
                HStack(spacing: 2) {
                    ForEach(MarkdownDisplayMode.allCases) { mode in
                        Button {
                            markdownMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 9.5, weight: markdownMode == mode ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(markdownMode == mode ? Color(hex: palette.accent) : Color.clear)
                                .foregroundColor(markdownMode == mode ? .white : Color(hex: palette.gutterForeground))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(1)
                .background(Color(hex: palette.currentLineBackground))
                .cornerRadius(5)
            }

            // 3. VS Code Language Mode Selector Badge (64 Languages + Auto-Detect)
            Button {
                showLanguagePickerSheet = true
            } label: {
                HStack(spacing: 3) {
                    FileLanguageIconView(language: activeTab.language, size: 9.5)
                    Text(activeTab.language.shortBadgeName)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(hex: palette.currentLineBackground))
                .foregroundColor(Color(hex: palette.foreground))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // 4. 1-Tap Format Code Button
            Button {
                formatActiveFile()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Format")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(hex: palette.currentLineBackground))
                .foregroundColor(Color(hex: palette.foreground))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            // 5. Quick Smart Autocomplete Status Pill (1-Tap Toggle)
            Button {
                preferences.enableCodeCompletion.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(preferences.enableCodeCompletion ? "Gợi ý: ON" : "Gợi ý: OFF")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(preferences.enableCodeCompletion ? Color(hex: palette.accent).opacity(0.16) : Color(hex: palette.currentLineBackground))
                .foregroundColor(preferences.enableCodeCompletion ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                .cornerRadius(4)
            }

            // 6. Inline Error / Warning Status Pill (Tap opens Problems or jumps to error)
            Button {
                if !preferences.enableLiveDiagnostics {
                    preferences.enableLiveDiagnostics = true
                } else {
                    bottomTab = .problems
                    withAnimation { showBottomPanel = true }
                    if let firstDiag = intelligence.diagnostics.first {
                        triggerJumpToLine(firstDiag.line)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    if !preferences.enableLiveDiagnostics {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 9.5))
                        Text("Báo lỗi: OFF")
                            .font(.system(size: 9.5, weight: .semibold))
                    } else if intelligence.errorCount > 0 {
                        Image(systemName: "xmark.octagon")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("\(intelligence.errorCount) lỗi")
                            .font(.system(size: 9.5, weight: .bold))
                    } else if intelligence.warningCount > 0 {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("\(intelligence.warningCount) cảnh báo")
                            .font(.system(size: 9.5, weight: .bold))
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("0 lỗi")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(diagnosticPillBackground(palette: palette))
                .foregroundColor(diagnosticPillForeground(palette: palette))
                .cornerRadius(4)
            }

            // 7. Local File Version Timeline Button
            Button {
                showTimelineSheet = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: palette.gutterForeground))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(Color(hex: palette.sidebarBackground))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.06))
        }
    }

    private func diagnosticPillBackground(palette: IDEColorPalette) -> Color {
        if !preferences.enableLiveDiagnostics { return Color(hex: palette.currentLineBackground) }
        if intelligence.errorCount > 0 { return Color.red.opacity(0.18) }
        if intelligence.warningCount > 0 { return Color.orange.opacity(0.18) }
        return Color.green.opacity(0.14)
    }

    private func diagnosticPillForeground(palette: IDEColorPalette) -> Color {
        if !preferences.enableLiveDiagnostics { return Color(hex: palette.gutterForeground) }
        if intelligence.errorCount > 0 { return .red }
        if intelligence.warningCount > 0 { return .orange }
        return .green
    }

    // MARK: - Top Header Bar
    @ViewBuilder
    private func topHeaderBar(palette: IDEColorPalette) -> some View {
        HStack(spacing: 5) {
            // Activity Drawer Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showLeftExplorer.toggle()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                        .frame(width: 28, height: 30)
                    if sshService.isConnected {
                        Circle().fill(Color.green).frame(width: 6, height: 6).offset(x: -2, y: 4)
                    }
                }
            }

            // Compact Scrollable Tab Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.openTabs) { tab in
                        let isSelected = (workspace.activeTabID == tab.id)
                        let isRemoteSFTP = (sshService.remotePathBound(to: tab.fileURL) != nil)
                        HStack(spacing: 4) {
                            if isRemoteSFTP {
                                Image(systemName: "icloud")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.cyan)
                            } else {
                                FileLanguageIconView(language: tab.language, size: 10.5)
                            }
                            Text(tab.title)
                                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                .foregroundColor(Color(hex: isSelected ? palette.foreground : palette.gutterForeground))
                                .lineLimit(1)

                            if tab.isDirty {
                                Circle()
                                    .fill(Color(hex: palette.accent))
                                    .frame(width: 5.5, height: 5.5)
                            }

                            Button {
                                workspace.closeTab(tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                                    .padding(2)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color(hex: palette.editorBackground) : Color.clear)
                        .cornerRadius(6)
                        .onTapGesture {
                            workspace.activeTabID = tab.id
                        }
                    }
                }
            }

            // 1-Tap Smart Run Button
            Button {
                triggerSmartRun()
            } label: {
                HStack(spacing: 3) {
                    if runner.isRunning {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("Run")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.88))
                .foregroundColor(.black)
                .cornerRadius(6)
            }

            // Tools & Intelligence Menu
            Menu {
                Button {
                    showCommandPalette = true
                } label: {
                    Label("Command Palette & Quick Open", systemImage: "command")
                }

                Button {
                    saveActiveTabWithCheckpoint()
                } label: {
                    Label("Lưu File & Tạo Mốc Lịch Sử", systemImage: "externaldrive.badge.checkmark")
                }

                Button {
                    showSymbolOutlineSheet = true
                } label: {
                    Label("Danh sách Hàm / Class (Symbol Outline)", systemImage: "list.bullet.indent")
                }

                Button {
                    showTimelineSheet = true
                } label: {
                    Label("Lịch sử Phiên bản File (Timeline)", systemImage: "clock.arrow.circlepath")
                }

                Divider()

                Toggle(isOn: $preferences.enableCodeCompletion) {
                    Label("Gợi ý Code thông minh (Smart IntelliSense)", systemImage: "text.cursor")
                }

                Toggle(isOn: $preferences.enableLiveDiagnostics) {
                    Label("Báo lỗi trực tiếp trên Editor", systemImage: "exclamationmark.triangle")
                }

                Toggle(isOn: $preferences.formatOnSave) {
                    Label("Tự động Format khi Lưu / Chạy", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    showLanguagePickerSheet = true
                } label: {
                    Label("Chọn Ngôn ngữ (\(workspace.activeTab?.language.shortBadgeName ?? "Auto"))", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    formatActiveFile()
                } label: {
                    Label("Format Document theo Ngôn ngữ", systemImage: "text.alignleft")
                }

                Divider()

                Button {
                    if !liveServer.isRunning {
                        liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                    }
                    let rel = (workspace.activeTab?.language == .html) ? workspace.relativePath(for: workspace.activeTab!.fileURL) : "index.html"
                    liveServer.openInSafari(relativePath: rel)
                } label: {
                    Label("Mở localhost:\(liveServer.port) trên Safari", systemImage: "safari")
                }

                Button {
                    bottomTab = .livePreview
                    withAnimation { showBottomPanel = true }
                } label: {
                    Label("Xem Split Preview & Web F12", systemImage: "rectangle.split.1x2")
                }

                Button {
                    bottomTab = .terminal
                    withAnimation { showBottomPanel.toggle() }
                } label: {
                    Label(sshService.isConnected ? "Mở SSH PTY Terminal (SwiftTerm)" : "Mở Terminal (SwiftTerm)", systemImage: "terminal")
                }

                Button {
                    findTriggerToken += 1
                } label: {
                    Label("Tìm kiếm & Thay thế", systemImage: "magnifyingglass")
                }

                Divider()

                Button {
                    exportWorkspaceAsZipAndShare()
                } label: {
                    Label("Xuất Dự án ra File .zip", systemImage: "doc.zipper")
                }

                Button {
                    showThemeStudioDirect = true
                } label: {
                    Label("Theme Studio (Tự chỉnh màu Code & App)", systemImage: "slider.horizontal.below.square.filled.and.square")
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Theme, Font & Cài đặt", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: liveServer.isRunning ? "antenna.radiowaves.left.and.right" : "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(liveServer.isRunning ? .green : Color(hex: palette.foreground))
                    .frame(width: 28, height: 30)
            }

            // Coding Agent Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showRightAIPanel.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Agent")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(showRightAIPanel ? Color(hex: palette.accent) : Color(hex: palette.currentLineBackground))
                .foregroundColor(showRightAIPanel ? .white : Color(hex: palette.accent))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(Color(hex: palette.headerBackground))
    }

    // MARK: - Hidden Bluetooth / Magic Keyboard Shortcuts Responder
    @ViewBuilder
    private var hardwareKeyboardShortcutsHost: some View {
        ZStack {
            Button("") { saveActiveTabWithCheckpoint() }
                .keyboardShortcut("s", modifiers: .command)
            Button("") { triggerSmartRun() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { showCommandPalette = true }
                .keyboardShortcut("p", modifiers: .command)
            Button("") { toggleCommentToken += 1 }
                .keyboardShortcut("/", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showLeftExplorer.toggle()
                }
            }
            .keyboardShortcut("b", modifiers: .command)
            Button("") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showRightAIPanel.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBottomPanel.toggle()
                }
            }
            .keyboardShortcut("j", modifiers: .command)
            Button("") { formatActiveFile() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func emptyEditorPlaceholder(palette: IDEColorPalette) -> some View {
        VStack(spacing: 14) {
            IDECodeMarkVector(
                size: 54,
                secondaryColor: Color(hex: palette.foreground)
            )
            Text("3012")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: palette.foreground))
            Text("Vuốt mép trái: Explorer • Git • SSH SFTP • OpenVSX\nVuốt mép phải: Coding Agent")
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: palette.gutterForeground))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button {
                    showLeftExplorer = true
                } label: {
                    Label("Mở Sidebar", systemImage: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(8)
                }

                Button {
                    showCommandPalette = true
                } label: {
                    Label("Command Palette", systemImage: "command")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: palette.accent))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions & Intelligence Wiring
    private func applyCompletionCandidate(_ item: CompletionCandidate) {
        intelligence.recordAcceptedCompletion(item.label)
        let nextToken = (completionRequest?.token ?? 0) + 1
        completionRequest = CompletionReplacementRequest(
            token: nextToken,
            range: item.replaceRange,
            replacement: item.insertText,
            cursorOffset: item.cursorOffsetInInsert
        )
        intelligence.clearCompletions()
    }

    private func triggerJumpToLine(_ line: Int) {
        let nextToken = (jumpRequest?.token ?? 0) + 1
        jumpRequest = JumpToLineRequest(token: nextToken, line: line)
    }

    private func refreshIntelligenceForActiveTab() {
        guard let active = workspace.activeTab else {
            intelligence.diagnostics = []
            intelligence.symbols = []
            intelligence.activeBreadcrumbSymbol = nil
            return
        }
        intelligence.scheduleAnalysis(
            code: active.content,
            language: active.language,
            fileName: active.title,
            cursorLocation: active.selectedRangeLocation,
            diagnosticsEnabled: preferences.enableLiveDiagnostics,
            sshService: sshService
        )
    }

    private func applyFormatOnSaveIfEnabled() {
        guard preferences.formatOnSave, let active = workspace.activeTab else { return }
        let formatted = CodeFormatterService.formatOfflineSynchronously(
            active.content,
            language: active.language,
            tabWidth: preferences.tabWidth
        )
        if formatted != active.content {
            workspace.updateActiveContent(formatted, autoSave: true)
        }
        if sshService.isConnected {
            let tabURL = active.fileURL
            let lang = active.language
            let width = preferences.tabWidth
            Task {
                let remoteFormatted = await CodeFormatterService.format(
                    formatted,
                    language: lang,
                    tabWidth: width,
                    sshService: sshService
                )
                if workspace.activeTab?.fileURL == tabURL && remoteFormatted != workspace.activeTab?.content {
                    workspace.updateActiveContent(remoteFormatted, autoSave: true)
                }
            }
        }
    }

    private func saveActiveTabWithCheckpoint() {
        applyFormatOnSaveIfEnabled()
        workspace.saveActiveTab()
        if let active = workspace.activeTab {
            timelineService.recordSnapshot(for: active.fileURL, content: active.content, label: "Saved")
        }
        refreshIntelligenceForActiveTab()
    }

    private func exportWorkspaceAsZipAndShare() {
        workspace.saveAllTabs()
        if let zipURL = timelineService.exportProjectZip(workspaceRoot: workspace.rootURL) {
            shareZipItem = ShareableZipFile(url: zipURL)
        }
    }

    private func fixDiagnosticWithAgent(_ diag: EditorDiagnostic) {
        guard let active = workspace.activeTab else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showRightAIPanel = true
        }
        let relPath = workspace.relativePath(for: active.fileURL)
        let prompt = "Hãy sửa lỗi sau tại dòng \(diag.line) trong file \(relPath): \"\(diag.message)\". Đề xuất bản sửa hoàn chỉnh bằng <file_edit>."
        Task {
            await aiService.sendPrompt(
                userPrompt: prompt,
                workspaceTree: workspace.workspaceSummaryTree(),
                activeFilePath: relPath,
                activeFileContent: active.content,
                selectedSnippet: workspace.selectedSnippetInActiveTab(),
                lastConsoleOutput: runner.consoleOutput,
                existingFileReader: { rel in
                    let url = workspace.rootURL.appendingPathComponent(rel)
                    return try? String(contentsOf: url, encoding: .utf8)
                }
            )
        }
    }

    private func triggerSmartRun() {
        applyFormatOnSaveIfEnabled()
        workspace.saveActiveTab()
        guard let active = workspace.activeTab else { return }

        if active.language == .markdown {
            markdownMode = (markdownMode == .preview) ? .editor : .preview
            return
        }

        if active.language == .html || active.language == .css || active.language == .scss {
            if !liveServer.isRunning {
                liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
            } else {
                liveServer.notifyFileChanged()
            }
            bottomTab = .livePreview
            withAnimation { showBottomPanel = true }
        } else {
            bottomTab = .output
            withAnimation { showBottomPanel = true }
            Task {
                await runner.runCode(code: active.content, language: active.language, fileName: active.title, sshService: sshService)
            }
        }
    }

    private func formatActiveFile() {
        guard let active = workspace.activeTab else { return }
        Task {
            let formatted = await CodeFormatterService.format(
                active.content,
                language: active.language,
                tabWidth: preferences.tabWidth,
                sshService: sshService
            )
            if formatted != active.content {
                workspace.updateActiveContent(formatted, autoSave: preferences.enableAutoSave)
                refreshIntelligenceForActiveTab()
            }
        }
    }

    private func checkSyntaxAndLSPDiagnostics() {
        guard let active = workspace.activeTab else { return }
        bottomTab = .problems
        withAnimation { showBottomPanel = true }
        intelligence.scheduleAnalysis(
            code: active.content,
            language: active.language,
            fileName: active.title,
            cursorLocation: active.selectedRangeLocation,
            diagnosticsEnabled: true,
            sshService: sshService
        )
    }

    private func insertTextIntoActiveTab(_ snippet: String) {
        guard let active = workspace.activeTab else { return }
        let ns = active.content as NSString
        let loc = min(max(0, active.selectedRangeLocation), ns.length)
        let len = min(max(0, active.selectedRangeLength), ns.length - loc)
        let updated = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: snippet)
        workspace.updateActiveContent(
            updated,
            selectedRange: NSRange(location: loc + (snippet as NSString).length, length: 0),
            autoSave: preferences.enableAutoSave
        )
        refreshIntelligenceForActiveTab()
    }

    private func buildPaletteCommands() -> [(title: String, icon: String, action: () -> Void)] {
        [
            ("Run Active File (Cmd+R)", "play.fill", { triggerSmartRun() }),
            ("Save File & Record Snapshot (Cmd+S)", "externaldrive.badge.checkmark", { saveActiveTabWithCheckpoint() }),
            ("Go to Symbol Outline in File", "list.bullet.indent", { showSymbolOutlineSheet = true }),
            ("Open File Version Timeline (Restore Snapshot)", "clock.arrow.circlepath", { showTimelineSheet = true }),
            ("Toggle Line Comment (Cmd+/)", "number", { toggleCommentToken += 1 }),
            ("Toggle Live Code Autocomplete (\(preferences.enableCodeCompletion ? "ON" : "OFF"))", "text.cursor", {
                preferences.enableCodeCompletion.toggle()
            }),
            ("Toggle Inline Error Highlighting (\(preferences.enableLiveDiagnostics ? "ON" : "OFF"))", "exclamationmark.triangle", {
                preferences.enableLiveDiagnostics.toggle()
            }),
            ("Open Theme Studio (Customize Code & App Colors)", "slider.horizontal.below.square.filled.and.square", {
                showThemeStudioDirect = true
            }),
            ("Select Language Mode (64 Languages / Auto-Detect)", "chevron.left.forwardslash.chevron.right", {
                showLanguagePickerSheet = true
            }),
            ("Format Document by Language (Cmd+Shift+F)", "text.alignleft", { formatActiveFile() }),
            ("Toggle Auto-Format on Save & Run (\(preferences.formatOnSave ? "ON" : "OFF"))", "arrow.triangle.2.circlepath", {
                preferences.formatOnSave.toggle()
            }),
            ("Show Problems & Inline Diagnostics", "checklist", { checkSyntaxAndLSPDiagnostics() }),
            ("Export Project Workspace as .zip", "doc.zipper", { exportWorkspaceAsZipAndShare() }),
            ("Open Live Server localhost:\(liveServer.port) in Safari", "safari", {
                if !liveServer.isRunning {
                    liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                }
                liveServer.openInSafari()
            }),
            ("Toggle Xterm / SSH PTY Terminal (Cmd+J)", "terminal", {
                bottomTab = .terminal
                withAnimation { showBottomPanel.toggle() }
            }),
            ("Toggle Coding Agent Panel (Cmd+I)", "cpu", {
                withAnimation { showRightAIPanel.toggle() }
            }),
            ("Open Themes, Fonts & IDE Settings", "slider.horizontal.3", {
                showSettingsSheet = true
            })
        ]
    }
}

private struct ShareableZipFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ZipActivityShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
