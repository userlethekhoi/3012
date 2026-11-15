import Foundation
import Network
import SwiftUI

public enum PCSyncTransportMode: String, Equatable {
    case disconnected
    case wifiLAN
    case internet4G

    public var badgeLabel: String {
        switch self {
        case .disconnected: return "Offline"
        case .wifiLAN: return "Wi-Fi LAN"
        case .internet4G: return "4G/5G Tunnel"
        }
    }
}

public struct PCSyncLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let direction: String // "IN", "OUT", "SYS", "ERR"
    public let detail: String
}

public struct SyncOutboxItem: Codable, Identifiable, Equatable {
    public let id: String
    public let kind: String // "upsert", "delete", "rename", "mkdir"
    public let path: String
    public let oldPath: String?
    public let content: String?
    public let isDir: Bool?
    public let queuedAt: Date
}

@MainActor
public final class PCSyncService: NSObject, ObservableObject {
    @Published public var lanWebSocketURL: String {
        didSet { UserDefaults.standard.set(lanWebSocketURL, forKey: "3012.pcsync.lanURL") }
    }
    @Published public var internetWebSocketURL: String {
        didSet { UserDefaults.standard.set(internetWebSocketURL, forKey: "3012.pcsync.wanURL") }
    }
    @Published public var authToken: String {
        didSet { KeychainVault.saveString(authToken, forKey: "3012.pcsync.token") }
    }
    @Published public var autoReconnect: Bool {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "3012.pcsync.autoReconnect") }
    }
    @Published public var autoSyncEdits: Bool {
        didSet { UserDefaults.standard.set(autoSyncEdits, forKey: "3012.pcsync.autoSync") }
    }

    @Published public private(set) var transportMode: PCSyncTransportMode = .disconnected
    @Published public private(set) var isConnecting: Bool = false
    @Published public private(set) var remoteProjectName: String = ""
    @Published public private(set) var remoteRootDir: String = ""
    @Published public private(set) var statusMessage: String = "Chưa kết nối PC VS Code"
    @Published public private(set) var networkInterfaceSummary: String = "Checking..."
    @Published public private(set) var isOnWiFi: Bool = false
    @Published public private(set) var pendingOutboxCount: Int = 0
    @Published public private(set) var syncedFilesCount: Int = 0
    @Published public private(set) var activityLogs: [PCSyncLogEntry] = []
    @Published public private(set) var discoveredWANURL: String = ""

    public var isConnected: Bool { transportMode != .disconnected }

    private weak var workspaceManager: WorkspaceManager?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.dev.app3012.pcsync.net")
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: Timer?
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var outbox: [SyncOutboxItem] = []
    private var pendingCommandContinuations: [String: CheckedContinuation<(Int, String), Never>] = [:]
    private var shouldStayConnected: Bool = false

    public override init() {
        self.lanWebSocketURL = UserDefaults.standard.string(forKey: "3012.pcsync.lanURL") ?? ""
        self.internetWebSocketURL = UserDefaults.standard.string(forKey: "3012.pcsync.wanURL") ?? ""
        self.authToken = KeychainVault.loadString(forKey: "3012.pcsync.token") ?? ""
        self.autoReconnect = UserDefaults.standard.object(forKey: "3012.pcsync.autoReconnect") as? Bool ?? true
        self.autoSyncEdits = UserDefaults.standard.object(forKey: "3012.pcsync.autoSync") as? Bool ?? true
        super.init()
        loadOutboxFromDisk()
        startNetworkMonitor()
    }

    public func attachWorkspace(_ manager: WorkspaceManager) {
        self.workspaceManager = manager
    }

    // MARK: - Network Interface Monitor (Automatic Wi-Fi <-> 4G/5G Handoff)
    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hasWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                let hasCell = path.usesInterfaceType(.cellular)
                let wasWiFi = self.isOnWiFi
                self.isOnWiFi = hasWiFi

                if path.status != .satisfied {
                    self.networkInterfaceSummary = "Offline (Outbox giữ thay đổi)"
                    return
                }
                self.networkInterfaceSummary = hasWiFi ? "Wi-Fi LAN + Internet" : (hasCell ? "4G / 5G Cellular" : "Online")

                // Handoff automatically when network changes between Wi-Fi and 4G
                if self.shouldStayConnected {
                    if !self.isConnected {
                        await self.connectAuto()
                    } else if wasWiFi && !hasWiFi && self.transportMode == .wifiLAN && !self.internetWebSocketURL.isEmpty {
                        self.appendLog("SYS", "Mất Wi-Fi -> tự động chuyển sang 4G/5G Tunnel...")
                        await self.connectAuto()
                    } else if !wasWiFi && hasWiFi && self.transportMode == .internet4G && !self.lanWebSocketURL.isEmpty {
                        self.appendLog("SYS", "Đã vào lại Wi-Fi -> ưu tiên nối nhanh qua LAN...")
                        await self.connectAuto()
                    }
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    // MARK: - 1-Tap Pairing Code Parser (`3012sync://pair?...` or `ws://` / `wss://`)
    @discardableResult
    public func applyPairingString(_ rawInput: String) -> Bool {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.lowercased().hasPrefix("3012sync://"),
           let comps = URLComponents(string: trimmed),
           let items = comps.queryItems {
            var updated = false
            for item in items {
                guard let val = item.value, !val.isEmpty else { continue }
                switch item.name.lowercased() {
                case "lan", "ws":
                    lanWebSocketURL = val
                    updated = true
                case "wan", "wss", "tunnel", "internet":
                    internetWebSocketURL = val
                    updated = true
                case "token", "secret":
                    authToken = val
                    updated = true
                default:
                    break
                }
            }
            if updated {
                appendLog("SYS", "Đã nạp cấu hình ghép đôi PC Sync thành công.")
                statusMessage = "Đã lưu thông số ghép đôi. Bấm Kết nối."
                return true
            }
        }

        if trimmed.lowercased().hasPrefix("wss://") {
            internetWebSocketURL = trimmed
            appendLog("SYS", "Đã cập nhật Tunnel 4G URL: \(trimmed)")
            return true
        }
        if trimmed.lowercased().hasPrefix("ws://") {
            lanWebSocketURL = trimmed
            appendLog("SYS", "Đã cập nhật Wi-Fi LAN URL: \(trimmed)")
            return true
        }
        return false
    }

    // MARK: - Connect (Wi-Fi LAN first, seamless fallback to 4G/5G Tunnel)
    public func connectAuto() async {
        shouldStayConnected = true
        reconnectTask?.cancel()
        disconnectInternal(keepDesired: true)

        let cleanLAN = lanWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWAN = internetWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanLAN.isEmpty || !cleanWAN.isEmpty else {
            statusMessage = "Nhập URL Wi-Fi LAN hoặc URL Tunnel 4G của PC."
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        if isOnWiFi && !cleanLAN.isEmpty {
            statusMessage = "Đang thử kết nối Wi-Fi LAN..."
            if await openWebSocket(urlString: cleanLAN, mode: .wifiLAN, timeoutSeconds: 3.5) {
                return
            }
            appendLog("SYS", "Wi-Fi LAN không phản hồi -> thử chuyển 4G/Internet Tunnel...")
        }

        if !cleanWAN.isEmpty {
            statusMessage = "Đang kết nối qua 4G/5G Tunnel..."
            if await openWebSocket(urlString: cleanWAN, mode: .internet4G, timeoutSeconds: 8.0) {
                return
            }
        }

        if !isOnWiFi && !cleanLAN.isEmpty {
            statusMessage = "Đang thử lại URL LAN..."
            if await openWebSocket(urlString: cleanLAN, mode: .wifiLAN, timeoutSeconds: 4.0) {
                return
            }
        }

        transportMode = .disconnected
        statusMessage = "Không thể kết nối PC Sync. Thay đổi vẫn được lưu trong Outbox (\(outbox.count))."
        scheduleReconnectIfNeeded()
    }

    public func disconnect() {
        shouldStayConnected = false
        reconnectTask?.cancel()
        disconnectInternal(keepDesired: false)
        statusMessage = "Đã ngắt kết nối PC Sync"
        appendLog("SYS", "Người dùng đã ngắt kết nối.")
    }

    private func disconnectInternal(keepDesired: Bool) {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        if !keepDesired {
            shouldStayConnected = false
        }
        transportMode = .disconnected

        let pending = pendingCommandContinuations
        pendingCommandContinuations.removeAll()
        for (_, cont) in pending {
            cont.resume(returning: (-1, "Disconnected from PC Sync"))
        }
    }

    private func openWebSocket(urlString: String, mode: PCSyncTransportMode, timeoutSeconds: TimeInterval) async -> Bool {
        var normalized = urlString
        if normalized.lowercased().hasPrefix("https://") {
            normalized = "wss://" + normalized.dropFirst("https://".count)
        } else if normalized.lowercased().hasPrefix("http://") {
            normalized = "ws://" + normalized.dropFirst("http://".count)
        }
        guard let url = URL(string: normalized) else { return false }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024

        self.urlSession = session
        self.webSocketTask = task
        task.resume()

        // Send auth hello + wait for first response (welcome)
        let hello: [String: Any] = [
            "type": "hello",
            "token": authToken,
            "client": "3012-iOS",
            "version": "5.0.0"
        ]
        guard await sendJSONDictionary(hello, on: task) else {
            task.cancel()
            session.invalidateAndCancel()
            return false
        }

        do {
            let firstMsg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                group.addTask {
                    try await task.receive()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    throw URLError(.timedOut)
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            self.transportMode = mode
            self.statusMessage = "Đã nối PC qua \(mode.badgeLabel)"
            appendLog("SYS", "Kết nối thành công (\(mode.badgeLabel))")
            handleIncomingWebSocketMessage(firstMsg)
            startReceiveLoop(for: task)
            startPingLoop()
            await flushOutbox()
            return true
        } catch {
            appendLog("ERR", "Kết nối \(mode.badgeLabel) thất bại: \(error.localizedDescription)")
            task.cancel()
            session.invalidateAndCancel()
            self.webSocketTask = nil
            self.urlSession = nil
            return false
        }
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while let self, self.webSocketTask === task {
                do {
                    let message = try await task.receive()
                    self.handleIncomingWebSocketMessage(message)
                } catch {
                    if self.webSocketTask === task {
                        self.transportMode = .disconnected
                        self.statusMessage = "Mất kết nối (\(error.localizedDescription))"
                        self.appendLog("ERR", "Mất kết nối WebSocket: \(error.localizedDescription)")
                        self.disconnectInternal(keepDesired: self.shouldStayConnected)
                        self.scheduleReconnectIfNeeded()
                    }
                    break
                }
            }
        }
    }

    private func startPingLoop() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let task = self.webSocketTask, self.isConnected else { return }
                let pingPayload: [String: Any] = ["type": "ping", "ts": Int(Date().timeIntervalSince1970 * 1000)]
                _ = await self.sendJSONDictionary(pingPayload, on: task)
            }
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard shouldStayConnected, autoReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, self.shouldStayConnected, !self.isConnected else { return }
            await self.connectAuto()
        }
    }

    // MARK: - Message Handling (PC -> Mobile)
    private func handleIncomingWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let str): data = Data(str.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "welcome":
            remoteProjectName = (obj["projectName"] as? String) ?? ""
            remoteRootDir = (obj["rootDir"] as? String) ?? ""
            if let wan = obj["wanUrl"] as? String, !wan.isEmpty {
                discoveredWANURL = wan
                if internetWebSocketURL.isEmpty {
                    internetWebSocketURL = wan
                }
            }
            if !remoteProjectName.isEmpty {
                statusMessage = "Đang đồng bộ '\(remoteProjectName)' (\(transportMode.badgeLabel))"
            }

        case "error":
            let errText = (obj["message"] as? String) ?? "Authentication or protocol error"
            statusMessage = "PC báo lỗi: \(errText)"
            appendLog("ERR", errText)
            if errText.lowercased().contains("token") || errText.lowercased().contains("unauthorized") {
                shouldStayConnected = false
                disconnectInternal(keepDesired: false)
            }

        case "snapshot":
            if let files = obj["files"] as? [String: String] {
                workspaceManager?.applyRemoteFullSnapshot(files)
                syncedFilesCount += files.count
                appendLog("IN", "Nhận snapshot toàn bộ \(files.count) file từ PC")
            }

        case "upsert":
            if let path = obj["path"] as? String, let content = obj["content"] as? String {
                workspaceManager?.applyRemoteUpsert(relativePath: path, content: content, recordConflictTimeline: true)
                syncedFilesCount += 1
                appendLog("IN", "PC cập nhật: \(path)")
            }

        case "delete":
            if let path = obj["path"] as? String {
                workspaceManager?.applyRemoteDelete(relativePath: path)
                appendLog("IN", "PC xóa: \(path)")
            }

        case "rename":
            if let oldPath = obj["oldPath"] as? String, let newPath = obj["newPath"] as? String {
                workspaceManager?.applyRemoteRename(oldRelativePath: oldPath, newRelativePath: newPath)
                appendLog("IN", "PC đổi tên: \(oldPath) -> \(newPath)")
            }

        case "mkdir":
            if let path = obj["path"] as? String {
                workspaceManager?.applyRemoteCreateDirectory(relativePath: path)
                appendLog("IN", "PC tạo thư mục: \(path)")
            }

        case "cmd_result":
            if let id = obj["id"] as? String,
               let cont = pendingCommandContinuations.removeValue(forKey: id) {
                let code = obj["exitCode"] as? Int ?? 0
                let out = (obj["stdout"] as? String ?? "") + (obj["stderr"] as? String ?? "")
                cont.resume(returning: (code, out))
            }

        default:
            break
        }
    }

    // MARK: - Outbound Sync (Mobile -> PC with 250ms debounce & offline Outbox)
    public func handleWorkspaceMutation(_ event: WorkspaceMutationEvent) {
        guard autoSyncEdits else { return }
        switch event {
        case .upsertFile(let rel, let content):
            let key = "upsert::\(rel)"
            debounceTasks[key]?.cancel()
            debounceTasks[key] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                let item = SyncOutboxItem(
                    id: key,
                    kind: "upsert",
                    path: rel,
                    oldPath: nil,
                    content: content,
                    isDir: nil,
                    queuedAt: Date()
                )
                await self.enqueueOrSend(item)
            }

        case .deleteItem(let rel, let isDir):
            debounceTasks["upsert::\(rel)"]?.cancel()
            let item = SyncOutboxItem(
                id: "del::\(rel)::\(UUID().uuidString.prefix(6))",
                kind: "delete",
                path: rel,
                oldPath: nil,
                content: nil,
                isDir: isDir,
                queuedAt: Date()
            )
            Task { await self.enqueueOrSend(item) }

        case .renameItem(let oldRel, let newRel, let isDir):
            debounceTasks["upsert::\(oldRel)"]?.cancel()
            let item = SyncOutboxItem(
                id: "ren::\(oldRel)->\(newRel)",
                kind: "rename",
                path: newRel,
                oldPath: oldRel,
                content: nil,
                isDir: isDir,
                queuedAt: Date()
            )
            Task { await self.enqueueOrSend(item) }

        case .createDirectory(let rel):
            let item = SyncOutboxItem(
                id: "mkdir::\(rel)",
                kind: "mkdir",
                path: rel,
                oldPath: nil,
                content: nil,
                isDir: true,
                queuedAt: Date()
            )
            Task { await self.enqueueOrSend(item) }
        }
    }

    public func pullSnapshotFromPC() async {
        guard let task = webSocketTask, isConnected else { return }
        _ = await sendJSONDictionary(["type": "request_snapshot"], on: task)
        appendLog("OUT", "Yêu cầu tải toàn bộ file từ PC")
    }

    public func pushFullWorkspaceToPC() async {
        guard let task = webSocketTask, isConnected, let workspaceManager else { return }
        let files = workspaceManager.collectAllSyncableTextFiles()
        let ok = await sendJSONDictionary(["type": "push_snapshot", "files": files], on: task)
        if ok {
            syncedFilesCount += files.count
            appendLog("OUT", "Đã đẩy toàn bộ \(files.count) file từ Mobile sang PC")
        }
    }

    public func executeCommandOnPC(_ command: String, timeoutSeconds: TimeInterval = 35) async -> (exitCode: Int, output: String) {
        guard let task = webSocketTask, isConnected else {
            return (-1, "PC Sync chưa kết nối.")
        }
        let reqID = UUID().uuidString
        let sent = await sendJSONDictionary(["type": "exec_cmd", "id": reqID, "command": command], on: task)
        guard sent else {
            return (-1, "Không gửi được lệnh tới PC.")
        }

        let raw: (Int, String) = await withCheckedContinuation { continuation in
            pendingCommandContinuations[reqID] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await MainActor.run { [weak self] in
                    if let pending = self?.pendingCommandContinuations.removeValue(forKey: reqID) {
                        pending.resume(returning: (-1, "Hết thời gian chờ phản hồi từ PC (\(Int(timeoutSeconds))s)."))
                    }
                }
            }
        }
        return (exitCode: raw.0, output: raw.1)
    }

    private func enqueueOrSend(_ item: SyncOutboxItem) async {
        // Coalesce repeated upserts for same file
        if item.kind == "upsert" {
            outbox.removeAll { $0.kind == "upsert" && $0.path == item.path }
        }
        outbox.append(item)
        saveOutboxToDisk()

        if isConnected {
            await flushOutbox()
        }
    }

    public func flushOutbox() async {
        guard let task = webSocketTask, isConnected, !outbox.isEmpty else { return }
        let snapshot = outbox
        var sentCount = 0
        for item in snapshot {
            var payload: [String: Any] = ["type": item.kind, "path": item.path]
            if let old = item.oldPath { payload["oldPath"] = old }
            if let content = item.content { payload["content"] = content }
            if let isDir = item.isDir { payload["isDir"] = isDir }
            if await sendJSONDictionary(payload, on: task) {
                outbox.removeAll { $0.id == item.id }
                sentCount += 1
                syncedFilesCount += 1
                appendLog("OUT", "\(item.kind): \(item.path)")
            } else {
                break
            }
        }
        if sentCount > 0 {
            saveOutboxToDisk()
        }
    }

    public func clearOutbox() {
        outbox.removeAll()
        saveOutboxToDisk()
    }

    private func sendJSONDictionary(_ dict: [String: Any], on task: URLSessionWebSocketTask) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return false }
        do {
            try await task.send(.string(text))
            return true
        } catch {
            return false
        }
    }

    private var outboxFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("3012PCSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("outbox.json")
    }

    private func saveOutboxToDisk() {
        pendingOutboxCount = outbox.count
        if let data = try? JSONEncoder().encode(outbox) {
            try? data.write(to: outboxFileURL, options: .atomic)
        }
    }

    private func loadOutboxFromDisk() {
        if let data = try? Data(contentsOf: outboxFileURL),
           let items = try? JSONDecoder().decode([SyncOutboxItem].self, from: data) {
            outbox = items
        }
        pendingOutboxCount = outbox.count
    }

    private func appendLog(_ direction: String, _ detail: String) {
        activityLogs.insert(PCSyncLogEntry(timestamp: Date(), direction: direction, detail: detail), at: 0)
        if activityLogs.count > 80 {
            activityLogs.removeLast(activityLogs.count - 80)
        }
    }

    // MARK: - Zero-Dependency Node.js Companion Script (Wi-Fi LAN + 4G Cloudflared Tunnel)
    public static func generateCompanionScript(port: Int = 3012, suggestedToken: String) -> String {
        let tokenLiteral = suggestedToken.isEmpty ? "change-me-secret" : suggestedToken
        return """
        #!/usr/bin/env node
        // 3012 PC Sync Companion v5.0 (Zero dependencies! Requires Node.js 18+)
        // Run inside your VS Code project folder: node 3012-pc-sync.mjs [port] [--token=SECRET] [--tunnel]
        import http from "node:http";
        import fs from "node:fs";
        import path from "node:path";
        import os from "node:os";
        import crypto from "node:crypto";
        import { spawn } from "node:child_process";

        const args = process.argv.slice(2);
        const portArg = args.find((a) => /^\\d+$/.test(a));
        const PORT = Number(portArg || process.env.SYNC_PORT || \(port));
        const TOKEN = (args.find((a) => a.startsWith("--token="))?.slice(8)) || process.env.SYNC_TOKEN || "\(tokenLiteral)";
        const ENABLE_TUNNEL = args.includes("--tunnel") || !args.includes("--lan-only");
        const ROOT = path.resolve(process.cwd());
        const IGNORED = new Set([".git", "node_modules", ".next", "dist", "build", ".DS_Store", "__pycache__", ".venv", ".build"]);

        function getLanIP() {
          const nets = os.networkInterfaces();
          for (const list of Object.values(nets)) {
            for (const info of list || []) {
              if (info.family === "IPv4" && !info.internal) return info.address;
            }
          }
          return "127.0.0.1";
        }

        function safeResolve(relPath) {
          const clean = String(relPath || "").replace(/^\\/+/, "");
          const abs = path.resolve(ROOT, clean);
          if (abs !== ROOT && !abs.startsWith(ROOT + path.sep)) return null;
          return abs;
        }

        function isTextBuffer(buf) {
          const sample = buf.subarray(0, Math.min(buf.length, 4096));
          for (let i = 0; i < sample.length; i++) {
            if (sample[i] === 0) return false;
          }
          return true;
        }

        function collectSnapshot(dir = ROOT, base = "", out = {}) {
          for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            if (IGNORED.has(entry.name) || entry.name.startsWith(".3012")) continue;
            const rel = base ? `${base}/${entry.name}` : entry.name;
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
              collectSnapshot(full, rel, out);
            } else if (entry.isFile()) {
              const stat = fs.statSync(full);
              if (stat.size <= 512 * 1024) {
                const buf = fs.readFileSync(full);
                if (isTextBuffer(buf)) out[rel] = buf.toString("utf8");
              }
            }
          }
          return out;
        }

        const clients = new Set();
        const suppressedPaths = new Map();
        let activeWanUrl = "";

        function suppressEcho(rel) {
          suppressedPaths.set(rel, Date.now() + 900);
        }
        function isSuppressed(rel) {
          const exp = suppressedPaths.get(rel);
          if (!exp) return false;
          if (Date.now() > exp) { suppressedPaths.delete(rel); return false; }
          return true;
        }

        function encodeFrame(text) {
          const payload = Buffer.from(text, "utf8");
          const len = payload.length;
          let header;
          if (len < 126) {
            header = Buffer.from([0x81, len]);
          } else if (len < 65536) {
            header = Buffer.alloc(4);
            header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2);
          } else {
            header = Buffer.alloc(10);
            header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2);
          }
          return Buffer.concat([header, payload]);
        }

        function broadcast(obj, except = null) {
          const frame = encodeFrame(JSON.stringify(obj));
          for (const c of clients) {
            if (c !== except && c.authenticated && !c.socket.destroyed) {
              c.socket.write(frame);
            }
          }
        }

        const server = http.createServer((req, res) => {
          res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
          res.end(`3012 PC Sync Companion running in ${ROOT}\\n`);
        });

        server.on("upgrade", (req, socket) => {
          const key = req.headers["sec-websocket-key"];
          if (!key) { socket.destroy(); return; }
          const accept = crypto.createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
          socket.write([
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            `Sec-WebSocket-Accept: ${accept}`,
            "\\r\\n"
          ].join("\\r\\n"));

          const client = { socket, authenticated: false, buf: Buffer.alloc(0) };
          clients.add(client);

          socket.on("data", (chunk) => {
            client.buf = Buffer.concat([client.buf, chunk]);
            while (client.buf.length >= 2) {
              const b1 = client.buf[0], b2 = client.buf[1];
              const opcode = b1 & 0x0f;
              const masked = (b2 & 0x80) !== 0;
              let payloadLen = b2 & 0x7f;
              let offset = 2;
              if (payloadLen === 126) {
                if (client.buf.length < 4) return;
                payloadLen = client.buf.readUInt16BE(2); offset = 4;
              } else if (payloadLen === 127) {
                if (client.buf.length < 10) return;
                payloadLen = Number(client.buf.readBigUInt64BE(2)); offset = 10;
              }
              const maskSize = masked ? 4 : 0;
              if (client.buf.length < offset + maskSize + payloadLen) return;
              const mask = masked ? client.buf.subarray(offset, offset + 4) : null;
              let payload = client.buf.subarray(offset + maskSize, offset + maskSize + payloadLen);
              client.buf = client.buf.subarray(offset + maskSize + payloadLen);
              if (mask) {
                const decoded = Buffer.allocUnsafe(payload.length);
                for (let i = 0; i < payload.length; i++) decoded[i] = payload[i] ^ mask[i % 4];
                payload = decoded;
              }
              if (opcode === 0x8) { socket.end(); return; }
              if (opcode === 0x9) { socket.write(Buffer.from([0x8a, 0x00])); continue; }
              if (opcode !== 0x1 && opcode !== 0x0) continue;

              let msg;
              try { msg = JSON.parse(payload.toString("utf8")); } catch { continue; }
              if (!client.authenticated) {
                if (msg.type === "hello" && msg.token === TOKEN) {
                  client.authenticated = true;
                  const lanUrl = `ws://${getLanIP()}:${PORT}`;
                  socket.write(encodeFrame(JSON.stringify({
                    type: "welcome",
                    projectName: path.basename(ROOT),
                    rootDir: ROOT,
                    lanUrl,
                    wanUrl: activeWanUrl
                  })));
                  socket.write(encodeFrame(JSON.stringify({ type: "snapshot", files: collectSnapshot() })));
                } else {
                  socket.write(encodeFrame(JSON.stringify({ type: "error", message: "Invalid Token" })));
                  socket.end();
                }
                continue;
              }

              if (msg.type === "ping") {
                socket.write(encodeFrame(JSON.stringify({ type: "pong", ts: msg.ts })));
              } else if (msg.type === "request_snapshot") {
                socket.write(encodeFrame(JSON.stringify({ type: "snapshot", files: collectSnapshot() })));
              } else if (msg.type === "push_snapshot" && msg.files && typeof msg.files === "object") {
                for (const [rel, body] of Object.entries(msg.files)) {
                  const abs = safeResolve(rel);
                  if (!abs || typeof body !== "string") continue;
                  suppressEcho(rel);
                  fs.mkdirSync(path.dirname(abs), { recursive: true });
                  fs.writeFileSync(abs, body, "utf8");
                }
              } else if (msg.type === "upsert" && typeof msg.path === "string" && typeof msg.content === "string") {
                const abs = safeResolve(msg.path);
                if (abs) {
                  suppressEcho(msg.path);
                  fs.mkdirSync(path.dirname(abs), { recursive: true });
                  fs.writeFileSync(abs, msg.content, "utf8");
                  broadcast(msg, client);
                }
              } else if (msg.type === "delete" && typeof msg.path === "string") {
                const abs = safeResolve(msg.path);
                if (abs && fs.existsSync(abs)) {
                  suppressEcho(msg.path);
                  fs.rmSync(abs, { recursive: true, force: true });
                  broadcast(msg, client);
                }
              } else if (msg.type === "rename" && msg.oldPath && msg.path) {
                const src = safeResolve(msg.oldPath);
                const dst = safeResolve(msg.path);
                if (src && dst && fs.existsSync(src)) {
                  suppressEcho(msg.oldPath);
                  suppressEcho(msg.path);
                  fs.mkdirSync(path.dirname(dst), { recursive: true });
                  fs.renameSync(src, dst);
                  broadcast(msg, client);
                }
              } else if (msg.type === "mkdir" && msg.path) {
                const abs = safeResolve(msg.path);
                if (abs) {
                  fs.mkdirSync(abs, { recursive: true });
                  broadcast(msg, client);
                }
              } else if (msg.type === "exec_cmd" && msg.command) {
                const child = spawn(msg.command, { cwd: ROOT, shell: true });
                let stdout = "", stderr = "";
                child.stdout.on("data", (d) => { stdout += d.toString("utf8"); });
                child.stderr.on("data", (d) => { stderr += d.toString("utf8"); });
                child.on("close", (code) => {
                  socket.write(encodeFrame(JSON.stringify({
                    type: "cmd_result", id: msg.id || "", exitCode: code ?? 0, stdout, stderr
                  })));
                });
              }
            }
          });
          socket.on("close", () => clients.delete(client));
          socket.on("error", () => clients.delete(client));
        });

        try {
          fs.watch(ROOT, { recursive: true }, (_event, filename) => {
            if (!filename) return;
            const rel = filename.split(path.sep).join("/");
            const parts = rel.split("/");
            if (parts.some((p) => IGNORED.has(p) || p.startsWith(".3012"))) return;
            if (isSuppressed(rel)) return;
            const abs = safeResolve(rel);
            if (!abs) return;
            setTimeout(() => {
              if (!fs.existsSync(abs)) {
                broadcast({ type: "delete", path: rel, isDir: false });
              } else {
                const st = fs.statSync(abs);
                if (st.isFile() && st.size <= 512 * 1024) {
                  const buf = fs.readFileSync(abs);
                  if (isTextBuffer(buf)) broadcast({ type: "upsert", path: rel, content: buf.toString("utf8") });
                }
              }
            }, 90);
          });
        } catch (err) {
          console.warn("Recursive fs.watch unavailable on this OS:", err.message);
        }

        function printPairing(lanUrl, wanUrl) {
          const q = [`lan=${encodeURIComponent(lanUrl)}`];
          if (wanUrl) q.push(`wan=${encodeURIComponent(wanUrl)}`);
          q.push(`token=${encodeURIComponent(TOKEN)}`);
          console.log("\\n[3012 PC SYNC READY]");
          console.log("Project :", ROOT);
          console.log("Wi-Fi   :", lanUrl);
          if (wanUrl) console.log("4G/5G   :", wanUrl);
          console.log("Pairing :", `3012sync://pair?${q.join("&")}\\n`);
        }

        server.listen(PORT, "0.0.0.0", () => {
          const lanUrl = `ws://${getLanIP()}:${PORT}`;
          printPairing(lanUrl, "");
          if (ENABLE_TUNNEL) {
            const cf = spawn("cloudflared", ["tunnel", "--url", `http://127.0.0.1:${PORT}`], { stdio: ["ignore", "pipe", "pipe"] });
            const handleTunnelOut = (chunk) => {
              const m = chunk.toString("utf8").match(/https:\\/\\/[a-z0-9-]+\\.trycloudflare\\.com/);
              if (m && !activeWanUrl) {
                activeWanUrl = m[0].replace("https://", "wss://");
                printPairing(lanUrl, activeWanUrl);
              }
            };
            cf.stdout.on("data", handleTunnelOut);
            cf.stderr.on("data", handleTunnelOut);
            cf.on("error", () => {
              console.log("[Tip] Cài cloudflared để tự mở 4G Tunnel: brew install cloudflared / winget install Cloudflare.cloudflared");
            });
          }
        });
        """
    }
}
