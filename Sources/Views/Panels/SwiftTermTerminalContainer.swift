import SwiftUI
import UIKit
import SwiftTerm

public struct SwiftTermTerminalContainer: UIViewRepresentable {
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences

    public init(
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences
    ) {
        self.sshService = sshService
        self.runner = runner
        self.workspace = workspace
        self.preferences = preferences
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = UIColor(hexString: preferences.activePalette.editorBackground)

        // Compact Special Terminal Key Bar (Esc, Tab, Ctrl+C, Arrows...)
        let keyBar = context.coordinator.makeTerminalShortcutBar()
        keyBar.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(keyBar)

        let termView = TerminalView(frame: .zero)
        termView.translatesAutoresizingMaskIntoConstraints = false
        termView.terminalDelegate = context.coordinator
        applyTheme(to: termView)
        wrapper.addSubview(termView)

        NSLayoutConstraint.activate([
            keyBar.topAnchor.constraint(equalTo: wrapper.topAnchor),
            keyBar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            keyBar.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            keyBar.heightAnchor.constraint(equalToConstant: 32),

            termView.topAnchor.constraint(equalTo: keyBar.bottomAnchor),
            termView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            termView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        context.coordinator.terminalView = termView
        context.coordinator.bindStreams()
        return wrapper
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if let termView = context.coordinator.terminalView {
            applyTheme(to: termView)
        }
        context.coordinator.syncConnectionModeIfChanged()
    }

    private func applyTheme(to termView: TerminalView) {
        let palette = preferences.activePalette
        termView.nativeBackgroundColor = UIColor(hexString: palette.editorBackground)
        termView.nativeForegroundColor = UIColor(hexString: palette.foreground)
        termView.caretColor = UIColor(hexString: palette.accent)
        let fSize = max(11, min(preferences.fontSize - 1, 20))
        termView.font = UIFont.monospacedSystemFont(ofSize: fSize, weight: .regular)
    }

    public final class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTermTerminalContainer
        weak var terminalView: TerminalView?
        private var wasConnectedSSH: Bool = false
        private var localLineBuffer: String = ""
        private var commandHistory: [String] = []
        private var historyCursor: Int = 0
        private var localCWD: URL?

        init(parent: SwiftTermTerminalContainer) {
            self.parent = parent
        }

        @MainActor
        func bindStreams() {
            wasConnectedSSH = parent.sshService.isConnected
            parent.sshService.onPTYOutput = { [weak self] bytes in
                guard let self, let tv = self.terminalView else { return }
                tv.feed(byteArray: bytes[...])
            }

            if parent.sshService.isConnected {
                feedWelcomeBanner(remote: true)
            } else {
                feedWelcomeBanner(remote: false)
                printLocalPrompt()
            }
        }

        @MainActor
        func syncConnectionModeIfChanged() {
            let nowSSH = parent.sshService.isConnected
            if nowSSH != wasConnectedSSH {
                wasConnectedSSH = nowSSH
                if nowSSH {
                    terminalView?.feed(text: "\r\n\u{001B}[1;32m[SSH] Connected to Remote PTY (\(parent.sshService.connectedProfile?.host ?? "VPS"))\u{001B}[0m\r\n")
                } else {
                    terminalView?.feed(text: "\r\n\u{001B}[1;33m[LOCAL] Switched back to Local Workspace Shell\u{001B}[0m\r\n")
                    printLocalPrompt()
                }
            }
        }

        private func feedWelcomeBanner(remote: Bool) {
            guard let tv = terminalView else { return }
            if remote {
                tv.feed(text: "\u{001B}[1;36m3012 Xterm-256Color Terminal — Remote SSH PTY Active\u{001B}[0m\r\n")
            } else {
                tv.feed(text: "\u{001B}[1;36m3012 Xterm-256Color Terminal\u{001B}[0m (Local Mode — Connect VPS in SSH tab for full Linux bash/vim/g++)\r\n")
                tv.feed(text: "Type \u{001B}[1;33mhelp\u{001B}[0m for local UNIX & JS commands.\r\n")
            }
        }

        @MainActor
        private func printLocalPrompt() {
            let cwd = localCWD ?? parent.workspace.rootURL
            let dirName = cwd.lastPathComponent
            terminalView?.feed(text: "\u{001B}[1;32m3012\u{001B}[0m:\u{001B}[1;34m\(dirName)\u{001B}[0m$ ")
        }

        func makeTerminalShortcutBar() -> UIView {
            let bar = UIScrollView()
            bar.backgroundColor = UIColor.black.withAlphaComponent(0.28)
            bar.showsHorizontalScrollIndicator = false

            let stack = UIStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.spacing = 5
            stack.alignment = .center
            bar.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: bar.contentLayoutGuide.leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: bar.contentLayoutGuide.trailingAnchor, constant: -8),
                stack.topAnchor.constraint(equalTo: bar.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: bar.contentLayoutGuide.bottomAnchor),
                stack.heightAnchor.constraint(equalTo: bar.frameLayoutGuide.heightAnchor)
            ])

            let keys: [(label: String?, sfSymbol: String?, seq: [UInt8])] = [
                ("ESC", nil, [0x1B]),
                (nil, "arrow.right.to.line", [0x09]),
                ("CTRL+C", nil, [0x03]),
                ("CTRL+D", nil, [0x04]),
                ("CTRL+L", nil, [0x0C]),
                (nil, "arrow.up", [0x1B, 0x5B, 0x41]),
                (nil, "arrow.down", [0x1B, 0x5B, 0x42]),
                (nil, "arrow.left", [0x1B, 0x5B, 0x44]),
                (nil, "arrow.right", [0x1B, 0x5B, 0x43]),
                ("-", nil, Array("-".utf8)),
                ("/", nil, Array("/".utf8)),
                ("~", nil, Array("~".utf8)),
                ("|", nil, Array("|".utf8))
            ]

            for item in keys {
                let btn = UIButton(type: .system)
                btn.tintColor = .white
                if let sf = item.sfSymbol {
                    btn.setImage(
                        UIImage(
                            systemName: sf,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                        ),
                        for: .normal
                    )
                } else if let label = item.label {
                    btn.setTitle(label, for: .normal)
                    btn.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
                    btn.setTitleColor(.white, for: .normal)
                }
                btn.backgroundColor = UIColor.white.withAlphaComponent(0.14)
                btn.layer.cornerRadius = 5
                btn.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
                let seq = item.seq
                btn.addAction(UIAction { [weak self] _ in
                    guard let self, let tv = self.terminalView else { return }
                    self.send(source: tv, data: seq[...])
                }, for: .touchUpInside)
                stack.addArrangedSubview(btn)
            }

            return bar
        }

        // MARK: - TerminalViewDelegate
        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor in
                if parent.sshService.isConnected {
                    parent.sshService.resizePTY(cols: newCols, rows: newRows)
                }
            }
        }

        public func setTerminalTitle(source: TerminalView, title: String) {}

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            Task { @MainActor in
                if parent.sshService.isConnected {
                    parent.sshService.sendPTYInput(bytes)
                } else {
                    handleLocalShellBytes(bytes, in: source)
                }
            }
        }

        public func scrolled(source: TerminalView, position: Double) {}

        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }

        public func bell(source: TerminalView) {}

        public func clipboardCopy(source: TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = str
            }
        }

        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        // MARK: - Local Interactive Line Discipline
        @MainActor
        private func handleLocalShellBytes(_ bytes: [UInt8], in tv: TerminalView) {
            if bytes == [0x03] { // Ctrl+C
                localLineBuffer = ""
                tv.feed(text: "^C\r\n")
                printLocalPrompt()
                return
            }
            if bytes == [0x0C] { // Ctrl+L (Clear screen)
                tv.feed(text: "\u{001B}[2J\u{001B}[H")
                printLocalPrompt()
                tv.feed(text: localLineBuffer)
                return
            }
            if bytes == [0x1B, 0x5B, 0x41] { // Up arrow
                guard !commandHistory.isEmpty else { return }
                historyCursor = max(0, historyCursor - 1)
                replaceCurrentInput(with: commandHistory[historyCursor], in: tv)
                return
            }
            if bytes == [0x1B, 0x5B, 0x42] { // Down arrow
                guard !commandHistory.isEmpty else { return }
                historyCursor = min(commandHistory.count, historyCursor + 1)
                let nextCmd = historyCursor < commandHistory.count ? commandHistory[historyCursor] : ""
                replaceCurrentInput(with: nextCmd, in: tv)
                return
            }

            for b in bytes {
                if b == 13 || b == 10 { // Enter
                    tv.feed(text: "\r\n")
                    let cmd = localLineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    localLineBuffer = ""
                    if !cmd.isEmpty {
                        commandHistory.append(cmd)
                        historyCursor = commandHistory.count
                        executeLocalCommand(cmd, in: tv)
                    }
                    printLocalPrompt()
                } else if b == 127 || b == 8 { // Backspace
                    if !localLineBuffer.isEmpty {
                        localLineBuffer.removeLast()
                        tv.feed(text: "\u{08} \u{08}")
                    }
                } else if b >= 32 {
                    let ch = String(UnicodeScalar(b))
                    localLineBuffer.append(ch)
                    tv.feed(text: ch)
                }
            }
        }

        private func replaceCurrentInput(with replacement: String, in tv: TerminalView) {
            let erase = String(repeating: "\u{08} \u{08}", count: localLineBuffer.count)
            tv.feed(text: erase + replacement)
            localLineBuffer = replacement
        }

        @MainActor
        private func executeLocalCommand(_ raw: String, in tv: TerminalView) {
            let cwd = localCWD ?? parent.workspace.rootURL
            let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let cmd = String(parts[0]).lowercased()
            let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            let fm = FileManager.default

            switch cmd {
            case "help":
                let helpText = [
                    "Local UNIX & IDE Commands:",
                    "  ls [-la]        List directory contents",
                    "  cd <dir>        Change directory",
                    "  pwd             Print working directory",
                    "  cat <file>      Display file content",
                    "  mkdir <dir>     Create directory",
                    "  touch <file>    Create empty file",
                    "  cp <a> <b>      Copy file",
                    "  mv <a> <b>      Move / rename file",
                    "  rm <target>     Delete file or directory",
                    "  grep <pat>      Search text across workspace",
                    "  js <code>       Run JavaScript locally via JavaScriptCore",
                    "  clear           Clear terminal screen"
                ].joined(separator: "\r\n")
                tv.feed(text: helpText + "\r\n")
            case "clear":
                tv.feed(text: "\u{001B}[2J\u{001B}[H")
            case "pwd":
                tv.feed(text: cwd.path + "\r\n")
            case "ls":
                let showHidden = arg.contains("-a") || arg.contains("-la")
                let cleanArg = arg.replacingOccurrences(of: "-la", with: "").replacingOccurrences(of: "-l", with: "").replacingOccurrences(of: "-a", with: "").trimmingCharacters(in: .whitespaces)
                let dir = cleanArg.isEmpty ? cwd : cwd.appendingPathComponent(cleanArg)
                let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
                let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: opts)) ?? []
                for u in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        tv.feed(text: "\u{001B}[1;34m\(u.lastPathComponent)/\u{001B}[0m  ")
                    } else {
                        tv.feed(text: "\(u.lastPathComponent)  ")
                    }
                }
                tv.feed(text: "\r\n")
            case "cd":
                if arg.isEmpty || arg == "~" {
                    localCWD = parent.workspace.rootURL
                } else {
                    let next = cwd.appendingPathComponent(arg).standardizedFileURL
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: next.path, isDirectory: &isDir), isDir.boolValue {
                        localCWD = next
                    } else {
                        tv.feed(text: "\u{001B}[31mcd: no such directory: \(arg)\u{001B}[0m\r\n")
                    }
                }
            case "cat":
                guard !arg.isEmpty else { tv.feed(text: "usage: cat <file>\r\n"); return }
                let target = cwd.appendingPathComponent(arg)
                if let content = try? String(contentsOf: target, encoding: .utf8) {
                    tv.feed(text: content.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
                } else {
                    tv.feed(text: "\u{001B}[31mcat: \(arg): No such file\u{001B}[0m\r\n")
                }
            case "mkdir":
                guard !arg.isEmpty else { tv.feed(text: "usage: mkdir <dir>\r\n"); return }
                try? fm.createDirectory(at: cwd.appendingPathComponent(arg), withIntermediateDirectories: true)
                parent.workspace.reloadTree()
            case "touch":
                guard !arg.isEmpty else { tv.feed(text: "usage: touch <file>\r\n"); return }
                let target = cwd.appendingPathComponent(arg)
                if !fm.fileExists(atPath: target.path) {
                    try? "".write(to: target, atomically: true, encoding: .utf8)
                }
                parent.workspace.reloadTree()
            case "rm":
                let clean = arg.replacingOccurrences(of: "-rf ", with: "").replacingOccurrences(of: "-r ", with: "").trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty else { tv.feed(text: "usage: rm <target>\r\n"); return }
                try? fm.removeItem(at: cwd.appendingPathComponent(clean))
                parent.workspace.reloadTree()
            case "cp", "mv":
                let sub = arg.split(separator: " ").map(String.init)
                guard sub.count >= 2 else { tv.feed(text: "usage: \(cmd) <src> <dst>\r\n"); return }
                let src = cwd.appendingPathComponent(sub[0])
                let dst = cwd.appendingPathComponent(sub[1])
                if cmd == "cp" { try? fm.copyItem(at: src, to: dst) }
                else { try? fm.moveItem(at: src, to: dst) }
                parent.workspace.reloadTree()
            case "grep":
                guard !arg.isEmpty else { tv.feed(text: "usage: grep <query>\r\n"); return }
                parent.workspace.performWorkspaceSearch(arg)
                for hit in parent.workspace.searchResults.prefix(25) {
                    tv.feed(text: "\u{001B}[36m\(parent.workspace.relativePath(for: hit.url)):\(hit.line)\u{001B}[0m: \(hit.preview)\r\n")
                }
            case "echo":
                tv.feed(text: arg + "\r\n")
            default:
                parent.runner.executeLocalShellCommand(raw, workspaceRoot: cwd) {
                    parent.workspace.reloadTree()
                }
                if let last = parent.runner.shellHistory.last {
                    tv.feed(text: last.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
                }
            }
        }
    }
}
