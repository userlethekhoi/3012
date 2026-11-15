import SwiftUI
import UIKit

public struct PCSyncCompanionSheet: View {
    @ObservedObject private var pcSync: PCSyncService
    @ObservedObject private var workspace: WorkspaceManager
    @ObservedObject private var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var pinInput: String = ""
    @State private var pairingInput: String = ""
    @State private var remoteCommand: String = "git status -s"
    @State private var remoteCommandOutput: String = ""
    @State private var remoteExitCode: Int? = nil
    @State private var isRunningRemoteCommand: Bool = false
    @State private var copiedMessage: String? = nil
    @State private var showManualOverrides: Bool = false
    @State private var showRemoteTerminal: Bool = false
    @State private var showActivityLogs: Bool = false

    public init(
        pcSync: PCSyncService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences
    ) {
        self.pcSync = pcSync
        self.workspace = workspace
        self.preferences = preferences
    }

    private var palette: IDEColorPalette {
        preferences.activePalette
    }

    private var oneLineCLIInstallCommand: String {
        let base = pcSync.relayServerURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let effectiveBase = base.isEmpty ? PCSyncService.defaultRelayBaseURL : base
        let safeKey = pcSync.permanentSyncKey.isEmpty ? "YOUR_SYNC_KEY" : pcSync.permanentSyncKey
        return "curl -fsSL \(effectiveBase)/sync.mjs -o 3012-sync.mjs && node 3012-sync.mjs --key \(safeKey)"
    }

    public var body: some View {
        CompatibleNavigationContainer {
            Form {
                statusSection
                quickPairSection
                pcSetupSection
                manualAndOutboxSection
            }
            .navigationTitle(preferences.tr("Đồng Bộ PC <-> Mobile", "PC <-> Mobile Sync"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(preferences.tr("Xong", "Done")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                pcSync.attachWorkspace(workspace)
            }
        }
    }

    // MARK: - Status Banner

    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: pcSync.isConnected ? "checkmark.circle.fill" : (pcSync.isConnecting ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right"))
                        .font(.title2)
                        .foregroundColor(pcSync.isConnected ? .green : (pcSync.isConnecting ? .orange : .accentColor))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionHeadline)
                            .font(.headline)
                        Text(pcSync.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Badges: E2EE + Peer Online + Transport
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        badgeView(
                            icon: "lock.shield.fill",
                            text: pcSync.isEndToEndEncrypted ? "AES-256-GCM E2EE" : "E2EE Ready",
                            color: pcSync.isEndToEndEncrypted ? .green : .blue
                        )

                        badgeView(
                            icon: pcSync.isPeerOnlineInRelay ? "laptopcomputer" : "wifi",
                            text: pcSync.isPeerOnlineInRelay
                                ? preferences.tr("PC Đang Online", "PC Online")
                                : (pcSync.isRelayRoomActive
                                    ? preferences.tr("Đang chờ PC...", "Waiting for PC...")
                                    : preferences.tr("Relay Chờ", "Relay Standby")),
                            color: pcSync.isPeerOnlineInRelay ? .green : .orange
                        )

                        badgeView(
                            icon: pcSync.isOnWiFi ? "wifi" : "antenna.radiowaves.left.and.right",
                            text: pcSync.networkInterfaceSummary,
                            color: .secondary
                        )
                    }
                }

                if !pcSync.remoteProjectName.isEmpty || pcSync.syncedFilesCount > 0 || pcSync.pendingOutboxCount > 0 {
                    HStack(spacing: 12) {
                        if !pcSync.remoteProjectName.isEmpty {
                            Label(pcSync.remoteProjectName, systemImage: "folder.fill")
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(pcSync.syncedFilesCount) " + preferences.tr("file", "files"))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        if pcSync.pendingOutboxCount > 0 {
                            Text("Outbox: \(pcSync.pendingOutboxCount)")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 2)
                }

                if let copied = copiedMessage {
                    Text(copied)
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var connectionHeadline: String {
        if pcSync.isConnected {
            if !pcSync.remoteProjectName.isEmpty {
                return preferences.tr("Đang đồng bộ: ", "Syncing: ") + pcSync.remoteProjectName
            }
            return preferences.tr("Đã kết nối PC", "Connected to PC")
        }
        if pcSync.isConnecting {
            return preferences.tr("Đang kết nối tới PC...", "Connecting to PC...")
        }
        if pcSync.isRelayRoomActive {
            return preferences.tr("Phòng Relay đang chờ PC", "Relay Room Ready")
        }
        return preferences.tr("Chưa kết nối PC", "Not Connected")
    }

    private func badgeView(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .foregroundColor(color == .secondary ? Color(hex: palette.foreground) : color)
        .cornerRadius(6)
    }

    // MARK: - Card 1: 6-digit PIN + Permanent Sync Key + Auto-Connect

    private var quickPairSection: some View {
        Section {
            // Option A: 6-digit Quick PIN
            VStack(alignment: .leading, spacing: 8) {
                Label(preferences.tr("Ghép đôi siêu tốc qua Relay (4G / Wi-Fi)", "Instant Relay Pairing (4G / Wi-Fi)"), systemImage: "bolt.fill")
                    .font(.subheadline.bold())

                Text(preferences.tr(
                    "Nhập mã PIN 6 số hiện trên VS Code PC — hệ thống tự nhận Permanent Sync Key được mã hóa E2EE để các lần sau tự kết nối 0-chạm.",
                    "Enter the 6-digit PIN shown in PC VS Code — your Permanent Sync Key upgrades automatically with E2EE for zero-touch reconnect."
                ))
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("123456", text: $pinInput)
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    Button {
                        let pin = pinInput
                        Task { () -> Void in
                            await pcSync.connectWithQuickPIN(pin)
                        }
                    } label: {
                        Text(preferences.tr("Ghép PIN", "Pair PIN"))
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinInput.filter(\.isNumber).count < 4 || pcSync.isConnecting)
                }
            }
            .padding(.vertical, 4)

            // Option B: Permanent Sync Key
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(preferences.tr("Permanent Sync Key (Tự nối 4G/Wi-Fi)", "Permanent Sync Key (Auto 4G/Wi-Fi)"), systemImage: "key.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Button(preferences.tr("Tạo Key Mới", "New Key")) {
                        let generated = pcSync.generateNewPermanentKey()
                        copyToClipboard(generated, notice: preferences.tr("Đã tạo & copy Key mới", "Generated & copied new Key"))
                    }
                    .font(.caption.bold())
                }

                HStack(spacing: 8) {
                    TextField("3012-XXXX-...", text: $pcSync.permanentSyncKey)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        copyToClipboard(pcSync.permanentSyncKey, notice: preferences.tr("Đã copy Permanent Key", "Copied Permanent Key"))
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .disabled(pcSync.permanentSyncKey.isEmpty)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { () -> Void in
                            await pcSync.connectAuto()
                        }
                    } label: {
                        Label(
                            pcSync.isConnected
                                ? preferences.tr("Kết nối lại", "Reconnect")
                                : preferences.tr("Kết nối ngay", "Connect Now"),
                            systemImage: "bolt.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pcSync.isConnecting)

                    if pcSync.isConnected || pcSync.isConnecting || pcSync.isRelayRoomActive {
                        Button(role: .destructive) {
                            pcSync.disconnect()
                        } label: {
                            Label(preferences.tr("Ngắt", "Disconnect"), systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 4)

            Toggle(preferences.tr("Tự động kết nối khi mở app (Zero-Touch)", "Auto-connect on launch (Zero-Touch)"), isOn: $pcSync.autoConnectEnabled)
            Toggle(preferences.tr("Đồng bộ 2 chiều tức thì khi sửa & lưu", "Instant 2-way sync on edit & save"), isOn: $pcSync.autoSyncEdits)
        } header: {
            Text(preferences.tr("Kết nối nhanh qua build.kaydus.xyz", "Quick Connect via build.kaydus.xyz"))
        }
    }

    // MARK: - Card 2: PC Setup (Extension .vsix & Node 1-Liner)

    private var pcSetupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(preferences.tr("Cách 1: Extension VS Code (.vsix)", "Option 1: VS Code Extension (.vsix)"), systemImage: "laptopcomputer")
                    .font(.subheadline.bold())
                Text(preferences.tr(
                    "Cài file 3012-vscode-sync.vsix (có sẵn trong GitHub Releases) vào VS Code trên PC, dán Permanent Sync Key hoặc bấm \"Show PIN 6 số\" ở thanh trạng thái.",
                    "Install 3012-vscode-sync.vsix (included in GitHub Releases) in PC VS Code, paste your Permanent Sync Key or click \"Show 6-digit PIN\" in the status bar."
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Label(preferences.tr("Cách 2: Lệnh 1 dòng (Không cần mở VS Code)", "Option 2: 1-Line CLI (No Extension Needed)"), systemImage: "terminal.fill")
                    .font(.subheadline.bold())

                Text(oneLineCLIInstallCommand)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                HStack {
                    Button {
                        copyToClipboard(oneLineCLIInstallCommand, notice: preferences.tr("Đã copy lệnh chạy trên PC", "Copied PC CLI command"))
                    } label: {
                        Label(preferences.tr("Copy lệnh 1 dòng", "Copy 1-Line Cmd"), systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        let script = PCSyncService.generateCompanionScript(
                            suggestedToken: pcSync.permanentSyncKey,
                            relayBaseURL: pcSync.relayServerURL
                        )
                        copyToClipboard(script, notice: preferences.tr("Đã copy hướng dẫn & Script", "Copied setup script"))
                    } label: {
                        Label(preferences.tr("Copy Script đầy đủ", "Copy Full Script"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(preferences.tr("Dán link ghép đôi (3012sync://pair?...)", "Paste Pairing URL (3012sync://pair?...)"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("3012sync://pair?...", text: $pairingInput)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    Button(preferences.tr("Áp dụng", "Apply")) {
                        if pcSync.applyPairingString(pairingInput) {
                            copiedMessage = preferences.tr("Đã áp dụng cấu hình ghép đôi!", "Pairing configuration applied!")
                            Task { () -> Void in
                                await pcSync.connectAuto()
                            }
                        } else {
                            copiedMessage = preferences.tr("Link ghép đôi không hợp lệ.", "Invalid pairing URL.")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(preferences.tr("Cài đặt 1 lần trên PC", "1-Time PC Setup"))
        }
    }

    // MARK: - Card 3: Manual Actions, LAN/Tunnel Overrides & Remote Terminal

    private var manualAndOutboxSection: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    Task { () -> Void in
                        await pcSync.pullSnapshotFromPC()
                    }
                } label: {
                    Label(preferences.tr("Kéo từ PC", "Pull from PC"), systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!pcSync.isConnected)

                Button {
                    Task { () -> Void in
                        await pcSync.pushFullWorkspaceToPC()
                    }
                } label: {
                    Label(preferences.tr("Đẩy lên PC", "Push to PC"), systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!pcSync.isConnected)
            }

            if pcSync.pendingOutboxCount > 0 {
                Button(role: .destructive) {
                    pcSync.clearOutbox()
                } label: {
                    Label(
                        preferences.tr("Xóa hàng đợi Outbox (\(pcSync.pendingOutboxCount))", "Clear Pending Outbox (\(pcSync.pendingOutboxCount))"),
                        systemImage: "trash"
                    )
                }
            }

            DisclosureGroup(
                preferences.tr("Cấu hình Relay / LAN Wi-Fi / Tunnel thủ công", "Manual Relay / LAN Wi-Fi / Tunnel Overrides"),
                isExpanded: $showManualOverrides
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField(preferences.tr("Relay Server (Mặc định build.kaydus.xyz)", "Relay Server"), text: $pcSync.relayServerURL, placeholder: PCSyncService.defaultRelayBaseURL)
                    labeledField(preferences.tr("LAN WebSocket (Cùng Wi-Fi)", "LAN WebSocket (Same Wi-Fi)"), text: $pcSync.lanWebSocketURL, placeholder: "ws://192.168.1.10:30120")
                    labeledField(preferences.tr("Tunnel / WSS dự phòng", "Backup WSS Tunnel"), text: $pcSync.internetWebSocketURL, placeholder: "wss://...")
                    labeledField(preferences.tr("Auth Token dự phòng", "Backup Auth Token"), text: $pcSync.authToken, placeholder: "token")
                    Toggle(preferences.tr("Tự kết nối lại khi rớt mạng", "Auto-reconnect on drop"), isOn: $pcSync.autoReconnect)
                }
                .padding(.vertical, 4)
            }

            DisclosureGroup(
                preferences.tr("Chạy lệnh từ xa trên PC (Remote Terminal)", "Remote PC Command Runner"),
                isExpanded: $showRemoteTerminal
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("npm run build", text: $remoteCommand)
                            .font(.system(.caption, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            let cmd = remoteCommand
                            isRunningRemoteCommand = true
                            Task { () -> Void in
                                let result = await pcSync.executeCommandOnPC(cmd)
                                await MainActor.run {
                                    remoteExitCode = result.exitCode
                                    remoteCommandOutput = result.output
                                    isRunningRemoteCommand = false
                                }
                            }
                        } label: {
                            if isRunningRemoteCommand {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!pcSync.isConnected || isRunningRemoteCommand || remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let code = remoteExitCode {
                        Text("Exit code: \(code)")
                            .font(.caption2.bold())
                            .foregroundColor(code == 0 ? .green : .red)
                    }

                    if !remoteCommandOutput.isEmpty {
                        ScrollView {
                            Text(remoteCommandOutput)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 150)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
            }

            DisclosureGroup(
                preferences.tr("Nhật ký đồng bộ (\(pcSync.activityLogs.count))", "Sync Activity Log (\(pcSync.activityLogs.count))"),
                isExpanded: $showActivityLogs
            ) {
                if pcSync.activityLogs.isEmpty {
                    Text(preferences.tr("Chưa có nhật ký.", "No logs yet."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(pcSync.activityLogs.prefix(25)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level)
                                .font(.caption2.bold().monospaced())
                                .foregroundColor(entry.level == "ERR" ? .red : (entry.level == "WARN" ? .orange : .green))
                            Text(entry.message)
                                .font(.caption2)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            Text(preferences.tr("Công cụ & Nâng cao", "Tools & Advanced"))
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .font(.system(.caption, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func copyToClipboard(_ value: String, notice: String) {
        UIPasteboard.general.string = value
        copiedMessage = notice
    }
}
