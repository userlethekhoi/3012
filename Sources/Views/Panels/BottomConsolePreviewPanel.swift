import SwiftUI
import WebKit
import UIKit

public enum BottomPanelTab: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
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
        case .half: return min(max(totalHeight * 0.45, 250), 380)
        case .expanded: return max(totalHeight * 0.76, 400)
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

public struct BottomConsolePreviewPanel: View {
    @Binding var selectedTab: BottomPanelTab
    @Binding var detent: BottomPanelDetent
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    var onClose: () -> Void

    @State private var selectedPreviewPort: UInt16? = nil

    public init(
        selectedTab: Binding<BottomPanelTab>,
        detent: Binding<BottomPanelDetent>,
        runner: CodeRunnerService,
        liveServer: LiveServerService,
        sshService: SSHWorkspaceService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        onClose: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self._detent = detent
        self.runner = runner
        self.liveServer = liveServer
        self.sshService = sshService
        self.workspace = workspace
        self.preferences = preferences
        self.onClose = onClose
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Compact Panel Header with 3-detent resize & Safari launcher
            HStack(spacing: 8) {
                ForEach(BottomPanelTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            if tab == .livePreview && liveServer.isRunning {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                            } else if tab == .terminal && sshService.isConnected {
                                Circle().fill(Color.cyan).frame(width: 6, height: 6)
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

                Spacer()

                if selectedTab == .livePreview {
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
                        workspace: workspace,
                        preferences: preferences
                    )
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
        case .output:
            return "Output"
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
        if let tunnelPort = selectedPreviewPort,
           let tunnelURL = URL(string: "http://127.0.0.1:\(tunnelPort)") {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                    Text("SSH Port Tunnel → http://localhost:\(tunnelPort)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: palette.foreground))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: palette.editorBackground))

                LiveServerWebView(url: tunnelURL, reloadToken: liveServer.reloadVersion)
            }
        } else if liveServer.isRunning,
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
