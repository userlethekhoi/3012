import Foundation
import JavaScriptCore

@MainActor
public final class CodeRunnerService: ObservableObject {
    @Published public var consoleOutput: String = "Ready. Tap ▶ Run to execute any file without configuring PATH or compilers.\n"
    @Published public var stdinInput: String = ""
    @Published public private(set) var isRunning: Bool = false
    @Published public var shellHistory: [String] = [
        "3012 Local Workspace Shell v1.0 — type 'help' for commands."
    ]
    @Published public private(set) var currentShellDirectory: URL?

    // Optional User VPS Runner Endpoint (Zero-Config Remote Compile Server)
    @Published public var vpsEndpointURL: String {
        didSet { UserDefaults.standard.set(vpsEndpointURL, forKey: "3012.vpsEndpointURL") }
    }
    @Published public var vpsAuthToken: String {
        didSet { UserDefaults.standard.set(vpsAuthToken, forKey: "3012.vpsAuthToken") }
    }

    public init() {
        self.vpsEndpointURL = UserDefaults.standard.string(forKey: "3012.vpsEndpointURL") ?? ""
        self.vpsAuthToken = UserDefaults.standard.string(forKey: "3012.vpsAuthToken") ?? ""
    }

    public static let vpsBootstrapCommand: String = """
    sudo apt-get update && sudo apt-get install -y build-essential gcc g++ gdb clang clangd cmake python3 python3-pip nodejs npm git ripgrep && echo "✅ 3012 VPS Toolchain Installed!"
    """

    public func runCode(code: String, language: CodeLanguage, fileName: String, sshService: SSHWorkspaceService? = nil) async {
        isRunning = true
        let startTime = Date()
        consoleOutput = "▶ Running \(fileName) (\(language.rawValue))...\n"

        defer {
            isRunning = false
        }

        // 0. If connected to SSH VPS (Phase 3), compile & run directly on the user's VPS!
        if let ssh = sshService, ssh.isConnected {
            let vpsOut = await ssh.compileAndRunOnVPS(code: code, language: language, fileName: fileName, stdin: stdinInput)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            consoleOutput += vpsOut + "\n\n✓ Finished in \(elapsed) ms (SSH VPS: \(ssh.connectedProfile?.host ?? "Remote"))"
            return
        }

        if language == .javascript {
            let output = executeJavaScriptLocally(code)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            consoleOutput += output + "\n\n✓ Finished in \(elapsed) ms (Local JavaScriptCore)"
            return
        }

        // 1. If user configured their private VPS Runner endpoint, prioritize VPS execution
        let trimmedVPS = vpsEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVPS.isEmpty, let vpsResult = await executeOnCustomVPS(endpoint: trimmedVPS, code: code, language: language, fileName: fileName, stdin: stdinInput) {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            consoleOutput += vpsResult + "\n\n✓ Finished in \(elapsed) ms (Remote VPS)"
            return
        }

        // 2. Zero-Config Instant Compiler Sandbox (Wandbox API — works immediately without API keys or MinGW setup)
        if let compilerName = wandboxCompiler(for: language) {
            let result = await executeViaZeroConfigSandbox(compiler: compilerName, code: code, stdin: stdinInput)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            consoleOutput += result + "\n\n✓ Finished in \(elapsed) ms (Zero-Config Toolchain: \(compilerName))"
        } else {
            consoleOutput += "ℹ️ Direct execution is not required for \(language.rawValue). For HTML/CSS, Live Server (:5500) handles instant preview."
        }
    }

    private func executeJavaScriptLocally(_ script: String) -> String {
        guard let context = JSContext() else {
            return "Failed to initialize JavaScriptCore context."
        }
        var logs: [String] = []

        let logBlock: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []
            let line = args.map { "\($0)" }.joined(separator: " ")
            logs.append(line)
        }
        let errorBlock: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []
            let line = args.map { "\($0)" }.joined(separator: " ")
            logs.append("❌ Error: " + line)
        }

        context.exceptionHandler = { _, exception in
            if let exc = exception {
                logs.append("⚠️ JS Exception: \(exc)")
            }
        }

        if let consoleObj = JSValue(newObjectIn: context) {
            consoleObj.setObject(logBlock, forKeyedSubscript: "log" as NSString)
            consoleObj.setObject(logBlock, forKeyedSubscript: "info" as NSString)
            consoleObj.setObject(logBlock, forKeyedSubscript: "warn" as NSString)
            consoleObj.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
            context.setObject(consoleObj, forKeyedSubscript: "console" as NSString)
        }

        let result = context.evaluateScript(script)
        if logs.isEmpty, let res = result, !res.isUndefined {
            logs.append("→ \(res)")
        }
        return logs.isEmpty ? "(No console output)" : logs.joined(separator: "\n")
    }

    private func wandboxCompiler(for language: CodeLanguage) -> String? {
        switch language {
        case .cpp: return "gcc-head"
        case .c: return "gcc-head-c"
        case .objectiveC: return "clang-head-c"
        case .python: return "cpython-3.12.7"
        case .swift: return "swift-6.0.1"
        case .typescript: return "typescript-5.6.2"
        case .shell: return "bash"
        default: return nil
        }
    }

    private func executeViaZeroConfigSandbox(compiler: String, code: String, stdin: String) async -> String {
        guard let url = URL(string: "https://wandbox.org/api/compile.json") else {
            return "Invalid compiler URL."
        }
        var payload: [String: Any] = [
            "compiler": compiler,
            "code": code,
            "stdin": stdin
        ]
        if compiler == "gcc-head" {
            payload["options"] = "warning,gnu++20"
            payload["compiler-option-raw"] = "-O2"
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return String(data: data, encoding: .utf8) ?? "Unexpected response."
            }
            var pieces: [String] = []
            if let compErr = json["compiler_error"] as? String, !compErr.isEmpty {
                pieces.append("🛠 Compiler Diagnostics:\n" + compErr)
            }
            if let progOut = json["program_output"] as? String, !progOut.isEmpty {
                pieces.append(progOut)
            } else if let progMsg = json["program_message"] as? String, !progMsg.isEmpty {
                pieces.append(progMsg)
            }
            if let progErr = json["program_error"] as? String, !progErr.isEmpty, pieces.isEmpty {
                pieces.append("⚠️ Runtime Error:\n" + progErr)
            }
            if let status = json["status"] as? String, status != "0" {
                pieces.append("[Exit code: \(status)]")
            }
            return pieces.isEmpty ? "(Program exited with 0 — no output)" : pieces.joined(separator: "\n")
        } catch {
            return "⚠️ Network error reaching Zero-Config Compiler (\(error.localizedDescription)). Configure your VPS or check internet connection."
        }
    }

    private func executeOnCustomVPS(endpoint: String, code: String, language: CodeLanguage, fileName: String, stdin: String) async -> String? {
        guard let url = URL(string: endpoint) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !vpsAuthToken.isEmpty {
            req.setValue("Bearer \(vpsAuthToken)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "language": language.rawValue,
            "filename": fileName,
            "code": code,
            "stdin": stdin
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let out = json["output"] as? String {
                return out
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Local Workspace Shell
    public func executeLocalShellCommand(_ rawCommand: String, workspaceRoot: URL, onFilesystemMutated: () -> Void) {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cwd = currentShellDirectory ?? workspaceRoot
        shellHistory.append("$ \(trimmed)")

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = String(parts[0]).lowercased()
        let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        let fm = FileManager.default
        switch cmd {
        case "help":
            shellHistory.append("""
            Available commands:
              ls              List files in current directory
              pwd             Show current directory
              cd <dir>        Change directory
              cat <file>      Print file contents
              touch <file>    Create empty file
              mkdir <dir>     Create directory
              rm <target>     Delete file or folder
              js <expr>       Evaluate JavaScript expression locally
              clear           Clear terminal history
            """)
        case "clear":
            shellHistory.removeAll()
        case "pwd":
            shellHistory.append(cwd.path)
        case "ls":
            let target = arg.isEmpty ? cwd : cwd.appendingPathComponent(arg)
            let items = (try? fm.contentsOfDirectory(atPath: target.path))?.sorted() ?? []
            shellHistory.append(items.isEmpty ? "(empty)" : items.joined(separator: "  "))
        case "cd":
            if arg.isEmpty || arg == "~" || arg == "/" {
                currentShellDirectory = workspaceRoot
            } else {
                let candidate = cwd.appendingPathComponent(arg).standardizedFileURL
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    currentShellDirectory = candidate
                } else {
                    shellHistory.append("cd: no such directory: \(arg)")
                }
            }
        case "cat":
            guard !arg.isEmpty else { shellHistory.append("usage: cat <file>"); return }
            let target = cwd.appendingPathComponent(arg)
            if let text = try? String(contentsOf: target, encoding: .utf8) {
                shellHistory.append(text)
            } else {
                shellHistory.append("cat: cannot read \(arg)")
            }
        case "touch":
            guard !arg.isEmpty else { shellHistory.append("usage: touch <file>"); return }
            let target = cwd.appendingPathComponent(arg)
            try? "".write(to: target, atomically: true, encoding: .utf8)
            onFilesystemMutated()
            shellHistory.append("Created \(arg)")
        case "mkdir":
            guard !arg.isEmpty else { shellHistory.append("usage: mkdir <dir>"); return }
            let target = cwd.appendingPathComponent(arg, isDirectory: true)
            try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            onFilesystemMutated()
            shellHistory.append("Directory created: \(arg)")
        case "rm":
            guard !arg.isEmpty else { shellHistory.append("usage: rm <path>"); return }
            let target = cwd.appendingPathComponent(arg)
            do {
                try fm.removeItem(at: target)
                onFilesystemMutated()
                shellHistory.append("Removed \(arg)")
            } catch {
                shellHistory.append("rm: \(error.localizedDescription)")
            }
        case "js", "node":
            guard !arg.isEmpty else { shellHistory.append("usage: js <javascript code>"); return }
            shellHistory.append(executeJavaScriptLocally(arg))
        default:
            shellHistory.append("Command '\(cmd)' not found in local sandbox. Type 'help' or connect VPS SSH in Phase 3 for full Linux bash.")
        }
    }
}
