import SwiftUI
import WebKit
import UIKit

public enum BottomPanelTab: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case problems = "Problems"
    case output = "Output"
    case livePreview = "Live :5500"

    public var id: String { rawValue }
}

public enum BottomPanelDetent: CaseIterable {
    case compact
    case half
    case expanded

    public func height(in totalHeight: CGFloat) -> CGFloat {
        switch self {
        case .compact: return min(max(totalHeight * 0.28, 175), 230)
        case .half: return min(max(totalHeight * 0.46, 260), 390)
        case .expanded: return max(totalHeight * 0.76, 410)
        }
    }

    public var next: BottomPanelDetent {
        switch self {
        case .compact: return .half
        case .half: return .expanded
        case .expanded: return .compact
        }
    }
}

public enum WebViewportPreset: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case mobile = "390px"
    case tablet = "768px"
    case desktop = "1280px"

    public var id: String { rawValue }

    public var targetWidth: CGFloat? {
        switch self {
        case .auto: return nil
        case .mobile: return 390
        case .tablet: return 768
        case .desktop: return 1280
        }
    }
}

public struct WebDevToolsLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let level: String // "log", "warn", "error", "result"
    public let message: String
    public let timestamp: Date = Date()
}

public struct BottomConsolePreviewPanel: View {
    @Binding var selectedTab: BottomPanelTab
    @Binding var detent: BottomPanelDetent
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var daemonService: LocalDaemonService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var intelligence: CodeIntelligenceService
    @ObservedObject var aiService: AIAgentService
    @ObservedObject var gitService: GitService
    var xtoolService: XtoolBuildService? = nil
    var onJumpToLine: (Int) -> Void
    var onFixDiagnosticWithAgent: (EditorDiagnostic) -> Void
    var onOpenDaemonManager: () -> Void
    var onClose: () -> Void

    @State private var selectedPreviewPort: UInt16? = nil
    @State private var viewportPreset: WebViewportPreset = .auto
    @State private var showWebConsoleDrawer: Bool = false
    @State private var webConsoleLogs: [WebDevToolsLogEntry] = []
    @State private var jsEvalInput: String = ""
    @State private var jsEvalTrigger: (token: Int, script: String)? = nil

    public init(
        selectedTab: Binding<BottomPanelTab>,
        detent: Binding<BottomPanelDetent>,
        runner: CodeRunnerService,
        liveServer: LiveServerService,
        sshService: SSHWorkspaceService,
        daemonService: LocalDaemonService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        intelligence: CodeIntelligenceService,
        aiService: AIAgentService,
        gitService: GitService,
        xtoolService: XtoolBuildService? = nil,
        onJumpToLine: @escaping (Int) -> Void,
        onFixDiagnosticWithAgent: @escaping (EditorDiagnostic) -> Void,
        onOpenDaemonManager: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self._detent = detent
        self.runner = runner
        self.liveServer = liveServer
        self.sshService = sshService
        self.daemonService = daemonService
        self.workspace = workspace
        self.preferences = preferences
        self.intelligence = intelligence
        self.aiService = aiService
        self.gitService = gitService
        self.xtoolService = xtoolService
        self.onJumpToLine = onJumpToLine
        self.onFixDiagnosticWithAgent = onFixDiagnosticWithAgent
        self.onOpenDaemonManager = onOpenDaemonManager
        self.onClose = onClose
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Compact Panel Header with 3-detent resize & Safari launcher
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(BottomPanelTab.allCases) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                HStack(spacing: 4) {
                                    if tab == .livePreview && liveServer.isRunning {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                    } else if tab == .terminal && sshService.isConnected {
                                        Circle().fill(Color.cyan).frame(width: 6, height: 6)
                                    } else if tab == .problems && !intelligence.diagnostics.isEmpty {
                                        Circle()
                                            .fill(intelligence.errorCount > 0 ? Color.red : Color.orange)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(tabLabel(tab))
                                        .font(.system(size: 11.5, weight: selectedTab == tab ? .bold : .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedTab == tab ? Color(hex: palette.currentLineBackground) : Color.clear)
                                .foregroundColor(selectedTab == tab ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                                .cornerRadius(6)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if selectedTab == .livePreview {
                    // Web F12 Console Toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showWebConsoleDrawer.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "ladybug")
                                .font(.system(size: 11, weight: .semibold))
                            Text("F12")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            if webConsoleLogs.contains(where: { $0.level == "error" }) {
                                Circle().fill(Color.red).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(showWebConsoleDrawer ? Color(hex: palette.accent) : Color(hex: palette.currentLineBackground))
                        .foregroundColor(showWebConsoleDrawer ? .white : Color(hex: palette.foreground))
                        .cornerRadius(6)
                    }

                    if !sshService.activeTunnels.isEmpty {
                        Menu {
                            Button("Local Live Server (:\(liveServer.port))") {
                                selectedPreviewPort = nil
                            }
                            ForEach(sshService.activeTunnels) { t in
                                Button("SSH Tunnel localhost:\(t.localPort)") {
                                    selectedPreviewPort = t.localPort
                                }
                            }
                        } label: {
                            Image(systemName: "network")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                    }

                    Button {
                        openCurrentPreviewInSafari()
                    } label: {
                        Label("Safari", systemImage: "safari.fill")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                } else if selectedTab == .terminal {
                    Button {
                        daemonService.keepTerminalAliveInBackground.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(daemonService.isKeepAliveActive ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(daemonService.keepTerminalAliveInBackground
                                 ? preferences.tr("24/7 Ngầm: ON", "24/7 BG: ON")
                                 : preferences.tr("24/7 Ngầm: OFF", "24/7 BG: OFF"))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(daemonService.isKeepAliveActive ? Color.green.opacity(0.18) : Color(hex: palette.currentLineBackground))
                        .foregroundColor(daemonService.isKeepAliveActive ? .green : Color(hex: palette.gutterForeground))
                        .cornerRadius(6)
                    }

                    Button {
                        onOpenDaemonManager()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "paperplane.circle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(preferences.tr("Treo Bot", "Daemons") + " (\(daemonService.runningJobsCount))")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(hex: palette.accent).opacity(0.2))
                        .foregroundColor(Color(hex: palette.accent))
                        .cornerRadius(6)
                    }
                } else if selectedTab == .output {
                    Button {
                        runner.consoleOutput = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                    }
                }

                // Cycle 3 Detent Sizes (Compact -> Half -> Full)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        detent = detent.next
                    }
                } label: {
                    Image(systemName: detent == .expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: palette.headerBackground))

            Divider().overlay(Color.white.opacity(0.08))

            Group {
                switch selectedTab {
                case .terminal:
                    SwiftTermTerminalContainer(
                        sshService: sshService,
                        runner: runner,
                        daemonService: daemonService,
                        workspace: workspace,
                        preferences: preferences,
                        aiService: aiService,
                        gitService: gitService,
                        xtoolService: xtoolService
                    )
                case .problems:
                    problemsListView(palette: palette)
                case .output:
                    outputView(palette: palette)
                case .livePreview:
                    liveWebPreviewBody(palette: palette)
                }
            }
        }
        .background(Color(hex: palette.sidebarBackground))
    }

    private func tabLabel(_ tab: BottomPanelTab) -> String {
        switch tab {
        case .terminal:
            return sshService.isConnected ? "SSH PTY" : "Terminal"
        case .problems:
            let count = intelligence.diagnostics.count
            let title = preferences.tr("Vấn đề", "Problems", zh: "问题", ja: "問題", ko: "문제", ru: "Проблемы", es: "Problemas")
            return count > 0 ? "\(title) (\(count))" : title
        case .output:
            return preferences.tr("Kết quả", "Output", zh: "输出", ja: "出力", ko: "출력", ru: "Вывод", es: "Salida")
        case .livePreview:
            if let customPort = selectedPreviewPort {
                return "Tunnel :\(customPort)"
            }
            return "Live :\(liveServer.port)"
        }
    }

    private func openCurrentPreviewInSafari() {
        if let tunnelPort = selectedPreviewPort,
           let url = URL(string: "http://localhost:\(tunnelPort)") {
            liveServer.updateBackgroundKeepAlive(enabled: preferences.keepServerInBackground)
            UIApplication.shared.open(url)
            return
        }
        if !liveServer.isRunning {
            liveServer.start(
                serving: workspace.rootURL,
                keepAliveInBackground: preferences.keepServerInBackground
            )
        }
        liveServer.openInSafari(relativePath: activeHTMLRelativePath())
    }

    // MARK: - Problems Tab (Live Diagnostics List + 1-Tap Jump + Fix with Agent)
    @ViewBuilder
    private func problemsListView(palette: IDEColorPalette) -> some View {
        if !preferences.enableLiveDiagnostics {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: palette.gutterForeground))
                Text(preferences.tr("Tính năng báo lỗi trực tiếp đang tắt.", "Inline error diagnostics is currently disabled."))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color(hex: palette.foreground))
                Button(preferences.tr("Bật lại Báo lỗi trực tiếp", "Enable Inline Diagnostics")) {
                    preferences.enableLiveDiagnostics = true
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: palette.accent))
                .foregroundColor(.white)
                .cornerRadius(7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if intelligence.diagnostics.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 26))
                    .foregroundColor(.green)
                Text(preferences.tr("Không phát hiện lỗi cú pháp trong file đang mở.", "No syntax issues found in the active file."))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Color(hex: palette.gutterForeground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(intelligence.diagnostics) { diag in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diag.severity.systemIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(diag.severity == .error ? .red : .orange)
                                .padding(.top, 2)

                            Button {
                                onJumpToLine(diag.line)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(diag.message)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(hex: palette.foreground))
                                        .multilineTextAlignment(.leading)
                                    Text("Dòng \(diag.line), Cột \(diag.column) — Chạm để nhảy tới dòng lỗi")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Color(hex: palette.gutterForeground))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                onFixDiagnosticWithAgent(diag)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "cpu")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Sửa")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: palette.accent).opacity(0.2))
                                .foregroundColor(Color(hex: palette.accent))
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                        .background(Color(hex: palette.editorBackground))
                        .cornerRadius(7)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Output & Stdin View
    @ViewBuilder
    private func outputView(palette: IDEColorPalette) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(runner.consoleOutput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: palette.foreground))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                Text("stdin:")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: palette.gutterForeground))
                TextField("Dữ liệu nhập cho cin / scanf / input()...", text: $runner.stdinInput)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: palette.headerBackground))
        }
    }

    // MARK: - Live Web Preview + Responsive Viewport + F12 Web DevTools
    @ViewBuilder
    private func liveWebPreviewBody(palette: IDEColorPalette) -> some View {
        if let activeURL = resolvedPreviewURL() {
            VStack(spacing: 0) {
                // Sub-toolbar: URL + Viewport Responsive Presets (Auto / 390px / 768px / 1280px)
                HStack(spacing: 6) {
                    Image(systemName: selectedPreviewPort != nil ? "point.3.connected.trianglepath.dotted" : (liveServer.isBackgroundKeepAliveActive ? "antenna.radiowaves.left.and.right" : "globe"))
                        .font(.system(size: 10))
                        .foregroundColor(selectedPreviewPort != nil ? .cyan : .green)

                    Text(activeURL.absoluteString)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .lineLimit(1)

                    Spacer()

                    ForEach(WebViewportPreset.allCases) { preset in
                        Button {
                            viewportPreset = preset
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 9.5, weight: viewportPreset == preset ? .bold : .regular, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(viewportPreset == preset ? Color(hex: palette.accent).opacity(0.24) : Color.clear)
                                .foregroundColor(viewportPreset == preset ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: palette.editorBackground))

                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: viewportPreset != .auto) {
                        LiveServerWebView(
                            url: activeURL,
                            reloadToken: liveServer.reloadVersion,
                            jsEvalTrigger: jsEvalTrigger,
                            onConsoleLog: { entry in
                                webConsoleLogs.append(entry)
                                if webConsoleLogs.count > 120 {
                                    webConsoleLogs.removeFirst(webConsoleLogs.count - 120)
                                }
                            }
                        )
                        .frame(
                            width: viewportPreset.targetWidth ?? proxy.size.width,
                            height: proxy.size.height
                        )
                    }
                }

                // F12 Web DevTools Console + Live JS Eval Drawer
                if showWebConsoleDrawer {
                    Divider().overlay(Color.white.opacity(0.12))
                    VStack(spacing: 0) {
                        HStack {
                            Label("Web Console (F12)", systemImage: "terminal")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(Color(hex: palette.accent))
                            Spacer()
                            Button {
                                webConsoleLogs.removeAll()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(hex: palette.headerBackground))

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                if webConsoleLogs.isEmpty {
                                    Text("Chưa có log từ console.log / console.error hoặc chạy thử lệnh JS bên dưới...")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Color(hex: palette.gutterForeground))
                                } else {
                                    ForEach(webConsoleLogs) { item in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: iconForWebLevel(item.level))
                                                .font(.system(size: 10))
                                                .foregroundColor(colorForWebLevel(item.level, palette: palette))
                                                .padding(.top, 2)
                                            Text(item.message)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(colorForWebLevel(item.level, palette: palette))
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .frame(height: 82)
                        .background(Color(hex: palette.editorBackground))

                        Divider().overlay(Color.white.opacity(0.08))

                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: palette.accent))
                            TextField("Chạy JS trên trang (vd: document.title)...", text: $jsEvalInput)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(Color(hex: palette.foreground))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onSubmit {
                                    triggerJSEval()
                                }
                            Button("Eval") {
                                triggerJSEval()
                            }
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: palette.accent))
                            .foregroundColor(.white)
                            .cornerRadius(5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: palette.headerBackground))
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Text("Live Server chưa bật.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: palette.foreground))
                Button {
                    liveServer.start(
                        serving: workspace.rootURL,
                        keepAliveInBackground: preferences.keepServerInBackground
                    )
                } label: {
                    Label("Khởi động Live Server (:5500)", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resolvedPreviewURL() -> URL? {
        if let tunnelPort = selectedPreviewPort {
            return URL(string: "http://127.0.0.1:\(tunnelPort)")
        }
        guard liveServer.isRunning else { return nil }
        let encoded = LiveServerService.encodeRelativePath(activeHTMLRelativePath())
        if encoded.isEmpty {
            return URL(string: liveServer.serverBaseURLString)
        }
        return URL(string: "\(liveServer.serverBaseURLString)/\(encoded)")
    }

    private func triggerJSEval() {
        let code = jsEvalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        let nextToken = (jsEvalTrigger?.token ?? 0) + 1
        jsEvalTrigger = (nextToken, code)
        jsEvalInput = ""
    }

    private func iconForWebLevel(_ level: String) -> String {
        switch level {
        case "error": return "xmark.octagon"
        case "warn": return "exclamationmark.triangle"
        case "result": return "arrow.turn.down.right"
        default: return "info.circle"
        }
    }

    private func colorForWebLevel(_ level: String, palette: IDEColorPalette) -> Color {
        switch level {
        case "error": return .red
        case "warn": return .orange
        case "result": return Color(hex: palette.accent)
        default: return Color(hex: palette.foreground)
        }
    }

    private func activeHTMLRelativePath() -> String {
        if let tab = workspace.activeTab, tab.language == .html {
            return workspace.relativePath(for: tab.fileURL)
        }
        if let htmlTab = workspace.openTabs.first(where: { $0.language == .html }) {
            return workspace.relativePath(for: htmlTab.fileURL)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: workspace.rootURL.appendingPathComponent("index.html").path) {
            return "index.html"
        }
        if let firstHTML = (try? fm.contentsOfDirectory(atPath: workspace.rootURL.path))?
            .sorted()
            .first(where: { name in
                let lower = name.lowercased()
                return lower.hasSuffix(".html") || lower.hasSuffix(".htm")
            }) {
            return firstHTML
        }
        return "index.html"
    }
}

private struct LiveServerWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    let jsEvalTrigger: (token: Int, script: String)?
    let onConsoleLog: (WebDevToolsLogEntry) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onConsoleLog: onConsoleLog)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let contentController = WKUserContentController()
        let consoleBridgeJS = """
        (function() {
          function sendTo3012(level, args) {
            try {
              var msg = Array.prototype.slice.call(args).map(function(x) {
                if (typeof x === 'object') { try { return JSON.stringify(x); } catch(e) { return String(x); } }
                return String(x);
              }).join(' ');
              window.webkit.messageHandlers.ide3012Console.postMessage({ level: level, message: msg });
            } catch (_) {}
          }
          var origLog = console.log, origWarn = console.warn, origErr = console.error;
          console.log = function() { sendTo3012('log', arguments); if (origLog) origLog.apply(console, arguments); };
          console.warn = function() { sendTo3012('warn', arguments); if (origWarn) origWarn.apply(console, arguments); };
          console.error = function() { sendTo3012('error', arguments); if (origErr) origErr.apply(console, arguments); };
          window.addEventListener('error', function(ev) {
            sendTo3012('error', [ev.message + ' (' + (ev.filename || 'inline') + ':' + ev.lineno + ')']);
          });
        })();
        """
        let userScript = WKUserScript(source: consoleBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        contentController.add(context.coordinator, name: "ide3012Console")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        context.coordinator.loadedURL = url
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onConsoleLog = onConsoleLog
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }

        if let eval = jsEvalTrigger, eval.token != context.coordinator.lastEvalToken {
            context.coordinator.lastEvalToken = eval.token
            webView.evaluateJavaScript(eval.script) { result, error in
                if let error {
                    onConsoleLog(WebDevToolsLogEntry(level: "error", message: error.localizedDescription))
                } else if let result {
                    onConsoleLog(WebDevToolsLogEntry(level: "result", message: "\(result)"))
                } else {
                    onConsoleLog(WebDevToolsLogEntry(level: "result", message: "undefined"))
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "ide3012Console")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedURL: URL?
        var lastReloadToken: Int = 0
        var lastEvalToken: Int = 0
        var onConsoleLog: (WebDevToolsLogEntry) -> Void

        init(onConsoleLog: @escaping (WebDevToolsLogEntry) -> Void) {
            self.onConsoleLog = onConsoleLog
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "ide3012Console",
                  let body = message.body as? [String: Any] else { return }
            let level = (body["level"] as? String) ?? "log"
            let text = (body["message"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.onConsoleLog(WebDevToolsLogEntry(level: level, message: text))
            }
        }
    }
}
