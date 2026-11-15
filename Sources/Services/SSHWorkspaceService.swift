import Foundation
import Network
import Citadel
import NIOCore
import NIO
import NIOSSH
import Crypto

public struct VPSHostProfile: Codable, Identifiable, Equatable {
    public enum AuthKind: String, Codable, CaseIterable, Identifiable {
        case password = "Password"
        case generatedEd25519 = "SSH Key (Ed25519)"

        public var id: String { rawValue }
    }

    public var id: UUID
    public var label: String
    public var host: String
    public var port: Int
    public var username: String
    public var authKind: AuthKind
    public var initialRemotePath: String

    public init(
        id: UUID = UUID(),
        label: String = "My VPS",
        host: String = "",
        port: Int = 22,
        username: String = "root",
        authKind: AuthKind = .password,
        initialRemotePath: String = "."
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.username = username
        self.authKind = authKind
        self.initialRemotePath = initialRemotePath
    }

    public var keychainPasswordKey: String {
        "vps.password.\(id.uuidString)"
    }
}

public struct SFTPRemoteItem: Identifiable, Equatable {
    public var id: String { fullPath }
    public let name: String
    public let fullPath: String
    public let isDirectory: Bool
    public let sizeBytes: UInt64
}

public struct ActivePortTunnel: Identifiable, Equatable {
    public let id: UUID = UUID()
    public let localPort: UInt16
    public let remoteHost: String
    public let remotePort: UInt16
}

private final class TunnelInboundBridgeHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    let nwConnection: NWConnection

    init(nwConnection: NWConnection) {
        self.nwConnection = nwConnection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
            nwConnection.send(content: Data(bytes), completion: .contentProcessed { _ in })
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        nwConnection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [nwConnection] _ in
            nwConnection.cancel()
        })
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        nwConnection.cancel()
        context.close(promise: nil)
    }
}

private final class TunnelConnectionStore: @unchecked Sendable {
    private let lock = NSLock()
    private var connectionsByPort: [UInt16: [ObjectIdentifier: NWConnection]] = [:]

    func add(_ conn: NWConnection, forPort port: UInt16) {
        let id = ObjectIdentifier(conn)
        lock.lock()
        var map = connectionsByPort[port] ?? [:]
        map[id] = conn
        connectionsByPort[port] = map
        lock.unlock()
    }

    func remove(_ conn: NWConnection, forPort port: UInt16) {
        let id = ObjectIdentifier(conn)
        lock.lock()
        connectionsByPort[port]?[id] = nil
        if connectionsByPort[port]?.isEmpty == true {
            connectionsByPort[port] = nil
        }
        lock.unlock()
    }

    func cancelAll(forPort port: UInt16) {
        lock.lock()
        let conns = connectionsByPort.removeValue(forKey: port)?.values
        lock.unlock()
        conns?.forEach { $0.cancel() }
    }

    func cancelAll() {
        lock.lock()
        let maps = Array(connectionsByPort.values)
        connectionsByPort.removeAll()
        lock.unlock()
        for map in maps {
            map.values.forEach { $0.cancel() }
        }
    }
}

@MainActor
public final class SSHWorkspaceService: ObservableObject {
    @Published public var savedProfiles: [VPSHostProfile] = [] {
        didSet { persistProfiles() }
    }
    @Published public private(set) var connectedProfile: VPSHostProfile?
    @Published public private(set) var isConnecting: Bool = false
    @Published public var statusMessage: String = "Chưa kết nối VPS"
    @Published public var currentRemoteDirectory: String = "/"
    @Published public private(set) var remoteEntries: [SFTPRemoteItem] = []
    @Published public private(set) var activeTunnels: [ActivePortTunnel] = []

    // Interactive PTY Bridge callbacks for SwiftTerm
    public var onPTYOutput: (([UInt8]) -> Void)?

    private var sshClient: SSHClient?
    private var sftpClient: SFTPClient?
    private var ptyTask: Task<Void, Never>?
    private var ptyStdinWriter: TTYStdinWriter?
    private var tunnelListeners: [UInt16: NWListener] = [:]
    private let tunnelConnectionStore = TunnelConnectionStore()
    private let tunnelQueue = DispatchQueue(label: "com.dev.app3012.sshtunnel", qos: .userInitiated)

    // Mapping from local cached file URL -> remote SFTP path so Editor tabs sync automatically on Save!
    private var remoteFileBindings: [URL: String] = [:]

    public var isConnected: Bool {
        sshClient != nil && connectedProfile != nil
    }

    public init() {
        loadProfiles()
    }

    // MARK: - Connection Lifecycle
    public func connect(to profile: VPSHostProfile, passwordOverride: String? = nil) async {
        guard !profile.host.trimmingCharacters(in: .whitespaces).isEmpty else {
            statusMessage = "Vui lòng nhập IP / Hostname của VPS."
            return
        }
        await disconnect()
        isConnecting = true
        statusMessage = "Đang kết nối SSH tới \(profile.username)@\(profile.host):\(profile.port)..."

        do {
            let authMethod: SSHAuthenticationMethod
            switch profile.authKind {
            case .password:
                let pwd = passwordOverride ?? KeychainVault.loadString(forKey: profile.keychainPasswordKey) ?? ""
                authMethod = .passwordBased(username: profile.username, password: pwd)
            case .generatedEd25519:
                let keyPair = KeychainVault.generateOrLoadDeviceEd25519Key()
                let privKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyPair.rawPrivateKey)
                authMethod = .ed25519(username: profile.username, privateKey: privKey)
            }

            let client = try await SSHClient.connect(
                host: profile.host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: profile.port,
                authenticationMethod: authMethod,
                hostKeyValidator: .acceptAnything(),
                reconnect: .once
            )

            let sftp = try await client.openSFTP()
            let resolvedStart = (try? await sftp.getRealPath(atPath: profile.initialRemotePath)) ?? "/"

            self.sshClient = client
            self.sftpClient = sftp
            self.connectedProfile = profile
            self.currentRemoteDirectory = resolvedStart
            self.isConnecting = false
            self.statusMessage = "Đã kết nối \(profile.username)@\(profile.host)"

            await refreshRemoteDirectory()
            startInteractivePTYShell()
        } catch {
            self.isConnecting = false
            self.statusMessage = "Lỗi kết nối SSH: \(error.localizedDescription)"
        }
    }

    public func disconnect() async {
        ptyTask?.cancel()
        ptyTask = nil
        ptyStdinWriter = nil

        for (_, listener) in tunnelListeners {
            listener.cancel()
        }
        tunnelListeners.removeAll()
        tunnelConnectionStore.cancelAll()
        activeTunnels.removeAll()
        remoteFileBindings.removeAll()

        if let sftp = sftpClient {
            try? await sftp.close()
        }
        sftpClient = nil

        if let client = sshClient {
            try? await client.close()
        }
        sshClient = nil
        connectedProfile = nil
        remoteEntries = []
        statusMessage = "Đã ngắt kết nối VPS"
    }

    // MARK: - SFTP Remote File Explorer & Seamless Editor Sync
    public func refreshRemoteDirectory(at customPath: String? = nil) async {
        guard let sftp = sftpClient else { return }
        let target = customPath ?? currentRemoteDirectory
        do {
            let canonical = (try? await sftp.getRealPath(atPath: target)) ?? target
            let namePackets = try await sftp.listDirectory(atPath: canonical)
            var parsed: [SFTPRemoteItem] = []

            for packet in namePackets {
                for comp in packet.components {
                    let fname = comp.filename
                    guard fname != "." && fname != ".." && !fname.contains("/") && !fname.contains("\\") else { continue }
                    let isDir: Bool
                    if let perms = comp.attributes.permissions {
                        isDir = (perms & 0o170000) == 0o040000
                    } else {
                        isDir = comp.longname.hasPrefix("d")
                    }
                    let joined = canonical == "/" ? "/\(fname)" : "\(canonical)/\(fname)"
                    parsed.append(SFTPRemoteItem(
                        name: fname,
                        fullPath: joined,
                        isDirectory: isDir,
                        sizeBytes: comp.attributes.size ?? 0
                    ))
                }
            }

            parsed.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            self.currentRemoteDirectory = canonical
            self.remoteEntries = parsed
        } catch {
            self.statusMessage = "Lỗi đọc SFTP: \(error.localizedDescription)"
        }
    }

    public func navigateUpRemoteDirectory() async {
        guard currentRemoteDirectory != "/" else { return }
        let parent = (currentRemoteDirectory as NSString).deletingLastPathComponent
        await refreshRemoteDirectory(at: parent.isEmpty ? "/" : parent)
    }

    public func downloadRemoteFileToLocalCache(remotePath: String) async -> URL? {
        guard let sftp = sftpClient, let profile = connectedProfile else { return nil }
        do {
            let buffer = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
                try await file.readAll()
            }
            let data = Data(buffer.readableBytesView)
            let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("RemoteSFTP", isDirectory: true)
                .appendingPathComponent(profile.id.uuidString, isDirectory: true)

            let cleanRel = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !cleanRel.contains("..") else {
                throw NSError(domain: "SSHWorkspaceService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Invalid SFTP path"])
            }
            let localMirrorURL = cacheRoot.appendingPathComponent(cleanRel)
            let canonRoot = WorkspaceManager.canonicalPath(cacheRoot)
            let canonMirror = WorkspaceManager.canonicalPath(localMirrorURL)
            guard canonMirror.hasPrefix(canonRoot.hasSuffix("/") ? canonRoot : canonRoot + "/") else {
                throw NSError(domain: "SSHWorkspaceService", code: 403, userInfo: [NSLocalizedDescriptionKey: "SFTP path outside cache root"])
            }
            try FileManager.default.createDirectory(at: localMirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: localMirrorURL, options: .atomic)
            remoteFileBindings[localMirrorURL.standardizedFileURL] = remotePath
            return localMirrorURL
        } catch {
            statusMessage = "Không tải được file SFTP: \(error.localizedDescription)"
            return nil
        }
    }

    public func remotePathBound(to localURL: URL) -> String? {
        remoteFileBindings[localURL.standardizedFileURL]
    }

    public func syncSavedLocalMirrorIfNeeded(localURL: URL, content: String) {
        guard let remotePath = remoteFileBindings[localURL.standardizedFileURL],
              let sftp = sftpClient else { return }
        Task {
            do {
                var buf = ByteBufferAllocator().buffer(capacity: content.utf8.count)
                buf.writeString(content)
                let finalBuf = buf
                try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
                    try await file.write(finalBuf)
                }
                self.statusMessage = "Đã lưu SFTP: \((remotePath as NSString).lastPathComponent)"
            } catch {
                self.statusMessage = "Lỗi lưu SFTP: \(error.localizedDescription)"
            }
        }
    }

    public func createRemoteFile(named name: String) async -> URL? {
        guard let sftp = sftpClient else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let remotePath = currentRemoteDirectory == "/" ? "/\(trimmed)" : "\(currentRemoteDirectory)/\(trimmed)"
        let template = CodeLanguage.detect(from: URL(fileURLWithPath: trimmed)).starterTemplate
        do {
            var buf = ByteBufferAllocator().buffer(capacity: template.utf8.count)
            buf.writeString(template)
            let finalBuf = buf
            try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
                try await file.write(finalBuf)
            }
            await refreshRemoteDirectory()
            return await downloadRemoteFileToLocalCache(remotePath: remotePath)
        } catch {
            statusMessage = "Lỗi tạo file SFTP: \(error.localizedDescription)"
            return nil
        }
    }

    public func createRemoteFolder(named name: String) async {
        guard let sftp = sftpClient else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let remotePath = currentRemoteDirectory == "/" ? "/\(trimmed)" : "\(currentRemoteDirectory)/\(trimmed)"
        do {
            try await sftp.createDirectory(atPath: remotePath)
            await refreshRemoteDirectory()
        } catch {
            statusMessage = "Lỗi tạo thư mục SFTP: \(error.localizedDescription)"
        }
    }

    public func deleteRemoteItem(_ item: SFTPRemoteItem) async {
        guard let sftp = sftpClient else { return }
        do {
            if item.isDirectory {
                try await sftp.rmdir(at: item.fullPath)
            } else {
                try await sftp.remove(at: item.fullPath)
            }
            await refreshRemoteDirectory()
        } catch {
            statusMessage = "Lỗi xóa trên VPS: \(error.localizedDescription)"
        }
    }

    public func uploadDataViaSFTP(data: Data, remotePath: String) async throws {
        guard let sftp = sftpClient else {
            throw NSError(domain: "SSHWorkspaceService", code: 503, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối SFTP tới VPS."])
        }
        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        let finalBuf = buf
        try await sftp.withFile(filePath: remotePath, flags: [.write, .create, .truncate]) { file in
            try await file.write(finalBuf)
        }
    }

    public func downloadDataViaSFTP(remotePath: String, maxBytes: Int = 128 * 1024 * 1024) async throws -> Data {
        guard let sftp = sftpClient else {
            throw NSError(domain: "SSHWorkspaceService", code: 503, userInfo: [NSLocalizedDescriptionKey: "Chưa kết nối SFTP tới VPS."])
        }
        let buffer = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            if maxBytes > 0, let attrs = try? await file.readAttributes(), let size = attrs.size, size > UInt64(maxBytes) {
                throw NSError(domain: "SSHWorkspaceService", code: 413, userInfo: [NSLocalizedDescriptionKey: "File vượt quá giới hạn \(maxBytes) bytes (\(size) bytes)."])
            }
            return try await file.readAll()
        }
        let data = Data(buffer.readableBytesView)
        if maxBytes > 0, data.count > maxBytes {
            throw NSError(domain: "SSHWorkspaceService", code: 413, userInfo: [NSLocalizedDescriptionKey: "File vượt quá giới hạn \(maxBytes) bytes (\(data.count) bytes)."])
        }
        return data
    }

    // MARK: - Remote Command & Zero-Config VPS Code Runner
    public func executeCommandOnVPS(_ command: String) async -> String {
        guard let client = sshClient else {
            return "Chưa kết nối SSH tới VPS."
        }
        let marker = "__3012_EXIT:"
        let wrapped = "(\n\(command)\n); printf '\\n\(marker)%d__' $?"
        do {
            let buffer = try await client.executeCommand(wrapped, maxResponseSize: 4 * 1024 * 1024, mergeStreams: true, inShell: true)
            let raw = String(buffer: buffer)
            guard let markerRange = raw.range(of: marker, options: .backwards) else {
                return raw
            }
            let body = String(raw[..<markerRange.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            let afterMarker = raw[markerRange.upperBound...]
            let codeStr = afterMarker.prefix { $0.isNumber || $0 == "-" }
            let exitCode = Int(codeStr) ?? 0
            if exitCode == 0 {
                return body
            }
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "[Process exited with code \(exitCode)]"
            }
            return "\(body)\n[Process exited with code \(exitCode)]"
        } catch let failed as SSHClient.CommandFailed {
            return "[Process exited with code \(failed.exitCode)]"
        } catch {
            return "[SSH Error] \(error.localizedDescription)"
        }
    }

    public func executeCommandStdoutOnZeroExit(_ command: String) async -> String? {
        guard let client = sshClient else { return nil }
        do {
            let buffer = try await client.executeCommand(command, maxResponseSize: 4 * 1024 * 1024, mergeStreams: false, inShell: true)
            return String(buffer: buffer)
        } catch {
            return nil
        }
    }

    private func shellSingleQuote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs `git` on the connected SSH VPS with an ephemeral 0700 `GIT_ASKPASS` script deleted cleanly on shell exit.
    public func executeGitCommandOnVPS(_ gitArgs: [String], in remoteDir: String, githubToken: String? = nil) async -> (exitCode: Int, output: String) {
        guard let client = sshClient else {
            return (1, "Chưa kết nối SSH tới VPS.")
        }
        let dirEsc = shellSingleQuote(remoteDir)
        let argsJoined = gitArgs.map { shellSingleQuote($0) }.joined(separator: " ")
        let cleanToken = (githubToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let script: String
        if !cleanToken.isEmpty {
            let tokenEsc = shellSingleQuote(cleanToken)
            script = """
            ASKPASS=$(mktemp /tmp/.3012_askpass_XXXXXX) && chmod 700 "$ASKPASS" && cat << 'EOF_3012_ASKPASS' > "$ASKPASS"
            #!/bin/sh
            case "$1" in
            *Username*|*username*) printf '%s\\n' "x-access-token" ;;
            *) printf '%s\\n' "$_3012_GH_TOK" ;;
            esac
            EOF_3012_ASKPASS
            rc=$?
            if [ "$rc" -eq 0 ]; then
                (cd \(dirEsc) && _3012_GH_TOK=\(tokenEsc) GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 git -c credential.helper= \(argsJoined))
                rc=$?
            fi
            rm -f "$ASKPASS"
            (exit "$rc")
            """
        } else {
            script = "cd \(dirEsc) && GIT_TERMINAL_PROMPT=0 git \(argsJoined)"
        }

        let marker = "__3012_EXIT:"
        let wrapped = "(\n\(script)\n); printf '\\n\(marker)%d__' $?"
        do {
            let buffer = try await client.executeCommand(wrapped, maxResponseSize: 4 * 1024 * 1024, mergeStreams: true, inShell: true)
            let raw = String(buffer: buffer)
            guard let markerRange = raw.range(of: marker, options: .backwards) else {
                return (0, raw)
            }
            let body = String(raw[..<markerRange.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            let afterMarker = raw[markerRange.upperBound...]
            let codeStr = afterMarker.prefix { $0.isNumber || $0 == "-" }
            let exitCode = Int(codeStr) ?? 0
            return (exitCode, body)
        } catch let failed as SSHClient.CommandFailed {
            return (Int(failed.exitCode), "[Process exited with code \(failed.exitCode)]")
        } catch {
            return (1, "[SSH Error] \(error.localizedDescription)")
        }
    }

    public func compileAndRunOnVPS(code: String, language: CodeLanguage, fileName: String, stdin: String) async -> String {
        guard sshClient != nil else { return "Not connected" }
        let rawBase = URL(fileURLWithPath: fileName).lastPathComponent
        let sanitized = String(rawBase.map { ch -> Character in
            if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-") {
                return ch
            }
            return "_"
        })
        let safeFile = (sanitized.isEmpty || sanitized == "." || sanitized == "..") ? "main.txt" : sanitized
        let b64Code = Data(code.utf8).base64EncodedString()
        let b64Stdin = Data(stdin.utf8).base64EncodedString()

        let runCmd: String
        switch language {
        case .cpp:
            runCmd = "g++ -std=c++20 -O2 '\(safeFile)' -o app_out && ./app_out < stdin.txt"
        case .c:
            runCmd = "gcc -std=c17 -O2 '\(safeFile)' -o app_out && ./app_out < stdin.txt"
        case .objectiveC:
            runCmd = "clang '\(safeFile)' -o app_out && ./app_out < stdin.txt"
        case .rust:
            runCmd = "rustc -O '\(safeFile)' -o app_out && ./app_out < stdin.txt"
        case .go:
            runCmd = "go run '\(safeFile)' < stdin.txt"
        case .zig:
            runCmd = "zig run '\(safeFile)' < stdin.txt"
        case .java:
            runCmd = "java '\(safeFile)' < stdin.txt"
        case .kotlin:
            runCmd = "kotlinc '\(safeFile)' -include-runtime -d app.jar && java -jar app.jar < stdin.txt"
        case .csharp:
            runCmd = "mcs '\(safeFile)' -out:app.exe && mono app.exe < stdin.txt"
        case .dart:
            runCmd = "dart run '\(safeFile)' < stdin.txt"
        case .python:
            runCmd = "python3 '\(safeFile)' < stdin.txt"
        case .javascript:
            runCmd = "node '\(safeFile)' < stdin.txt"
        case .typescript, .tsx:
            runCmd = "npx --yes tsx '\(safeFile)' < stdin.txt"
        case .php:
            runCmd = "php '\(safeFile)' < stdin.txt"
        case .ruby:
            runCmd = "ruby '\(safeFile)' < stdin.txt"
        case .perl:
            runCmd = "perl '\(safeFile)' < stdin.txt"
        case .lua:
            runCmd = "lua '\(safeFile)' < stdin.txt"
        case .r:
            runCmd = "Rscript '\(safeFile)' < stdin.txt"
        case .julia:
            runCmd = "julia '\(safeFile)' < stdin.txt"
        case .elixir:
            runCmd = "elixir '\(safeFile)' < stdin.txt"
        case .haskell:
            runCmd = "runghc '\(safeFile)' < stdin.txt"
        case .ocaml:
            runCmd = "ocaml '\(safeFile)' < stdin.txt"
        case .scala:
            runCmd = "scala '\(safeFile)' < stdin.txt"
        case .pascal:
            runCmd = "fpc '\(safeFile)' -oapp_out && ./app_out < stdin.txt"
        case .sql:
            runCmd = "sqlite3 :memory: < '\(safeFile)'"
        case .swift:
            runCmd = "swift '\(safeFile)' < stdin.txt"
        case .shell, .fish:
            runCmd = "bash '\(safeFile)' < stdin.txt"
        default:
            return "Ngôn ngữ \(language.rawValue) không cần biên dịch trực tiếp trên VPS."
        }

        let fullScript = """
        WORK_DIR="$(mktemp -d /tmp/3012_runner.XXXXXX)" && \
        trap 'rm -rf "$WORK_DIR"' EXIT && \
        cd "$WORK_DIR" && \
        echo '\(b64Code)' | base64 -d > '\(safeFile)' && \
        echo '\(b64Stdin)' | base64 -d > stdin.txt && \
        (\(runCmd)) 2>&1
        """
        return await executeCommandOnVPS(fullScript)
    }

    public func provisionVPSToolchain() async -> String {
        let script = """
        if command -v apt-get >/dev/null 2>&1; then
          DEBIAN_FRONTEND=noninteractive sudo -n apt-get update && DEBIAN_FRONTEND=noninteractive sudo -n apt-get install -y build-essential gcc g++ gdb clang clangd cmake python3 python3-pip nodejs npm git ripgrep || (apt-get update && apt-get install -y build-essential gcc g++ gdb clang clangd cmake python3 python3-pip nodejs npm git ripgrep)
        elif command -v apk >/dev/null 2>&1; then
          apk add --no-cache build-base clang python3 nodejs npm git ripgrep
        fi
        echo "[OK] Installed versions:"
        g++ --version | head -n 1 || true
        python3 --version || true
        node --version || true
        """
        return await executeCommandOnVPS(script)
    }

    // MARK: - Interactive SSH PTY for SwiftTerm
    public func startInteractivePTYShell(cols: Int = 80, rows: Int = 24) {
        guard let client = sshClient else { return }
        ptyTask?.cancel()
        ptyTask = Task { [weak self] in
            let ptyReq = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: max(cols, 40),
                terminalRowHeight: max(rows, 12),
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            )
            do {
                try await client.withPTY(ptyReq) { inbound, outbound in
                    await MainActor.run {
                        self?.ptyStdinWriter = outbound
                    }
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buf), .stderr(let buf):
                            let bytes = Array(buf.readableBytesView)
                            await MainActor.run {
                                self?.onPTYOutput?(bytes)
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    let notice = Array("\r\n[SSH PTY disconnected: \(error.localizedDescription)]\r\n".utf8)
                    self?.onPTYOutput?(notice)
                }
            }
        }
    }

    public func sendPTYInput(_ bytes: [UInt8]) {
        guard let writer = ptyStdinWriter else { return }
        var buf = ByteBufferAllocator().buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        let sendBuf = buf
        Task {
            try? await writer.write(sendBuf)
        }
    }

    public func resizePTY(cols: Int, rows: Int) {
        guard let writer = ptyStdinWriter, cols > 10, rows > 4 else { return }
        Task {
            try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }

    // MARK: - SSH Local Port Forwarding (Expose VPS port on iPhone localhost -> Safari!)
    public func startLocalPortForward(localPort: UInt16, remoteHost: String = "127.0.0.1", remotePort: UInt16) {
        guard let client = sshClient else {
            statusMessage = "Hãy kết nối SSH trước khi bật Port Forwarding."
            return
        }
        if tunnelListeners[localPort] != nil {
            stopLocalPortForward(localPort: localPort)
        }
        guard let nwPort = NWEndpoint.Port(rawValue: localPort) else { return }

        let queue = self.tunnelQueue
        let connStore = self.tunnelConnectionStore
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.acceptLocalOnly = true
            let listener = try NWListener(using: params, on: nwPort)

            listener.newConnectionHandler = { nwConn in
                connStore.add(nwConn, forPort: localPort)
                let startOnce = PortForwardOnceFlag()
                nwConn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard startOnce.claim() else { return }
                        Task {
                            do {
                                let originator = try SocketAddress(ipAddress: "127.0.0.1", port: Int(localPort))
                                let settings = SSHChannelType.DirectTCPIP(
                                    targetHost: remoteHost,
                                    targetPort: Int(remotePort),
                                    originatorAddress: originator
                                )
                                let sshChannel = try await client.createDirectTCPIPChannel(using: settings) { ch in
                                    ch.pipeline.addHandler(TunnelInboundBridgeHandler(nwConnection: nwConn))
                                }
                                Self.pumpNWConnectionToSSHChannel(nwConn: nwConn, sshChannel: sshChannel, queue: queue)
                            } catch {
                                nwConn.cancel()
                            }
                        }
                    case .failed, .cancelled:
                        connStore.remove(nwConn, forPort: localPort)
                    default:
                        break
                    }
                }
                nwConn.start(queue: queue)
            }

            listener.start(queue: tunnelQueue)
            tunnelListeners[localPort] = listener
            activeTunnels.append(ActivePortTunnel(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort))
            statusMessage = "Đã forward localhost:\(localPort) -> VPS \(remoteHost):\(remotePort)"
        } catch {
            statusMessage = "Không mở được cổng cục bộ \(localPort): \(error.localizedDescription)"
        }
    }

    public func stopLocalPortForward(localPort: UInt16) {
        tunnelListeners[localPort]?.cancel()
        tunnelListeners.removeValue(forKey: localPort)
        tunnelConnectionStore.cancelAll(forPort: localPort)
        activeTunnels.removeAll { $0.localPort == localPort }
    }

    nonisolated private static func pumpNWConnectionToSSHChannel(nwConn: NWConnection, sshChannel: Channel, queue: DispatchQueue) {
        nwConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                var buffer = sshChannel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                sshChannel.writeAndFlush(buffer).whenComplete { result in
                    switch result {
                    case .success:
                        if isComplete || error != nil {
                            sshChannel.close(promise: nil)
                            nwConn.cancel()
                        } else {
                            pumpNWConnectionToSSHChannel(nwConn: nwConn, sshChannel: sshChannel, queue: queue)
                        }
                    case .failure:
                        sshChannel.close(promise: nil)
                        nwConn.cancel()
                    }
                }
            } else if isComplete || error != nil {
                sshChannel.close(promise: nil)
                nwConn.cancel()
            } else {
                pumpNWConnectionToSSHChannel(nwConn: nwConn, sshChannel: sshChannel, queue: queue)
            }
        }
    }

    // MARK: - Profile Persistence
    public func saveOrUpdateProfile(_ profile: VPSHostProfile, password: String?) {
        if let password, !password.isEmpty {
            KeychainVault.saveString(password, forKey: profile.keychainPasswordKey)
        }
        if let idx = savedProfiles.firstIndex(where: { $0.id == profile.id }) {
            savedProfiles[idx] = profile
        } else {
            savedProfiles.append(profile)
        }
    }

    public func deleteProfile(_ profile: VPSHostProfile) {
        KeychainVault.delete(forKey: profile.keychainPasswordKey)
        savedProfiles.removeAll { $0.id == profile.id }
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(savedProfiles) {
            UserDefaults.standard.set(data, forKey: "3012.vpsProfiles")
        }
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: "3012.vpsProfiles"),
           let decoded = try? JSONDecoder().decode([VPSHostProfile].self, from: data) {
            self.savedProfiles = decoded
        }
    }
}

private final class PortForwardOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
