import SwiftUI
import UIKit
import SwiftTerm
import ZIPFoundation

public struct SwiftTermTerminalContainer: UIViewRepresentable {
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var daemonService: LocalDaemonService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var aiService: AIAgentService
    @ObservedObject var gitService: GitService

    public init(
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        daemonService: LocalDaemonService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        aiService: AIAgentService,
        gitService: GitService
    ) {
        self.sshService = sshService
        self.runner = runner
        self.daemonService = daemonService
        self.workspace = workspace
        self.preferences = preferences
        self.aiService = aiService
        self.gitService = gitService
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIView {
        let wrapper = UIView()
        wrapper.backgroundColor = UIColor(hexString: preferences.activePalette.editorBackground)

        // Compact Special Terminal Key Bar (Esc, Tab, Ctrl+C, Arrows + Quick CLI Pills)
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
        private var activeREPL: String? = nil
        private var isExecutingAsyncCommand: Bool = false
        private var sessionEnv: [String: String] = [
            "OS": "iOS_NonJB_Sandbox",
            "SHELL": "3012-Workstation-Shell",
            "TERM": "xterm-256color",
            "HOME": "Documents/Workspace",
            "PATH": "/usr/local/bin:/usr/bin:/bin"
        ]

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
            parent.daemonService.onTerminalOutput = { [weak self] text in
                guard let self, let tv = self.terminalView, !self.parent.sshService.isConnected else { return }
                tv.feed(text: "\r\n\u{001B}[38;5;114m\(text)\u{001B}[0m")
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
                    terminalView?.feed(text: "\r\n\u{001B}[1;33m[LOCAL] Switched back to 3012 Full Workstation Shell\u{001B}[0m\r\n")
                    printLocalPrompt()
                }
            }
        }

        @MainActor
        private func feedWelcomeBanner(remote: Bool) {
            guard let tv = terminalView else { return }
            if remote {
                tv.feed(text: "\u{001B}[1;36m3012 Xterm-256Color Terminal — Remote SSH PTY Active\u{001B}[0m\r\n")
            } else {
                let keepTag = parent.daemonService.isKeepAliveActive
                    ? "\u{001B}[1;32m24/7 Keep-Alive ON\u{001B}[0m"
                    : "\u{001B}[33mKeep-Alive OFF\u{001B}[0m"
                tv.feed(text: "\u{001B}[1;36m3012 Workstation Terminal v3.7\u{001B}[0m (\(keepTag) • Full Sandbox R/W)\r\n")
                tv.feed(text: "Supports Windows + Linux CLI, \u{001B}[1;35mclaude\u{001B}[0m / \u{001B}[1;35mopencode\u{001B}[0m, \u{001B}[36mcode <file>\u{001B}[0m, \u{001B}[36mgit\u{001B}[0m, \u{001B}[36mg++/py/node\u{001B}[0m, \u{001B}[36mzip\u{001B}[0m. Type \u{001B}[1;33mhelp\u{001B}[0m.\r\n")
            }
        }

        @MainActor
        private func printLocalPrompt() {
            let cwd = localCWD ?? parent.workspace.rootURL
            let dirName = (cwd.standardizedFileURL == parent.workspace.rootURL.standardizedFileURL)
                ? "Workspace"
                : cwd.lastPathComponent
            if let repl = activeREPL {
                terminalView?.feed(text: "\u{001B}[1;35m\(repl)\u{001B}[0m:\u{001B}[1;34m\(dirName)\u{001B}[0m> ")
            } else {
                terminalView?.feed(text: "\u{001B}[1;32m3012\u{001B}[0m:\u{001B}[1;34m\(dirName)\u{001B}[0m$ ")
            }
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
                ("TAB", "arrow.right.to.line", [0x09]),
                ("CTRL+C", nil, [0x03]),
                ("CTRL+D", nil, [0x04]),
                ("CTRL+L", nil, [0x0C]),
                (nil, "arrow.up", [0x1B, 0x5B, 0x41]),
                (nil, "arrow.down", [0x1B, 0x5B, 0x42]),
                (nil, "arrow.left", [0x1B, 0x5B, 0x44]),
                (nil, "arrow.right", [0x1B, 0x5B, 0x43]),
                ("-", nil, Array("-".utf8)),
                ("/", nil, Array("/".utf8)),
                (">", nil, Array(">".utf8)),
                ("&&", nil, Array(" && ".utf8)),
                ("claude", nil, Array("claude ".utf8)),
                ("opencode", nil, Array("opencode ".utf8)),
                ("code", nil, Array("code ".utf8)),
                ("dir", nil, Array("dir\r".utf8))
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
                    let isCLI = (label == "claude" || label == "opencode")
                    btn.setTitleColor(isCLI ? UIColor.systemPurple : .white, for: .normal)
                }
                let isCLI = (item.label == "claude" || item.label == "opencode")
                btn.backgroundColor = isCLI
                    ? UIColor.systemPurple.withAlphaComponent(0.25)
                    : UIColor.white.withAlphaComponent(0.14)
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
                if let repl = activeREPL {
                    activeREPL = nil
                    tv.feed(text: "^C\r\nLeft \(repl) interactive CLI.\r\n")
                } else {
                    tv.feed(text: "^C\r\n")
                }
                printLocalPrompt()
                return
            }
            if bytes == [0x04] { // Ctrl+D
                if let repl = activeREPL {
                    activeREPL = nil
                    localLineBuffer = ""
                    tv.feed(text: "\r\nExited \(repl) REPL.\r\n")
                    printLocalPrompt()
                }
                return
            }
            if bytes == [0x0C] { // Ctrl+L
                tv.feed(text: "\u{001B}[2J\u{001B}[H")
                printLocalPrompt()
                tv.feed(text: localLineBuffer)
                return
            }
            if bytes == [0x09] { // Tab completion
                handleTabCompletion(in: tv)
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
                    guard !cmd.isEmpty else {
                        printLocalPrompt()
                        continue
                    }
                    commandHistory.append(cmd)
                    historyCursor = commandHistory.count

                    Task { @MainActor [weak self, weak tv] in
                        guard let self, let tv else { return }
                        self.isExecutingAsyncCommand = true
                        await self.dispatchEnteredLine(cmd, in: tv)
                        self.isExecutingAsyncCommand = false
                        self.printLocalPrompt()
                    }
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
        private func handleTabCompletion(in tv: TerminalView) {
            let cwd = localCWD ?? parent.workspace.rootURL
            let parts = localLineBuffer.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            let token = parts.last ?? ""

            var candidates: [String] = []
            if parts.count <= 1 {
                let cmds = ["claude", "opencode", "code", "open", "dir", "ls", "cd", "cls", "clear", "pwd", "tree", "type", "cat", "copy", "cp", "move", "mv", "del", "rm", "mkdir", "rmdir", "touch", "findstr", "grep", "git", "gcc", "g++", "python", "node", "swift", "run", "npm", "zip", "unzip", "wget", "curl", "ping", "ipconfig", "systeminfo", "tasklist", "taskkill", "ps", "kill", "bot", "keepalive", "files", "set", "help"]
                candidates.append(contentsOf: cmds.filter { token.isEmpty || $0.lowercased().hasPrefix(token.lowercased()) })
            }

            let items = (try? FileManager.default.contentsOfDirectory(at: cwd, includingPropertiesForKeys: nil, options: [])) ?? []
            for u in items {
                let name = u.lastPathComponent
                if token.isEmpty || name.lowercased().hasPrefix(token.lowercased()) {
                    candidates.append(name)
                }
            }

            guard let match = candidates.first else { return }
            let suffix = String(match.dropFirst(token.count))
            if !suffix.isEmpty {
                localLineBuffer.append(suffix)
                tv.feed(text: suffix)
            }
        }

        // MARK: - Command Chaining (&&, ;) & Output Redirection (>, >>)
        @MainActor
        private func dispatchEnteredLine(_ rawLine: String, in tv: TerminalView) async {
            let cwd = localCWD ?? parent.workspace.rootURL

            if let repl = activeREPL {
                let low = rawLine.lowercased()
                if low == "exit" || low == "quit" || low == "/exit" || low == "/quit" {
                    activeREPL = nil
                    tv.feed(text: "Left \(repl) interactive mode.\r\n")
                    return
                }
                await parent.aiService.runTerminalAgentCLI(
                    cliName: repl,
                    rawArgs: rawLine,
                    cwd: cwd,
                    workspace: parent.workspace,
                    lastConsoleOutput: parent.runner.consoleOutput
                ) { [weak tv] chunk in
                    tv?.feed(text: chunk.replacingOccurrences(of: "\n", with: "\r\n"))
                }
                return
            }

            let segments = splitChainedCommands(rawLine)
            for seg in segments {
                let (coreCommand, redirTarget, appendMode) = extractRedirection(seg)
                let cleanSeg = coreCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanSeg.isEmpty else { continue }

                var captured = ""
                await executeSingleCommand(cleanSeg, in: tv) { [weak tv] text in
                    if redirTarget != nil {
                        captured += text
                    } else {
                        tv?.feed(text: text.replacingOccurrences(of: "\n", with: "\r\n"))
                    }
                }

                if let targetName = redirTarget {
                    let activeCWD = localCWD ?? parent.workspace.rootURL
                    let destURL = resolvePath(targetName, cwd: activeCWD)
                    let plainText = stripANSIEscapes(captured).replacingOccurrences(of: "\r\n", with: "\n")
                    try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if appendMode, let existing = try? String(contentsOf: destURL, encoding: .utf8) {
                        try? (existing + plainText).write(to: destURL, atomically: true, encoding: .utf8)
                    } else {
                        try? plainText.write(to: destURL, atomically: true, encoding: .utf8)
                    }
                    parent.workspace.reloadTree()
                }
            }
        }

        // MARK: - Full Workstation Command Execution Engine
        @MainActor
        private func executeSingleCommand(
            _ raw: String,
            in tv: TerminalView,
            emit: @escaping @MainActor (String) -> Void
        ) async {
            let cwd = localCWD ?? parent.workspace.rootURL
            let runInBackground = raw.hasSuffix("&") && !raw.hasSuffix("&&")
            let cleanedRaw = runInBackground ? String(raw.dropLast()).trimmingCharacters(in: .whitespaces) : raw
            let tokens = tokenizeArgs(cleanedRaw)
            guard let firstToken = tokens.first else { return }

            let cmd = firstToken.lowercased()
            let args = Array(tokens.dropFirst())
            let rawArgString: String = {
                guard let range = cleanedRaw.range(of: firstToken) else { return "" }
                return String(cleanedRaw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }()
            let fm = FileManager.default

            switch cmd {
            case "help", "/?", "man":
                emit("""
                \u{001B}[1;36m3012 Workstation Terminal — Windows + Linux + AI Coding CLI (Full Sandbox R/W)\u{001B}[0m

                \u{001B}[1;35mAI Coding CLI (Full Read/Write Workspace Access):\u{001B}[0m
                  claude "<prompt>"       Run Claude Code CLI directly on project files
                  opencode "<prompt>"     Run OpenCode CLI directly on project files
                  claude / opencode       Enter interactive AI CLI mode (REPL)
                  claude auth <API_KEY>   Save key to iOS Keychain (or use 'models', 'model <id>')

                \u{001B}[1;32mOpen & Edit Files in 3012 IDE:\u{001B}[0m
                  code <file>             Open (or create & open) file in 3012 Code Editor
                  open / notepad <file>   Aliases for 'code <file>' (code . refreshes tree)
                  files / realpath        Show iOS Files.app path ("On My iPhone > 3012 > Workspace")

                \u{001B}[1;33mWindows CMD & Linux File Commands:\u{001B}[0m
                  dir / ls [-la]          List directory contents (supports &&, ;, >, >>)
                  cd / chdir <dir>        Change directory (cd ~ resets to Workspace root)
                  tree [dir]              Display ASCII folder tree
                  type / cat <file>       Print file contents (also: head, tail, wc, stat)
                  mkdir / md <dir>        Create folder   | rmdir / rd <dir>  Remove folder
                  touch / copy / cp       Create/copy     | move / mv / ren   Move/rename
                  del / rm [-rf] <path>   Delete item     | cls / clear       Clear terminal
                  findstr / grep <query>  Search in files | where / find <q>  Locate files

                \u{001B}[1;36mCompilers, Git, Archive, Network & 24/7 Bot Daemons:\u{001B}[0m
                  gcc / g++ / clang / swift / python / node / run <file>
                  npm [init|start|run]    Manage package.json & run scripts locally
                  git [status|init|add|commit|log|diff|branch|clone <url>]
                  zip <out.zip> <src>     | unzip <file.zip> [dest]
                  wget / curl [-O] <url>  | ping <host> | ipconfig | systeminfo | set | env
                  bot new [token] | bg <file> | ps / tasklist | logs <pid> | kill / taskkill <pid> | keepalive [on|off]
                \n
                """)

            // MARK: AI Coding CLI
            case "claude", "opencode", "ai", "agent":
                let cliLabel = (cmd == "ai" || cmd == "agent") ? "claude" : cmd
                if rawArgString.isEmpty {
                    activeREPL = cliLabel
                    emit("\u{001B}[1;35m[\(cliLabel.uppercased()) INTERACTIVE CLI]\u{001B}[0m Full Workspace Read/Write ready at \(workspaceRelativeLabel(cwd)).\n")
                    emit("Type any coding task, 'models', 'auth <API_KEY>', or 'exit' to return.\n")
                } else {
                    await parent.aiService.runTerminalAgentCLI(
                        cliName: cliLabel,
                        rawArgs: rawArgString,
                        cwd: cwd,
                        workspace: parent.workspace,
                        lastConsoleOutput: parent.runner.consoleOutput,
                        onPrint: emit
                    )
                }

            // MARK: Open in Editor
            case "code", "open", "edit", "notepad", "nano", "vim":
                let targetName = args.first ?? "."
                if targetName == "." {
                    parent.workspace.reloadTree()
                    let count = parent.workspace.flattenFiles(in: parent.workspace.fileTree).count
                    emit("\u{001B}[32m[WORKSPACE]\u{001B}[0m Refreshed Workspace (\(count) files). Path: On My iPhone > 3012 > Workspace\n")
                    return
                }
                let targetURL = resolvePath(targetName, cwd: cwd)
                if !fm.fileExists(atPath: targetURL.path) {
                    try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let starter = CodeLanguage.detect(from: targetURL).starterTemplate
                    try? starter.write(to: targetURL, atomically: true, encoding: .utf8)
                    emit("\u{001B}[36m[NEW]\u{001B}[0m Created \(parent.workspace.relativePath(for: targetURL))\n")
                }
                parent.workspace.reloadTree()
                parent.workspace.openFile(at: targetURL)
                emit("\u{001B}[1;32m[OPENED]\u{001B}[0m \(parent.workspace.relativePath(for: targetURL)) in 3012 Code Editor.\n")

            // MARK: Screen & Directory Info
            case "clear", "cls":
                tv.feed(text: "\u{001B}[2J\u{001B}[H")

            case "pwd":
                emit(cwd.path + "\n")

            case "files", "realpath":
                let rel = parent.workspace.relativePath(for: cwd)
                let label = (cwd.standardizedFileURL == parent.workspace.rootURL.standardizedFileURL) ? "" : "/\(rel)"
                emit("Files.app : On My iPhone > 3012 > Workspace\(label)\n")
                emit("Sandbox   : \(cwd.path)\n")
                emit("Rights    : Read / Write / Create / Delete / Execute JS & Bots (Full App Container)\n")

            case "dir":
                let targetDir = args.first.map { resolvePath($0, cwd: cwd) } ?? cwd
                let items = (try? fm.contentsOfDirectory(
                    at: targetDir,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                    options: []
                )) ?? []
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd  HH:mm"
                emit(" Directory of On My iPhone\\3012\\\(workspaceRelativeLabel(targetDir))\n\n")
                var fileCount = 0
                var dirCount = 0
                var totalBytes = 0
                for u in items.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
                    let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let isDir = vals?.isDirectory ?? false
                    let size = vals?.fileSize ?? 0
                    let dateStr = vals?.contentModificationDate.map { fmt.string(from: $0) } ?? "2026-11-13  00:00"
                    if isDir {
                        dirCount += 1
                        emit("\(dateStr)    <DIR>          \(u.lastPathComponent)\n")
                    } else {
                        fileCount += 1
                        totalBytes += size
                        let sizeCol = "\(size)".padding(toLength: 14, withPad: " ", startingAt: 0)
                        emit("\(dateStr)    \(sizeCol) \(u.lastPathComponent)\n")
                    }
                }
                emit("               \(fileCount) File(s)    \(totalBytes) bytes\n")
                emit("               \(dirCount) Dir(s)\n")

            case "ls":
                let showHidden = args.contains(where: { $0.contains("a") })
                let longList = args.contains(where: { $0.contains("l") })
                let pathArg = args.first(where: { !$0.hasPrefix("-") })
                let dir = pathArg.map { resolvePath($0, cwd: cwd) } ?? cwd
                let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
                let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: opts)) ?? []
                let sorted = urls.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })
                if longList {
                    for u in sorted {
                        let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                        let isDir = vals?.isDirectory ?? false
                        let perm = isDir ? "drwxr-xr-x" : "-rw-r--r--"
                        let sz = "\(vals?.fileSize ?? 0)".padding(toLength: 8, withPad: " ", startingAt: 0)
                        let displayName = isDir ? "\u{001B}[1;34m\(u.lastPathComponent)/\u{001B}[0m" : u.lastPathComponent
                        emit("\(perm)  \(sz)  \(displayName)\n")
                    }
                } else {
                    for u in sorted {
                        let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if isDir {
                            emit("\u{001B}[1;34m\(u.lastPathComponent)/\u{001B}[0m  ")
                        } else {
                            emit("\(u.lastPathComponent)  ")
                        }
                    }
                    emit("\n")
                }

            case "tree":
                let targetDir = args.first.map { resolvePath($0, cwd: cwd) } ?? cwd
                emit("\(targetDir.lastPathComponent)/\n")
                emit(renderDirectoryTree(at: targetDir, prefix: ""))

            case "cd", "chdir", "set-location":
                if rawArgString.isEmpty && cmd == "cd" {
                    emit(cwd.path + "\n")
                    return
                }
                let targetArg = rawArgString.isEmpty ? "~" : stripQuotes(rawArgString)
                if targetArg == "~" || targetArg == "/" || targetArg == "\\" {
                    localCWD = parent.workspace.rootURL
                } else {
                    let next = resolvePath(targetArg, cwd: cwd)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: next.path, isDirectory: &isDir), isDir.boolValue {
                        localCWD = next
                    } else {
                        emit("\u{001B}[31mcd: no such directory: \(targetArg)\u{001B}[0m\n")
                    }
                }

            case "cat", "type", "get-content":
                guard let first = args.first else { emit("usage: \(cmd) <file>\n"); return }
                let target = resolvePath(first, cwd: cwd)
                if let content = try? String(contentsOf: target, encoding: .utf8) {
                    emit(content + (content.hasSuffix("\n") ? "" : "\n"))
                } else {
                    emit("\u{001B}[31m\(cmd): \(first): No such file\u{001B}[0m\n")
                }

            case "head", "tail":
                var lineLimit = 15
                var fileArg: String?
                for a in args {
                    if a.hasPrefix("-n"), let n = Int(a.dropFirst(2)) { lineLimit = max(1, n) }
                    else if a.hasPrefix("-"), let n = Int(a.dropFirst(1)) { lineLimit = max(1, n) }
                    else { fileArg = a }
                }
                guard let f = fileArg else { emit("usage: \(cmd) [-n15] <file>\n"); return }
                let target = resolvePath(f, cwd: cwd)
                if let content = try? String(contentsOf: target, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines)
                    let slice = (cmd == "head") ? Array(lines.prefix(lineLimit)) : Array(lines.suffix(lineLimit))
                    emit(slice.joined(separator: "\n") + "\n")
                } else {
                    emit("\u{001B}[31m\(cmd): \(f): No such file\u{001B}[0m\n")
                }

            case "wc":
                guard let first = args.first else { emit("usage: wc <file>\n"); return }
                let target = resolvePath(first, cwd: cwd)
                if let content = try? String(contentsOf: target, encoding: .utf8) {
                    let lines = content.components(separatedBy: .newlines).count
                    let words = content.split(whereSeparator: { $0.isWhitespace }).count
                    let bytes = content.utf8.count
                    emit("  \(lines)  \(words)  \(bytes) \(first)\n")
                } else {
                    emit("\u{001B}[31mwc: \(first): No such file\u{001B}[0m\n")
                }

            case "stat", "attrib":
                guard let first = args.first else { emit("usage: \(cmd) <path>\n"); return }
                let target = resolvePath(first, cwd: cwd)
                guard fm.fileExists(atPath: target.path) else {
                    emit("\u{001B}[31m\(cmd): cannot stat '\(first)': No such file or directory\u{001B}[0m\n")
                    return
                }
                let attrs = try? fm.attributesOfItem(atPath: target.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                let mod = (attrs?[.modificationDate] as? Date).map { "\($0)" } ?? "-"
                emit("  File: \(target.lastPathComponent)\n  Path: \(target.path)\n  Size: \(size) bytes\n  Mod : \(mod)\n  Perm: Read/Write (3012 Sandbox Full Access)\n")

            case "mkdir", "md":
                guard !args.isEmpty else { emit("usage: \(cmd) <dir>\n"); return }
                for d in args where !d.hasPrefix("-") {
                    try? fm.createDirectory(at: resolvePath(d, cwd: cwd), withIntermediateDirectories: true)
                }
                parent.workspace.reloadTree()

            case "touch", "new-item":
                guard !args.isEmpty else { emit("usage: \(cmd) <file>\n"); return }
                for f in args where !f.hasPrefix("-") {
                    let target = resolvePath(f, cwd: cwd)
                    try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if !fm.fileExists(atPath: target.path) {
                        try? "".write(to: target, atomically: true, encoding: .utf8)
                    }
                }
                parent.workspace.reloadTree()

            case "rm", "del", "erase", "rmdir", "rd", "remove-item":
                let paths = args.filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
                guard !paths.isEmpty else { emit("usage: \(cmd) <target>\n"); return }
                for p in paths {
                    let target = resolvePath(p, cwd: cwd)
                    if fm.fileExists(atPath: target.path) {
                        try? fm.removeItem(at: target)
                    } else {
                        emit("\u{001B}[31m\(cmd): cannot remove '\(p)': No such file or directory\u{001B}[0m\n")
                    }
                }
                parent.workspace.reloadTree()

            case "cp", "copy", "xcopy", "mv", "move", "ren", "rename":
                let paths = args.filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
                guard paths.count >= 2 else { emit("usage: \(cmd) <source> <dest>\n"); return }
                let src = resolvePath(paths[0], cwd: cwd)
                var dst = resolvePath(paths[1], cwd: cwd)
                var isDstDir: ObjCBool = false
                if fm.fileExists(atPath: dst.path, isDirectory: &isDstDir), isDstDir.boolValue {
                    dst = dst.appendingPathComponent(src.lastPathComponent)
                }
                do {
                    if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                    if cmd == "cp" || cmd == "copy" || cmd == "xcopy" {
                        try fm.copyItem(at: src, to: dst)
                    } else {
                        try fm.moveItem(at: src, to: dst)
                    }
                    parent.workspace.reloadTree()
                } catch {
                    emit("\u{001B}[31m\(cmd): \(error.localizedDescription)\u{001B}[0m\n")
                }

            case "grep", "findstr", "select-string":
                let clean = args.filter { !$0.hasPrefix("-") && !$0.hasPrefix("/") }
                guard let query = clean.first else { emit("usage: \(cmd) <query> [file]\n"); return }
                if clean.count >= 2 {
                    let fileURL = resolvePath(clean[1], cwd: cwd)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        for (idx, line) in content.components(separatedBy: .newlines).enumerated() where line.localizedCaseInsensitiveContains(query) {
                            emit("\(clean[1]):\(idx + 1): \(line)\n")
                        }
                    }
                } else {
                    parent.workspace.performWorkspaceSearch(query)
                    for hit in parent.workspace.searchResults.prefix(30) {
                        emit("\u{001B}[36m\(parent.workspace.relativePath(for: hit.url)):\(hit.line)\u{001B}[0m: \(hit.preview)\n")
                    }
                }

            case "find", "where", "which":
                guard let q = args.last(where: { !$0.hasPrefix("-") }) else { emit("usage: \(cmd) <name>\n"); return }
                let builtins = ["claude", "opencode", "code", "open", "dir", "ls", "cd", "cls", "clear", "git", "gcc", "g++", "clang", "python", "node", "swift", "npm", "zip", "unzip", "wget", "curl", "ping"]
                if (cmd == "which" || cmd == "where") && builtins.contains(q.lowercased()) {
                    emit("/usr/local/bin/\(q.lowercased()) (3012 Workstation Built-in)\n")
                } else {
                    let allFiles = parent.workspace.flattenFiles(in: parent.workspace.fileTree)
                    let hits = allFiles.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(q) }
                    for h in hits.prefix(30) {
                        emit("./\(parent.workspace.relativePath(for: h))\n")
                    }
                }

            case "echo", "write-output":
                let expanded = rawArgString.replacingOccurrences(of: "$PATH", with: sessionEnv["PATH"] ?? "")
                    .replacingOccurrences(of: "%CD%", with: cwd.path)
                emit(stripQuotes(expanded) + "\n")

            // MARK: Compilers & Runtimes (Foreground + 24/7 Background)
            case "bg", "node", "js":
                let targetName = args.first ?? ""
                guard !targetName.isEmpty else { emit("usage: \(cmd) <file.js> [&]\n"); return }
                let fileURL = resolvePath(targetName, cwd: cwd)
                if !fm.fileExists(atPath: fileURL.path) {
                    if cmd == "node" || cmd == "js" {
                        parent.daemonService.keepTerminalAliveInBackground = true
                        let job = parent.daemonService.startInlineCommand(name: "inline.js", jsCode: rawArgString, workspaceRoot: parent.workspace.rootURL)
                        emit("\u{001B}[1;32m[DAEMON]\u{001B}[0m Inline JS started as PID \(job.pid)\n")
                        return
                    }
                    emit("\u{001B}[31m\(cmd): file not found: \(targetName)\u{001B}[0m\n")
                    return
                }
                if runInBackground || cmd == "bg" {
                    parent.daemonService.keepTerminalAliveInBackground = true
                    let job = parent.daemonService.startJob(fileURL: fileURL, workspaceRoot: parent.workspace.rootURL)
                    emit("\u{001B}[1;32m[DAEMON]\u{001B}[0m PID \(job.pid) running 24/7 on-device (\(job.name)). Safe to lock screen.\n")
                } else if let content = try? String(contentsOf: fileURL, encoding: .utf8),
                          (content.contains("TelegramBot") || content.contains("setInterval(") || content.contains("startPolling")) {
                    parent.daemonService.keepTerminalAliveInBackground = true
                    let job = parent.daemonService.startJob(fileURL: fileURL, workspaceRoot: parent.workspace.rootURL)
                    emit("\u{001B}[1;32m[DAEMON]\u{001B}[0m Long-running JS/Bot PID \(job.pid) started 24/7 on-device.\n")
                } else if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    await parent.runner.runCode(code: content, language: .javascript, fileName: fileURL.lastPathComponent, sshService: nil)
                    emit(parent.runner.consoleOutput + "\n")
                }

            case "python", "python3", "py", "gcc", "g++", "clang", "swift", "go", "rustc", "javac", "php", "ruby", "lua", "run":
                if args.contains("--version") || args.contains("-v") || args.contains("-V") {
                    emit("\(cmd) (3012 Zero-Config Toolchain + On-Device Sandbox Runtime)\n")
                    return
                }
                guard let fileArg = args.first(where: { !$0.hasPrefix("-") && !$0.hasSuffix(".out") && !$0.hasSuffix(".exe") }) else {
                    emit("usage: \(cmd) <source_file>\n")
                    return
                }
                let fileURL = resolvePath(fileArg, cwd: cwd)
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    emit("\u{001B}[31m\(cmd): cannot open '\(fileArg)': No such file\u{001B}[0m\n")
                    return
                }
                let isPython = (cmd == "python" || cmd == "python3" || cmd == "py")
                let looksLikeBot = content.contains("startPolling") || content.contains("polling(") || content.contains("Application") || content.contains("telebot")
                if isPython && (runInBackground || looksLikeBot) {
                    parent.daemonService.keepTerminalAliveInBackground = true
                    let job = parent.daemonService.startJob(fileURL: fileURL, workspaceRoot: parent.workspace.rootURL)
                    emit("\u{001B}[1;32m[DAEMON]\u{001B}[0m Python Bot PID \(job.pid) running 24/7 on-device.\n")
                    return
                }
                let lang: CodeLanguage = {
                    switch cmd {
                    case "gcc": return .c
                    case "g++": return .cpp
                    case "clang": return fileURL.pathExtension.lowercased() == "c" ? .c : .cpp
                    case "swift": return .swift
                    case "go": return .go
                    case "rustc": return .rust
                    case "javac": return .java
                    case "php": return .php
                    case "ruby": return .ruby
                    case "lua": return .lua
                    case "python", "python3", "py": return .python
                    default: return CodeLanguage.detect(from: fileURL, contentSample: content)
                    }
                }()
                emit("\u{001B}[36m[EXEC]\u{001B}[0m Compiling & running \(fileURL.lastPathComponent) (\(lang.rawValue))...\n")
                await parent.runner.runCode(code: content, language: lang, fileName: fileURL.lastPathComponent, sshService: nil)
                emit(parent.runner.consoleOutput + "\n")

            case "npm":
                let sub = args.first?.lowercased() ?? ""
                if sub == "init" {
                    let pkgURL = cwd.appendingPathComponent("package.json")
                    let pkg = """
                    {
                      "name": "\(cwd.lastPathComponent.lowercased())",
                      "version": "1.0.0",
                      "main": "app.js",
                      "scripts": {
                        "start": "node app.js"
                      }
                    }
                    """
                    try? pkg.write(to: pkgURL, atomically: true, encoding: .utf8)
                    parent.workspace.reloadTree()
                    emit("Wrote \(parent.workspace.relativePath(for: pkgURL))\n")
                } else if sub == "start" || sub == "run" {
                    let pkgURL = cwd.appendingPathComponent("package.json")
                    var targetScript = "app.js"
                    if let data = try? Data(contentsOf: pkgURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let scripts = json["scripts"] as? [String: String],
                           let scriptName = (sub == "start") ? "start" : args.dropFirst().first,
                           let cmdLine = scripts[scriptName] {
                            let fileToken = cmdLine.split(separator: " ").last.map(String.init) ?? targetScript
                            targetScript = fileToken
                        } else if let mainField = json["main"] as? String {
                            targetScript = mainField
                        }
                    }
                    let fileURL = resolvePath(targetScript, cwd: cwd)
                    if fm.fileExists(atPath: fileURL.path) {
                        parent.daemonService.keepTerminalAliveInBackground = true
                        let job = parent.daemonService.startJob(fileURL: fileURL, workspaceRoot: parent.workspace.rootURL)
                        emit("\u{001B}[1;32m[NPM]\u{001B}[0m Launched \(targetScript) as PID \(job.pid) on-device.\n")
                    } else {
                        emit("\u{001B}[31mnpm ERR!\u{001B}[0m Missing entry script: \(targetScript)\n")
                    }
                } else {
                    emit("3012 npm compatibility wrapper v1.0 — try 'npm init -y', 'npm start', or 'npm run <script>'\n")
                }

            // MARK: Git CLI
            case "git":
                await handleGitCommand(args: args, cwd: cwd, emit: emit)

            // MARK: Zip & Unzip
            case "zip":
                guard args.count >= 2 else { emit("usage: zip <archive.zip> <file_or_folder>\n"); return }
                let archiveName = args[0].hasSuffix(".zip") ? args[0] : "\(args[0]).zip"
                let zipURL = resolvePath(archiveName, cwd: cwd)
                let sourceURL = resolvePath(args[1], cwd: cwd)
                do {
                    if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
                    try fm.zipItem(at: sourceURL, to: zipURL, shouldKeepParent: true)
                    parent.workspace.reloadTree()
                    emit("\u{001B}[32m[ZIP]\u{001B}[0m Created \(zipURL.lastPathComponent)\n")
                } catch {
                    emit("\u{001B}[31mzip error:\u{001B}[0m \(error.localizedDescription)\n")
                }

            case "unzip":
                guard let zipArg = args.first else { emit("usage: unzip <archive.zip> [dest_folder]\n"); return }
                let zipURL = resolvePath(zipArg, cwd: cwd)
                let destURL = args.count >= 2 ? resolvePath(args[1], cwd: cwd) : cwd
                do {
                    try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
                    try fm.unzipItem(at: zipURL, to: destURL)
                    parent.workspace.reloadTree()
                    emit("\u{001B}[32m[UNZIP]\u{001B}[0m Extracted \(zipURL.lastPathComponent) into \(workspaceRelativeLabel(destURL))\n")
                } catch {
                    emit("\u{001B}[31munzip error:\u{001B}[0m \(error.localizedDescription)\n")
                }

            // MARK: Bot Daemon Commands
            case "bot":
                let subCmd = args.first?.lowercased() ?? ""
                if subCmd == "new" {
                    let token = args.count > 1 ? args[1] : ""
                    parent.daemonService.keepTerminalAliveInBackground = true
                    let botURL = parent.daemonService.scaffoldTelegramBot(botToken: token, in: parent.workspace, startImmediately: true)
                    emit("\u{001B}[1;32m[BOT]\u{001B}[0m Created & launched \(botURL.lastPathComponent) on-device (24/7 Keep-Alive ON).\n")
                } else {
                    emit("usage: bot new [TELEGRAM_BOT_TOKEN]\n")
                }

            case "ps", "jobs", "tasklist", "get-process":
                let jobs = parent.daemonService.jobs
                if jobs.isEmpty {
                    emit("No background jobs running on device.\n")
                } else {
                    emit("PID    STATE     UPTIME     SCRIPT\n")
                    for job in jobs {
                        let pidCol = "\(job.pid)".padding(toLength: 6, withPad: " ", startingAt: 0)
                        let stCol = (job.isRunning ? "RUNNING" : "STOPPED").padding(toLength: 9, withPad: " ", startingAt: 0)
                        let upCol = job.uptimeFormatted.padding(toLength: 9, withPad: " ", startingAt: 0)
                        emit("\(pidCol) \(stCol) \(upCol)  \(job.scriptPath)\n")
                    }
                }

            case "logs":
                guard let pidStr = args.first, let pid = Int(pidStr) else {
                    emit("usage: logs <pid>\n"); return
                }
                if let job = parent.daemonService.jobs.first(where: { $0.pid == pid }) {
                    let recent = job.logs.suffix(40)
                    emit(recent.isEmpty ? "(no logs)\n" : recent.joined(separator: "\n") + "\n")
                } else {
                    emit("\u{001B}[31mlogs: unknown PID \(pid)\u{001B}[0m\n")
                }

            case "kill", "taskkill", "stop-process":
                let cleanTarget = args.last(where: { !$0.hasPrefix("-") && !$0.hasPrefix("/") }) ?? ""
                if cleanTarget.lowercased() == "all" {
                    parent.daemonService.stopAllJobs()
                    emit("Stopped all on-device background jobs.\n")
                } else if let pid = Int(cleanTarget) {
                    parent.daemonService.stopJob(pid: pid)
                    emit("Stopped PID \(pid).\n")
                } else {
                    emit("usage: \(cmd) <pid|all>\n")
                }

            case "keepalive":
                let toggleArg = args.first?.lowercased() ?? ""
                switch toggleArg {
                case "on", "1", "true": parent.daemonService.keepTerminalAliveInBackground = true
                case "off", "0", "false": parent.daemonService.keepTerminalAliveInBackground = false
                default: break
                }
                let st = parent.daemonService.isKeepAliveActive ? "ACTIVE (24/7 screen-off ready)" : "OFF"
                emit("On-Device Keep-Alive: \(st) | Battery: \(parent.daemonService.batteryPercentage)%\n")

            // MARK: Network & System Info
            case "wget", "curl":
                let saveToFile = (cmd == "wget") || args.contains("-O") || args.contains("--output")
                let urlArg = args.first(where: { $0.hasPrefix("http://") || $0.hasPrefix("https://") }) ?? args.last ?? ""
                guard !urlArg.isEmpty else { emit("usage: \(cmd) <https://...>\n"); return }
                let fullURL = urlArg.hasPrefix("http") ? urlArg : "https://\(urlArg)"
                guard let url = URL(string: fullURL) else { emit("Invalid URL: \(urlArg)\n"); return }

                if saveToFile {
                    var outName = url.lastPathComponent.isEmpty ? "downloaded.txt" : url.lastPathComponent
                    if let oIdx = args.firstIndex(where: { $0 == "-O" || $0 == "-o" }), oIdx + 1 < args.count {
                        outName = args[oIdx + 1]
                    }
                    emit("Downloading \(fullURL) -> \(outName)...\n")
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let destURL = resolvePath(outName, cwd: cwd)
                        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destURL)
                        parent.workspace.reloadTree()
                        emit("\u{001B}[32m[SAVED]\u{001B}[0m \(outName) (\(data.count) bytes)\n")
                    } catch {
                        emit("\u{001B}[31m\(cmd): \(error.localizedDescription)\u{001B}[0m\n")
                    }
                } else {
                    emit("Fetching \(fullURL)...\n")
                    let res = await parent.daemonService.performHTTPGet(urlString: fullURL)
                    emit(res + "\n")
                }

            case "ping":
                guard let hostArg = args.last(where: { !$0.hasPrefix("-") }) else { emit("usage: ping <host_or_url>\n"); return }
                let targetURLStr = hostArg.hasPrefix("http") ? hostArg : "https://\(hostArg)"
                guard let url = URL(string: targetURLStr) else { emit("ping: cannot resolve \(hostArg)\n"); return }
                emit("Pinging \(hostArg) via HTTPS probe (4 packets)...\n")
                for seq in 1...4 {
                    var req = URLRequest(url: url, timeoutInterval: 6)
                    req.httpMethod = "HEAD"
                    let t0 = Date()
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: req)
                        let ms = Int(Date().timeIntervalSince(t0) * 1000)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                        emit("Reply from \(hostArg): seq=\(seq) status=\(code) time=\(ms)ms\n")
                    } catch {
                        emit("Request timed out (seq=\(seq)): \(error.localizedDescription)\n")
                    }
                }

            case "ipconfig", "ifconfig":
                let net = parent.daemonService.networkOnline ? "Connected" : "Offline"
                let ssh = parent.sshService.isConnected ? (parent.sshService.connectedProfile?.host ?? "Connected") : "Disconnected"
                emit("""
                3012 Network Adapter Status:
                  Internet / Wi-Fi / 5G : \(net)
                  Local Live Server     : http://127.0.0.1:5500 (loopback)
                  Remote SSH PTY        : \(ssh)
                  24/7 Keep-Alive       : \(parent.daemonService.isKeepAliveActive ? "ACTIVE" : "OFF")
                \n
                """)

            case "systeminfo", "uname", "ver":
                let sysVer = UIDevice.current.systemVersion
                let model = UIDevice.current.model
                emit("""
                Host OS      : iOS \(sysVer) (\(model) • Non-Jailbreak Secure Container)
                Shell Engine : 3012 Full Workstation Terminal v3.7 (Windows + Linux + AI CLI)
                Workspace    : On My iPhone > 3012 > Workspace
                Sandbox Path : \(parent.workspace.rootURL.path)
                Battery      : \(parent.daemonService.batteryPercentage)% (\(parent.daemonService.isCharging ? "Charging" : "Battery"))
                Active Jobs  : \(parent.daemonService.runningJobsCount) running
                \n
                """)

            case "whoami", "hostname":
                emit(cmd == "whoami" ? "3012-mobile-dev (Full Workspace Rights)\n" : "iphone-3012.local\n")

            case "date", "time":
                emit("\(Date())\n")

            case "uptime":
                emit("Keep-Alive: \(parent.daemonService.isKeepAliveActive ? "ON" : "OFF") | Running daemons: \(parent.daemonService.runningJobsCount)\n")

            case "set", "env", "export":
                if rawArgString.isEmpty {
                    for (k, v) in sessionEnv.sorted(by: { $0.key < $1.key }) {
                        emit("\(k)=\(v)\n")
                    }
                } else if rawArgString.contains("=") {
                    let kv = rawArgString.split(separator: "=", maxSplits: 1).map(String.init)
                    let key = kv[0].trimmingCharacters(in: .whitespaces)
                    let val = stripQuotes(kv.count > 1 ? kv[1] : "")
                    sessionEnv[key] = val
                    emit("Set \(key)=\(val)\n")
                } else {
                    let key = rawArgString.trimmingCharacters(in: .whitespaces)
                    emit("\(key)=\(sessionEnv[key] ?? "")\n")
                }

            default:
                parent.runner.executeLocalShellCommand(raw, workspaceRoot: cwd) { [weak self] in
                    self?.parent.workspace.reloadTree()
                }
                if let last = parent.runner.shellHistory.last {
                    emit(last + "\n")
                }
            }
        }

        // MARK: - Git Subcommand Handler
        @MainActor
        private func handleGitCommand(
            args: [String],
            cwd: URL,
            emit: @escaping @MainActor (String) -> Void
        ) async {
            let sub = args.first?.lowercased() ?? "status"
            let root = parent.workspace.rootURL

            switch sub {
            case "status":
                await parent.gitService.refreshStatus(workspaceRoot: root, sshService: nil)
                emit("On branch \(parent.gitService.currentBranch)\n")
                if parent.gitService.changedFiles.isEmpty {
                    emit("nothing to commit, working tree clean\n")
                } else {
                    for item in parent.gitService.changedFiles {
                        emit("  [\(item.statusBadge)] \(item.relativePath) (+\(item.addedLines)/-\(item.removedLines))\n")
                    }
                }
            case "init":
                await parent.gitService.refreshStatus(workspaceRoot: root, sshService: nil)
                emit("Initialized local 3012 Git repository tracking in \(root.lastPathComponent)\n")
            case "add":
                await parent.gitService.refreshStatus(workspaceRoot: root, sshService: nil)
                emit("Staged changes in workspace (\(parent.gitService.changedFiles.count) modified/untracked files).\n")
            case "commit":
                var message = "Update from 3012 Terminal"
                if let mIdx = args.firstIndex(where: { $0 == "-m" || $0 == "-am" }), mIdx + 1 < args.count {
                    message = args[mIdx + 1]
                }
                await parent.gitService.commitAll(message: message, workspaceRoot: root, sshService: nil)
                emit(parent.gitService.statusBanner + "\n")
            case "log":
                await parent.gitService.refreshStatus(workspaceRoot: root, sshService: nil)
                if parent.gitService.commits.isEmpty {
                    emit("No commits yet. Run: git commit -m \"Initial commit\"\n")
                } else {
                    for c in parent.gitService.commits.prefix(15) {
                        emit("commit \(c.id) | \(c.author) | \(c.message)\n")
                    }
                }
            case "diff":
                if let fileArg = args.dropFirst().first {
                    let target = resolvePath(fileArg, cwd: cwd)
                    let rel = parent.workspace.relativePath(for: target)
                    emit(parent.gitService.diffPreview(for: rel, workspaceRoot: root) + "\n")
                } else {
                    await parent.gitService.refreshStatus(workspaceRoot: root, sshService: nil)
                    for item in parent.gitService.changedFiles.prefix(8) {
                        emit("--- \(item.relativePath) ---\n")
                        emit(parent.gitService.diffPreview(for: item.relativePath, workspaceRoot: root) + "\n")
                    }
                }
            case "branch":
                emit("* \(parent.gitService.currentBranch)\n")
            case "clone":
                guard args.count >= 2 else { emit("usage: git clone <owner/repo | https://github.com/owner/repo>\n"); return }
                let repoInput = args[1]
                emit("Cloning \(repoInput) into Workspace...\n")
                if let dest = await parent.gitService.cloneGitHubRepository(repoInput: repoInput, into: parent.workspace.rootURL) {
                    parent.workspace.reloadTree()
                    emit("\u{001B}[32m[CLONED]\u{001B}[0m \(repoInput) -> \(dest.lastPathComponent)/\n")
                } else {
                    emit("\u{001B}[31m\(parent.gitService.statusBanner)\u{001B}[0m\n")
                }
            default:
                emit("3012 Git CLI: supports status, init, add, commit -m \"...\", log, diff [file], branch, clone <repo>\n")
            }
        }

        // MARK: - Helpers
        @MainActor
        private func resolvePath(_ raw: String, cwd: URL) -> URL {
            let clean = stripQuotes(raw).replacingOccurrences(of: "\\", with: "/")
            if clean == "~" { return parent.workspace.rootURL }
            if clean.hasPrefix("~/") {
                return parent.workspace.rootURL.appendingPathComponent(String(clean.dropFirst(2))).standardizedFileURL
            }
            if clean.hasPrefix("/var/") || clean.hasPrefix("/private/") {
                return URL(fileURLWithPath: clean).standardizedFileURL
            }
            return cwd.appendingPathComponent(clean).standardizedFileURL
        }

        @MainActor
        private func workspaceRelativeLabel(_ url: URL) -> String {
            if url.standardizedFileURL == parent.workspace.rootURL.standardizedFileURL {
                return "Workspace"
            }
            return "Workspace\\" + parent.workspace.relativePath(for: url).replacingOccurrences(of: "/", with: "\\")
        }

        private func renderDirectoryTree(at dir: URL, prefix: String, depth: Int = 0) -> String {
            guard depth < 4 else { return "" }
            let items = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ))?.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) ?? []

            var out = ""
            for (idx, item) in items.enumerated() {
                let isLast = (idx == items.count - 1)
                let connector = isLast ? "└── " : "├── "
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                out += "\(prefix)\(connector)\(item.lastPathComponent)\(isDir ? "/" : "")\n"
                if isDir {
                    let nextPrefix = prefix + (isLast ? "    " : "│   ")
                    out += renderDirectoryTree(at: item, prefix: nextPrefix, depth: depth + 1)
                }
            }
            return out
        }

        private func tokenizeArgs(_ input: String) -> [String] {
            var tokens: [String] = []
            var current = ""
            var quote: Character? = nil
            for ch in input {
                if let q = quote {
                    if ch == q {
                        quote = nil
                    } else {
                        current.append(ch)
                    }
                } else if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch.isWhitespace {
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty {
                tokens.append(current)
            }
            return tokens
        }

        private func splitChainedCommands(_ line: String) -> [String] {
            var segments: [String] = []
            var current = ""
            var quote: Character? = nil
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if let q = quote {
                    current.append(ch)
                    if ch == q { quote = nil }
                    i += 1
                    continue
                }
                if ch == "\"" || ch == "'" {
                    quote = ch
                    current.append(ch)
                    i += 1
                    continue
                }
                if ch == ";" {
                    segments.append(current)
                    current = ""
                    i += 1
                    continue
                }
                if ch == "&", i + 1 < chars.count, chars[i + 1] == "&" {
                    segments.append(current)
                    current = ""
                    i += 2
                    continue
                }
                current.append(ch)
                i += 1
            }
            if !current.isEmpty {
                segments.append(current)
            }
            return segments
        }

        private func extractRedirection(_ segment: String) -> (cmd: String, file: String?, append: Bool) {
            var quote: Character? = nil
            let chars = Array(segment)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if let q = quote {
                    if ch == q { quote = nil }
                    i += 1
                    continue
                }
                if ch == "\"" || ch == "'" {
                    quote = ch
                    i += 1
                    continue
                }
                if ch == ">" {
                    let isAppend = (i + 1 < chars.count && chars[i + 1] == ">")
                    let cmdPart = String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
                    let startIdx = isAppend ? i + 2 : i + 1
                    let targetPart = stripQuotes(String(chars[startIdx..<chars.count]).trimmingCharacters(in: .whitespaces))
                    return (cmdPart, targetPart.isEmpty ? nil : targetPart, isAppend)
                }
                i += 1
            }
            return (segment, nil, false)
        }

        private func stripQuotes(_ text: String) -> String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 2, ((t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'"))) {
                return String(t.dropFirst().dropLast())
            }
            return t
        }

        private func stripANSIEscapes(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        }
    }
}
