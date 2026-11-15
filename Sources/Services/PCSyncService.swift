import CryptoKit
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
        case .internet4G: return "4G/5G Relay"
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
    public let id: UUID
    public let kind: String // "upsert", "delete", "rename", "mkdir"
    public let path: String
    public let oldPath: String?
    public let content: String?
    public let isDir: Bool?
    public let queuedAt: Date

    public init(
        id: UUID = UUID(),
        kind: String,
        path: String,
        oldPath: String?,
        content: String?,
        isDir: Bool?,
        queuedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.path = path
        self.oldPath = oldPath
        self.content = content
        self.isDir = isDir
        self.queuedAt = queuedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedUUID = try? c.decode(UUID.self, forKey: .id) {
            self.id = decodedUUID
        } else if let strID = try? c.decode(String.self, forKey: .id),
                  let parsed = UUID(uuidString: strID) {
            self.id = parsed
        } else {
            self.id = UUID()
        }
        self.kind = try c.decode(String.self, forKey: .kind)
        self.path = try c.decode(String.self, forKey: .path)
        self.oldPath = try c.decodeIfPresent(String.self, forKey: .oldPath)
        self.content = try c.decodeIfPresent(String.self, forKey: .content)
        self.isDir = try c.decodeIfPresent(Bool.self, forKey: .isDir)
        self.queuedAt = (try? c.decode(Date.self, forKey: .queuedAt)) ?? Date()
    }
}

@MainActor
public final class PCSyncService: NSObject, ObservableObject {
    nonisolated public static let defaultRelayBaseURL = "https://build.kaydus.xyz"

    @Published public var relayServerURL: String {
        didSet { UserDefaults.standard.set(relayServerURL, forKey: "3012.pcsync.relay") }
    }
    @Published public var permanentSyncKey: String {
        didSet { KeychainVault.saveString(permanentSyncKey, forKey: "pcsync.permanentKey") }
    }
    @Published public var quickPairPin: String = ""
    @Published public var autoConnectEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoConnectEnabled, forKey: "3012.pcsync.autoconnect")
            autoReconnect = autoConnectEnabled
        }
    }

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
    @Published public private(set) var isRelayRoomActive: Bool = false
    @Published public private(set) var isPeerOnlineInRelay: Bool = false
    @Published public private(set) var isEndToEndEncrypted: Bool = false

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

    private var connectionGeneration: UInt64 = 0
    private var isFlushingOutbox: Bool = false
    private var isSessionRelay: Bool = false
    private var activeRelayAESKey: SymmetricKey? = nil
    private var activeRelayRoomSecret: String = ""
    private var activeSessionIsPinPairing: Bool = false
    private var activeHandshakeCompleted: Bool = false
    private let clientDeviceUUID: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
    private var boundWorkspaceCanonicalPath: String? = nil

    public override init() {
        let savedRelay = UserDefaults.standard.string(forKey: "3012.pcsync.relay") ?? Self.defaultRelayBaseURL
        let savedPerm = KeychainVault.loadString(forKey: "pcsync.permanentKey") ?? ""
        let savedAuto = UserDefaults.standard.object(forKey: "3012.pcsync.autoconnect") as? Bool
            ?? UserDefaults.standard.object(forKey: "3012.pcsync.autoReconnect") as? Bool
            ?? true
        self.relayServerURL = savedRelay.isEmpty ? Self.defaultRelayBaseURL : savedRelay
        self.permanentSyncKey = savedPerm
        self.autoConnectEnabled = savedAuto
        self.lanWebSocketURL = UserDefaults.standard.string(forKey: "3012.pcsync.lanURL") ?? ""
        self.internetWebSocketURL = UserDefaults.standard.string(forKey: "3012.pcsync.wanURL") ?? ""
        let legacyTok = KeychainVault.loadString(forKey: "3012.pcsync.token") ?? ""
        self.authToken = legacyTok.isEmpty ? savedPerm : legacyTok
        self.autoReconnect = savedAuto
        self.autoSyncEdits = UserDefaults.standard.object(forKey: "3012.pcsync.autoSync") as? Bool ?? true
        super.init()
        loadOutboxFromDisk()
        startNetworkMonitor()
    }

    deinit {
        pathMonitor.cancel()
    }

    public func attachWorkspace(_ manager: WorkspaceManager) {
        self.workspaceManager = manager
        self.boundWorkspaceCanonicalPath = WorkspaceManager.canonicalPath(manager.rootURL)
    }

    public func handleWorkspaceRootChanged(to newRoot: URL) {
        let newCanon = WorkspaceManager.canonicalPath(newRoot)
        guard let previous = boundWorkspaceCanonicalPath else {
            boundWorkspaceCanonicalPath = newCanon
            return
        }
        guard previous != newCanon else { return }
        boundWorkspaceCanonicalPath = newCanon
        for (_, task) in debounceTasks { task.cancel() }
        debounceTasks.removeAll()
        if !outbox.isEmpty {
            outbox.removeAll()
            saveOutboxToDisk()
        }
        if isConnected || isConnecting {
            disconnectInternal(keepDesired: false)
            isConnecting = false
            statusMessage = "Đã đổi Workspace — tạm ngắt PC Sync cũ để tránh ghi đè chéo dự án."
            appendLog("SYS", "Đổi Workspace sang \(newRoot.lastPathComponent): đã xoá Outbox cũ và ngắt phiên PC Sync trước đó.")
        }
    }

    // MARK: - E2EE Key Derivation & AES-256-GCM Helpers (Identical to extension.js & sync.mjs)
    public nonisolated static func deriveRoomID(secret: String) -> String {
        let normalized = "3012-room-v1:" + secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public nonisolated static func deriveAESKey(secret: String) -> SymmetricKey {
        let normalized = "3012-e2ee-v1:" + secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return SymmetricKey(data: Data(digest))
    }

    public nonisolated static func sealRelayPayload(_ dict: [String: Any], key: SymmetricKey) -> String? {
        guard let plainData = try? JSONSerialization.data(withJSONObject: dict),
              let sealed = try? AES.GCM.seal(plainData, using: key),
              let combined = sealed.combined else {
            return nil
        }
        return combined.base64EncodedString()
    }

    public nonisolated static func openRelayPayload(_ base64String: String, key: SymmetricKey) -> [String: Any]? {
        guard let combined = Data(base64Encoded: base64String),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let decrypted = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            return nil
        }
        return obj
    }

    @discardableResult
    public func generateNewPermanentKey() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var suffix = ""
        for _ in 0..<20 {
            let idx = Int.random(in: 0..<alphabet.count)
            suffix.append(alphabet[idx])
        }
        let generated = "3012-\(suffix)"
        permanentSyncKey = generated
        authToken = generated
        return generated
    }

    public func relayWebSocketEndpoint() -> String {
        var raw = relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { raw = Self.defaultRelayBaseURL }
        if raw.lowercased().hasPrefix("https://") {
            raw = "wss://" + raw.dropFirst("https://".count)
        } else if raw.lowercased().hasPrefix("http://") {
            raw = "ws://" + raw.dropFirst("http://".count)
        } else if !raw.lowercased().hasPrefix("ws://") && !raw.lowercased().hasPrefix("wss://") {
            raw = "wss://\(raw)"
        }
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        if !raw.lowercased().hasSuffix("/v1/sync") {
            raw += "/v1/sync"
        }
        return raw
    }

    // MARK: - Network Interface Monitor (Automatic Wi-Fi <-> 4G/5G Handoff)
    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] () -> Void in
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

                if self.shouldStayConnected {
                    if !self.isConnected && !self.isRelayRoomActive {
                        await self.connectAuto()
                    } else if wasWiFi && !hasWiFi && self.transportMode == .wifiLAN {
                        self.appendLog("SYS", "Mất Wi-Fi -> tự động chuyển sang 4G/5G Relay...")
                        await self.connectAuto()
                    } else if !wasWiFi && hasWiFi && self.transportMode == .internet4G && !self.lanWebSocketURL.isEmpty {
                        self.appendLog("SYS", "Đã vào lại Wi-Fi -> thử chuyển nhanh sang LAN...")
                        self.probeAndUpgradeToLAN(
                            lanURL: self.lanWebSocketURL,
                            token: self.effectiveAuthToken(),
                            currentGen: self.connectionGeneration
                        )
                    }
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func effectiveAuthToken() -> String {
        let perm = permanentSyncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !perm.isEmpty { return perm }
        return authToken.trimmingCharacters(in: .whitespacesAndNewlines)
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
                case "relay":
                    relayServerURL = val
                    updated = true
                case "key":
                    permanentSyncKey = val
                    authToken = val
                    updated = true
                case "pin":
                    quickPairPin = val
                    updated = true
                case "lan", "ws":
                    lanWebSocketURL = val
                    updated = true
                case "wan", "wss", "tunnel", "internet":
                    internetWebSocketURL = val
                    updated = true
                case "token", "secret":
                    authToken = val
                    if permanentSyncKey.isEmpty {
                        permanentSyncKey = val
                    }
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
            if trimmed.lowercased().contains("/v1/sync") {
                relayServerURL = trimmed
            } else {
                internetWebSocketURL = trimmed
            }
            appendLog("SYS", "Đã cập nhật Tunnel/Relay 4G URL: \(trimmed)")
            return true
        }
        if trimmed.lowercased().hasPrefix("ws://") {
            lanWebSocketURL = trimmed
            appendLog("SYS", "Đã cập nhật Wi-Fi LAN URL: \(trimmed)")
            return true
        }
        if trimmed.count == 6, trimmed.allSatisfy({ $0.isNumber }) {
            quickPairPin = trimmed
            return true
        }
        if trimmed.hasPrefix("3012-") && trimmed.count >= 12 {
            permanentSyncKey = trimmed
            authToken = trimmed
            return true
        }
        return false
    }

    // MARK: - Auto-Connect on Launch / Foreground
    public func autoConnectIfConfigured() {
        guard autoConnectEnabled else { return }
        let perm = permanentSyncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDirect = !lanWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !internetWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !perm.isEmpty || hasDirect else { return }
        guard !isConnected && !isConnecting && !isRelayRoomActive else { return }
        Task { @MainActor [weak self] () -> Void in
            await self?.connectAuto()
        }
    }

    public func connectWithQuickPIN(_ rawPin: String) async {
        let pin = rawPin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pin.isEmpty else {
            statusMessage = "Nhập mã PIN 6 số hiển thị trên VS Code."
            return
        }
        quickPairPin = pin
        shouldStayConnected = true
        reconnectTask?.cancel()
        disconnectInternal(keepDesired: true)
        isConnecting = true
        defer { isConnecting = false }
        let _ = await connectViaRelay(secret: pin, isPinPairing: true, timeoutSeconds: 8.0)
    }

    // MARK: - Connect (Wi-Fi LAN <5ms -> Permanent Key E2EE Relay -> Legacy Tunnel)
    public func connectAuto() async {
        shouldStayConnected = true
        reconnectTask?.cancel()
        disconnectInternal(keepDesired: true)

        let cleanLAN = lanWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWAN = internetWebSocketURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPerm = permanentSyncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPin = quickPairPin.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanPerm.isEmpty || !cleanPin.isEmpty || !cleanLAN.isEmpty || !cleanWAN.isEmpty else {
            statusMessage = "Nhập mã PIN 6 số hoặc Khóa Vĩnh Viễn để nối PC."
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        if isOnWiFi && !cleanLAN.isEmpty && !effectiveAuthToken().isEmpty {
            statusMessage = "Đang thử nối nhanh Wi-Fi LAN..."
            if await openDirectWebSocket(urlString: cleanLAN, mode: .wifiLAN, token: effectiveAuthToken(), timeoutSeconds: 2.2) {
                return
            }
            appendLog("SYS", "Wi-Fi LAN không phản hồi -> chuyển qua Relay build.kaydus.xyz...")
        }

        if !cleanPerm.isEmpty {
            if await connectViaRelay(secret: cleanPerm, isPinPairing: false, timeoutSeconds: 8.0) {
                return
            }
        }

        if !cleanPin.isEmpty {
            if await connectViaRelay(secret: cleanPin, isPinPairing: true, timeoutSeconds: 8.0) {
                return
            }
        }

        if !cleanWAN.isEmpty {
            statusMessage = "Đang kết nối qua 4G/5G Tunnel..."
            if await openDirectWebSocket(urlString: cleanWAN, mode: .internet4G, token: effectiveAuthToken(), timeoutSeconds: 8.0) {
                return
            }
        }

        if !isOnWiFi && !cleanLAN.isEmpty && !effectiveAuthToken().isEmpty {
            statusMessage = "Đang thử lại URL LAN..."
            if await openDirectWebSocket(urlString: cleanLAN, mode: .wifiLAN, token: effectiveAuthToken(), timeoutSeconds: 3.5) {
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
        connectionGeneration &+= 1
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isSessionRelay = false
        activeRelayAESKey = nil
        activeRelayRoomSecret = ""
        activeSessionIsPinPairing = false
        activeHandshakeCompleted = false
        isRelayRoomActive = false
        isPeerOnlineInRelay = false
        isEndToEndEncrypted = false
        isFlushingOutbox = false

        if !keepDesired {
            shouldStayConnected = false
        }
        transportMode = .disconnected

        let pending = pendingCommandContinuations
        pendingCommandContinuations.removeAll()
        for (_, cont) in pending {
            let result: (Int, String) = (-1, "Disconnected from PC Sync")
            cont.resume(returning: result)
        }
    }

    // MARK: - Zero-Knowledge Relay Connection (wss://build.kaydus.xyz/v1/sync)
    private func connectViaRelay(secret: String, isPinPairing: Bool, timeoutSeconds: TimeInterval) async -> Bool {
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty else { return false }

        let endpoint = relayWebSocketEndpoint()
        guard let url = URL(string: endpoint) else {
            statusMessage = "Relay URL không hợp lệ: \(endpoint)"
            return false
        }

        connectionGeneration &+= 1
        let gen = connectionGeneration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024

        self.urlSession = session
        self.webSocketTask = task
        self.isSessionRelay = true
        self.activeRelayRoomSecret = cleanSecret
        self.activeRelayAESKey = Self.deriveAESKey(secret: cleanSecret)
        self.activeSessionIsPinPairing = isPinPairing
        self.activeHandshakeCompleted = false
        self.isRelayRoomActive = false
        self.isPeerOnlineInRelay = false
        self.isEndToEndEncrypted = true

        statusMessage = isPinPairing ? "Đang ghép PIN \(cleanSecret) qua Relay..." : "Đang nối Relay E2EE..."
        task.resume()

        let roomID = Self.deriveRoomID(secret: cleanSecret)
        let joinPayload: [String: Any] = [
            "type": "relay_join",
            "room": roomID,
            "role": "mobile",
            "clientId": clientDeviceUUID
        ]
        guard await sendRawJSON(joinPayload, on: task) else {
            if self.connectionGeneration == gen {
                disconnectInternal(keepDesired: self.shouldStayConnected)
            }
            return false
        }

        do {
            let firstMsg = try await receiveMessageWithTimeout(task: task, timeoutSeconds: timeoutSeconds)
            guard self.connectionGeneration == gen, self.webSocketTask === task else { return false }
            self.handleIncomingWebSocketMessage(firstMsg, generation: gen)
            guard self.connectionGeneration == gen, self.webSocketTask === task, self.isRelayRoomActive else {
                return false
            }
            startReceiveLoop(for: task, generation: gen)
            startPingLoop(generation: gen)
            return true
        } catch {
            appendLog("ERR", "Relay lỗi kết nối: \(error.localizedDescription)")
            if self.connectionGeneration == gen {
                task.cancel()
                session.invalidateAndCancel()
                self.webSocketTask = nil
                self.urlSession = nil
                self.isSessionRelay = false
                self.activeRelayAESKey = nil
                self.isRelayRoomActive = false
                self.isEndToEndEncrypted = false
            }
            return false
        }
    }

    // MARK: - Direct WebSocket Connection (LAN <5ms or Cloudflare Tunnel)
    private func openDirectWebSocket(
        urlString: String,
        mode: PCSyncTransportMode,
        token: String,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("https://") {
            normalized = "wss://" + normalized.dropFirst("https://".count)
        } else if normalized.lowercased().hasPrefix("http://") {
            normalized = "ws://" + normalized.dropFirst("http://".count)
        }
        guard let url = URL(string: normalized) else { return false }

        connectionGeneration &+= 1
        let gen = connectionGeneration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024

        self.urlSession = session
        self.webSocketTask = task
        self.isSessionRelay = false
        self.activeRelayAESKey = nil
        self.activeRelayRoomSecret = ""
        self.activeSessionIsPinPairing = false
        self.activeHandshakeCompleted = false
        self.isRelayRoomActive = false
        self.isPeerOnlineInRelay = false
        self.isEndToEndEncrypted = false

        task.resume()

        let hello: [String: Any] = [
            "type": "hello",
            "token": token,
            "client": "3012-iOS",
            "version": "5.1.0"
        ]
        guard await sendRawJSON(hello, on: task) else {
            if self.connectionGeneration == gen {
                task.cancel()
                session.invalidateAndCancel()
                self.webSocketTask = nil
                self.urlSession = nil
            }
            return false
        }

        do {
            let firstMsg = try await receiveMessageWithTimeout(task: task, timeoutSeconds: timeoutSeconds)
            guard self.connectionGeneration == gen, self.webSocketTask === task else { return false }
            self.handleIncomingWebSocketMessage(firstMsg, generation: gen, directMode: mode)
            guard self.connectionGeneration == gen, self.webSocketTask === task, self.activeHandshakeCompleted else {
                task.cancel()
                session.invalidateAndCancel()
                self.webSocketTask = nil
                self.urlSession = nil
                return false
            }
            startReceiveLoop(for: task, generation: gen)
            startPingLoop(generation: gen)
            return true
        } catch {
            appendLog("ERR", "Kết nối \(mode.badgeLabel) thất bại: \(error.localizedDescription)")
            if self.connectionGeneration == gen {
                task.cancel()
                session.invalidateAndCancel()
                self.webSocketTask = nil
                self.urlSession = nil
            }
            return false
        }
    }

    private func receiveMessageWithTimeout(
        task: URLSessionWebSocketTask,
        timeoutSeconds: TimeInterval
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await task.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.5, timeoutSeconds) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.cannotConnectToHost)
            }
            group.cancelAll()
            return result
        }
    }

    private func probeAndUpgradeToLAN(lanURL: String, token: String, currentGen: UInt64) {
        let cleanLAN = lanURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOnWiFi, !cleanLAN.isEmpty, !token.isEmpty,
              !cleanLAN.contains("0.0.0.0"),
              !cleanLAN.contains("127.0.0.1"),
              transportMode != .wifiLAN else {
            return
        }
        Task { @MainActor [weak self] () -> Void in
            guard let self, self.connectionGeneration == currentGen,
                  let url = URL(string: cleanLAN) else { return }

            let cfg = URLSessionConfiguration.default
            // Timeout probe quickly via receiveMessageWithTimeout, but keep promoted LAN session healthy when idle
            cfg.timeoutIntervalForRequest = 60
            cfg.waitsForConnectivity = false
            let lanSession = URLSession(configuration: cfg)
            let lanTask = lanSession.webSocketTask(with: url)
            lanTask.maximumMessageSize = 16 * 1024 * 1024
            lanTask.resume()

            let hello: [String: Any] = [
                "type": "hello",
                "token": token,
                "client": "3012-iOS-LAN",
                "version": "5.1.0"
            ]
            guard await self.sendRawJSON(hello, on: lanTask) else {
                lanTask.cancel()
                lanSession.invalidateAndCancel()
                return
            }

            do {
                let msg = try await self.receiveMessageWithTimeout(task: lanTask, timeoutSeconds: 1.5)
                guard self.connectionGeneration == currentGen, self.shouldStayConnected else {
                    lanTask.cancel()
                    lanSession.invalidateAndCancel()
                    return
                }
                let rawData: Data
                switch msg {
                case .string(let s): rawData = Data(s.utf8)
                case .data(let d): rawData = d
                @unknown default:
                    lanTask.cancel()
                    lanSession.invalidateAndCancel()
                    return
                }
                guard let obj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
                      (obj["type"] as? String) == "welcome" else {
                    lanTask.cancel()
                    lanSession.invalidateAndCancel()
                    return
                }

                // Switch cleanly to ultra-fast <5ms direct Wi-Fi LAN socket
                self.pingTimer?.invalidate()
                self.pingTimer = nil
                self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                self.urlSession?.invalidateAndCancel()

                self.connectionGeneration &+= 1
                let lanGen = self.connectionGeneration
                self.urlSession = lanSession
                self.webSocketTask = lanTask
                self.isSessionRelay = false
                self.activeRelayAESKey = nil
                self.isRelayRoomActive = false
                self.isEndToEndEncrypted = false
                self.activeHandshakeCompleted = true
                self.transportMode = .wifiLAN
                self.lanWebSocketURL = cleanLAN
                self.statusMessage = "Đang đồng bộ '\(self.remoteProjectName.isEmpty ? "PC" : self.remoteProjectName)' (Wi-Fi LAN <5ms)"
                self.appendLog("SYS", "Đã tự nâng cấp lên kết nối Wi-Fi LAN <5ms.")
                self.startReceiveLoop(for: lanTask, generation: lanGen)
                self.startPingLoop(generation: lanGen)
                if !self.outbox.isEmpty {
                    await self.flushOutbox()
                }
            } catch {
                lanTask.cancel()
                lanSession.invalidateAndCancel()
            }
        }
    }

    private func startReceiveLoop(for task: URLSessionWebSocketTask, generation: UInt64) {
        Task { [weak self] () -> Void in
            while let self, self.webSocketTask === task, self.connectionGeneration == generation {
                do {
                    let message = try await task.receive()
                    guard self.webSocketTask === task, self.connectionGeneration == generation else { break }
                    self.handleIncomingWebSocketMessage(message, generation: generation)
                } catch {
                    if self.webSocketTask === task && self.connectionGeneration == generation {
                        self.transportMode = .disconnected
                        self.isRelayRoomActive = false
                        self.isPeerOnlineInRelay = false
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

    private func startPingLoop(generation: UInt64) {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 18.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] () -> Void in
                guard let self,
                      self.connectionGeneration == generation,
                      let task = self.webSocketTask else { return }
                let ts = Int(Date().timeIntervalSince1970 * 1000)
                if self.isSessionRelay {
                    _ = await self.sendRawJSON(["type": "relay_ping", "ts": ts], on: task)
                    if self.isConnected {
                        _ = await self.sendProtocolJSON(["type": "ping", "ts": ts], on: task)
                    }
                } else if self.isConnected {
                    _ = await self.sendRawJSON(["type": "ping", "ts": ts], on: task)
                }
            }
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard shouldStayConnected, autoReconnect else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] () -> Void in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled, let self, self.shouldStayConnected,
                  !self.isConnected, !self.isRelayRoomActive else { return }
            await self.connectAuto()
        }
    }

    // MARK: - Message Handling (PC -> Mobile)
    private func handleIncomingWebSocketMessage(
        _ message: URLSessionWebSocketTask.Message,
        generation: UInt64,
        directMode: PCSyncTransportMode? = nil
    ) {
        guard generation == connectionGeneration else { return }
        let data: Data
        switch message {
        case .string(let str): data = Data(str.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let envType = envelope["type"] as? String else { return }

        // Handle Zero-Knowledge Relay Control Envelopes
        if isSessionRelay {
            switch envType {
            case "relay_joined":
                isRelayRoomActive = true
                let peers = (envelope["peers"] as? [[String: Any]]) ?? []
                let hasPC = peers.contains { ($0["role"] as? String) == "pc" }
                if hasPC {
                    isPeerOnlineInRelay = true
                    statusMessage = "Đang bắt tay E2EE với PC..."
                    sendRelayHello(generation: generation)
                } else {
                    isPeerOnlineInRelay = false
                    transportMode = .disconnected
                    statusMessage = "Đang chờ PC mở VS Code..."
                    appendLog("SYS", "Đã vào phòng Relay \(relayServerURL). Chờ PC kết nối...")
                }
                return

            case "relay_peer_joined":
                let role = (envelope["role"] as? String) ?? "pc"
                if role == "pc" {
                    isPeerOnlineInRelay = true
                    statusMessage = "PC vừa online -> Đang bắt tay E2EE..."
                    appendLog("SYS", "PC vừa tham gia Relay room -> gửi hello...")
                    sendRelayHello(generation: generation)
                }
                return

            case "relay_peer_left":
                let role = (envelope["role"] as? String) ?? "pc"
                if role == "pc" {
                    isPeerOnlineInRelay = false
                    activeHandshakeCompleted = false
                    transportMode = .disconnected
                    statusMessage = "PC đã tạm ngắt -> Đang chờ PC mở VS Code lại..."
                    appendLog("SYS", "PC rời khỏi phòng đồng bộ (Outbox vẫn giữ chỉnh sửa).")
                }
                return

            case "relay_error":
                let errMsg = (envelope["message"] as? String) ?? "Relay error"
                statusMessage = "Relay báo lỗi: \(errMsg)"
                appendLog("ERR", errMsg)
                disconnectInternal(keepDesired: false)
                return

            case "relay_pong":
                return

            case "relay_packet":
                guard let encryptedB64 = envelope["p"] as? String,
                      let aesKey = activeRelayAESKey,
                      let decrypted = Self.openRelayPayload(encryptedB64, key: aesKey) else {
                    appendLog("ERR", "Giải mã E2EE thất bại (Sai Khóa Đồng Bộ?)")
                    return
                }
                dispatchAppProtocolMessage(decrypted, generation: generation, modeForWelcome: .internet4G)
                return

            default:
                break
            }
        }

        dispatchAppProtocolMessage(envelope, generation: generation, modeForWelcome: directMode ?? .wifiLAN)
    }

    private func sendRelayHello(generation: UInt64) {
        guard let task = webSocketTask, connectionGeneration == generation else { return }
        let hello: [String: Any] = [
            "type": "hello",
            "client": "3012-iOS",
            "version": "5.1.0",
            "pinPairing": activeSessionIsPinPairing
        ]
        Task { @MainActor [weak self] () -> Void in
            guard let self, self.connectionGeneration == generation else { return }
            _ = await self.sendProtocolJSON(hello, on: task)
        }
    }

    private func dispatchAppProtocolMessage(
        _ obj: [String: Any],
        generation: UInt64,
        modeForWelcome: PCSyncTransportMode
    ) {
        guard generation == connectionGeneration,
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
            let lanURL = (obj["lanUrl"] as? String) ?? ""
            let lanToken = (obj["lanToken"] as? String) ?? ""
            if !lanURL.isEmpty, !lanURL.contains("0.0.0.0"), !lanURL.contains("127.0.0.1") {
                lanWebSocketURL = lanURL
            }
            if let issuedPerm = obj["issuedPermanentKey"] as? String, !issuedPerm.isEmpty {
                permanentSyncKey = issuedPerm
                authToken = issuedPerm
                autoConnectEnabled = true
                quickPairPin = ""
                appendLog("SYS", "Đã nhận & lưu Khóa Vĩnh Viễn E2EE tự động nối về sau!")
            }

            transportMode = modeForWelcome
            activeHandshakeCompleted = true
            let modeDesc = isSessionRelay ? "4G/5G E2EE Relay" : modeForWelcome.badgeLabel
            statusMessage = remoteProjectName.isEmpty
                ? "Đã nối PC qua \(modeDesc)"
                : "Đang đồng bộ '\(remoteProjectName)' (\(modeDesc))"
            appendLog("SYS", "Kết nối thành công (\(modeDesc))")

            // Strict Outbox-First Handshake: flush offline edits BEFORE requesting snapshot!
            Task { @MainActor [weak self] () -> Void in
                guard let self, self.connectionGeneration == generation else { return }
                if !self.outbox.isEmpty {
                    await self.flushOutbox()
                }
                guard self.connectionGeneration == generation,
                      self.isConnected,
                      self.outbox.isEmpty,
                      let task = self.webSocketTask else { return }
                _ = await self.sendProtocolJSON(["type": "request_snapshot"], on: task)
                self.appendLog("OUT", "Đồng bộ xong Outbox -> yêu cầu snapshot PC")

                if self.isSessionRelay && self.isOnWiFi && !lanURL.isEmpty {
                    let probeTok = lanToken.isEmpty ? self.effectiveAuthToken() : lanToken
                    self.probeAndUpgradeToLAN(lanURL: lanURL, token: probeTok, currentGen: generation)
                }
            }

        case "error":
            let errText = (obj["message"] as? String) ?? "Authentication or protocol error"
            statusMessage = "PC báo lỗi: \(errText)"
            appendLog("ERR", errText)
            if errText.lowercased().contains("token")
                || errText.lowercased().contains("unauthorized")
                || errText.lowercased().contains("sai khoa") {
                shouldStayConnected = false
                disconnectInternal(keepDesired: false)
            }

        case "pong":
            break

        case "snapshot":
            if !outbox.isEmpty || isFlushingOutbox {
                appendLog("SYS", "Bỏ qua snapshot ban đầu để bảo vệ \(outbox.count) thay đổi trong Outbox.")
                return
            }
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
            if let oldPath = obj["oldPath"] as? String,
               let newPath = (obj["path"] as? String) ?? (obj["newPath"] as? String) {
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
                let result: (Int, String) = (code, out)
                cont.resume(returning: result)
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
            debounceTasks[key] = Task { [weak self] () -> Void in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                let item = SyncOutboxItem(
                    kind: "upsert",
                    path: rel,
                    oldPath: nil,
                    content: content,
                    isDir: nil
                )
                await self.enqueueOrSend(item)
            }

        case .deleteItem(let rel, let isDir):
            debounceTasks["upsert::\(rel)"]?.cancel()
            debounceTasks.removeValue(forKey: "upsert::\(rel)")
            if isDir {
                let keyPrefix = "upsert::\(rel)/"
                for k in debounceTasks.keys where k.hasPrefix(keyPrefix) {
                    debounceTasks[k]?.cancel()
                    debounceTasks.removeValue(forKey: k)
                }
            }
            let item = SyncOutboxItem(
                kind: "delete",
                path: rel,
                oldPath: nil,
                content: nil,
                isDir: isDir
            )
            Task { @MainActor [weak self] () -> Void in
                await self?.enqueueOrSend(item)
            }

        case .renameItem(let oldRel, let newRel, let isDir):
            debounceTasks["upsert::\(oldRel)"]?.cancel()
            debounceTasks.removeValue(forKey: "upsert::\(oldRel)")
            if isDir {
                let keyPrefix = "upsert::\(oldRel)/"
                for k in debounceTasks.keys where k.hasPrefix(keyPrefix) {
                    debounceTasks[k]?.cancel()
                    debounceTasks.removeValue(forKey: k)
                }
            }
            let item = SyncOutboxItem(
                kind: "rename",
                path: newRel,
                oldPath: oldRel,
                content: nil,
                isDir: isDir
            )
            Task { @MainActor [weak self] () -> Void in
                await self?.enqueueOrSend(item)
            }

        case .createDirectory(let rel):
            let item = SyncOutboxItem(
                kind: "mkdir",
                path: rel,
                oldPath: nil,
                content: nil,
                isDir: true
            )
            Task { @MainActor [weak self] () -> Void in
                await self?.enqueueOrSend(item)
            }
        }
    }

    public func pullSnapshotFromPC() async {
        guard let task = webSocketTask, isConnected else { return }
        _ = await sendProtocolJSON(["type": "request_snapshot"], on: task)
        appendLog("OUT", "Yêu cầu tải toàn bộ file từ PC")
    }

    public func pushFullWorkspaceToPC() async {
        guard let task = webSocketTask, isConnected, let workspaceManager else { return }
        let files = workspaceManager.collectAllSyncableTextFiles()
        let ok = await sendProtocolJSON(["type": "push_snapshot", "files": files], on: task)
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
        let raw: (Int, String) = await withCheckedContinuation { continuation in
            // Register continuation BEFORE sending to avoid early cmd_result race [PCSYNC-1]
            pendingCommandContinuations[reqID] = continuation
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                let sent = await self.sendProtocolJSON(["type": "exec_cmd", "id": reqID, "command": command], on: task)
                if !sent {
                    if let pending = self.pendingCommandContinuations.removeValue(forKey: reqID) {
                        let res: (Int, String) = (-1, "Không gửi được lệnh tới PC.")
                        pending.resume(returning: res)
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let pending = self.pendingCommandContinuations.removeValue(forKey: reqID) {
                    let res: (Int, String) = (-1, "Hết thời gian chờ phản hồi từ PC (\(Int(timeoutSeconds))s).")
                    pending.resume(returning: res)
                }
            }
        }
        return (exitCode: raw.0, output: raw.1)
    }

    private func enqueueOrSend(_ item: SyncOutboxItem) async {
        if item.kind == "upsert" {
            outbox.removeAll { $0.kind == "upsert" && $0.path == item.path }
        } else if item.kind == "delete" {
            let prefix = item.path + "/"
            outbox.removeAll { existing in
                (existing.kind == "upsert" || existing.kind == "mkdir") &&
                (existing.path == item.path || (item.isDir == true && existing.path.hasPrefix(prefix)))
            }
        }
        outbox.append(item)
        saveOutboxToDisk()

        if isConnected {
            await flushOutbox()
        }
    }

    public func flushOutbox() async {
        guard !isFlushingOutbox, let task = webSocketTask, isConnected, !outbox.isEmpty else { return }
        isFlushingOutbox = true
        defer { isFlushingOutbox = false }

        var sentCount = 0
        while let item = outbox.first {
            guard self.webSocketTask === task, self.isConnected else { break }
            var payload: [String: Any] = ["type": item.kind, "path": item.path]
            if let old = item.oldPath { payload["oldPath"] = old }
            if let content = item.content { payload["content"] = content }
            if let isDir = item.isDir { payload["isDir"] = isDir }
            if await sendProtocolJSON(payload, on: task) {
                if let idx = outbox.firstIndex(where: { $0.id == item.id }) {
                    outbox.remove(at: idx)
                }
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

    // MARK: - Transport Encoding (Direct JSON or AES-256-GCM Relay Envelope)
    private func sendProtocolJSON(_ dict: [String: Any], on task: URLSessionWebSocketTask) async -> Bool {
        if isSessionRelay {
            guard let aesKey = activeRelayAESKey,
                  let sealedB64 = Self.sealRelayPayload(dict, key: aesKey) else {
                return false
            }
            return await sendRawJSON(["type": "relay_packet", "p": sealedB64], on: task)
        }
        return await sendRawJSON(dict, on: task)
    }

    private func sendRawJSON(_ dict: [String: Any], on task: URLSessionWebSocketTask) async -> Bool {
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

    // MARK: - Zero-Dependency Node.js Companion Script (Matches GET https://build.kaydus.xyz/sync.mjs)
    private static func jsStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value]),
           let arr = String(data: data, encoding: .utf8),
           arr.hasPrefix("["), arr.hasSuffix("]") {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }

    public static func generateCompanionScript(
        port: Int = 30120,
        suggestedToken: String,
        relayBaseURL: String = defaultRelayBaseURL
    ) -> String {
        let keyLiteral = suggestedToken.isEmpty ? "3012-replace-with-your-key" : suggestedToken
        let relayClean = relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let relayDefault = relayClean.isEmpty ? defaultRelayBaseURL : relayClean
        let keyJS = jsStringLiteral(keyLiteral)
        let relayJS = jsStringLiteral(relayDefault)
        return """
        #!/usr/bin/env node
        // 3012 Zero-Dependency PC <-> Mobile 2-Way E2EE Companion (Node.js 18+)
        // Auto-generated offline fallback — official latest script: \(relayDefault)/sync.mjs
        import fs from "node:fs";
        import path from "node:path";
        import http from "node:http";
        import net from "node:net";
        import tls from "node:tls";
        import os from "node:os";
        import crypto from "node:crypto";
        import { spawn } from "node:child_process";

        const args = process.argv.slice(2);
        const getArg = (name, fallback = "") => {
          const prefix = `--${name}=`;
          for (let i = 0; i < args.length; i++) {
            if (args[i].startsWith(prefix)) return args[i].slice(prefix.length);
            if (args[i] === `--${name}` && args[i + 1]) return args[i + 1];
          }
          return fallback;
        };

        const ROOT = path.resolve(getArg("dir", process.cwd()));
        const PORT = Number(getArg("port", "\(port)"));
        const RELAY_BASE = getArg("relay", \(relayJS)).replace(/\\/+$/, "");
        const PERMANENT_KEY = getArg("key", getArg("token", \(keyJS))).trim();
        const QUICK_PIN = getArg("pin", "").trim();
        const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        const IGNORED = new Set([".git", "node_modules", ".next", "dist", "build", ".DS_Store", ".3012"]);
        const CLIENT_ID = "pc-" + crypto.randomBytes(6).toString("hex");

        function deriveRoom(secret) {
          return crypto.createHash("sha256").update("3012-room-v1:" + String(secret || "").trim(), "utf8").digest("hex");
        }
        function deriveAESKey(secret) {
          return crypto.createHash("sha256").update("3012-e2ee-v1:" + String(secret || "").trim(), "utf8").digest();
        }
        function encryptE2EE(obj, aesKey) {
          const iv = crypto.randomBytes(12);
          const cipher = crypto.createCipheriv("aes-256-gcm", aesKey, iv);
          const enc = Buffer.concat([cipher.update(JSON.stringify(obj), "utf8"), cipher.final()]);
          return Buffer.concat([iv, enc, cipher.getAuthTag()]).toString("base64");
        }
        function decryptE2EE(b64, aesKey) {
          const raw = Buffer.from(b64, "base64");
          if (raw.length < 28) return null;
          const decipher = crypto.createDecipheriv("aes-256-gcm", aesKey, raw.subarray(0, 12));
          decipher.setAuthTag(raw.subarray(raw.length - 16));
          const dec = Buffer.concat([decipher.update(raw.subarray(12, raw.length - 16)), decipher.final()]);
          return JSON.parse(dec.toString("utf8"));
        }
        function safeResolve(rel) {
          const clean = String(rel || "").replace(/\\\\/g, "/").replace(/^\\/+/, "");
          if (!clean || clean === "." || clean.split("/").some((s) => s === ".." || s === "")) return null;
          const resolved = path.resolve(ROOT, clean);
          if (resolved !== ROOT && !resolved.startsWith(ROOT + path.sep)) return null;
          try {
            let probe = resolved;
            while (probe !== ROOT && !fs.existsSync(probe)) {
              probe = path.dirname(probe);
            }
            const realProbe = fs.realpathSync(probe);
            const realRoot = fs.realpathSync(ROOT);
            if (realProbe !== realRoot && !realProbe.startsWith(realRoot + path.sep)) return null;
          } catch {
            return null;
          }
          return resolved;
        }
        function isTextBuffer(buf) {
          const limit = Math.min(buf.length, 4096);
          for (let i = 0; i < limit; i++) if (buf[i] === 0) return false;
          return true;
        }
        function collectSnapshot() {
          const files = {};
          const walk = (dir) => {
            let entries;
            try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
            for (const entry of entries) {
              if (IGNORED.has(entry.name) || entry.name.startsWith(".3012") || entry.isSymbolicLink()) continue;
              const full = path.join(dir, entry.name);
              if (entry.isDirectory()) walk(full);
              else if (entry.isFile()) {
                try {
                  const st = fs.statSync(full);
                  if (st.size <= 512 * 1024) {
                    const buf = fs.readFileSync(full);
                    if (isTextBuffer(buf)) files[path.relative(ROOT, full).split(path.sep).join("/")] = buf.toString("utf8");
                  }
                } catch {}
              }
            }
          };
          walk(ROOT);
          return files;
        }
        const suppressedEcho = new Map();
        const suppress = (rel) => suppressedEcho.set(rel, Date.now() + 900);
        const isSuppressed = (rel) => {
          const exp = suppressedEcho.get(rel);
          if (!exp) return false;
          if (Date.now() > exp) { suppressedEcho.delete(rel); return false; }
          return true;
        };
        function getLanIP() {
          const nets = os.networkInterfaces();
          for (const list of Object.values(nets)) {
            for (const netInfo of list || []) {
              if (netInfo.family === "IPv4" && !netInfo.internal) return netInfo.address;
            }
          }
          return "127.0.0.1";
        }
        function encodeWsFrame(opcode, payloadBuf, mask = false) {
          const len = payloadBuf.length;
          let hdr;
          if (len < 126) { hdr = Buffer.alloc(2); hdr[0] = 0x80 | opcode; hdr[1] = (mask ? 0x80 : 0) | len; }
          else if (len < 65536) { hdr = Buffer.alloc(4); hdr[0] = 0x80 | opcode; hdr[1] = (mask ? 0x80 : 0) | 126; hdr.writeUInt16BE(len, 2); }
          else { hdr = Buffer.alloc(10); hdr[0] = 0x80 | opcode; hdr[1] = (mask ? 0x80 : 0) | 127; hdr.writeBigUInt64BE(BigInt(len), 2); }
          if (!mask) return Buffer.concat([hdr, payloadBuf]);
          const m = crypto.randomBytes(4);
          const out = Buffer.allocUnsafe(len);
          for (let i = 0; i < len; i++) out[i] = payloadBuf[i] ^ m[i % 4];
          return Buffer.concat([hdr, m, out]);
        }
        function attachWsDecoder(sock, onMsg, onClose) {
          let buf = Buffer.alloc(0);
          let fragChunks = [];
          let closed = false;
          const finish = () => { if (!closed) { closed = true; onClose && onClose(); } };
          sock.on("data", (chunk) => {
            buf = Buffer.concat([buf, chunk]);
            while (buf.length >= 2) {
              const fin = (buf[0] & 0x80) !== 0;
              const opcode = buf[0] & 0x0f;
              const masked = (buf[1] & 0x80) !== 0;
              let payloadLen = buf[1] & 0x7f;
              let off = 2;
              if (payloadLen === 126) { if (buf.length < 4) break; payloadLen = buf.readUInt16BE(2); off = 4; }
              else if (payloadLen === 127) { if (buf.length < 10) break; payloadLen = Number(buf.readBigUInt64BE(2)); off = 10; }
              const maskLen = masked ? 4 : 0;
              if (buf.length < off + maskLen + payloadLen) break;
              let payload = Buffer.from(buf.subarray(off + maskLen, off + maskLen + payloadLen));
              if (masked) { const mk = buf.subarray(off, off + 4); for (let i = 0; i < payload.length; i++) payload[i] ^= mk[i % 4]; }
              buf = buf.subarray(off + maskLen + payloadLen);
              if (opcode === 0x8) { finish(); sock.end(); return; }
              if (opcode === 0x9) { try { sock.write(encodeWsFrame(0xA, payload, !masked)); } catch {} continue; }
              if (opcode === 0xA) continue;
              fragChunks.push(payload);
              if (fin) { const full = Buffer.concat(fragChunks); fragChunks = []; onMsg(full); }
            }
          });
          sock.on("close", finish);
          sock.on("error", finish);
        }
        const clients = new Set();
        const relayWorkers = [];
        function broadcastAll(obj, exceptSock = null) {
          for (const c of clients) {
            if (c.authed && c.sock !== exceptSock && !c.sock.destroyed) {
              try { c.sock.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(obj), "utf8"), false)); } catch {}
            }
          }
          for (const rw of relayWorkers) rw.ready && rw.sendApp(obj);
        }
        function handleMsg(msg, replyFn, exceptSock = null, isPinRoom = false) {
          if (!msg || typeof msg !== "object") return;
          if (msg.type === "hello") {
            replyFn({ type: "welcome", projectName: path.basename(ROOT), rootDir: ROOT, lanUrl: `ws://${getLanIP()}:${PORT}`, lanToken: PERMANENT_KEY, issuedPermanentKey: isPinRoom ? PERMANENT_KEY : undefined });
          } else if (msg.type === "ping") {
            replyFn({ type: "pong", ts: msg.ts });
          } else if (msg.type === "request_snapshot") {
            replyFn({ type: "snapshot", files: collectSnapshot() });
          } else if (msg.type === "push_snapshot" && msg.files) {
            for (const [rel, body] of Object.entries(msg.files)) {
              const abs = safeResolve(rel);
              if (abs && typeof body === "string") { suppress(rel); fs.mkdirSync(path.dirname(abs), { recursive: true }); fs.writeFileSync(abs, body, "utf8"); }
            }
          } else if (msg.type === "upsert" && msg.path && typeof msg.content === "string") {
            const abs = safeResolve(msg.path);
            if (abs) { suppress(msg.path); fs.mkdirSync(path.dirname(abs), { recursive: true }); fs.writeFileSync(abs, msg.content, "utf8"); broadcastAll(msg, exceptSock); }
          } else if (msg.type === "delete" && msg.path) {
            const abs = safeResolve(msg.path);
            if (abs && fs.existsSync(abs)) { suppress(msg.path); fs.rmSync(abs, { recursive: true, force: true }); broadcastAll(msg, exceptSock); }
          } else if (msg.type === "rename" && msg.oldPath && msg.path) {
            const s = safeResolve(msg.oldPath), d = safeResolve(msg.path);
            if (s && d && fs.existsSync(s)) { suppress(msg.oldPath); suppress(msg.path); fs.mkdirSync(path.dirname(d), { recursive: true }); fs.renameSync(s, d); broadcastAll(msg, exceptSock); }
          } else if (msg.type === "mkdir" && msg.path) {
            const abs = safeResolve(msg.path);
            if (abs) { fs.mkdirSync(abs, { recursive: true }); broadcastAll(msg, exceptSock); }
          } else if (msg.type === "exec_cmd" && msg.command) {
            const ch = spawn(msg.command, { cwd: ROOT, shell: true });
            let out = "", err = "";
            const t = setTimeout(() => { try { ch.kill("SIGTERM"); } catch {} }, 30000);
            ch.stdout.on("data", (d) => out += d.toString("utf8"));
            ch.stderr.on("data", (d) => err += d.toString("utf8"));
            ch.on("close", (code) => { clearTimeout(t); replyFn({ type: "cmd_result", id: msg.id || "", exitCode: code ?? 0, stdout: out, stderr: err }); });
          }
        }
        const server = http.createServer((_, res) => { res.writeHead(200); res.end("3012 PC Sync Ready\\n"); });
        server.on("upgrade", (req, sock) => {
          const k = req.headers["sec-websocket-key"];
          if (!k) return sock.destroy();
          const accept = crypto.createHash("sha1").update(k + WS_GUID).digest("base64");
          sock.write(["HTTP/1.1 101 Switching Protocols", "Upgrade: websocket", "Connection: Upgrade", `Sec-WebSocket-Accept: ${accept}`, "\\r\\n"].join("\\r\\n"));
          const c = { sock, authed: false };
          clients.add(c);
          const reply = (o) => !sock.destroyed && sock.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(o), "utf8"), false));
          attachWsDecoder(sock, (buf) => {
            let msg; try { msg = JSON.parse(buf.toString("utf8")); } catch { return; }
            if (!c.authed) {
              if (msg.type === "hello" && (msg.token === PERMANENT_KEY || (QUICK_PIN && msg.token === QUICK_PIN))) { c.authed = true; handleMsg(msg, reply, sock, QUICK_PIN && msg.token === QUICK_PIN); }
              else { reply({ type: "error", message: "Unauthorized" }); sock.end(); }
              return;
            }
            handleMsg(msg, reply, sock, false);
          }, () => clients.delete(c));
        });
        function startRelay(secret, isPin) {
          if (!secret) return null;
          const wsRaw = RELAY_BASE.replace(/^http/i, "ws");
          const u = new URL(wsRaw);
          if (!u.pathname || u.pathname === "/") u.pathname = "/v1/sync";
          const pathWithQuery = u.pathname + (u.search || "");
          const isTLS = u.protocol === "wss:", p = Number(u.port || (isTLS ? 443 : 80));
          const room = deriveRoom(secret), aesKey = deriveAESKey(secret);
          const rw = { ready: false, closed: false, sock: null, sendApp: () => {}, close: () => {} };
          relayWorkers.push(rw);
          const connectOnce = () => {
            if (rw.closed) return;
            const s = isTLS ? tls.connect({ host: u.hostname, port: p, servername: u.hostname }) : net.connect({ host: u.hostname, port: p });
            rw.sock = s;
            let hdrDone = false, hBuf = Buffer.alloc(0);
            const rawSend = (o) => !s.destroyed && s.write(encodeWsFrame(0x1, Buffer.from(JSON.stringify(o), "utf8"), true));
            rw.sendApp = (o) => rw.ready && rawSend({ type: "relay_packet", p: encryptE2EE(o, aesKey) });
            const pt = setInterval(() => rw.ready && rawSend({ type: "relay_ping", ts: Date.now() }), 20000);
            rw.close = () => { rw.closed = true; rw.ready = false; clearInterval(pt); try { s.destroy(); } catch {} };
            s.on("connect", () => s.write([`GET ${pathWithQuery} HTTP/1.1`, `Host: ${u.host}`, "Upgrade: websocket", "Connection: Upgrade", `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString("base64")}`, "Sec-WebSocket-Version: 13", "\\r\\n"].join("\\r\\n")));
            const onD = (chunk) => {
              if (hdrDone) return;
              hBuf = Buffer.concat([hBuf, chunk]);
              const i = hBuf.indexOf("\\r\\n\\r\\n");
              if (i < 0) return;
              const head = hBuf.subarray(0, i).toString("latin1");
              const left = hBuf.subarray(i + 4);
              s.removeListener("data", onD);
              if (!/^HTTP\\/1\\.[01]\\s+101\\b/i.test(head)) { s.destroy(); return; }
              hdrDone = true;
              rw.ready = true;
              rawSend({ type: "relay_join", room, role: "pc", clientId: CLIENT_ID });
              attachWsDecoder(s, (b) => {
                let env; try { env = JSON.parse(b.toString("utf8")); } catch { return; }
                if (env.type === "relay_packet" && typeof env.p === "string") {
                  let msg; try { msg = decryptE2EE(env.p, aesKey); } catch { return; }
                  if (msg) {
                    handleMsg(msg, rw.sendApp, null, isPin);
                    if (isPin && msg.type === "hello") setTimeout(() => rw.close(), 1500);
                  }
                }
              }, () => { clearInterval(pt); rw.ready = false; });
              if (left.length) s.emit("data", left);
            };
            s.on("data", onD);
            s.on("close", () => { clearInterval(pt); rw.ready = false; if (!rw.closed) setTimeout(connectOnce, 3500); });
            s.on("error", () => {});
          };
          connectOnce();
          return rw;
        }
        fs.watch(ROOT, { recursive: true }, (_, filename) => {
          if (!filename) return;
          const rel = String(filename).split(path.sep).join("/");
          if (rel.split("/").some((p) => IGNORED.has(p) || p.startsWith(".3012")) || isSuppressed(rel)) return;
          const abs = safeResolve(rel);
          if (!abs) return;
          setTimeout(() => {
            try {
              if (!fs.existsSync(abs)) broadcastAll({ type: "delete", path: rel, isDir: false });
              else {
                const st = fs.lstatSync(abs);
                if (!st.isSymbolicLink() && st.isFile() && st.size <= 512 * 1024) {
                  const b = fs.readFileSync(abs);
                  if (isTextBuffer(b)) broadcastAll({ type: "upsert", path: rel, content: b.toString("utf8") });
                }
              }
            } catch {}
          }, 120);
        });
        server.listen(PORT, "0.0.0.0", () => {
          console.log("\\n[3012 PC SYNC E2EE READY] ->", RELAY_BASE);
          console.log("Key :", PERMANENT_KEY);
          if (QUICK_PIN) console.log("PIN :", QUICK_PIN);
          startRelay(PERMANENT_KEY, false);
          if (QUICK_PIN) {
            const pinWorker = startRelay(QUICK_PIN, true);
            if (pinWorker) setTimeout(() => pinWorker.close(), 180000);
          }
        });
        """
    }
}
