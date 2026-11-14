import SwiftUI
import UIKit
import Runestone

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
    @StateObject private var timelineService = FileTimelineAndArchiveService.shared
    @StateObject private var theosService = TheosBuildService()
    @StateObject private var daemonService = LocalDaemonService()

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
                timelineService: timelineService,
                theosService: theosService,
                daemonService: daemonService
            )
            .preferredColorScheme(preferences.activePalette.isDark ? .dark : .light)
            .environment(\.locale, Locale(identifier: preferences.appLanguage.localeIdentifier))
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
    @ObservedObject var theosService: TheosBuildService
    @ObservedObject var daemonService: LocalDaemonService

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
    @State private var showTheosBuilderSheet: Bool = false
    @State private var showDaemonManagerSheet: Bool = false
    @State private var shareZipItem: ShareableZipFile? = nil
    @State private var rootDocumentPickerMode: WorkspaceDocumentPickerMode? = nil

    @State private var markdownMode: MarkdownDisplayMode = .editor
    @State private var findTriggerToken: Int = 0
    @State private var toggleCommentToken: Int = 0
    @State private var completionRequest: CompletionReplacementRequest? = nil
    @State private var jumpRequest: JumpToLineRequest? = nil
    @State private var selectRangeRequest: SelectRangeRequest? = nil
    @State private var quickActionRequest: EditorQuickActionRequest? = nil
    @State private var showQuickNewFileAlert: Bool = false
    @State private var quickNewFileName: String = ""
    @State private var showInlineFindBar: Bool = false
    @State private var showReplaceRow: Bool = false
    @State private var findQuery: String = ""
    @State private var replaceQuery: String = ""
    @State private var findCaseSensitive: Bool = false
    @State private var findMatchRanges: [NSRange] = []
    @State private var currentFindMatchIndex: Int = 0
    @State private var showGoToLineAlert: Bool = false
    @State private var goToLineInput: String = ""

    // Resizable Split View States (Editor/Markdown Split, Bottom Panel Height, Right AI Agent Width)
    @State private var editorSplitRatio: CGFloat = 0.50
    @State private var dragStartEditorSplitRatio: CGFloat? = nil
    @State private var customBottomPanelHeight: CGFloat? = nil
    @State private var dragStartBottomHeight: CGFloat? = nil
    @State private var rightAIPanelRatio: CGFloat = 0.38
    @State private var dragStartRightAIWidth: CGFloat? = nil

    public var body: some View {
        let palette = preferences.activePalette

        GeometryReader { geo in
            let isWideLayout = geo.size.width >= 680

            ZStack(alignment: .leading) {
                // Hidden Hardware Bluetooth / Magic Keyboard Shortcuts Responder
                hardwareKeyboardShortcutsHost

                VStack(spacing: 0) {
                    // 1. Ultra-Slim 38pt Top Header Bar (Workspace + Quick Undo/Redo/Copy/Paste + Run + Agent)
                    topHeaderBar(palette: palette)

                    // 2. Dedicated VS Code File Tab Bar Row (Newest on Left -> Older pushed Right)
                    if !workspace.openTabs.isEmpty {
                        openFilesTabStrip(palette: palette)
                    }

                    // 3. Slim 27pt Breadcrumb, Diagnostics, Quick Toggles & Markdown/Timeline Strip
                    if let activeTab = workspace.activeTab {
                        editorSubToolbar(activeTab: activeTab, palette: palette)
                        if showInlineFindBar {
                            inlineFindReplaceBar(activeTab: activeTab, palette: palette)
                        }
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
                                let maxBottomH = max(160, geo.size.height * 0.80)
                                let activeBottomH = min(
                                    max(customBottomPanelHeight ?? bottomDetent.height(in: geo.size.height), 120),
                                    maxBottomH
                                )
                                resizableSplitBar(
                                    isHorizontal: true,
                                    palette: palette,
                                    onDragChanged: { value in
                                        if dragStartBottomHeight == nil {
                                            dragStartBottomHeight = activeBottomH
                                        }
                                        let base = dragStartBottomHeight ?? activeBottomH
                                        customBottomPanelHeight = min(max(base - value.translation.height, 120), maxBottomH)
                                    },
                                    onDragEnded: {
                                        dragStartBottomHeight = nil
                                    },
                                    onDoubleTapReset: {
                                        customBottomPanelHeight = nil
                                    }
                                )
                                BottomConsolePreviewPanel(
                                    selectedTab: $bottomTab,
                                    detent: $bottomDetent,
                                    runner: runner,
                                    liveServer: liveServer,
                                    sshService: sshService,
                                    daemonService: daemonService,
                                    workspace: workspace,
                                    preferences: preferences,
                                    intelligence: intelligence,
                                    aiService: aiService,
                                    gitService: gitService,
                                    onJumpToLine: { line in
                                        triggerJumpToLine(line)
                                    },
                                    onFixDiagnosticWithAgent: { diag in
                                        fixDiagnosticWithAgent(diag)
                                    },
                                    onOpenDaemonManager: {
                                        showDaemonManagerSheet = true
                                    },
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showBottomPanel = false
                                        }
                                    }
                                )
                                .frame(height: activeBottomH)
                                .onChange(of: bottomDetent) { _, _ in
                                    customBottomPanelHeight = nil
                                }
                            }
                        }

                        // Side-by-side Coding Agent Panel when screen is wide (Landscape iPhone / iPad)
                        if showRightAIPanel && isWideLayout {
                            let maxAIW = max(280, geo.size.width * 0.65)
                            let activeAIW = min(max(geo.size.width * rightAIPanelRatio, 240), maxAIW)
                            resizableSplitBar(
                                isHorizontal: false,
                                palette: palette,
                                onDragChanged: { value in
                                    if dragStartRightAIWidth == nil {
                                        dragStartRightAIWidth = activeAIW
                                    }
                                    let baseW = dragStartRightAIWidth ?? activeAIW
                                    let clampedW = min(max(baseW - value.translation.width, 240), maxAIW)
                                    rightAIPanelRatio = clampedW / max(geo.size.width, 1)
                                },
                                onDragEnded: {
                                    dragStartRightAIWidth = nil
                                },
                                onDoubleTapReset: {
                                    rightAIPanelRatio = 0.38
                                }
                            )
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
                            .frame(width: activeAIW)
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
                        onOpenTheosBuilder: {
                            showLeftExplorer = false
                            showTheosBuilderSheet = true
                        },
                        onRequestOpenSingleFile: {
                            rootDocumentPickerMode = .singleFile
                        },
                        onRequestOpenFolder: {
                            rootDocumentPickerMode = .folder
                        },
                        onRequestImportZip: {
                            rootDocumentPickerMode = .zip
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
            if showInlineFindBar {
                recomputeFindMatches(jumpToFirst: false)
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
                runner: runner,
                daemonService: daemonService,
                onOpenDaemonManager: {
                    showDaemonManagerSheet = true
                }
            )
        }
        .sheet(isPresented: $showDaemonManagerSheet) {
            LocalDaemonManagerSheet(
                daemonService: daemonService,
                workspace: workspace,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showThemeStudioDirect) {
            ThemeStudioEditorSheet(preferences: preferences)
        }
        .sheet(isPresented: $showTheosBuilderSheet) {
            TheosBuilderSheet(
                theosService: theosService,
                workspace: workspace,
                sshService: sshService,
                runner: runner,
                preferences: preferences
            )
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
        .onOpenURL { url in
            workspace.handleIncomingURL(url)
            liveServer.updateRootDirectory(workspace.rootURL)
        }
        .onChange(of: workspace.rootURL) { _, newRoot in
            liveServer.updateRootDirectory(newRoot)
        }
        .sheet(item: $rootDocumentPickerMode) { mode in
            SystemDocumentPickerSheet(
                mode: mode,
                onPickURL: { pickedURL in
                    switch mode {
                    case .singleFile:
                        workspace.openExternalSingleFile(from: pickedURL)
                        liveServer.updateRootDirectory(workspace.rootURL)
                    case .folder:
                        workspace.switchWorkspaceFolder(to: pickedURL)
                        liveServer.updateRootDirectory(workspace.rootURL)
                    case .zip:
                        if workspace.importAndOpenZip(from: pickedURL) {
                            liveServer.updateRootDirectory(workspace.rootURL)
                        }
                    case .themeJSON:
                        break
                    }
                },
                onPickURLs: mode == .singleFile ? { pickedURLs in
                    for url in pickedURLs {
                        workspace.openExternalSingleFile(from: url)
                    }
                    liveServer.updateRootDirectory(workspace.rootURL)
                } : nil
            )
        }
        .sheet(item: $shareZipItem) { item in
            ZipActivityShareSheet(fileURL: item.url)
        }
        .alert(preferences.tr("Tạo File Mới", "New File"), isPresented: $showQuickNewFileAlert) {
            TextField(preferences.tr("Tên file (vd: script.py)", "File name (e.g. script.py)"), text: $quickNewFileName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button(preferences.tr("Tạo", "Create")) {
                let name = quickNewFileName
                quickNewFileName = ""
                if let created = workspace.createFile(named: name) {
                    workspace.openFile(at: created)
                }
            }
            Button(preferences.tr("Hủy", "Cancel"), role: .cancel) {
                quickNewFileName = ""
            }
        }
        .alert(preferences.tr("Đi tới dòng (Go to Line)", "Go to Line"), isPresented: $showGoToLineAlert) {
            TextField(preferences.tr("Số dòng (vd: 42)", "Line number (e.g. 42)"), text: $goToLineInput)
                .keyboardType(.numberPad)
            Button(preferences.tr("Đi tới", "Go")) {
                if let lineNum = Int(goToLineInput.trimmingCharacters(in: .whitespacesAndNewlines)), lineNum > 0 {
                    triggerJumpToLine(lineNum)
                }
                goToLineInput = ""
            }
            Button(preferences.tr("Hủy", "Cancel"), role: .cancel) {
                goToLineInput = ""
            }
        } message: {
            if let tab = workspace.activeTab {
                let totalLines = max(1, tab.content.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
                Text(preferences.tr("File hiện có \(totalLines) dòng.", "File has \(totalLines) lines."))
            }
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
            GeometryReader { splitGeo in
                if isWide {
                    let availW = max(160, splitGeo.size.width - 14)
                    let leftW = min(max(availW * editorSplitRatio, 100), max(100, availW - 100))
                    let rightW = max(100, availW - leftW)
                    HStack(spacing: 0) {
                        editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
                            .frame(width: leftW)
                        resizableSplitBar(
                            isHorizontal: false,
                            palette: palette,
                            onDragChanged: { value in
                                if dragStartEditorSplitRatio == nil {
                                    dragStartEditorSplitRatio = editorSplitRatio
                                }
                                let baseRatio = dragStartEditorSplitRatio ?? editorSplitRatio
                                let delta = value.translation.width / max(availW, 1)
                                editorSplitRatio = min(max(baseRatio + delta, 0.22), 0.78)
                            },
                            onDragEnded: {
                                dragStartEditorSplitRatio = nil
                            },
                            onDoubleTapReset: {
                                editorSplitRatio = 0.50
                            }
                        )
                        MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette)
                            .frame(width: rightW)
                    }
                } else {
                    let availH = max(160, splitGeo.size.height - 14)
                    let topH = min(max(availH * editorSplitRatio, 90), max(90, availH - 90))
                    let bottomH = max(90, availH - topH)
                    VStack(spacing: 0) {
                        editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
                            .frame(height: topH)
                        resizableSplitBar(
                            isHorizontal: true,
                            palette: palette,
                            onDragChanged: { value in
                                if dragStartEditorSplitRatio == nil {
                                    dragStartEditorSplitRatio = editorSplitRatio
                                }
                                let baseRatio = dragStartEditorSplitRatio ?? editorSplitRatio
                                let delta = value.translation.height / max(availH, 1)
                                editorSplitRatio = min(max(baseRatio + delta, 0.22), 0.78)
                            },
                            onDragEnded: {
                                dragStartEditorSplitRatio = nil
                            },
                            onDoubleTapReset: {
                                editorSplitRatio = 0.50
                            }
                        )
                        MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette)
                            .frame(height: bottomH)
                    }
                }
            }
        } else {
            editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
        }
    }

    @ViewBuilder
    private func resizableSplitBar(
        isHorizontal: Bool,
        palette: IDEColorPalette,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping () -> Void,
        onDoubleTapReset: @escaping () -> Void
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: palette.headerBackground).opacity(0.90))
            Capsule()
                .fill(Color(hex: palette.accent).opacity(0.65))
                .frame(
                    width: isHorizontal ? 38 : 3.5,
                    height: isHorizontal ? 3.5 : 38
                )
        }
        .frame(height: isHorizontal ? 14 : nil)
        .frame(width: isHorizontal ? nil : 14)
        .frame(maxWidth: isHorizontal ? .infinity : nil, maxHeight: isHorizontal ? nil : .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    onDragChanged(value)
                }
                .onEnded { _ in
                    onDragEnded()
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                onDoubleTapReset()
            }
        }
        .overlay(Divider().overlay(Color.white.opacity(0.12)))
    }

    @ViewBuilder
    private func editorWithAutocompleteOverlay(activeTab: OpenTab, palette: IDEColorPalette) -> some View {
        ZStack(alignment: .bottomLeading) {
            RunestoneEditorView(
                fileURL: activeTab.fileURL,
                text: activeTab.content,
                language: activeTab.language,
                preferences: preferences,
                highlightedRanges: mergedHighlightedRanges(for: activeTab),
                ghostSuggestion: preferences.enableCodeCompletion ? intelligence.completions.first : nil,
                completionRequest: completionRequest,
                jumpRequest: jumpRequest,
                selectRangeRequest: selectRangeRequest,
                quickActionRequest: quickActionRequest,
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
                    if showInlineFindBar {
                        recomputeFindMatches(in: updatedCode, jumpToFirst: false)
                    }
                },
                onSelectionChange: { range in
                    workspace.updateSelectionOnly(range)
                    intelligence.updateActiveBreadcrumb(cursorLocation: range.location, in: activeTab.content)
                    if range.length > 0 {
                        intelligence.clearCompletions()
                    } else if let top = intelligence.completions.first,
                              range.location < top.replaceRange.location || range.location > top.replaceRange.upperBound {
                        intelligence.clearCompletions()
                    }
                },
                onToggleAI: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        showRightAIPanel.toggle()
                    }
                },
                onTriggerGoToLine: {
                    let cursor = cursorLineAndColumn(in: activeTab.content, location: activeTab.selectedRangeLocation)
                    goToLineInput = "\(cursor.line)"
                    showGoToLineAlert = true
                },
                onTriggerFindBar: {
                    openInlineFindBar()
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

    // MARK: - Slim Sub-Toolbar (Breadcrumbs + Language Mode + Format + Quick Tools + Diagnostics + Timeline)
    @ViewBuilder
    private func editorSubToolbar(activeTab: OpenTab, palette: IDEColorPalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                                .fixedSize(horizontal: true, vertical: false)

                            if let activeSym = intelligence.activeBreadcrumbSymbol {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                                Text(activeSym)
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(hex: palette.accent))
                                    .fixedSize(horizontal: true, vertical: false)
                            } else if !intelligence.symbols.isEmpty {
                                Image(systemName: "list.bullet.indent")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // 1.5 Live Cursor Position (Ln, Col) + 1-Tap Go to Line
                let cursorPos = cursorLineAndColumn(in: activeTab.content, location: activeTab.selectedRangeLocation)
                Button {
                    goToLineInput = "\(cursorPos.line)"
                    showGoToLineAlert = true
                } label: {
                    Text("Ln \(cursorPos.line), Col \(cursorPos.column)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

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
                        FileLanguageIconView(language: activeTab.language, fileName: activeTab.title, size: 9.5)
                        Text(activeTab.language.shortBadgeName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
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
                        Text(preferences.tr("Format", "Format"))
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // 4.1 1-Tap Toggle Comment & Inline Find/Replace Pills
                Button {
                    toggleCommentToken += 1
                } label: {
                    Text("//")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    if showInlineFindBar {
                        showInlineFindBar = false
                        findMatchRanges = []
                    } else {
                        openInlineFindBar()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(preferences.tr("Tìm", "Find"))
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(showInlineFindBar ? Color(hex: palette.accent).opacity(0.22) : Color(hex: palette.currentLineBackground))
                    .foregroundColor(showInlineFindBar ? Color(hex: palette.accent) : Color(hex: palette.foreground))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                // 4.2 Quick Line / Clipboard Menu (Cut, Select All, Duplicate/Delete Line)
                Menu {
                    Button { triggerQuickAction(.undo) } label: {
                        Label(preferences.tr("Hoàn tác (Ctrl+Z)", "Undo (Ctrl+Z)"), systemImage: "arrow.uturn.backward")
                    }
                    Button { triggerQuickAction(.redo) } label: {
                        Label(preferences.tr("Làm lại (Ctrl+Y)", "Redo (Ctrl+Y)"), systemImage: "arrow.uturn.forward")
                    }
                    Divider()
                    Button { triggerQuickAction(.copy) } label: {
                        Label(preferences.tr("Sao chép / Dòng hiện tại (Ctrl+C)", "Copy / Current Line (Ctrl+C)"), systemImage: "doc.on.doc")
                    }
                    Button { triggerQuickAction(.paste) } label: {
                        Label(preferences.tr("Dán (Ctrl+V)", "Paste (Ctrl+V)"), systemImage: "doc.on.clipboard")
                    }
                    Button { triggerQuickAction(.cut) } label: {
                        Label(preferences.tr("Cắt / Dòng hiện tại (Ctrl+X)", "Cut / Current Line (Ctrl+X)"), systemImage: "scissors")
                    }
                    Button { triggerQuickAction(.selectAll) } label: {
                        Label(preferences.tr("Chọn tất cả (Ctrl+A)", "Select All (Ctrl+A)"), systemImage: "selection.pin.in.out")
                    }
                    Divider()
                    Button { toggleCommentToken += 1 } label: {
                        Label(preferences.tr("Chú thích dòng (Cmd+/)", "Toggle Comment (Cmd+/)"), systemImage: "number")
                    }
                    Button { triggerQuickAction(.moveLineUp) } label: {
                        Label(preferences.tr("Đẩy dòng lên (Alt+↑)", "Move Line Up (Alt+↑)"), systemImage: "arrow.up.to.line")
                    }
                    Button { triggerQuickAction(.moveLineDown) } label: {
                        Label(preferences.tr("Đẩy dòng xuống (Alt+↓)", "Move Line Down (Alt+↓)"), systemImage: "arrow.down.to.line")
                    }
                    Button { triggerQuickAction(.duplicateLine) } label: {
                        Label(preferences.tr("Nhân đôi dòng", "Duplicate Line"), systemImage: "plus.square.on.square")
                    }
                    Button { triggerQuickAction(.deleteLine) } label: {
                        Label(preferences.tr("Xóa dòng hiện tại", "Delete Line"), systemImage: "delete.left")
                    }
                    Divider()
                    Button { openInlineFindBar() } label: {
                        Label(preferences.tr("Tìm & Thay thế (Cmd+F)", "Find & Replace (Cmd+F)"), systemImage: "magnifyingglass")
                    }
                    Button {
                        goToLineInput = "\(cursorPos.line)"
                        showGoToLineAlert = true
                    } label: {
                        Label(preferences.tr("Đi tới dòng... (Ctrl+G)", "Go to Line... (Ctrl+G)"), systemImage: "arrow.right.to.line")
                    }
                    Button { workspace.reopenLastClosedTab() } label: {
                        Label(preferences.tr("Mở lại Tab vừa đóng (Cmd+Shift+T)", "Reopen Closed Tab (Cmd+Shift+T)"), systemImage: "arrow.uturn.left.circle")
                    }
                    .disabled(!workspace.canReopenClosedTab)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "scissors")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(preferences.tr("Sửa", "Edit"))
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(4)
                }

                // 4.5 Theos Build Pill (when inside a Theos project or Logos/control file)
                if isTheosBuildContext(activeTab: activeTab) {
                    Button {
                        showTheosBuilderSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            if theosService.isBuilding {
                                ProgressView().scaleEffect(0.55)
                            } else {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            Text("Theos .deb")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: palette.accent).opacity(0.18))
                        .foregroundColor(Color(hex: palette.accent))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                // 5. Quick Smart Autocomplete Status Pill (1-Tap Toggle)
                Button {
                    preferences.enableCodeCompletion.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(preferences.enableCodeCompletion
                             ? preferences.tr("Gợi ý: ON", "Hint: ON", zh: "提示: 开", ja: "補完: ON", ko: "자동완성: ON", ru: "Подсказки: ВКЛ", es: "Sugerir: ON")
                             : preferences.tr("Gợi ý: OFF", "Hint: OFF", zh: "提示: 关", ja: "補完: OFF", ko: "자동완성: OFF", ru: "Подсказки: ВЫКЛ", es: "Sugerir: OFF"))
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
                            Text(preferences.tr("Báo lỗi: OFF", "Lint: OFF", zh: "诊断: 关", ja: "診断: OFF", ko: "진단: OFF", ru: "Ошибки: ВЫКЛ", es: "Errores: OFF"))
                                .font(.system(size: 9.5, weight: .semibold))
                        } else if intelligence.errorCount > 0 {
                            Image(systemName: "xmark.octagon")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("\(intelligence.errorCount) \(preferences.tr("lỗi", "err", zh: "错", ja: "エラー", ko: "오류", ru: "ош.", es: "err"))")
                                .font(.system(size: 9.5, weight: .bold))
                        } else if intelligence.warningCount > 0 {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("\(intelligence.warningCount) \(preferences.tr("cảnh báo", "warn", zh: "警", ja: "警告", ko: "경고", ru: "пред.", es: "aviso"))")
                                .font(.system(size: 9.5, weight: .bold))
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("0 \(preferences.tr("lỗi", "err", zh: "错", ja: "エラー", ko: "오류", ru: "ош.", es: "err"))")
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
        }
        .frame(height: 27)
        .background(Color(hex: palette.sidebarBackground))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.06))
        }
    }

    // MARK: - VS Code Inline Find & Replace Bar (Undo-Safe)
    @ViewBuilder
    private func inlineFindReplaceBar(activeTab: OpenTab, palette: IDEColorPalette) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        showReplaceRow.toggle()
                    }
                } label: {
                    Image(systemName: showReplaceRow ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .frame(width: 22, height: 26)
                        .background(Color(hex: palette.currentLineBackground))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    TextField(preferences.tr("Tìm trong file...", "Find in file..."), text: $findQuery)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: palette.foreground))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { stepFindMatch(forward: true) }
                        .onChange(of: findQuery) { _, _ in
                            recomputeFindMatches(jumpToFirst: true)
                        }

                    if !findQuery.isEmpty {
                        Button {
                            findQuery = ""
                            findMatchRanges = []
                            currentFindMatchIndex = 0
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: palette.gutterForeground))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: palette.editorBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                )
                .cornerRadius(5)

                Text(findMatchRanges.isEmpty ? (findQuery.isEmpty ? "0/0" : "0/0") : "\(currentFindMatchIndex + 1)/\(findMatchRanges.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(findMatchRanges.isEmpty && !findQuery.isEmpty ? .red : Color(hex: palette.gutterForeground))
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    findCaseSensitive.toggle()
                    recomputeFindMatches(jumpToFirst: true)
                } label: {
                    Text("Aa")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .frame(width: 25, height: 26)
                        .background(findCaseSensitive ? Color(hex: palette.accent).opacity(0.28) : Color(hex: palette.currentLineBackground))
                        .foregroundColor(findCaseSensitive ? Color(hex: palette.accent) : Color(hex: palette.foreground))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button { stepFindMatch(forward: false) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(width: 24, height: 26)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(findMatchRanges.isEmpty)

                Button { stepFindMatch(forward: true) } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(width: 24, height: 26)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(findMatchRanges.isEmpty)

                Button {
                    showInlineFindBar = false
                    findMatchRanges = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(width: 24, height: 26)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }

            if showReplaceRow {
                HStack(spacing: 5) {
                    Spacer().frame(width: 22)

                    TextField(preferences.tr("Thay bằng...", "Replace with..."), text: $replaceQuery)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: palette.foreground))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(hex: palette.editorBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                        )
                        .cornerRadius(5)

                    Button {
                        replaceCurrentFindMatch()
                    } label: {
                        Text(preferences.tr("Thay", "Replace"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.foreground))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(findMatchRanges.isEmpty)

                    Button {
                        replaceAllFindMatches()
                    } label: {
                        Text(preferences.tr("Tất cả", "All"))
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Color(hex: palette.accent).opacity(0.22))
                            .foregroundColor(Color(hex: palette.accent))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(findMatchRanges.isEmpty)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: palette.sidebarBackground))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.08))
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

    // MARK: - Top Header Bar (Workspace + Quick Undo/Redo/Copy/Paste + Run + Agent)
    @ViewBuilder
    private func topHeaderBar(palette: IDEColorPalette) -> some View {
        HStack(spacing: 5) {
            // Brand Emblem + Activity Drawer Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showLeftExplorer.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    IDECodeMarkVector(size: 22)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(Color(hex: palette.foreground))
                            .frame(width: 22, height: 30)
                        if sshService.isConnected {
                            Circle().fill(Color.green).frame(width: 6, height: 6).offset(x: 1, y: 4)
                        }
                    }
                }
            }

            // Current Workspace Badge (Tap for Command Palette & Quick Open)
            Button {
                showCommandPalette = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: palette.accent))
                    Text(workspace.rootURL.lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: palette.currentLineBackground))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)

            Spacer(minLength: 2)

            // Quick Top Edit Strip: Undo (Ctrl+Z) / Redo / Copy / Paste (always accessible)
            if workspace.activeTab != nil {
                HStack(spacing: 1) {
                    quickHeaderEditButton(icon: "arrow.uturn.backward", palette: palette) {
                        triggerQuickAction(.undo)
                    }
                    quickHeaderEditButton(icon: "arrow.uturn.forward", palette: palette) {
                        triggerQuickAction(.redo)
                    }
                    quickHeaderEditButton(icon: "doc.on.doc", palette: palette) {
                        triggerQuickAction(.copy)
                    }
                    quickHeaderEditButton(icon: "doc.on.clipboard", palette: palette) {
                        triggerQuickAction(.paste)
                    }
                }
                .padding(2)
                .background(Color(hex: palette.currentLineBackground))
                .cornerRadius(6)
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
                    Label(preferences.tr("Command Palette & Mở nhanh", "Command Palette & Quick Open"), systemImage: "command")
                }

                Button {
                    saveActiveTabWithCheckpoint()
                } label: {
                    Label(preferences.tr("Lưu File & Tạo Mốc Lịch Sử", "Save File & Record Snapshot"), systemImage: "externaldrive.badge.checkmark")
                }

                Button {
                    showSymbolOutlineSheet = true
                } label: {
                    Label(preferences.tr("Danh sách Hàm / Class (Symbol Outline)", "Symbol Outline (Functions / Classes)"), systemImage: "list.bullet.indent")
                }

                Button {
                    showTimelineSheet = true
                } label: {
                    Label(preferences.tr("Lịch sử Phiên bản File (Timeline)", "File Version Timeline"), systemImage: "clock.arrow.circlepath")
                }

                Divider()

                Toggle(isOn: $preferences.enableCodeCompletion) {
                    Label(preferences.tr("Gợi ý Code thông minh (Smart IntelliSense)", "Smart Code IntelliSense"), systemImage: "text.cursor")
                }

                Toggle(isOn: $preferences.enableLiveDiagnostics) {
                    Label(preferences.tr("Báo lỗi trực tiếp trên Editor", "Inline Error Diagnostics"), systemImage: "exclamationmark.triangle")
                }

                Toggle(isOn: $preferences.formatOnSave) {
                    Label(preferences.tr("Tự động Format khi Lưu / Chạy", "Auto-Format on Save / Run"), systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    showLanguagePickerSheet = true
                } label: {
                    Label(preferences.tr("Chọn Ngôn ngữ Code", "Code Language Mode") + " (\(workspace.activeTab?.language.shortBadgeName ?? "Auto"))", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Button {
                    formatActiveFile()
                } label: {
                    Label(preferences.tr("Format Document theo Ngôn ngữ", "Format Document by Language"), systemImage: "text.alignleft")
                }

                Divider()

                Button {
                    if !liveServer.isRunning {
                        liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                    }
                    let rel = (workspace.activeTab?.language == .html) ? workspace.relativePath(for: workspace.activeTab!.fileURL) : "index.html"
                    liveServer.openInSafari(relativePath: rel)
                } label: {
                    Label(preferences.tr("Mở localhost:\(liveServer.port) trên Safari", "Open localhost:\(liveServer.port) in Safari"), systemImage: "safari")
                }

                Button {
                    bottomTab = .livePreview
                    withAnimation { showBottomPanel = true }
                } label: {
                    Label(preferences.tr("Xem Split Preview & Web F12", "Open Split Preview & Web F12"), systemImage: "rectangle.split.1x2")
                }

                Button {
                    bottomTab = .terminal
                    withAnimation { showBottomPanel.toggle() }
                } label: {
                    Label(sshService.isConnected
                          ? preferences.tr("Mở SSH PTY Terminal (SwiftTerm)", "Open SSH PTY Terminal (SwiftTerm)")
                          : preferences.tr("Mở Terminal (SwiftTerm)", "Open Terminal (SwiftTerm)"), systemImage: "terminal")
                }

                Button {
                    openInlineFindBar()
                } label: {
                    Label(preferences.tr("Tìm kiếm & Thay thế", "Find & Replace"), systemImage: "magnifyingglass")
                }

                Divider()

                Button {
                    showDaemonManagerSheet = true
                } label: {
                    Label(
                        preferences.tr(
                            "Treo Bot & Chạy Ngầm Terminal (24/7 Trên Máy)",
                            "24/7 Background Terminal & Bot Runner (On-Device)",
                            zh: "24/7 本机后台终端与 Bot 运行器",
                            ja: "24/7 端末内バックグラウンド＆Bot",
                            ko: "24/7 기기 내 백그라운드 & 봇 실행",
                            ru: "Локальный 24/7 терминал и боты",
                            es: "Terminal y Bots 24/7 (Local)"
                        ),
                        systemImage: "waveform.path.ecg"
                    )
                }

                Button {
                    showTheosBuilderSheet = true
                } label: {
                    Label(preferences.tr("Tạo & Build Theos Tweak / Mod Menu (.deb / .dylib)", "Build Theos Tweak / Mod Menu (.deb / .dylib)"), systemImage: "hammer.fill")
                }

                Button {
                    rootDocumentPickerMode = .singleFile
                } label: {
                    Label(preferences.tr("Mở File lẻ trên máy (Files)...", "Open File(s) on Device (Files)..."), systemImage: "doc.badge.arrow.up")
                }

                Button {
                    rootDocumentPickerMode = .folder
                } label: {
                    Label(preferences.tr("Mở Thư mục trên máy (Files)...", "Open Folder on Device (Files)..."), systemImage: "folder.badge.gearshape")
                }

                Button {
                    rootDocumentPickerMode = .zip
                } label: {
                    Label(preferences.tr("Nhập & Tự giải nén File .zip...", "Import & Auto-Extract .zip File..."), systemImage: "doc.zipper")
                }

                Button {
                    exportWorkspaceAsZipAndShare()
                } label: {
                    Label(preferences.tr("Xuất Dự án ra File .zip", "Export Project Workspace as .zip"), systemImage: "square.and.arrow.up")
                }

                Button {
                    showThemeStudioDirect = true
                } label: {
                    Label(preferences.tr("Theme Studio (Tự chỉnh màu Code & App)", "Theme Studio (Customize Code & App Colors)"), systemImage: "slider.horizontal.below.square.filled.and.square")
                }

                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            preferences.appLanguage = lang
                        } label: {
                            if preferences.appLanguage == lang {
                                Label("\(lang.shortBadge) — \(lang.displayName(in: preferences.appLanguage))", systemImage: "checkmark")
                            } else {
                                Text("\(lang.shortBadge) — \(lang.displayName(in: preferences.appLanguage))")
                            }
                        }
                    }
                } label: {
                    Label(
                        preferences.tr("Ngôn ngữ App", "App Language", zh: "应用语言", ja: "アプリ言語", ko: "앱 언어", ru: "Язык приложения", es: "Idioma de la app") + " (\(preferences.appLanguage.shortBadge))",
                        systemImage: "globe"
                    )
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    Label(preferences.tr("Theme, Font & Cài đặt", "Themes, Fonts & Settings"), systemImage: "slider.horizontal.3")
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

    @ViewBuilder
    private func quickHeaderEditButton(icon: String, palette: IDEColorPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: palette.foreground))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dedicated VS Code Open File Tab Strip (Newest Left -> Older pushed Right)
    @ViewBuilder
    private func openFilesTabStrip(palette: IDEColorPalette) -> some View {
        HStack(spacing: 4) {
            // Quick '+' New File Button
            Button {
                quickNewFileName = ""
                showQuickNewFileAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: palette.accent))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Quick 1-Tap Open Standalone File(s) from Files.app
            Button {
                rootDocumentPickerMode = .singleFile
            } label: {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: palette.foreground))
                    .frame(width: 26, height: 26)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // 1-Tap Reopen Last Closed Tab Button
            if workspace.canReopenClosedTab {
                Button {
                    workspace.reopenLastClosedTab()
                } label: {
                    Image(systemName: "arrow.uturn.left.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                        .frame(width: 26, height: 26)
                        .background(Color(hex: palette.currentLineBackground))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(workspace.openTabs) { tab in
                            let isSelected = (workspace.activeTabID == tab.id)
                            let isRemoteSFTP = (sshService.remotePathBound(to: tab.fileURL) != nil)
                            let tabDiffStatus = workspace.diffStatus(for: tab.fileURL)
                            let tabStatusColor: Color = {
                                if let hex = tabDiffStatus.colorHex(isDark: palette.isDark) {
                                    return Color(hex: hex)
                                }
                                return Color(hex: isSelected ? palette.foreground : palette.gutterForeground)
                            }()

                            VStack(spacing: 0) {
                                // Top VS Code active tab accent bar
                                Rectangle()
                                    .fill(isSelected ? Color(hex: palette.accent) : Color.clear)
                                    .frame(height: 2.5)

                                HStack(spacing: 5) {
                                    if tab.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundColor(Color(hex: palette.accent))
                                    }
                                    if isRemoteSFTP {
                                        Image(systemName: "icloud")
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundColor(.cyan)
                                    } else {
                                        FileLanguageIconView(language: tab.language, fileName: tab.title, size: 11)
                                    }

                                    Text(tab.title)
                                        .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                        .foregroundColor(tabStatusColor)
                                        .strikethrough(tabDiffStatus.isStrikethrough, color: tabStatusColor)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)

                                    if let badge = tabDiffStatus.badgeText {
                                        Text(badge)
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(tabStatusColor)
                                    } else if tab.isDirty {
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
                                            .frame(width: 16, height: 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                            }
                            .background(isSelected ? Color(hex: palette.editorBackground) : Color(hex: palette.sidebarBackground).opacity(0.65))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color(hex: palette.accent).opacity(0.45) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .opacity(isSelected ? 1.0 : 0.76)
                            .id(tab.id)
                            .onTapGesture {
                                workspace.activeTabID = tab.id
                            }
                            .contextMenu {
                                Button {
                                    workspace.togglePinTab(tab.id)
                                } label: {
                                    Label(
                                        tab.isPinned
                                            ? preferences.tr("Bỏ ghim Tab", "Unpin Tab")
                                            : preferences.tr("Ghim Tab bên trái", "Pin Tab"),
                                        systemImage: tab.isPinned ? "pin.slash" : "pin"
                                    )
                                }
                                Button {
                                    workspace.moveTabToFront(tab.id)
                                } label: {
                                    Label(preferences.tr("Đưa sang trái (Đầu danh sách)", "Move Tab to Leftmost"), systemImage: "arrow.left.to.line")
                                }
                                Button {
                                    UIPasteboard.general.string = workspace.relativePath(for: tab.fileURL)
                                } label: {
                                    Label(preferences.tr("Sao chép đường dẫn", "Copy Relative Path"), systemImage: "doc.on.doc")
                                }
                                if workspace.canReopenClosedTab {
                                    Button {
                                        workspace.reopenLastClosedTab()
                                    } label: {
                                        Label(preferences.tr("Mở lại Tab vừa đóng", "Reopen Closed Tab"), systemImage: "arrow.uturn.left.circle")
                                    }
                                }
                                Divider()
                                Button {
                                    workspace.closeTab(tab.id)
                                } label: {
                                    Label(preferences.tr("Đóng Tab này", "Close Tab"), systemImage: "xmark")
                                }
                                Button {
                                    workspace.closeOtherTabs(keeping: tab.id)
                                } label: {
                                    Label(preferences.tr("Đóng các Tab khác", "Close Other Tabs"), systemImage: "xmark.square")
                                }
                                Button(role: .destructive) {
                                    workspace.closeAllTabs()
                                } label: {
                                    Label(preferences.tr("Đóng tất cả Tab", "Close All Tabs"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .onChange(of: workspace.activeTabID) { _, newID in
                    if let newID {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 35)
        .background(Color(hex: palette.headerBackground).opacity(0.92))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.08))
        }
    }

    // MARK: - Hidden Bluetooth / Magic Keyboard Shortcuts Responder
    @ViewBuilder
    private var hardwareKeyboardShortcutsHost: some View {
        ZStack {
            Button("") { rootDocumentPickerMode = .singleFile }
                .keyboardShortcut("o", modifiers: .command)
            Button("") { saveActiveTabWithCheckpoint() }
                .keyboardShortcut("s", modifiers: .command)
            Button("") { triggerSmartRun() }
                .keyboardShortcut("r", modifiers: .command)
            Button("") { showCommandPalette = true }
                .keyboardShortcut("p", modifiers: .command)
            Button("") { toggleCommentToken += 1 }
                .keyboardShortcut("/", modifiers: .command)
            Button("") { openInlineFindBar() }
                .keyboardShortcut("f", modifiers: .command)
            Button("") {
                if showInlineFindBar {
                    stepFindMatch(forward: true)
                } else {
                    goToLineInput = ""
                    showGoToLineAlert = true
                }
            }
            .keyboardShortcut("g", modifiers: .command)
            Button("") {
                goToLineInput = ""
                showGoToLineAlert = true
            }
            .keyboardShortcut("g", modifiers: .control)
            Button("") {
                if let activeID = workspace.activeTabID {
                    workspace.closeTab(activeID)
                }
            }
            .keyboardShortcut("w", modifiers: .command)
            Button("") { workspace.reopenLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("") {
                quickNewFileName = ""
                showQuickNewFileAlert = true
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("") { triggerQuickAction(.moveLineUp) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("") { triggerQuickAction(.moveLineDown) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("") {
                if showInlineFindBar {
                    showInlineFindBar = false
                    findMatchRanges = []
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
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
        VStack(spacing: 16) {
            IDECodeMarkVector(size: 76)
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 6)

            VStack(spacing: 8) {
                Brand3012WordmarkView(
                    height: 28,
                    inkColor: Color(hex: palette.foreground)
                )

                Text("NATIVE CODE EDITOR & REMOTE WORKSTATION")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundColor(Color(hex: palette.gutterForeground))
            }

            Text(preferences.tr(
                "Vuốt mép trái: Explorer • Git • SSH SFTP • OpenVSX\nVuốt mép phải: Coding Agent   |   Cmd+P: Command Palette",
                "Swipe left edge: Explorer • Git • SSH SFTP • OpenVSX\nSwipe right edge: Coding Agent   |   Cmd+P: Command Palette",
                zh: "左边缘右滑：Explorer • Git • SSH SFTP • OpenVSX\n右边缘左滑：Coding Agent   |   Cmd+P：命令面板",
                ja: "左端スワイプ：Explorer • Git • SSH SFTP • OpenVSX\n右端スワイプ：Coding Agent   |   Cmd+P：コマンドパレット",
                ko: "왼쪽 스와이프: Explorer • Git • SSH SFTP • OpenVSX\n오른쪽 스와이프: Coding Agent   |   Cmd+P: 명령 팔레트",
                ru: "Свайп слева: Explorer • Git • SSH SFTP • OpenVSX\nСвайп справа: Coding Agent   |   Cmd+P: Палитра команд",
                es: "Deslizar izq.: Explorer • Git • SSH SFTP • OpenVSX\nDeslizar der.: Coding Agent   |   Cmd+P: Paleta de comandos"
            ))
            .font(.system(size: 12))
            .foregroundColor(Color(hex: palette.gutterForeground))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button {
                    showLeftExplorer = true
                } label: {
                    Label(preferences.tr("Mở Sidebar", "Open Sidebar", zh: "打开侧边栏", ja: "サイドバー", ko: "사이드바 열기", ru: "Открыть панель", es: "Abrir barra"), systemImage: "sidebar.left")
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

            VStack(spacing: 9) {
                Button {
                    rootDocumentPickerMode = .singleFile
                } label: {
                    Label(preferences.tr("Mở File lẻ (Files)", "Open Standalone File(s) (Files)"), systemImage: "doc.badge.arrow.up")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: palette.accent).opacity(0.18))
                        .foregroundColor(Color(hex: palette.accent))
                        .cornerRadius(7)
                }

                HStack(spacing: 10) {
                    Button {
                        rootDocumentPickerMode = .folder
                    } label: {
                        Label(preferences.tr("Mở Thư mục (Files)", "Open Folder (Files)"), systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.foreground))
                            .cornerRadius(7)
                    }

                    Button {
                        rootDocumentPickerMode = .zip
                    } label: {
                        Label(preferences.tr("Nhập & Giải nén .zip", "Import & Extract .zip"), systemImage: "doc.zipper")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.foreground))
                            .cornerRadius(7)
                    }
                }
            }

            if workspace.canReopenClosedTab {
                Button {
                    workspace.reopenLastClosedTab()
                } label: {
                    Label(preferences.tr("Mở lại Tab vừa đóng (Cmd+Shift+T)", "Reopen Last Closed Tab (Cmd+Shift+T)"), systemImage: "arrow.uturn.left.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(7)
                }
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            preferences.appLanguage = lang
                        } label: {
                            if preferences.appLanguage == lang {
                                Label("\(lang.shortBadge) — \(lang.displayName(in: preferences.appLanguage))", systemImage: "checkmark")
                            } else {
                                Text("\(lang.shortBadge) — \(lang.displayName(in: preferences.appLanguage))")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(preferences.appLanguage.shortBadge) • \(preferences.appLanguage.displayName(in: preferences.appLanguage))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(7)
                }

                Button {
                    showSettingsSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                        Text(preferences.tr("Cài đặt & Thông tin", "Settings & Info", zh: "设置与信息", ja: "設定と情報", ko: "설정 및 정보", ru: "Настройки", es: "Ajustes"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.accent))
                    .cornerRadius(7)
                }
            }
            .padding(.top, 4)
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

    private func triggerSelectRange(_ range: NSRange) {
        let nextToken = (selectRangeRequest?.token ?? 0) + 1
        selectRangeRequest = SelectRangeRequest(token: nextToken, range: range)
    }

    private func triggerQuickAction(_ kind: EditorQuickActionKind) {
        let nextToken = (quickActionRequest?.token ?? 0) + 1
        quickActionRequest = EditorQuickActionRequest(token: nextToken, kind: kind)
    }

    private func cursorLineAndColumn(in text: String, location: Int) -> (line: Int, column: Int) {
        let utf16 = text.utf16
        let clamped = max(0, min(location, utf16.count))
        var line = 1
        var col = 1
        var idx = utf16.startIndex
        var remaining = clamped
        while remaining > 0, idx < utf16.endIndex {
            if utf16[idx] == 10 {
                line += 1
                col = 1
            } else {
                col += 1
            }
            idx = utf16.index(after: idx)
            remaining -= 1
        }
        return (line, col)
    }

    private func mergedHighlightedRanges(for tab: OpenTab) -> [HighlightedRange] {
        var ranges = intelligence.makeRunestoneHighlightedRanges(enabled: preferences.enableLiveDiagnostics)
        guard showInlineFindBar, !findMatchRanges.isEmpty else { return ranges }
        let docLen = (tab.content as NSString).length
        for (idx, range) in findMatchRanges.enumerated() {
            guard range.location >= 0, range.length > 0, range.upperBound <= docLen else { continue }
            let isCurrent = (idx == currentFindMatchIndex)
            let color = isCurrent
                ? UIColor.systemOrange.withAlphaComponent(0.48)
                : UIColor.systemYellow.withAlphaComponent(0.22)
            ranges.append(
                HighlightedRange(
                    id: "find_\(idx)_\(range.location)",
                    range: range,
                    color: color,
                    cornerRadius: 3
                )
            )
        }
        return ranges
    }

    private func openInlineFindBar() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showInlineFindBar = true
        }
        if !findQuery.isEmpty {
            recomputeFindMatches(jumpToFirst: true)
        }
    }

    private func recomputeFindMatches(in explicitCode: String? = nil, jumpToFirst: Bool) {
        guard let tab = workspace.activeTab else {
            findMatchRanges = []
            currentFindMatchIndex = 0
            return
        }
        let code = explicitCode ?? tab.content
        guard !findQuery.isEmpty else {
            findMatchRanges = []
            currentFindMatchIndex = 0
            return
        }
        let nsText = code as NSString
        let docLen = nsText.length
        let options: NSString.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchLocation = 0
        let maxMatches = 500

        while searchLocation < docLen, matches.count < maxMatches {
            let searchRange = NSRange(location: searchLocation, length: docLen - searchLocation)
            let found = nsText.range(of: findQuery, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            matches.append(found)
            searchLocation = found.upperBound
        }

        findMatchRanges = matches
        guard !matches.isEmpty else {
            currentFindMatchIndex = 0
            return
        }

        if jumpToFirst {
            let cursor = tab.selectedRangeLocation
            currentFindMatchIndex = matches.firstIndex(where: { $0.location >= cursor }) ?? 0
            triggerSelectRange(matches[currentFindMatchIndex])
        } else {
            currentFindMatchIndex = max(0, min(currentFindMatchIndex, matches.count - 1))
        }
    }

    private func stepFindMatch(forward: Bool) {
        guard !findQuery.isEmpty else { return }
        if findMatchRanges.isEmpty {
            recomputeFindMatches(jumpToFirst: true)
            return
        }
        let count = findMatchRanges.count
        if forward {
            currentFindMatchIndex = (currentFindMatchIndex + 1) % count
        } else {
            currentFindMatchIndex = (currentFindMatchIndex - 1 + count) % count
        }
        triggerSelectRange(findMatchRanges[currentFindMatchIndex])
    }

    private func replaceCurrentFindMatch() {
        guard !findMatchRanges.isEmpty,
              let tab = workspace.activeTab,
              currentFindMatchIndex >= 0,
              currentFindMatchIndex < findMatchRanges.count else { return }
        let targetRange = findMatchRanges[currentFindMatchIndex]
        let docLen = (tab.content as NSString).length
        guard targetRange.location >= 0, targetRange.upperBound <= docLen else {
            recomputeFindMatches(jumpToFirst: false)
            return
        }
        let containsSelf = replaceQuery.range(
            of: findQuery,
            options: findCaseSensitive ? [] : [.caseInsensitive]
        ) != nil
        if containsSelf {
            currentFindMatchIndex += 1
        }
        let nextToken = (completionRequest?.token ?? 0) + 1
        completionRequest = CompletionReplacementRequest(
            token: nextToken,
            range: targetRange,
            replacement: replaceQuery,
            cursorOffset: (replaceQuery as NSString).length
        )
    }

    private func replaceAllFindMatches() {
        guard !findQuery.isEmpty, let tab = workspace.activeTab else { return }
        let nsText = tab.content as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let options: NSString.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
        let updated = nsText.replacingOccurrences(of: findQuery, with: replaceQuery, options: options, range: fullRange)
        guard updated != tab.content else { return }
        let nextToken = (completionRequest?.token ?? 0) + 1
        completionRequest = CompletionReplacementRequest(
            token: nextToken,
            range: fullRange,
            replacement: updated,
            cursorOffset: min((updated as NSString).length, tab.selectedRangeLocation)
        )
        findMatchRanges = []
        currentFindMatchIndex = 0
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

    private func isTheosBuildContext(activeTab: OpenTab) -> Bool {
        let ext = activeTab.fileURL.pathExtension.lowercased()
        let lowerName = activeTab.fileURL.lastPathComponent.lowercased()
        if ["x", "xm", "xi", "xmi"].contains(ext) || lowerName == "control" || lowerName == "makefile" {
            return theosService.isTheosWorkspace(workspace.rootURL) || ["x", "xm", "xi", "xmi"].contains(ext)
        }
        return theosService.isTheosWorkspace(workspace.rootURL)
    }

    private func triggerSmartRun() {
        applyFormatOnSaveIfEnabled()
        workspace.saveActiveTab()
        guard let active = workspace.activeTab else { return }

        if isTheosBuildContext(activeTab: active) {
            if theosService.buildMode == .communityServer && !theosService.hasAcceptedPrivacyConsent {
                showTheosBuilderSheet = true
                return
            }
            workspace.saveAllTabs()
            bottomTab = .output
            withAnimation { showBottomPanel = true }
            theosService.startBuild(
                workspaceRoot: workspace.rootURL,
                sshService: sshService,
                runner: runner,
                onWorkspaceChanged: { [weak workspace] in
                    workspace?.reloadTree()
                }
            )
            return
        }

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
            (preferences.tr("Chạy File hiện tại (Cmd+R)", "Run Active File (Cmd+R)"), "play.fill", { triggerSmartRun() }),
            (preferences.tr("Lưu File & Tạo Mốc Lịch Sử (Cmd+S)", "Save File & Record Snapshot (Cmd+S)"), "externaldrive.badge.checkmark", { saveActiveTabWithCheckpoint() }),
            (preferences.tr("Đi tới Symbol Outline trong File", "Go to Symbol Outline in File"), "list.bullet.indent", { showSymbolOutlineSheet = true }),
            (preferences.tr("Tìm kiếm & Thay thế trong File (Cmd+F)", "Find & Replace in File (Cmd+F)"), "magnifyingglass", { openInlineFindBar() }),
            (preferences.tr("Đi tới dòng (Go to Line) (Ctrl+G)", "Go to Line (Ctrl+G)"), "arrow.right.to.line", {
                goToLineInput = ""
                showGoToLineAlert = true
            }),
            (preferences.tr("Mở lại Tab vừa đóng (Cmd+Shift+T)", "Reopen Closed Tab (Cmd+Shift+T)"), "arrow.uturn.left.circle", { workspace.reopenLastClosedTab() }),
            (preferences.tr("Ghim / Bỏ ghim Tab đang mở", "Pin / Unpin Active Tab"), "pin", {
                if let activeID = workspace.activeTabID {
                    workspace.togglePinTab(activeID)
                }
            }),
            (preferences.tr("Đẩy dòng hiện tại lên trên (Alt+↑)", "Move Current Line Up (Alt+↑)"), "arrow.up.to.line", { triggerQuickAction(.moveLineUp) }),
            (preferences.tr("Đẩy dòng hiện tại xuống dưới (Alt+↓)", "Move Current Line Down (Alt+↓)"), "arrow.down.to.line", { triggerQuickAction(.moveLineDown) }),
            (preferences.tr("Mở Lịch sử Phiên bản File (Timeline)", "Open File Version Timeline (Restore Snapshot)"), "clock.arrow.circlepath", { showTimelineSheet = true }),
            (preferences.tr("Bật/tắt Chú thích dòng (Cmd+/)", "Toggle Line Comment (Cmd+/)"), "number", { toggleCommentToken += 1 }),
            (preferences.tr("Bật/tắt Gợi ý Code thông minh", "Toggle Live Code Autocomplete") + " (\(preferences.enableCodeCompletion ? "ON" : "OFF"))", "text.cursor", {
                preferences.enableCodeCompletion.toggle()
            }),
            (preferences.tr("Bật/tắt Báo lỗi trực tiếp", "Toggle Inline Error Highlighting") + " (\(preferences.enableLiveDiagnostics ? "ON" : "OFF"))", "exclamationmark.triangle", {
                preferences.enableLiveDiagnostics.toggle()
            }),
            (preferences.tr("Mở Theme Studio (Tự chỉnh màu Code & App)", "Open Theme Studio (Customize Code & App Colors)"), "slider.horizontal.below.square.filled.and.square", {
                showThemeStudioDirect = true
            }),
            (preferences.tr("Chọn Ngôn ngữ Code (64 Ngôn ngữ / Auto)", "Select Code Language Mode (64 Languages / Auto-Detect)"), "chevron.left.forwardslash.chevron.right", {
                showLanguagePickerSheet = true
            }),
            (preferences.tr("Format Document theo Ngôn ngữ (Cmd+Shift+F)", "Format Document by Language (Cmd+Shift+F)"), "text.alignleft", { formatActiveFile() }),
            (preferences.tr("Bật/tắt Tự động Format khi Lưu & Chạy", "Toggle Auto-Format on Save & Run") + " (\(preferences.formatOnSave ? "ON" : "OFF"))", "arrow.triangle.2.circlepath", {
                preferences.formatOnSave.toggle()
            }),
            (preferences.tr("Xem Problems & Báo lỗi trực tiếp", "Show Problems & Inline Diagnostics"), "checklist", { checkSyntaxAndLSPDiagnostics() }),
            (preferences.tr("Treo Bot Telegram & Chạy Ngầm Terminal 24/7 (Trên Máy)", "24/7 Background Terminal & Telegram Bot Runner (On-Device)"), "waveform.path.ecg", { showDaemonManagerSheet = true }),
            (preferences.tr("Tạo & Build Theos Tweak / Mod Menu (.deb / .dylib)", "Build Theos Tweak / Mod Menu (.deb / .dylib)"), "hammer.fill", { showTheosBuilderSheet = true }),
            (preferences.tr("Mở File lẻ trên máy (Files)... (Cmd+O)", "Open File(s) from Files... (Cmd+O)"), "doc.badge.arrow.up", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    rootDocumentPickerMode = .singleFile
                }
            }),
            (preferences.tr("Mở Thư mục trên máy (Files)...", "Open Folder on Device (Files)..."), "folder.badge.gearshape", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    rootDocumentPickerMode = .folder
                }
            }),
            (preferences.tr("Nhập & Tự giải nén File .zip...", "Import & Auto-Extract .zip Archive..."), "doc.zipper", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    rootDocumentPickerMode = .zip
                }
            }),
            (preferences.tr("Xuất Dự án ra File .zip", "Export Project Workspace as .zip"), "square.and.arrow.up", { exportWorkspaceAsZipAndShare() }),
            (preferences.tr("Mở Live Server localhost:\(liveServer.port) trên Safari", "Open Live Server localhost:\(liveServer.port) in Safari"), "safari", {
                if !liveServer.isRunning {
                    liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                }
                liveServer.openInSafari()
            }),
            (preferences.tr("Đóng/mở Xterm / SSH PTY Terminal (Cmd+J)", "Toggle Xterm / SSH PTY Terminal (Cmd+J)"), "terminal", {
                bottomTab = .terminal
                withAnimation { showBottomPanel.toggle() }
            }),
            (preferences.tr("Đóng/mở Coding Agent Panel (Cmd+I)", "Toggle Coding Agent Panel (Cmd+I)"), "cpu", {
                withAnimation { showRightAIPanel.toggle() }
            }),
            (preferences.tr("Ngôn ngữ Giao diện & Thông tin Tác giả (\(IDEAuthorInfo.telegramHandle))", "Interface Language & Author Info (\(IDEAuthorInfo.telegramHandle))"), "globe", {
                showSettingsSheet = true
            }),
            (preferences.tr("Mở Cài đặt, Theme & Font chữ", "Open Themes, Fonts & IDE Settings"), "slider.horizontal.3", {
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
