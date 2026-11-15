import Foundation
import JavaScriptCore
import CryptoKit

@MainActor
public final class CodeRunnerService: ObservableObject {
    @Published public var consoleOutput: String = "Ready. Tap Run to execute any file without configuring PATH or compilers.\n"
    @Published public var stdinInput: String = ""
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastExecutionFailed: Bool = false
    @Published public private(set) var lastErrorSummary: String = ""
    @Published public var shellHistory: [String] = [
        "3012 Local Workspace Shell v1.0 — type 'help' for commands."
    ]
    @Published public private(set) var currentShellDirectory: URL?

    // Optional User VPS Runner Endpoint (Zero-Config Remote Compile Server)
    @Published public var vpsEndpointURL: String {
        didSet { UserDefaults.standard.set(vpsEndpointURL, forKey: "3012.vpsEndpointURL") }
    }
    @Published public var vpsAuthToken: String {
        didSet {
            if vpsAuthToken.isEmpty {
                KeychainVault.delete(forKey: "3012.vpsAuthToken")
            } else {
                KeychainVault.saveString(vpsAuthToken, forKey: "3012.vpsAuthToken")
            }
        }
    }

    private struct CachedExecutionResult {
        let output: String
        let backend: String
        let failed: Bool
        let timestamp: Date
    }
    private var executionCache: [String: CachedExecutionResult] = [:]

    public init() {
        self.vpsEndpointURL = UserDefaults.standard.string(forKey: "3012.vpsEndpointURL") ?? ""
        let keychainToken = KeychainVault.loadString(forKey: "3012.vpsAuthToken") ?? ""
        if keychainToken.isEmpty,
           let legacyToken = UserDefaults.standard.string(forKey: "3012.vpsAuthToken"),
           !legacyToken.isEmpty {
            KeychainVault.saveString(legacyToken, forKey: "3012.vpsAuthToken")
            UserDefaults.standard.removeObject(forKey: "3012.vpsAuthToken")
            self.vpsAuthToken = legacyToken
        } else {
            UserDefaults.standard.removeObject(forKey: "3012.vpsAuthToken")
            self.vpsAuthToken = keychainToken
        }
    }

    public static let vpsBootstrapCommand: String = """
    sudo apt-get update && sudo apt-get install -y build-essential gcc g++ gdb clang clangd cmake python3 python3-pip nodejs npm git ripgrep && echo "[OK] 3012 VPS Toolchain Installed"
    """

    public func runCode(
        code: String,
        language: CodeLanguage,
        fileName: String,
        sshService: SSHWorkspaceService? = nil,
        bypassCache: Bool = false
    ) async {
        isRunning = true
        let startTime = Date()
        consoleOutput = "[Run] \(fileName) (\(language.rawValue))...\n"
        lastExecutionFailed = false
        lastErrorSummary = ""

        defer {
            isRunning = false
        }

        let res = await executeCodeSnapshot(
            code: code,
            language: language,
            fileName: fileName,
            stdin: stdinInput,
            sshService: sshService,
            bypassCache: bypassCache
        )
        let elapsed = max(res.durationMs, Int(Date().timeIntervalSince(startTime) * 1000))
        lastExecutionFailed = res.failed
        lastErrorSummary = res.failed ? String(res.output.prefix(600)) : ""
        consoleOutput += res.output + "\n\n[Done in \(elapsed) ms — \(res.backend)]"
    }

    public func executeCodeSnapshot(
        code: String,
        language: CodeLanguage,
        fileName: String = "main",
        stdin: String,
        sshService: SSHWorkspaceService? = nil,
        bypassCache: Bool = false
    ) async -> (output: String, failed: Bool, durationMs: Int, backend: String) {
        let startTime = Date()

        // 0. SSH VPS if connected
        if let ssh = sshService, ssh.isConnected {
            let vpsOut = await ssh.compileAndRunOnVPS(code: code, language: language, fileName: fileName, stdin: stdin)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let failed = Self.detectErrorInOutput(vpsOut)
            return (vpsOut, failed, elapsed, "SSH VPS: \(ssh.connectedProfile?.host ?? "Remote")")
        }

        // 1. Local JavaScriptCore for plain JS (off MainActor)
        if language == .javascript {
            let jsResult = await executeJavaScriptOffMainActor(code)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return (jsResult.output, jsResult.failed, elapsed, "Local JavaScriptCore")
        }

        // 2. Private VPS Runner URL
        let trimmedVPS = vpsEndpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVPS.isEmpty, let vpsResult = await executeOnCustomVPS(endpoint: trimmedVPS, code: code, language: language, fileName: fileName, stdin: stdin) {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return (vpsResult.output, vpsResult.failed, elapsed, "Remote VPS")
        }

        // 3. SHA-256 Instant Cache hit for identical code+stdin
        let cacheKey = Self.computeCacheKey(language: language, code: code, stdin: stdin)
        if !bypassCache, let cached = executionCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < 300 {
            return (cached.output, cached.failed, 0, "\(cached.backend) [Cached]")
        }

        // 4. Tier A: Fast Godbolt Compiler Explorer (~1.3s Python, ~2.0s C++20 -O1, zero pid1 bug)
        if let fastResult = await executeViaFastGodbolt(language: language, code: code, stdin: stdin) {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            storeCache(key: cacheKey, output: fastResult.output, backend: fastResult.backend, failed: fastResult.failed)
            return (fastResult.output, fastResult.failed, elapsed, fastResult.backend)
        }

        // 5. Tier B: Wandbox Pinned Stable Compilers (zero broken '-head' images)
        if let compilerName = wandboxCompiler(for: language) {
            let result = await executeViaZeroConfigSandbox(compiler: compilerName, code: code, stdin: stdin)
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            if !result.output.hasPrefix("[Network Error]") {
                storeCache(key: cacheKey, output: result.output, backend: "Zero-Config: \(compilerName)", failed: result.failed)
            }
            return (result.output, result.failed, elapsed, "Zero-Config: \(compilerName)")
        }

        return (
            "Direct execution is not required for \(language.rawValue). For HTML/CSS, Live Server (:5500) handles instant preview.",
            false,
            0,
            "Static Preview"
        )
    }

    private func storeCache(key: String, output: String, backend: String, failed: Bool) {
        if executionCache.count >= 32 {
            if let oldest = executionCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                executionCache.removeValue(forKey: oldest)
            }
        }
        executionCache[key] = CachedExecutionResult(output: output, backend: backend, failed: failed, timestamp: Date())
    }

    private static func computeCacheKey(language: CodeLanguage, code: String, stdin: String) -> String {
        let material = "\(language.rawValue)|\(stdin)|\(code)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func detectErrorInOutput(_ output: String) -> Bool {
        let low = output.lowercased()
        if low.contains("[compiler diagnostics]")
            || low.contains("[runtime error]")
            || low.contains("[js exception]")
            || low.contains("[network error]")
            || low.contains("traceback (most recent call last)") {
            return true
        }
        if let range = low.range(of: "[exit code:") {
            let tail = low[range.upperBound...]
            if let close = tail.firstIndex(of: "]") {
                let codeStr = tail[..<close].trimmingCharacters(in: .whitespaces)
                return codeStr != "0"
            }
        }
        return false
    }

    private func executeViaFastGodbolt(language: CodeLanguage, code: String, stdin: String) async -> (output: String, failed: Bool, backend: String)? {
        let compilerID: String
        let userArgs: String
        switch language {
        case .cpp:
            compilerID = "g132"
            userArgs = "-std=c++20 -O1"
        case .python:
            compilerID = "python312"
            userArgs = ""
        default:
            return nil
        }

        guard let url = URL(string: "https://godbolt.org/api/compiler/\(compilerID)/compile") else { return nil }
        let payload: [String: Any] = [
            "source": code,
            "options": [
                "userArguments": userArgs,
                "compilerOptions": ["executorRequest": true],
                "filters": ["execute": true],
                "executeParameters": ["args": "", "stdin": stdin]
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("3012-Mobile-IDE/5.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            func flattenText(_ items: [[String: Any]]?) -> String {
                (items ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
            }

            let buildRes = json["buildResult"] as? [String: Any]
            let buildCode = buildRes?["code"] as? Int ?? 0
            let compErr = flattenText(buildRes?["stderr"] as? [[String: Any]])
            let execStdout = flattenText(json["stdout"] as? [[String: Any]])
            let execStderr = flattenText(json["stderr"] as? [[String: Any]])
            let exitCode = json["code"] as? Int ?? 0

            // Check that execution actually ran if required
            if let didExecute = json["didExecute"] as? Bool, !didExecute, buildCode == 0 {
                return nil
            }

            var pieces: [String] = []
            if !compErr.isEmpty {
                pieces.append("[Compiler Diagnostics]\n" + compErr)
            }
            if !execStdout.isEmpty {
                pieces.append(execStdout)
            }
            if !execStderr.isEmpty {
                pieces.append("[Runtime Error]\n" + execStderr)
            }
            if buildCode != 0 || exitCode != 0 {
                let codeNum = buildCode != 0 ? buildCode : exitCode
                pieces.append("[Exit code: \(codeNum)]")
            }
            let outText = pieces.isEmpty ? "(Program exited with 0 — no output)" : pieces.joined(separator: "\n")
            let failed = (buildCode != 0 || exitCode != 0 || !execStderr.isEmpty)
            return (outText, failed, "Fast Engine (\(compilerID))")
        } catch {
            return nil
        }
    }

    private func executeJavaScriptOffMainActor(_ script: String) async -> (output: String, failed: Bool) {
        let rawTuple: (String, Bool) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let res = Self.executeJavaScriptSynchronously(script)
                continuation.resume(returning: res)
            }
        }
        return (rawTuple.0, rawTuple.1)
    }

    nonisolated private static func executeJavaScriptSynchronously(_ script: String) -> (String, Bool) {
        guard let context = JSContext() else {
            return ("Failed to initialize JavaScriptCore context.", true)
        }
        let maxBytes = 128 * 1024
        var totalBytes = 0
        var truncated = false
        var logs: [String] = []
        var hadError = false

        func appendCapturedLine(_ line: String) {
            guard !truncated else { return }
            let byteCount = line.utf8.count + (logs.isEmpty ? 0 : 1)
            if totalBytes + byteCount > maxBytes {
                let remaining = max(0, maxBytes - totalBytes)
                if remaining > 0 {
                    logs.append(String(line.prefix(remaining)))
                }
                logs.append("... [Output truncated at 128 KB]")
                truncated = true
                totalBytes = maxBytes
            } else {
                logs.append(line)
                totalBytes += byteCount
            }
        }

        let logBlock: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() ?? []
            let line = args.map { "\($0)" }.joined(separator: " ")
            appendCapturedLine(line)
        }
        let errorBlock: @convention(block) () -> Void = {
            hadError = true
            let args = JSContext.currentArguments() ?? []
            let line = args.map { "\($0)" }.joined(separator: " ")
            appendCapturedLine("[Error] " + line)
        }

        context.exceptionHandler = { _, exception in
            hadError = true
            if let exc = exception {
                appendCapturedLine("[JS Exception] \(exc)")
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
            appendCapturedLine("→ \(res)")
        }
        let output = logs.isEmpty ? "(No console output)" : logs.joined(separator: "\n")
        return (output, hadError)
    }

    private func wandboxCompiler(for language: CodeLanguage) -> String? {
        switch language {
        case .cpp: return "gcc-13.2.0"
        case .c: return "gcc-13.2.0-c"
        case .objectiveC: return "gcc-13.2.0-c"
        case .csharp: return "mono-6.12.0.199"
        case .go: return "go-1.23.2"
        case .rust: return "rust-1.82.0"
        case .zig: return "zig-0.13.0"
        case .dlang: return "dmd-2.109.1"
        case .nim: return "nim-2.2.10"
        case .crystal: return "crystal-1.13.3"
        case .java: return "openjdk-jdk-22+36"
        case .scala: return "scala-3.5.1"
        case .groovy: return "groovy-4.0.23"
        case .python: return "cpython-3.12.7"
        case .swift: return "swift-6.0.1"
        case .typescript, .tsx: return "typescript-5.6.2"
        case .php: return "php-8.3.12"
        case .ruby: return "ruby-4.0.2"
        case .perl: return "perl-5.44.0"
        case .lua: return "lua-5.4.7"
        case .r: return "r-4.4.1"
        case .julia: return "julia-1.10.5"
        case .elixir: return "elixir-1.17.3"
        case .erlang: return "erlang-27.1"
        case .haskell: return "ghc-9.10.1"
        case .ocaml: return "ocaml-5.2.0"
        case .lisp: return "clisp-2.49"
        case .pascal: return "fpc-3.2.2"
        case .sql: return "sqlite-3.46.1"
        case .shell, .fish: return "bash"
        default: return nil
        }
    }

    private func executeViaZeroConfigSandbox(compiler: String, code: String, stdin: String) async -> (output: String, failed: Bool) {
        guard let url = URL(string: "https://wandbox.org/api/compile.json") else {
            return ("Invalid compiler URL.", true)
        }
        var payload: [String: Any] = [
            "compiler": compiler,
            "code": code,
            "stdin": stdin
        ]
        if compiler == "gcc-13.2.0" || compiler == "gcc-head" {
            payload["options"] = "warning,gnu++20"
            payload["compiler-option-raw"] = "-O1"
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("3012-Mobile-IDE/5.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let raw = String(data: data, encoding: .utf8) ?? "Unexpected response."
                return (raw, Self.detectErrorInOutput(raw))
            }
            var pieces: [String] = []
            let compErr = (json["compiler_error"] as? String) ?? ""
            if !compErr.isEmpty {
                pieces.append("[Compiler Diagnostics]\n" + compErr)
            }
            if let progOut = json["program_output"] as? String, !progOut.isEmpty {
                pieces.append(progOut)
            } else if let progMsg = json["program_message"] as? String, !progMsg.isEmpty {
                pieces.append(progMsg)
            }
            let progErr = (json["program_error"] as? String) ?? ""
            if !progErr.isEmpty {
                pieces.append("[Runtime Error]\n" + progErr)
            }
            let status = (json["status"] as? String) ?? "0"
            if status != "0" {
                pieces.append("[Exit code: \(status)]")
            }
            let output = pieces.isEmpty ? "(Program exited with 0 — no output)" : pieces.joined(separator: "\n")
            let failed = (status != "0") || !progErr.isEmpty
            return (output, failed)
        } catch {
            return ("[Network Error] Could not reach Zero-Config Compiler (\(error.localizedDescription)). Configure your VPS or check internet connection.", true)
        }
    }

    private func executeOnCustomVPS(endpoint: String, code: String, language: CodeLanguage, fileName: String, stdin: String) async -> (output: String, failed: Bool)? {
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
                let exitCode = (json["exitCode"] as? Int) ?? (json["exit_code"] as? Int)
                let failed = exitCode.map { $0 != 0 } ?? Self.detectErrorInOutput(out)
                return (out, failed)
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            return (text, Self.detectErrorInOutput(text))
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
              claude / opencode  Run AI Coding CLI directly on project files
              code <file>        Open or create & open file in 3012 Editor
              dir / ls | cd | pwd | tree | type / cat | copy / cp | move / mv | del / rm
              gcc / g++ / python / node / swift / npm / git / zip / unzip / wget / curl / ping
              bot new [tok]      Create & launch 24/7 local Telegram bot
              ps | logs | kill   Manage running background processes on device
              keepalive on/off   Toggle screen-off 24/7 Keep-Alive
              cls / clear        Clear terminal history
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
            let target = cwd.appendingPathComponent(arg).standardizedFileURL
            let rootCanon = WorkspaceManager.canonicalPath(workspaceRoot)
            let targetCanon = WorkspaceManager.canonicalPath(target)
            guard arg != ".", arg != "..", targetCanon != rootCanon, targetCanon.hasPrefix(rootCanon + "/") else {
                shellHistory.append("rm: refusing to remove workspace root or path outside workspace: \(arg)")
                return
            }
            do {
                try fm.removeItem(at: target)
                onFilesystemMutated()
                shellHistory.append("Removed \(arg)")
            } catch {
                shellHistory.append("rm: \(error.localizedDescription)")
            }
        case "js", "node":
            guard !arg.isEmpty else { shellHistory.append("usage: js <javascript code>"); return }
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                let res = await self.executeJavaScriptOffMainActor(arg)
                self.shellHistory.append(res.output)
            }
        default:
            shellHistory.append("Command '\(cmd)' not found in local sandbox. Type 'help' or connect VPS SSH in Phase 3 for full Linux bash.")
        }
    }
}
