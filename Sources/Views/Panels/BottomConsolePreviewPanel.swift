import SwiftUI
import WebKit

public enum BottomPanelTab: String, CaseIterable, Identifiable {
    case output = "Output"
    case livePreview = "Live :5500"
    case shell = "Terminal"

    public var id: String { rawValue }
}

public struct BottomConsolePreviewPanel: View {
    @Binding var selectedTab: BottomPanelTab
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    var onClose: () -> Void

    @State private var shellInput: String = ""

    public init(
        selectedTab: Binding<BottomPanelTab>,
        runner: CodeRunnerService,
        liveServer: LiveServerService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        onClose: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self.runner = runner
        self.liveServer = liveServer
        self.workspace = workspace
        self.preferences = preferences
        self.onClose = onClose
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Compact Panel Header
            HStack(spacing: 10) {
                ForEach(BottomPanelTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            if tab == .livePreview && liveServer.isRunning {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                            }
                            Text(tab == .livePreview ? "Live :\(liveServer.port)" : tab.rawValue)
                                .font(.system(size: 11.5, weight: selectedTab == tab ? .bold : .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTab == tab ? Color(hex: palette.currentLineBackground) : Color.clear)
                        .foregroundColor(selectedTab == tab ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                        .cornerRadius(6)
                    }
                }

                Spacer()

                if selectedTab == .livePreview {
                    Button {
                        if !liveServer.isRunning {
                            liveServer.start(
                                serving: workspace.rootURL,
                                keepAliveInBackground: preferences.keepServerInBackground
                            )
                        }
                        let rel = activeHTMLRelativePath()
                        liveServer.openInSafari(relativePath: rel)
                    } label: {
                        Label("Safari", systemImage: "safari.fill")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.85))
                            .foregroundColor(.white)
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

            // Body
            Group {
                switch selectedTab {
                case .output:
                    outputView(palette: palette)
                case .livePreview:
                    liveWebPreviewBody(palette: palette)
                case .shell:
                    localShellView(palette: palette)
                }
            }
        }
        .background(Color(hex: palette.sidebarBackground))
    }

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

    @ViewBuilder
    private func liveWebPreviewBody(palette: IDEColorPalette) -> some View {
        if liveServer.isRunning,
           let url = URL(string: "\(liveServer.serverBaseURLString)/\(activeHTMLRelativePath())") {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: liveServer.isBackgroundKeepAliveActive ? "antenna.radiowaves.left.and.right" : "globe")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("http://localhost:\(liveServer.port)/\(activeHTMLRelativePath())")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .lineLimit(1)
                    Spacer()
                    if liveServer.isBackgroundKeepAliveActive {
                        Text("BG Keep-Alive ON")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: palette.editorBackground))

                LiveServerWebView(url: url, reloadToken: liveServer.reloadVersion)
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

    @ViewBuilder
    private func localShellView(palette: IDEColorPalette) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(runner.shellHistory.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(line.hasPrefix("$") ? Color(hex: palette.accent) : Color(hex: palette.foreground))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                Text("$")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                TextField("ls, cat index.html, touch test.cpp, js 2+2...", text: $shellInput)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        runShellLine()
                    }
                Button("Run") {
                    runShellLine()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: palette.accent))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(hex: palette.headerBackground))
        }
    }

    private func runShellLine() {
        let cmd = shellInput
        shellInput = ""
        runner.executeLocalShellCommand(cmd, workspaceRoot: workspace.rootURL) {
            workspace.reloadTree()
        }
    }

    private func activeHTMLRelativePath() -> String {
        if let tab = workspace.activeTab, tab.language == .html {
            return workspace.relativePath(for: tab.fileURL)
        }
        return "index.html"
    }
}

private struct LiveServerWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        context.coordinator.loadedURL = url
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        var lastReloadToken: Int = 0
    }
}
