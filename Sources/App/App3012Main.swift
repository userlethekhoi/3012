import SwiftUI

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
                extStore: extStore
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

    @State private var showLeftExplorer: Bool = false
    @State private var showRightAIPanel: Bool = false
    @State private var showBottomPanel: Bool = false
    @State private var bottomTab: BottomPanelTab = .terminal
    @State private var bottomDetent: BottomPanelDetent = .half
    @State private var showSettingsSheet: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var findTriggerToken: Int = 0

    public var body: some View {
        let palette = preferences.activePalette

        GeometryReader { geo in
            let isWideLayout = geo.size.width >= 680

            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    // 1. Ultra-Slim 38pt Top Header Bar (~90% screen preserved for code!)
                    topHeaderBar(palette: palette)

                    // 2. Central Workspace Area (Editor + Optional Side-by-Side AI on wide screens)
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if let activeTab = workspace.activeTab {
                                RunestoneEditorView(
                                    fileURL: activeTab.fileURL,
                                    text: activeTab.content,
                                    language: activeTab.language,
                                    preferences: preferences,
                                    findTriggerToken: findTriggerToken,
                                    onTextChange: { updatedCode, range in
                                        workspace.updateActiveContent(updatedCode, selectedRange: range)
                                    },
                                    onSelectionChange: { range in
                                        workspace.updateSelectionOnly(range)
                                    },
                                    onToggleAI: {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                            showRightAIPanel.toggle()
                                        }
                                    }
                                )
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
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showBottomPanel = false
                                        }
                                    }
                                )
                                .frame(height: bottomDetent.height(in: geo.size.height))
                            }
                        }

                        // Side-by-side AI Agent Panel when screen is wide (Landscape iPhone / iPad)
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

                // Right AI Coding Agent Drawer (Portrait Overlay mode)
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
            workspace.onAnyTabSavedWithURL = { [weak sshService] fileURL, updatedText in
                sshService?.syncSavedLocalMirrorIfNeeded(localURL: fileURL, content: updatedText)
            }
            liveServer.start(
                serving: workspace.rootURL,
                keepAliveInBackground: preferences.keepServerInBackground
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsAndThemesSheet(
                preferences: preferences,
                liveServer: liveServer,
                runner: runner
            )
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteSheet(
                workspace: workspace,
                preferences: preferences,
                commands: buildPaletteCommands()
            )
        }
    }

    @ViewBuilder
    private func topHeaderBar(palette: IDEColorPalette) -> some View {
        HStack(spacing: 5) {
            // Activity Drawer Button (with green dot when SSH VPS connected!)
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
                            Image(systemName: isRemoteSFTP ? "cloud.fill" : tab.language.systemIcon)
                                .font(.system(size: 10))
                                .foregroundColor(isRemoteSFTP ? .cyan : Color(hex: palette.accent))
                            Text(tab.title)
                                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                .foregroundColor(Color(hex: isSelected ? palette.foreground : palette.gutterForeground))
                                .lineLimit(1)
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

            // 1-Tap Smart Run Button (Local / VPS SSH / Live Server)
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

            // Tools & Live Server Menu
            Menu {
                Button {
                    showCommandPalette = true
                } label: {
                    Label("Command Palette & Quick Open", systemImage: "command")
                }

                Button {
                    formatActiveFile()
                } label: {
                    Label("Format Document (Làm đẹp Code)", systemImage: "wand.and.stars")
                }

                Button {
                    checkSyntaxAndLSPDiagnostics()
                } label: {
                    Label("Kiểm tra Lỗi Cú pháp / Remote LSP", systemImage: "checkmark.shield")
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
                    Label("Xem Split Preview trong App", systemImage: "rectangle.bottomhalf.inset.filled")
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

                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Theme, Font & Cài đặt", systemImage: "paintbrush")
                }
            } label: {
                Image(systemName: liveServer.isRunning ? "globe.badge.chevron.backward" : "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(liveServer.isRunning ? .green : Color(hex: palette.foreground))
                    .frame(width: 28, height: 30)
            }

            // AI Coding Agent Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showRightAIPanel.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text("AI")
                        .font(.system(size: 11.5, weight: .bold))
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
    private func emptyEditorPlaceholder(palette: IDEColorPalette) -> some View {
        VStack(spacing: 14) {
            Text("3012")
                .font(.system(size: 34, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: palette.accent))
            Text("Vuốt mép trái: Explorer • Git • SSH SFTP • OpenVSX\nVuốt mép phải: AI Coding Agent")
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

    private func triggerSmartRun() {
        workspace.saveActiveTab()
        guard let active = workspace.activeTab else { return }

        if active.language == .html || active.language == .css {
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
            let formatted = await ExtensionStoreService.formatCode(
                active.content,
                language: active.language,
                tabWidth: preferences.tabWidth,
                sshService: sshService
            )
            workspace.updateActiveContent(formatted)
        }
    }

    private func checkSyntaxAndLSPDiagnostics() {
        guard let active = workspace.activeTab else { return }
        bottomTab = .output
        withAnimation { showBottomPanel = true }
        Task {
            let report = await ExtensionStoreService.runSyntaxDiagnostics(
                code: active.content,
                language: active.language,
                fileName: active.title,
                sshService: sshService
            )
            runner.consoleOutput = report
        }
    }

    private func insertTextIntoActiveTab(_ snippet: String) {
        guard let active = workspace.activeTab else { return }
        let ns = active.content as NSString
        let loc = min(max(0, active.selectedRangeLocation), ns.length)
        let len = min(max(0, active.selectedRangeLength), ns.length - loc)
        let updated = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: snippet)
        workspace.updateActiveContent(updated, selectedRange: NSRange(location: loc + (snippet as NSString).length, length: 0))
    }

    private func buildPaletteCommands() -> [(title: String, icon: String, action: () -> Void)] {
        [
            ("Run Active File (▶ Run)", "play.fill", { triggerSmartRun() }),
            ("Format Document (clang-format / prettier / built-in)", "wand.and.stars", { formatActiveFile() }),
            ("Run Syntax & Remote LSP Diagnostics", "checkmark.shield", { checkSyntaxAndLSPDiagnostics() }),
            ("Open Live Server localhost:\(liveServer.port) in Safari", "safari", {
                if !liveServer.isRunning {
                    liveServer.start(serving: workspace.rootURL, keepAliveInBackground: preferences.keepServerInBackground)
                }
                liveServer.openInSafari()
            }),
            ("Toggle Xterm / SSH PTY Terminal", "terminal", {
                bottomTab = .terminal
                withAnimation { showBottomPanel.toggle() }
            }),
            ("Toggle AI Coding Agent Panel", "sparkles", {
                withAnimation { showRightAIPanel.toggle() }
            }),
            ("Open Themes, Fonts & IDE Settings", "paintbrush", {
                showSettingsSheet = true
            })
        ]
    }
}
