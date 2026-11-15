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
    @StateObject private var xtoolService = XtoolBuildService()
    @StateObject private var daemonService = LocalDaemonService()
    @StateObject private var pcSyncService = PCSyncService()

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
                xtoolService: xtoolService,
                daemonService: daemonService,
                pcSyncService: pcSyncService
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
    @ObservedObject var xtoolService: XtoolBuildService
    @ObservedObject var daemonService: LocalDaemonService
    @ObservedObject var pcSyncService: PCSyncService

    @Environment(\.scenePhase) private var scenePhase

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
    @State private var showXtoolBuilderSheet: Bool = false
    @State private var showDaemonManagerSheet: Bool = false
    @State private var showPCSyncSheet: Bool = false
    @State private var showLiveShareSheet: Bool = false
    @State private var showPowerToolsSheet: Bool = false
    @State private var showOpenFolderHubSheet: Bool = false

    @State private var isFullScreenZenMode: Bool = false
    @State private var isEditorKeyboardActive: Bool = false
    @State private var pendingSaveSideEffectTask: Task<Void, Never>? = nil
    @State private var pendingSavedTabInfo: (url: URL, content: String)? = nil
    @State private var findAdvanceMinLocation: Int? = nil

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

        ZStack {
            Color(hex: palette.editorBackground)
                .ignoresSafeArea()

            // Hidden Hardware Bluetooth / Magic Keyboard Shortcuts Responder
            hardwareKeyboardShortcutsHost

            GeometryReader { geo in
                let isWideLayout = geo.size.width >= 680

                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        if !isFullScreenZenMode {
                            // 1. Ultra-Slim Top Header Bar (Responsive down to 320pt iPad Slide Over & 375pt iPhone 7/8)
                            topHeaderBar(palette: palette, containerWidth: geo.size.width)

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
                        }

                        // 4. Central Workspace Area (Editor / Markdown Preview + Optional Side-by-Side Agent)
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                if let activeTab = workspace.activeTab {
                                    centralEditorAndPreviewArea(activeTab: activeTab, palette: palette, isWide: isWideLayout)
                                } else {
                                    emptyEditorPlaceholder(palette: palette)
                                }

                                if !isFullScreenZenMode && showBottomPanel {
                                    bottomSplitSection(totalHeight: geo.size.height, palette: palette)
                                }
                            }

                            // Side-by-side Coding Agent Panel when screen is wide (Landscape iPhone / iPad)
                            if !isFullScreenZenMode && showRightAIPanel && isWideLayout {
                                rightAISplitSection(totalWidth: geo.size.width, palette: palette)
                            }
                        }
                    }
                    .background(Color(hex: palette.editorBackground))

                    // Subtle Floating Button to Exit Full-Screen Zen Mode
                    if isFullScreenZenMode {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isFullScreenZenMode = false
                            }
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: palette.accent))
                                .padding(8)
                                .background(Color(hex: palette.headerBackground).opacity(0.88))
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(Color(hex: palette.accent).opacity(0.35), lineWidth: 1)
                                )
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 10)
                        .zIndex(9)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 22, coordinateSpace: .local)
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
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
            .ignoresSafeArea(
                .container,
                edges: (!isFullScreenZenMode && showBottomPanel) ? [] : .bottom
            )

            // Portrait Overlay Drawers Layer (Respects Safe Area & Keyboard)
            GeometryReader { overlayGeo in
                let isWideLayout = overlayGeo.size.width >= 680

                ZStack(alignment: .leading) {
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
                            pcSync: pcSyncService,
                            onInsertSnippet: { snippetBody in
                                insertTextIntoActiveTab(snippetBody)
                            },
                            onOpenTheosBuilder: {
                                showLeftExplorer = false
                                showTheosBuilderSheet = true
                            },
                            onOpenXtoolBuilder: {
                                showLeftExplorer = false
                                showXtoolBuilderSheet = true
                            },
                            onRequestOpenSingleFile: {
                                presentWorkspaceDocumentPicker(.singleFile)
                            },
                            onRequestOpenFolder: {
                                showLeftExplorer = false
                                showOpenFolderHubSheet = true
                            },
                            onRequestImportZip: {
                                presentWorkspaceDocumentPicker(.zip)
                            },
                            onOpenPCSyncSheet: {
                                showLeftExplorer = false
                                showPCSyncSheet = true
                            },
                            onOpenLiveShareSheet: {
                                showLeftExplorer = false
                                liveServer.updateBackgroundKeepAlive(enabled: preferences.keepServerInBackground)
                                showLiveShareSheet = true
                            },
                            onOpenPowerToolsSheet: {
                                showLeftExplorer = false
                                showPowerToolsSheet = true
                            },
                            onJumpToSearchHit: { url, line in
                                workspace.openFile(at: url)
                                showLeftExplorer = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    triggerJumpToLine(line)
                                }
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
                        .frame(width: min(overlayGeo.size.width * 0.86, 350))
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
                                intelligence: intelligence,
                                gitService: gitService,
                                onClose: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showRightAIPanel = false
                                    }
                                }
                            )
                            .frame(width: min(overlayGeo.size.width * 0.88, 360))
                            .shadow(color: .black.opacity(0.45), radius: 14, x: -4, y: 0)
                        }
                        .transition(.move(edge: .trailing))
                        .zIndex(11)
                    }
                }
            }
        }
        .onAppear {
            workspace.onFileSavedOrChanged = { [weak liveServer] in
                liveServer?.notifyFileChanged()
            }
            workspace.onAnyTabSavedWithURL = { fileURL, updatedText in
                scheduleDebouncedSaveSideEffects(fileURL: fileURL, content: updatedText)
            }
            pcSyncService.attachWorkspace(workspace)
            workspace.onWorkspaceMutation = { [weak pcSyncService] event in
                pcSyncService?.handleWorkspaceMutation(event)
            }
            pcSyncService.autoConnectIfConfigured()
            liveServer.start(
                serving: workspace.rootURL,
                keepAliveInBackground: false
            )
            intelligence.reindexWorkspaceFiles(workspace.flattenFiles(in: workspace.fileTree))
            refreshIntelligenceForActiveTab()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                pcSyncService.autoConnectIfConfigured()
            case .inactive, .background:
                flushPendingSaveSideEffects()
                if preferences.enableAutoSave {
                    workspace.saveAllTabs()
                }
            @unknown default:
                break
            }
        }
        .onChange(of: workspace.fileTree) { updatedTree in
            intelligence.reindexWorkspaceFiles(workspace.flattenFiles(in: updatedTree))
        }
        .onChange(of: workspace.activeTabID) { _ in
            flushPendingSaveSideEffects()
            intelligence.clearCompletions()
            if workspace.activeTab?.language != .markdown {
                markdownMode = .editor
            }
            if showInlineFindBar {
                recomputeFindMatches(jumpToFirst: false)
            }
            refreshIntelligenceForActiveTab()
        }
        .onChange(of: preferences.enableLiveDiagnostics) { enabled in
            if enabled {
                refreshIntelligenceForActiveTab()
            } else {
                intelligence.diagnostics = []
            }
        }
        .onChange(of: preferences.enableCodeCompletion) { enabled in
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
        .sheet(isPresented: $showXtoolBuilderSheet) {
            XtoolBuilderSheet(
                xtoolService: xtoolService,
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
            } else {
                missingActiveFileSheetFallback(palette: palette) {
                    showSymbolOutlineSheet = false
                }
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
            } else {
                missingActiveFileSheetFallback(palette: palette) {
                    showLanguagePickerSheet = false
                }
            }
        }
        .sheet(isPresented: $showTimelineSheet) {
            if let activeTab = workspace.activeTab {
                FileTimelineSheet(
                    fileURL: activeTab.fileURL,
                    currentContent: activeTab.content,
                    timelineService: timelineService,
                    onRestoreContent: { restored in
                        guard workspace.activeTab?.id == activeTab.id else { return }
                        let docLen = (activeTab.content as NSString).length
                        let nextToken = (completionRequest?.token ?? 0) + 1
                        completionRequest = CompletionReplacementRequest(
                            token: nextToken,
                            range: NSRange(location: 0, length: docLen),
                            replacement: restored,
                            cursorOffset: min(activeTab.selectedRangeLocation, (restored as NSString).length)
                        )
                        timelineService.recordSnapshot(for: activeTab.fileURL, content: restored, label: "Restored Snapshot")
                        refreshIntelligenceForActiveTab()
                    }
                )
            } else {
                missingActiveFileSheetFallback(palette: palette) {
                    showTimelineSheet = false
                }
            }
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "3012sync" {
                if pcSyncService.applyPairingString(url.absoluteString) {
                    showPCSyncSheet = true
                }
                return
            }
            workspace.handleIncomingURL(url)
            liveServer.updateRootDirectory(workspace.rootURL)
        }
        .onChange(of: workspace.rootURL) { newRoot in
            liveServer.updateRootDirectory(newRoot)
        }
        .sheet(isPresented: $showPCSyncSheet) {
            PCSyncCompanionSheet(
                pcSync: pcSyncService,
                workspace: workspace,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showLiveShareSheet) {
            LiveServerShareSheet(
                liveServer: liveServer,
                workspace: workspace,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showPowerToolsSheet) {
            DeveloperPowerToolsSheet(
                workspace: workspace,
                runner: runner,
                sshService: sshService,
                preferences: preferences
            )
        }
        .sheet(isPresented: $showOpenFolderHubSheet) {
            OpenFolderHubSheet(
                workspace: workspace,
                onRequestReopenHub: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showOpenFolderHubSheet = true
                    }
                }
            )
            .onDisappear {
                liveServer.updateRootDirectory(workspace.rootURL)
            }
        }
        .compatibleTextInputAlert(
            preferences.tr("Tạo File Mới", "New File"),
            isPresented: $showQuickNewFileAlert,
            text: $quickNewFileName,
            placeholder: preferences.tr("Tên file (vd: script.py)", "File name (e.g. script.py)"),
            confirmTitle: preferences.tr("Tạo", "Create"),
            cancelTitle: preferences.tr("Hủy", "Cancel"),
            onConfirm: {
                let name = quickNewFileName
                quickNewFileName = ""
                if let created = workspace.createFile(named: name) {
                    workspace.openFile(at: created)
                }
            }
        )
        .compatibleTextInputAlert(
            preferences.tr("Đi tới dòng (Go to Line)", "Go to Line"),
            isPresented: $showGoToLineAlert,
            text: $goToLineInput,
            placeholder: preferences.tr("Số dòng (vd: 42)", "Line number (e.g. 42)"),
            message: workspace.activeTab.map { tab in
                let totalLines = max(1, tab.content.reduce(1) { $1 == "\n" ? $0 + 1 : $0 })
                return preferences.tr("File hiện có \(totalLines) dòng.", "File has \(totalLines) lines.")
            },
            confirmTitle: preferences.tr("Đi tới", "Go"),
            cancelTitle: preferences.tr("Hủy", "Cancel"),
            keyboardType: .numberPad,
            onConfirm: {
                if let lineNum = Int(goToLineInput.trimmingCharacters(in: .whitespacesAndNewlines)), lineNum > 0 {
                    triggerJumpToLine(lineNum)
                }
                goToLineInput = ""
            }
        )
    }

    // MARK: - Central Editor + Floating Live Autocomplete + Markdown/Mermaid View
    @ViewBuilder
    private func centralEditorAndPreviewArea(activeTab: OpenTab, palette: IDEColorPalette, isWide: Bool) -> some View {
        let showMarkdownSplit = (activeTab.language == .markdown && markdownMode == .split)
        let showMarkdownOnly = (activeTab.language == .markdown && markdownMode == .preview)
        let markdownBaseDir = activeTab.fileURL.deletingLastPathComponent()

        if showMarkdownOnly {
            MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette, baseDirectoryURL: markdownBaseDir)
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
                        MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette, baseDirectoryURL: markdownBaseDir)
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
                        MarkdownMermaidPreviewView(markdown: activeTab.content, palette: palette, baseDirectoryURL: markdownBaseDir)
                            .frame(height: bottomH)
                    }
                }
            }
        } else {
            editorWithAutocompleteOverlay(activeTab: activeTab, palette: palette)
        }
    }

    @ViewBuilder
    private func bottomSplitSection(totalHeight: CGFloat, palette: IDEColorPalette) -> some View {
        let maxBottomH = max(160, totalHeight * 0.80)
        let activeBottomH = min(
            max(customBottomPanelHeight ?? bottomDetent.height(in: totalHeight), 120),
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
            xtoolService: xtoolService,
            onJumpToLine: { line in
                triggerJumpToLine(line)
            },
            onFixDiagnosticWithAgent: { diag in
                fixDiagnosticWithAgent(diag)
            },
            onOpenDaemonManager: {
                showDaemonManagerSheet = true
            },
            onOpenShareSheet: {
                showLiveShareSheet = true
            },
            onFixRawErrorWithAgent: { rawError in
                fixRawErrorWithAgent(rawError)
            },
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBottomPanel = false
                }
            }
        )
        .frame(height: activeBottomH)
        .onChange(of: bottomDetent) { _ in
            customBottomPanelHeight = nil
        }
    }

    @ViewBuilder
    private func rightAISplitSection(totalWidth: CGFloat, palette: IDEColorPalette) -> some View {
        let maxAIW = max(280, totalWidth * 0.65)
        let activeAIW = min(max(totalWidth * rightAIPanelRatio, 240), maxAIW)
        resizableSplitBar(
            isHorizontal: false,
            palette: palette,
            onDragChanged: { value in
                if dragStartRightAIWidth == nil {
                    dragStartRightAIWidth = activeAIW
                }
                let baseW = dragStartRightAIWidth ?? activeAIW
                let clampedW = min(max(baseW - value.translation.width, 240), maxAIW)
                rightAIPanelRatio = clampedW / max(totalWidth, 1)
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
            intelligence: intelligence,
            gitService: gitService,
            onClose: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRightAIPanel = false
                }
            }
        )
        .frame(width: activeAIW)
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
                },
                onEditingChanged: { active in
                    isEditorKeyboardActive = active
                    if !active {
                        intelligence.clearCompletions()
                    }
                }
            )

            // Floating VS Code Smart IntelliSense & Parameter Signature Widget (hidden when keyboard closes)
            if isEditorKeyboardActive && preferences.enableCodeCompletion && (!intelligence.completions.isEmpty || intelligence.activeSignatureHint != nil) {
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
                if activeTab.selectedRangeLength > 0 {
                    Menu {
                        Button {
                            runSelectionAIAction(
                                slashCommand: "/explain",
                                instruction: "Giải thích rõ đoạn code đang chọn ở trên hoạt động như thế nào."
                            )
                        } label: {
                            Label(preferences.tr("Giải thích đoạn chọn (/explain)", "Explain Selection (/explain)"), systemImage: "text.bubble")
                        }
                        Button {
                            runSelectionAIAction(
                                slashCommand: "/refactor",
                                instruction: "Tối ưu / Refactor đoạn code đang chọn cho sạch hơn, nhanh hơn và đề xuất bằng <file_edit>."
                            )
                        } label: {
                            Label(preferences.tr("Tối ưu đoạn chọn (/refactor)", "Refactor Selection (/refactor)"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            runSelectionAIAction(
                                slashCommand: "/fix",
                                instruction: "Tìm lỗi tiềm ẩn trong đoạn code đang chọn và sửa lại bằng <file_edit>."
                            )
                        } label: {
                            Label(preferences.tr("Tìm & sửa lỗi đoạn chọn (/fix)", "Fix Selection (/fix)"), systemImage: "wrench.and.screwdriver")
                        }
                        Button {
                            runSelectionAIAction(
                                slashCommand: "/test",
                                instruction: "Viết Unit Test cho đoạn code đang chọn và đề xuất bằng <file_edit>."
                            )
                        } label: {
                            Label(preferences.tr("Viết Test cho đoạn chọn (/test)", "Generate Tests (/test)"), systemImage: "checkmark.seal")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("AI")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: palette.accent).opacity(0.22))
                        .foregroundColor(Color(hex: palette.accent))
                        .cornerRadius(4)
                    }
                }

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

                // 4.6 xtool SwiftPM / .ipa Pill
                if isXtoolBuildContext(activeTab: activeTab) {
                    Button {
                        showXtoolBuilderSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            if xtoolService.isBuilding || xtoolService.isInjecting {
                                ProgressView().scaleEffect(0.55)
                            } else {
                                Image(systemName: "cube.transparent.fill")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            Text("xtool .ipa")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.18))
                        .foregroundColor(.blue)
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

                // 8. 1-Tap Full-Screen Zen Mode Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isFullScreenZenMode.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: palette.accent))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(hex: palette.accent).opacity(0.14))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
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
                        .onChange(of: findQuery) { _ in
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
    private func topHeaderBar(palette: IDEColorPalette, containerWidth: CGFloat) -> some View {
        let isUltraNarrow = containerWidth < 355
        let isCompactPhone = containerWidth < 395

        HStack(spacing: isUltraNarrow ? 3 : 5) {
            // Brand Emblem + Activity Drawer Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showLeftExplorer.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    if !isUltraNarrow {
                        IDECodeMarkVector(size: isCompactPhone ? 18 : 22)
                    }
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: isCompactPhone ? 12.5 : 13.5, weight: .semibold))
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
                    Text(workspace.workspaceDisplayName)
                        .font(.system(size: isCompactPhone ? 10.5 : 11, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(1)
                    if pcSyncService.isConnected {
                        Circle()
                            .fill(pcSyncService.transportMode == .wifiLAN ? Color.green : Color.cyan)
                            .frame(width: 5.5, height: 5.5)
                    }
                }
                .padding(.horizontal, isCompactPhone ? 6 : 7)
                .padding(.vertical, 4)
                .background(Color(hex: palette.currentLineBackground))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .layoutPriority(-1)

            Spacer(minLength: 2)

            // Quick Top Edit Strip: Undo / Redo (+ Copy / Paste when >= 360pt)
            if workspace.activeTab != nil {
                HStack(spacing: 1) {
                    quickHeaderEditButton(icon: "arrow.uturn.backward", palette: palette) {
                        triggerQuickAction(.undo)
                    }
                    quickHeaderEditButton(icon: "arrow.uturn.forward", palette: palette) {
                        triggerQuickAction(.redo)
                    }
                    if !isUltraNarrow {
                        quickHeaderEditButton(icon: "doc.on.doc", palette: palette) {
                            triggerQuickAction(.copy)
                        }
                        quickHeaderEditButton(icon: "doc.on.clipboard", palette: palette) {
                            triggerQuickAction(.paste)
                        }
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
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    Text("Run")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, isCompactPhone ? 7 : 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.88))
                .foregroundColor(.black)
                .cornerRadius(6)
                .fixedSize(horizontal: true, vertical: false)
            }

            // Tools & Intelligence Menu (Equatable wrapper prevents scroll reset on high-frequency updates)
            HeaderToolsMenuView(
                appLanguage: preferences.appLanguage,
                activeLanguageBadge: workspace.activeTab?.language.shortBadgeName ?? "Auto",
                enableCodeCompletion: preferences.enableCodeCompletion,
                enableLiveDiagnostics: preferences.enableLiveDiagnostics,
                formatOnSave: preferences.formatOnSave,
                liveServerRunning: liveServer.isRunning,
                liveServerPort: liveServer.port,
                isShareLinkEnabled: liveServer.isShareLinkEnabled,
                sharedViewerCount: liveServer.sharedViewerCount,
                sshConnected: sshService.isConnected,
                pcSyncConnected: pcSyncService.isConnected,
                pcSyncTransportLabel: pcSyncService.transportMode.badgeLabel,
                isFullScreenZen: isFullScreenZenMode,
                foregroundHex: palette.foreground,
                accentHex: palette.accent,
                onCommandPalette: { showCommandPalette = true },
                onSaveSnapshot: { saveActiveTabWithCheckpoint() },
                onSymbolOutline: {
                    if workspace.activeTab != nil {
                        showSymbolOutlineSheet = true
                    }
                },
                onTimeline: {
                    if workspace.activeTab != nil {
                        showTimelineSheet = true
                    }
                },
                onSetCodeCompletion: { preferences.enableCodeCompletion = $0 },
                onSetLiveDiagnostics: { preferences.enableLiveDiagnostics = $0 },
                onSetFormatOnSave: { preferences.formatOnSave = $0 },
                onLanguagePicker: {
                    if workspace.activeTab != nil {
                        showLanguagePickerSheet = true
                    }
                },
                onFormatDocument: { formatActiveFile() },
                onToggleFullScreenZen: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isFullScreenZenMode.toggle()
                    }
                },
                onOpenSafari: {
                    if !liveServer.isRunning {
                        liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                    } else if preferences.keepServerInBackground {
                        liveServer.updateBackgroundKeepAlive(enabled: true)
                    }
                    let rel: String
                    if let active = workspace.activeTab, active.language == .html {
                        rel = workspace.relativePath(for: active.fileURL)
                    } else {
                        rel = "index.html"
                    }
                    liveServer.openInSafari(relativePath: rel)
                },
                onOpenLiveShare: {
                    if !liveServer.isRunning {
                        liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                    } else if preferences.keepServerInBackground {
                        liveServer.updateBackgroundKeepAlive(enabled: true)
                    }
                    liveServer.refreshLANAddress()
                    showLiveShareSheet = true
                },
                onOpenSplitPreview: {
                    bottomTab = .livePreview
                    withAnimation { showBottomPanel = true }
                },
                onToggleTerminal: {
                    bottomTab = .terminal
                    withAnimation { showBottomPanel.toggle() }
                },
                onOpenFindBar: { openInlineFindBar() },
                onOpenPCSync: { showPCSyncSheet = true },
                onOpenPowerTools: { showPowerToolsSheet = true },
                onScaffoldStarter: { kind in
                    _ = workspace.scaffoldStarterTemplate(kind: kind)
                    liveServer.updateRootDirectory(workspace.rootURL)
                },
                onOpenDaemonManager: { showDaemonManagerSheet = true },
                onOpenTheos: { showTheosBuilderSheet = true },
                onOpenXtool: { showXtoolBuilderSheet = true },
                onPickFile: { presentWorkspaceDocumentPicker(.singleFile) },
                onPickFolder: { showOpenFolderHubSheet = true },
                onPickZip: { presentWorkspaceDocumentPicker(.zip) },
                onExportZip: { exportWorkspaceAsZipAndShare() },
                onOpenThemeStudio: { showThemeStudioDirect = true },
                onSelectLanguage: { preferences.appLanguage = $0 },
                onOpenSettings: { showSettingsSheet = true },
                tr: { vi, en, zh, ja, ko, ru, es in
                    preferences.tr(vi, en, zh: zh, ja: ja, ko: ko, ru: ru, es: es)
                },
                langDisplayName: { lang in
                    lang.displayName(in: preferences.appLanguage)
                }
            )
            .equatable()

            // Coding Agent Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showRightAIPanel.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isCompactPhone ? "AI" : "Agent")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, isCompactPhone ? 6.5 : 8)
                .padding(.vertical, 5)
                .background(showRightAIPanel ? Color(hex: palette.accent) : Color(hex: palette.currentLineBackground))
                .foregroundColor(showRightAIPanel ? .white : Color(hex: palette.accent))
                .cornerRadius(6)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, isUltraNarrow ? 6 : 8)
        .frame(height: 38)
        .background(Color(hex: palette.headerBackground).ignoresSafeArea(.container, edges: .top))
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
                presentWorkspaceDocumentPicker(.singleFile)
            } label: {
                Image(systemName: "arrow.up.doc")
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
                .onChange(of: workspace.activeTabID) { newID in
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
            Button("") { presentWorkspaceDocumentPicker(.singleFile) }
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
                } else if workspace.activeTab != nil {
                    goToLineInput = ""
                    showGoToLineAlert = true
                }
            }
            .keyboardShortcut("g", modifiers: .command)
            Button("") {
                if workspace.activeTab != nil {
                    goToLineInput = ""
                    showGoToLineAlert = true
                }
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
            if showInlineFindBar {
                Button("") {
                    showInlineFindBar = false
                    findMatchRanges = []
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
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
                    presentWorkspaceDocumentPicker(.singleFile)
                } label: {
                    Label(preferences.tr("Mở File lẻ (File)", "Open Standalone File (File)"), systemImage: "arrow.up.doc")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: palette.accent).opacity(0.18))
                        .foregroundColor(Color(hex: palette.accent))
                        .cornerRadius(7)
                }

                HStack(spacing: 10) {
                    Button {
                        showOpenFolderHubSheet = true
                    } label: {
                        Label(preferences.tr("Mở Thư mục (Folder)", "Open Folder (Folder)"), systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.foreground))
                            .cornerRadius(7)
                    }

                    Button {
                        presentWorkspaceDocumentPicker(.zip)
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

                HStack(spacing: 10) {
                    Button {
                        showPCSyncSheet = true
                    } label: {
                        Label(preferences.tr("Đồng bộ PC (Wi-Fi / 4G)", "PC Sync (Wi-Fi / 4G)"), systemImage: "desktopcomputer")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.16))
                            .foregroundColor(.green)
                            .cornerRadius(7)
                    }

                    Button {
                        showPowerToolsSheet = true
                    } label: {
                        Label(preferences.tr("Công cụ Dev", "Dev Tools"), systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.accent))
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
        let docLen = (tab.content as NSString).length
        var ranges = intelligence.makeRunestoneHighlightedRanges(enabled: preferences.enableLiveDiagnostics).filter {
            $0.range.location >= 0 && $0.range.length > 0 && $0.range.upperBound <= docLen
        }
        guard showInlineFindBar, !findMatchRanges.isEmpty else { return ranges }
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

        if let minLoc = findAdvanceMinLocation {
            findAdvanceMinLocation = nil
            currentFindMatchIndex = matches.firstIndex(where: { $0.location >= minLoc }) ?? 0
            triggerSelectRange(matches[currentFindMatchIndex])
        } else if jumpToFirst {
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
        findAdvanceMinLocation = targetRange.location + (replaceQuery as NSString).length
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
        findAdvanceMinLocation = nil
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

    private func scheduleDebouncedSaveSideEffects(fileURL: URL, content: String) {
        pendingSavedTabInfo = (fileURL, content)
        pendingSaveSideEffectTask?.cancel()
        let delayNs: UInt64 = 550_000_000
        pendingSaveSideEffectTask = Task { @MainActor () -> Void in
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }
            flushPendingSaveSideEffects()
        }
    }

    private func flushPendingSaveSideEffects() {
        pendingSaveSideEffectTask?.cancel()
        pendingSaveSideEffectTask = nil
        guard let saved = pendingSavedTabInfo else { return }
        pendingSavedTabInfo = nil
        sshService.syncSavedLocalMirrorIfNeeded(localURL: saved.url, content: saved.content)
        liveServer.notifyFileChanged()
        if let active = workspace.activeTab, active.fileURL.standardizedFileURL == saved.url.standardizedFileURL {
            intelligence.scheduleAnalysis(
                code: saved.content,
                language: active.language,
                fileName: active.title,
                cursorLocation: active.selectedRangeLocation,
                diagnosticsEnabled: preferences.enableLiveDiagnostics,
                sshService: sshService
            )
        }
        Task { @MainActor () -> Void in
            await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService)
        }
    }

    private func applyFormatOnSaveIfEnabled() {
        guard preferences.formatOnSave, let active = workspace.activeTab else { return }
        let tabID = active.id
        let original = active.content
        let formatted = CodeFormatterService.formatOfflineSynchronously(
            original,
            language: active.language,
            tabWidth: preferences.tabWidth
        )
        if formatted != original {
            let docLen = (original as NSString).length
            let nextToken = (completionRequest?.token ?? 0) + 1
            completionRequest = CompletionReplacementRequest(
                token: nextToken,
                range: NSRange(location: 0, length: docLen),
                replacement: formatted,
                cursorOffset: min(active.selectedRangeLocation, (formatted as NSString).length)
            )
            workspace.updateActiveContent(formatted, autoSave: true)
        }
        if sshService.isConnected {
            let lang = active.language
            let width = preferences.tabWidth
            let baselineText = formatted
            Task { @MainActor () -> Void in
                let remoteFormatted = await CodeFormatterService.format(
                    baselineText,
                    language: lang,
                    tabWidth: width,
                    sshService: sshService
                )
                guard let current = workspace.activeTab,
                      current.id == tabID,
                      current.content == baselineText,
                      remoteFormatted != baselineText else { return }
                let docLen = (current.content as NSString).length
                let nextToken = (completionRequest?.token ?? 0) + 1
                completionRequest = CompletionReplacementRequest(
                    token: nextToken,
                    range: NSRange(location: 0, length: docLen),
                    replacement: remoteFormatted,
                    cursorOffset: min(current.selectedRangeLocation, (remoteFormatted as NSString).length)
                )
                workspace.updateActiveContent(remoteFormatted, autoSave: true)
            }
        }
    }

    private func saveActiveTabWithCheckpoint() {
        flushPendingSaveSideEffects()
        applyFormatOnSaveIfEnabled()
        workspace.saveActiveTab()
        flushPendingSaveSideEffects()
        if let active = workspace.activeTab {
            timelineService.recordSnapshot(for: active.fileURL, content: active.content, label: "Saved")
        }
        refreshIntelligenceForActiveTab()
    }

    private func exportWorkspaceAsZipAndShare() {
        flushPendingSaveSideEffects()
        workspace.saveAllTabs()
        if let zipURL = timelineService.exportProjectZip(
            workspaceRoot: workspace.rootURL,
            preferredArchiveName: workspace.workspaceDisplayName
        ) {
            NativeDocumentPickerPresenter.shared.presentShareSheet(for: zipURL)
        }
    }

    private func presentWorkspaceDocumentPicker(_ mode: WorkspaceDocumentPickerMode, delay: TimeInterval = 0.08) {
        if mode == .folder {
            showOpenFolderHubSheet = true
            return
        }
        NativeDocumentPickerPresenter.shared.presentResourcePicker(
            mode: mode,
            initialDelay: delay
        ) { resources in
            guard !resources.isEmpty else { return }
            switch mode {
            case .singleFile:
                workspace.openExternalSingleFiles(from: resources)
                liveServer.updateRootDirectory(workspace.rootURL)
            case .folder:
                let first = resources[0]
                workspace.switchWorkspaceFolder(to: first.url, hasSecurityScope: first.hasSecurityScope)
                liveServer.updateRootDirectory(workspace.rootURL)
            case .zip:
                let first = resources[0]
                if workspace.importAndOpenZip(from: first.url, hasSecurityScope: first.hasSecurityScope) {
                    liveServer.updateRootDirectory(workspace.rootURL)
                }
            case .themeJSON, .folderFilesCopy:
                break
            }
        }
    }

    private func currentDiagnosticsSummary() -> String {
        intelligence.diagnostics.prefix(20).map {
            "Line \($0.line) [\($0.severity == .error ? "ERROR" : "WARN")]: \($0.message)"
        }.joined(separator: "\n")
    }

    private func currentGitDiffSummary() -> String {
        gitService.changedFiles.prefix(20).map {
            "\($0.statusBadge) \($0.relativePath) (+\($0.addedLines)/-\($0.removedLines))"
        }.joined(separator: "\n")
    }

    private func agentExistingFileReader(_ relPath: String) -> String? {
        guard WorkspaceManager.isSafeRelativeSyncPath(relPath) else { return nil }
        let clean = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let url = workspace.rootURL.appendingPathComponent(clean)
        let rootCanon = WorkspaceManager.canonicalPath(workspace.rootURL)
        let targetCanon = WorkspaceManager.canonicalPath(url)
        guard targetCanon.hasPrefix(rootCanon + "/") else { return nil }
        if let tab = workspace.openTabs.first(where: { $0.fileURL.standardizedFileURL == url.standardizedFileURL }) {
            return tab.content
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func fixDiagnosticWithAgent(_ diag: EditorDiagnostic) {
        guard let active = workspace.activeTab else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showRightAIPanel = true
        }
        let relPath = workspace.relativePath(for: active.fileURL)
        let prompt = "/fix Hãy sửa lỗi sau tại dòng \(diag.line) trong file \(relPath): \"\(diag.message)\". Đề xuất bản sửa hoàn chỉnh bằng <file_edit>."
        let diags = currentDiagnosticsSummary()
        let gitDiff = currentGitDiffSummary()
        Task {
            await aiService.sendPrompt(
                userPrompt: prompt,
                workspaceTree: workspace.workspaceSummaryTree(),
                activeFilePath: relPath,
                activeFileContent: active.content,
                selectedSnippet: workspace.selectedSnippetInActiveTab(),
                lastConsoleOutput: runner.consoleOutput,
                diagnosticsSummary: diags,
                gitDiffSummary: gitDiff,
                existingFileReader: { rel in
                    agentExistingFileReader(rel)
                }
            )
        }
    }

    private func fixRawErrorWithAgent(_ rawError: String) {
        let active = workspace.activeTab
        let relPath = active.map { workspace.relativePath(for: $0.fileURL) }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showRightAIPanel = true
        }
        let targetNote = relPath.map { "File hiện tại: \($0)\n" } ?? ""
        let prompt = "/fix \(targetNote)Hãy phân tích lỗi bên dưới, tìm nguyên nhân gốc rễ và sửa hoàn chỉnh bằng <file_edit>:\n```\n\(rawError)\n```"
        let diags = currentDiagnosticsSummary()
        let gitDiff = currentGitDiffSummary()
        Task {
            await aiService.sendPrompt(
                userPrompt: prompt,
                workspaceTree: workspace.workspaceSummaryTree(),
                activeFilePath: relPath,
                activeFileContent: active?.content,
                selectedSnippet: workspace.selectedSnippetInActiveTab(),
                lastConsoleOutput: runner.consoleOutput,
                diagnosticsSummary: diags,
                gitDiffSummary: gitDiff,
                existingFileReader: { rel in
                    agentExistingFileReader(rel)
                }
            )
        }
    }

    private func runSelectionAIAction(slashCommand: String, instruction: String) {
        guard let active = workspace.activeTab else { return }
        let relPath = workspace.relativePath(for: active.fileURL)
        let snippet = workspace.selectedSnippetInActiveTab()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showRightAIPanel = true
        }
        let prompt = "\(slashCommand) @selection (trong \(relPath))\n\(instruction)"
        let diags = currentDiagnosticsSummary()
        let gitDiff = currentGitDiffSummary()
        Task {
            await aiService.sendPrompt(
                userPrompt: prompt,
                workspaceTree: workspace.workspaceSummaryTree(),
                activeFilePath: relPath,
                activeFileContent: active.content,
                selectedSnippet: snippet,
                lastConsoleOutput: runner.consoleOutput,
                diagnosticsSummary: diags,
                gitDiffSummary: gitDiff,
                existingFileReader: { rel in
                    agentExistingFileReader(rel)
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

    private func isXtoolBuildContext(activeTab: OpenTab) -> Bool {
        let lowerName = activeTab.fileURL.lastPathComponent.lowercased()
        if lowerName == "xtool.yml" {
            return true
        }
        if lowerName == "package.swift" && xtoolService.isXtoolWorkspace(workspace.rootURL) {
            return true
        }
        return activeTab.language == .swift && xtoolService.isXtoolWorkspace(workspace.rootURL)
    }

    private func triggerSmartRun() {
        flushPendingSaveSideEffects()
        applyFormatOnSaveIfEnabled()
        workspace.saveActiveTab()
        flushPendingSaveSideEffects()
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

        if isXtoolBuildContext(activeTab: active) {
            if xtoolService.buildMode == .privateSSHVPS && !sshService.isConnected {
                showXtoolBuilderSheet = true
                return
            }
            workspace.saveAllTabs()
            bottomTab = .output
            withAnimation { showBottomPanel = true }
            xtoolService.startBuild(
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
                // Split Preview runs in-app; keep-alive activates lazily on Safari/Share
                liveServer.start(serving: workspace.rootURL, keepAliveInBackground: false)
            } else {
                liveServer.notifyFileChanged()
            }
            bottomTab = .livePreview
            withAnimation { showBottomPanel = true }
        } else {
            bottomTab = .output
            withAnimation { showBottomPanel = true }
            Task { @MainActor () -> Void in
                await runner.runCode(code: active.content, language: active.language, fileName: active.title, sshService: sshService)
            }
        }
    }

    private func formatActiveFile() {
        guard let active = workspace.activeTab else { return }
        let tabID = active.id
        let originalContent = active.content
        let lang = active.language
        let width = preferences.tabWidth
        Task { @MainActor () -> Void in
            let formatted = await CodeFormatterService.format(
                originalContent,
                language: lang,
                tabWidth: width,
                sshService: sshService
            )
            guard let current = workspace.activeTab,
                  current.id == tabID,
                  current.content == originalContent,
                  formatted != originalContent else { return }
            let docLen = (originalContent as NSString).length
            let nextToken = (completionRequest?.token ?? 0) + 1
            completionRequest = CompletionReplacementRequest(
                token: nextToken,
                range: NSRange(location: 0, length: docLen),
                replacement: formatted,
                cursorOffset: min(current.selectedRangeLocation, (formatted as NSString).length)
            )
            refreshIntelligenceForActiveTab()
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
        let nextToken = (completionRequest?.token ?? 0) + 1
        completionRequest = CompletionReplacementRequest(
            token: nextToken,
            range: NSRange(location: loc, length: len),
            replacement: snippet,
            cursorOffset: (snippet as NSString).length
        )
        refreshIntelligenceForActiveTab()
    }

    private func buildPaletteCommands() -> [(title: String, icon: String, action: () -> Void)] {
        [
            (preferences.tr("Chạy File hiện tại (Cmd+R)", "Run Active File (Cmd+R)"), "play.fill", { triggerSmartRun() }),
            (preferences.tr("Lưu File & Tạo Mốc Lịch Sử (Cmd+S)", "Save File & Record Snapshot (Cmd+S)"), "externaldrive.badge.checkmark", { saveActiveTabWithCheckpoint() }),
            (preferences.tr("Đi tới Symbol Outline trong File", "Go to Symbol Outline in File"), "list.bullet.indent", {
                if workspace.activeTab != nil { showSymbolOutlineSheet = true }
            }),
            (preferences.tr("Tìm kiếm & Thay thế trong File (Cmd+F)", "Find & Replace in File (Cmd+F)"), "magnifyingglass", { openInlineFindBar() }),
            (preferences.tr("Đi tới dòng (Go to Line) (Ctrl+G)", "Go to Line (Ctrl+G)"), "arrow.right.to.line", {
                if workspace.activeTab != nil {
                    goToLineInput = ""
                    showGoToLineAlert = true
                }
            }),
            (preferences.tr("Mở lại Tab vừa đóng (Cmd+Shift+T)", "Reopen Closed Tab (Cmd+Shift+T)"), "arrow.uturn.left.circle", { workspace.reopenLastClosedTab() }),
            (preferences.tr("Ghim / Bỏ ghim Tab đang mở", "Pin / Unpin Active Tab"), "pin", {
                if let activeID = workspace.activeTabID {
                    workspace.togglePinTab(activeID)
                }
            }),
            (preferences.tr("Đẩy dòng hiện tại lên trên (Alt+↑)", "Move Current Line Up (Alt+↑)"), "arrow.up.to.line", { triggerQuickAction(.moveLineUp) }),
            (preferences.tr("Đẩy dòng hiện tại xuống dưới (Alt+↓)", "Move Current Line Down (Alt+↓)"), "arrow.down.to.line", { triggerQuickAction(.moveLineDown) }),
            (preferences.tr("Mở Lịch sử Phiên bản File (Timeline)", "Open File Version Timeline (Restore Snapshot)"), "clock.arrow.circlepath", {
                if workspace.activeTab != nil { showTimelineSheet = true }
            }),
            (preferences.tr("Chế độ Toàn Màn Hình (Full-Screen Zen)", "Toggle Full-Screen Zen Mode"), "arrow.up.left.and.arrow.down.right", {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isFullScreenZenMode.toggle()
                }
            }),
            (preferences.tr("Bật/tắt Chú thích dòng (Cmd+/)", "Toggle Line Comment (Cmd+/)"), "number", { toggleCommentToken += 1 }),
            (preferences.tr("Bật/tắt Gợi ý Code thông minh", "Toggle Live Code Autocomplete") + " (\(preferences.enableCodeCompletion ? "ON" : "OFF"))", "text.cursor", {
                preferences.enableCodeCompletion.toggle()
            }),
            (preferences.tr("Bật/tắt Báo lỗi trực tiếp", "Toggle Inline Error Highlighting") + " (\(preferences.enableLiveDiagnostics ? "ON" : "OFF"))", "exclamationmark.triangle", {
                preferences.enableLiveDiagnostics.toggle()
            }),
            (preferences.tr("Mở Theme Studio (Tự chỉnh màu Code & App)", "Open Theme Studio (Customize Code & App Colors)"), "paintpalette", {
                showThemeStudioDirect = true
            }),
            (preferences.tr("Chọn Ngôn ngữ Code (64 Ngôn ngữ / Auto)", "Select Code Language Mode (64 Languages / Auto-Detect)"), "chevron.left.forwardslash.chevron.right", {
                if workspace.activeTab != nil { showLanguagePickerSheet = true }
            }),
            (preferences.tr("Format Document theo Ngôn ngữ (Cmd+Shift+F)", "Format Document by Language (Cmd+Shift+F)"), "text.alignleft", { formatActiveFile() }),
            (preferences.tr("Bật/tắt Tự động Format khi Lưu & Chạy", "Toggle Auto-Format on Save & Run") + " (\(preferences.formatOnSave ? "ON" : "OFF"))", "arrow.triangle.2.circlepath", {
                preferences.formatOnSave.toggle()
            }),
            (preferences.tr("Xem Problems & Báo lỗi trực tiếp", "Show Problems & Inline Diagnostics"), "checklist", { checkSyntaxAndLSPDiagnostics() }),
            (preferences.tr("Treo Bot Telegram & Chạy Ngầm Terminal 24/7 (Trên Máy)", "24/7 Background Terminal & Telegram Bot Runner (On-Device)"), "waveform.path.ecg", { showDaemonManagerSheet = true }),
            (preferences.tr("Tạo & Build Theos Tweak / Mod Menu (.deb / .dylib)", "Build Theos Tweak / Mod Menu (.deb / .dylib)"), "hammer.fill", { showTheosBuilderSheet = true }),
            (preferences.tr("xtool Studio — Build SwiftUI .ipa & Nhúng .dylib", "xtool Studio — Build SwiftUI .ipa & Inject .dylib"), "cube.transparent.fill", { showXtoolBuilderSheet = true }),
            (preferences.tr("Mở File lẻ trên máy (File)... (Cmd+O)", "Open File on Device (File)... (Cmd+O)"), "arrow.up.doc", {
                presentWorkspaceDocumentPicker(.singleFile, delay: 0.35)
            }),
            (preferences.tr("Mở Thư mục trên máy (Folder)...", "Open Folder on Device (Folder)..."), "folder.badge.gearshape", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showOpenFolderHubSheet = true
                }
            }),
            (preferences.tr("Nhập & Tự giải nén File .zip...", "Import & Auto-Extract .zip Archive..."), "doc.zipper", {
                presentWorkspaceDocumentPicker(.zip, delay: 0.35)
            }),
            (preferences.tr("Đồng bộ 2 chiều PC <-> Mobile (Wi-Fi / 4G)", "2-Way PC <-> Mobile Sync (Wi-Fi / 4G)"), "desktopcomputer", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showPCSyncSheet = true
                }
            }),
            (preferences.tr("Chia sẻ Link Live Preview (:\(liveServer.port))", "Share Live Preview Link (:\(liveServer.port))"), "dot.radiowaves.left.and.right", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if !liveServer.isRunning {
                        liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                    } else if preferences.keepServerInBackground {
                        liveServer.updateBackgroundKeepAlive(enabled: true)
                    }
                    liveServer.refreshLANAddress()
                    showLiveShareSheet = true
                }
            }),
            (preferences.tr("Bộ Công Cụ Dev (CP Judge / API / .env / Color)", "Developer Power Tools (CP Judge / API / .env / Color)"), "wrench.and.screwdriver.fill", {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showPowerToolsSheet = true
                }
            }),
            (preferences.tr("Xuất Dự án ra File .zip", "Export Project Workspace as .zip"), "square.and.arrow.up", { exportWorkspaceAsZipAndShare() }),
            (preferences.tr("Mở Live Server localhost:\(liveServer.port) trên Safari", "Open Live Server localhost:\(liveServer.port) in Safari"), "safari", {
                if !liveServer.isRunning {
                    liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                } else if preferences.keepServerInBackground {
                    liveServer.updateBackgroundKeepAlive(enabled: true)
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

    @ViewBuilder
    private func missingActiveFileSheetFallback(palette: IDEColorPalette, onDismiss: @escaping () -> Void) -> some View {
        CompatibleNavigationContainer {
            VStack(spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(Color(hex: palette.gutterForeground))
                Text(preferences.tr("Không có tệp nào đang mở.", "No active file open."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(preferences.tr("Đóng", "Done"), action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: palette.editorBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done"), action: onDismiss)
                }
            }
        }
    }
}

private struct HeaderToolsMenuView: View, Equatable {
    let appLanguage: AppLanguage
    let activeLanguageBadge: String
    let enableCodeCompletion: Bool
    let enableLiveDiagnostics: Bool
    let formatOnSave: Bool
    let liveServerRunning: Bool
    let liveServerPort: UInt16
    let isShareLinkEnabled: Bool
    let sharedViewerCount: Int
    let sshConnected: Bool
    let pcSyncConnected: Bool
    let pcSyncTransportLabel: String
    let isFullScreenZen: Bool
    let foregroundHex: String
    let accentHex: String

    let onCommandPalette: () -> Void
    let onSaveSnapshot: () -> Void
    let onSymbolOutline: () -> Void
    let onTimeline: () -> Void
    let onSetCodeCompletion: (Bool) -> Void
    let onSetLiveDiagnostics: (Bool) -> Void
    let onSetFormatOnSave: (Bool) -> Void
    let onLanguagePicker: () -> Void
    let onFormatDocument: () -> Void
    let onToggleFullScreenZen: () -> Void
    let onOpenSafari: () -> Void
    let onOpenLiveShare: () -> Void
    let onOpenSplitPreview: () -> Void
    let onToggleTerminal: () -> Void
    let onOpenFindBar: () -> Void
    let onOpenPCSync: () -> Void
    let onOpenPowerTools: () -> Void
    let onScaffoldStarter: (ProjectStarterKind) -> Void
    let onOpenDaemonManager: () -> Void
    let onOpenTheos: () -> Void
    let onOpenXtool: () -> Void
    let onPickFile: () -> Void
    let onPickFolder: () -> Void
    let onPickZip: () -> Void
    let onExportZip: () -> Void
    let onOpenThemeStudio: () -> Void
    let onSelectLanguage: (AppLanguage) -> Void
    let onOpenSettings: () -> Void
    let tr: (String, String, String?, String?, String?, String?, String?) -> String
    let langDisplayName: (AppLanguage) -> String

    static func == (lhs: HeaderToolsMenuView, rhs: HeaderToolsMenuView) -> Bool {
        lhs.appLanguage == rhs.appLanguage &&
        lhs.activeLanguageBadge == rhs.activeLanguageBadge &&
        lhs.enableCodeCompletion == rhs.enableCodeCompletion &&
        lhs.enableLiveDiagnostics == rhs.enableLiveDiagnostics &&
        lhs.formatOnSave == rhs.formatOnSave &&
        lhs.liveServerRunning == rhs.liveServerRunning &&
        lhs.liveServerPort == rhs.liveServerPort &&
        lhs.isShareLinkEnabled == rhs.isShareLinkEnabled &&
        lhs.sharedViewerCount == rhs.sharedViewerCount &&
        lhs.sshConnected == rhs.sshConnected &&
        lhs.pcSyncConnected == rhs.pcSyncConnected &&
        lhs.pcSyncTransportLabel == rhs.pcSyncTransportLabel &&
        lhs.isFullScreenZen == rhs.isFullScreenZen &&
        lhs.foregroundHex == rhs.foregroundHex &&
        lhs.accentHex == rhs.accentHex
    }

    var body: some View {
        Menu {
            Button(action: onCommandPalette) {
                Label(tr("Command Palette & Mở nhanh", "Command Palette & Quick Open", nil, nil, nil, nil, nil), systemImage: "command")
            }

            Button(action: onToggleFullScreenZen) {
                Label(
                    isFullScreenZen
                        ? tr("Thoát Toàn Màn Hình", "Exit Full-Screen Zen", nil, nil, nil, nil, nil)
                        : tr("Toàn Màn Hình (Full-Screen Zen)", "Full-Screen Zen Mode", nil, nil, nil, nil, nil),
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
            }

            Button(action: onSaveSnapshot) {
                Label(tr("Lưu File & Tạo Mốc Lịch Sử", "Save File & Record Snapshot", nil, nil, nil, nil, nil), systemImage: "externaldrive.badge.checkmark")
            }

            Button(action: onSymbolOutline) {
                Label(tr("Danh sách Hàm / Class (Symbol Outline)", "Symbol Outline (Functions / Classes)", nil, nil, nil, nil, nil), systemImage: "list.bullet.indent")
            }

            Button(action: onTimeline) {
                Label(tr("Lịch sử Phiên bản File (Timeline)", "File Version Timeline", nil, nil, nil, nil, nil), systemImage: "clock.arrow.circlepath")
            }

            Divider()

            Toggle(isOn: Binding(get: { enableCodeCompletion }, set: onSetCodeCompletion)) {
                Label(tr("Gợi ý Code thông minh (Smart IntelliSense)", "Smart Code IntelliSense", nil, nil, nil, nil, nil), systemImage: "text.cursor")
            }

            Toggle(isOn: Binding(get: { enableLiveDiagnostics }, set: onSetLiveDiagnostics)) {
                Label(tr("Báo lỗi trực tiếp trên Editor", "Inline Error Diagnostics", nil, nil, nil, nil, nil), systemImage: "exclamationmark.triangle")
            }

            Toggle(isOn: Binding(get: { formatOnSave }, set: onSetFormatOnSave)) {
                Label(tr("Tự động Format khi Lưu / Chạy", "Auto-Format on Save / Run", nil, nil, nil, nil, nil), systemImage: "arrow.triangle.2.circlepath")
            }

            Button(action: onLanguagePicker) {
                Label(tr("Chọn Ngôn ngữ Code", "Code Language Mode", nil, nil, nil, nil, nil) + " (\(activeLanguageBadge))", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button(action: onFormatDocument) {
                Label(tr("Format Document theo Ngôn ngữ", "Format Document by Language", nil, nil, nil, nil, nil), systemImage: "text.alignleft")
            }

            Divider()

            Button(action: onOpenSafari) {
                Label(tr("Mở localhost:\(liveServerPort) trên Safari", "Open localhost:\(liveServerPort) in Safari", nil, nil, nil, nil, nil), systemImage: "safari")
            }

            Button(action: onOpenLiveShare) {
                Label(
                    isShareLinkEnabled
                        ? tr("Chia sẻ Live Preview (BẬT • \(sharedViewerCount))", "Share Live Preview (ON • \(sharedViewerCount))", nil, nil, nil, nil, nil)
                        : tr("Chia sẻ Link Live Preview (:\(liveServerPort))...", "Share Live Preview Link (:\(liveServerPort))...", nil, nil, nil, nil, nil),
                    systemImage: "dot.radiowaves.left.and.right"
                )
            }

            Button(action: onOpenSplitPreview) {
                Label(tr("Xem Split Preview & Web F12", "Open Split Preview & Web F12", nil, nil, nil, nil, nil), systemImage: "rectangle.split.1x2")
            }

            Button(action: onToggleTerminal) {
                Label(
                    sshConnected
                        ? tr("Mở SSH PTY Terminal (SwiftTerm)", "Open SSH PTY Terminal (SwiftTerm)", nil, nil, nil, nil, nil)
                        : tr("Mở Terminal (SwiftTerm)", "Open Terminal (SwiftTerm)", nil, nil, nil, nil, nil),
                    systemImage: "terminal"
                )
            }

            Button(action: onOpenFindBar) {
                Label(tr("Tìm kiếm & Thay thế", "Find & Replace", nil, nil, nil, nil, nil), systemImage: "magnifyingglass")
            }

            Divider()

            Button(action: onOpenPCSync) {
                Label(
                    pcSyncConnected
                        ? tr("Đồng bộ PC <-> Mobile (\(pcSyncTransportLabel))", "PC <-> Mobile Sync (\(pcSyncTransportLabel))", nil, nil, nil, nil, nil)
                        : tr("Đồng bộ 2 chiều PC <-> Mobile (Wi-Fi & 4G/5G)...", "2-Way PC <-> Mobile Sync (Wi-Fi & 4G/5G)...", nil, nil, nil, nil, nil),
                    systemImage: "desktopcomputer"
                )
            }

            Button(action: onOpenPowerTools) {
                Label(tr("Bộ Công Cụ Developer (CP Judge / API / .env / Color)...", "Developer Power Tools (CP Judge / API / .env / Color)...", nil, nil, nil, nil, nil), systemImage: "wrench.and.screwdriver.fill")
            }

            Menu {
                Button { onScaffoldStarter(.modernWebLanding) } label: {
                    Label("Web HTML/CSS/JS Live", systemImage: "globe")
                }
                Button { onScaffoldStarter(.cppCompetitive) } label: {
                    Label("C++20 Competitive", systemImage: "cpu")
                }
                Button { onScaffoldStarter(.pythonAutomation) } label: {
                    Label("Python 3.12 Automation", systemImage: "terminal")
                }
                Button { onScaffoldStarter(.markdownDocs) } label: {
                    Label("Markdown + Mermaid Docs", systemImage: "doc.richtext")
                }
            } label: {
                Label(tr("Tạo Dự Án Mẫu (Starter Templates)", "Starter Templates", nil, nil, nil, nil, nil), systemImage: "rectangle.stack.badge.plus")
            }

            Divider()

            Button(action: onOpenDaemonManager) {
                Label(
                    tr(
                        "Treo Bot & Chạy Ngầm Terminal (24/7 Trên Máy)",
                        "24/7 Background Terminal & Bot Runner (On-Device)",
                        "24/7 本机后台终端与 Bot 运行器",
                        "24/7 端末内バックグラウンド＆Bot",
                        "24/7 기기 내 백그라운드 & 봇 실행",
                        "Локальный 24/7 терминал и боты",
                        "Terminal y Bots 24/7 (Local)"
                    ),
                    systemImage: "waveform.path.ecg"
                )
            }

            Button(action: onOpenTheos) {
                Label(tr("Tạo & Build Theos Tweak / Mod Menu (.deb / .dylib)", "Build Theos Tweak / Mod Menu (.deb / .dylib)", nil, nil, nil, nil, nil), systemImage: "hammer.fill")
            }

            Button(action: onOpenXtool) {
                Label(tr("xtool Studio (Build SwiftUI .ipa & Nhúng .dylib)", "xtool Studio (Build SwiftUI .ipa & Inject .dylib)", nil, nil, nil, nil, nil), systemImage: "cube.transparent.fill")
            }

            Button(action: onPickFile) {
                Label(tr("Mở File lẻ trên máy (File)...", "Open File on Device (File)...", nil, nil, nil, nil, nil), systemImage: "arrow.up.doc")
            }

            Button(action: onPickFolder) {
                Label(tr("Mở Thư mục trên máy (Folder)...", "Open Folder on Device (Folder)...", nil, nil, nil, nil, nil), systemImage: "folder.badge.gearshape")
            }

            Button(action: onPickZip) {
                Label(tr("Nhập & Tự giải nén File .zip...", "Import & Auto-Extract .zip File...", nil, nil, nil, nil, nil), systemImage: "doc.zipper")
            }

            Button(action: onExportZip) {
                Label(tr("Xuất Dự án ra File .zip", "Export Project Workspace as .zip", nil, nil, nil, nil, nil), systemImage: "square.and.arrow.up")
            }

            Button(action: onOpenThemeStudio) {
                Label(tr("Theme Studio (Tự chỉnh màu Code & App)", "Theme Studio (Customize Code & App Colors)", nil, nil, nil, nil, nil), systemImage: "paintpalette")
            }

            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        onSelectLanguage(lang)
                    } label: {
                        if appLanguage == lang {
                            Label("\(lang.shortBadge) — \(langDisplayName(lang))", systemImage: "checkmark")
                        } else {
                            Text("\(lang.shortBadge) — \(langDisplayName(lang))")
                        }
                    }
                }
            } label: {
                Label(
                    tr("Ngôn ngữ App", "App Language", "应用语言", "アプリ言語", "앱 언어", "Язык приложения", "Idioma de la app") + " (\(appLanguage.shortBadge))",
                    systemImage: "globe"
                )
            }

            Button(action: onOpenSettings) {
                Label(tr("Theme, Font & Cài đặt", "Themes, Fonts & Settings", nil, nil, nil, nil, nil), systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: liveServerRunning ? "antenna.radiowaves.left.and.right" : "ellipsis.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(liveServerRunning ? .green : Color(hex: foregroundHex))
                .frame(width: 28, height: 30)
        }
    }
}
