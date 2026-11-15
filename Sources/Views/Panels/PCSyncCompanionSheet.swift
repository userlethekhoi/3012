import SwiftUI
import UIKit

public struct PCSyncCompanionSheet: View {
    @ObservedObject var pcSync: PCSyncService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var pairingInput: String = ""
    @State private var remoteCmd: String = "git status"
    @State private var remoteCmdOutput: String = ""
    @State private var isRunningRemoteCmd: Bool = false
    @State private var generatedToken: String = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
    @State private var copiedNotice: String? = nil

    public init(
        pcSync: PCSyncService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences
    ) {
        self.pcSync = pcSync
        self.workspace = workspace
        self.preferences = preferences
    }

    public var body: some View {
        CompatibleNavigationContainer {
            Form {
                // Status Header
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: pcSync.isConnected ? "arrow.triangle.2.circlepath.circle.fill" : "desktopcomputer")
                            .font(.system(size: 28))
                            .foregroundColor(pcSync.isConnected ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(pcSync.isConnected
                                 ? (pcSync.remoteProjectName.isEmpty ? "PC Sync Active" : pcSync.remoteProjectName)
                                 : preferences.tr("Đồng bộ 2 chiều PC <-> Mobile", "2-Way PC <-> Mobile Sync"))
                                .font(.headline)
                            Text(pcSync.statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Label(pcSync.networkInterfaceSummary, systemImage: pcSync.isOnWiFi ? "wifi" : "antenna.radiowaves.left.and.right")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                if pcSync.pendingOutboxCount > 0 {
                                    Text("Outbox: \(pcSync.pendingOutboxCount)")
                                        .font(.caption2.monospacedDigit())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        Spacer()
                        Text(pcSync.transportMode.badgeLabel)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(pcSync.isConnected ? Color.green.opacity(0.18) : Color.secondary.opacity(0.15))
                            .foregroundColor(pcSync.isConnected ? .green : .secondary)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }

                // Quick Pairing
                Section(preferences.tr("Ghép đôi nhanh (Wi-Fi + 4G/5G)", "Quick Pair (Wi-Fi + 4G/5G)")) {
                    HStack(spacing: 8) {
                        TextField("3012sync://pair?lan=...&wan=...&token=...", text: $pairingInput)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button(preferences.tr("Dán", "Paste")) {
                            if let clip = UIPasteboard.general.string {
                                pairingInput = clip
                                _ = pcSync.applyPairingString(clip)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if !pairingInput.isEmpty {
                        Button {
                            if pcSync.applyPairingString(pairingInput) {
                                Task { await pcSync.connectAuto() }
                            }
                        } label: {
                            Label(preferences.tr("Áp dụng Link ghép đôi & Kết nối", "Apply Pairing Link & Connect"), systemImage: "link.badge.plus")
                        }
                    }

                    TextField("Wi-Fi LAN URL (ws://192.168.1.x:3012)", text: $pcSync.lanWebSocketURL)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("4G/5G Tunnel URL (wss://...trycloudflare.com)", text: $pcSync.internetWebSocketURL)
                        .font(.system(size: 12.5, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField(preferences.tr("Mã Token bí mật", "Secret Auth Token"), text: $pcSync.authToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Toggle(preferences.tr("Tự động đồng bộ ngay khi lưu / sửa", "Real-Time Auto-Save Sync"), isOn: $pcSync.autoSyncEdits)
                    Toggle(preferences.tr("Tự nối lại & chuyển Wi-Fi <-> 4G tự động", "Auto-Reconnect & Wi-Fi <-> 4G Handoff"), isOn: $pcSync.autoReconnect)

                    HStack(spacing: 10) {
                        Button {
                            if pcSync.isConnected {
                                pcSync.disconnect()
                            } else {
                                Task { await pcSync.connectAuto() }
                            }
                        } label: {
                            HStack {
                                if pcSync.isConnecting {
                                    ProgressView().scaleEffect(0.8)
                                }
                                Text(pcSync.isConnected
                                     ? preferences.tr("Ngắt kết nối", "Disconnect")
                                     : preferences.tr("Kết nối PC ngay", "Connect to PC"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(pcSync.isConnected ? .red : .blue)
                    }
                }

                // Manual Two-Way Sync Actions
                if pcSync.isConnected || pcSync.pendingOutboxCount > 0 {
                    Section(preferences.tr("Thao tác Đồng bộ Thủ công", "Manual Sync Controls")) {
                        if pcSync.isConnected {
                            Button {
                                Task { await pcSync.pullSnapshotFromPC() }
                            } label: {
                                Label(preferences.tr("Tải toàn bộ thư mục PC về Mobile", "Pull Full Project Snapshot from PC"), systemImage: "arrow.down.doc")
                            }

                            Button {
                                Task { await pcSync.pushFullWorkspaceToPC() }
                            } label: {
                                Label(preferences.tr("Đẩy toàn bộ workspace Mobile lên PC", "Push Mobile Workspace to PC"), systemImage: "arrow.up.doc")
                            }
                        }

                        if pcSync.pendingOutboxCount > 0 {
                            Button(role: .destructive) {
                                pcSync.clearOutbox()
                            } label: {
                                Label(preferences.tr("Xóa hàng đợi Outbox chưa gửi (\(pcSync.pendingOutboxCount))", "Clear Pending Outbox (\(pcSync.pendingOutboxCount))"), systemImage: "trash")
                            }
                        }
                    }
                }

                // Remote PC Terminal Runner (Works over Wi-Fi AND 4G!)
                if pcSync.isConnected {
                    Section(preferences.tr("Chạy lệnh Terminal trên PC từ xa", "Remote PC Command Runner")) {
                        HStack {
                            TextField("npm run build / git status / python main.py", text: $remoteCmd)
                                .font(.system(size: 12.5, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button {
                                runCmdOnPC()
                            } label: {
                                if isRunningRemoteCmd {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Text(preferences.tr("Chạy", "Run"))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunningRemoteCmd || remoteCmd.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !remoteCmdOutput.isEmpty {
                            ScrollView {
                                Text(remoteCmdOutput)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                }

                // PC Companion Script Generator
                Section {
                    let activeToken = pcSync.authToken.isEmpty ? generatedToken : pcSync.authToken
                    let scriptText = PCSyncService.generateCompanionScript(suggestedToken: activeToken)
                    let oneLiner = "node 3012-pc-sync.mjs --token=\(activeToken) --tunnel"

                    Button {
                        if pcSync.authToken.isEmpty {
                            pcSync.authToken = activeToken
                        }
                        UIPasteboard.general.string = scriptText
                        copiedNotice = preferences.tr("Đã copy file 3012-pc-sync.mjs! Hãy lưu vào thư mục code trên PC.", "Copied 3012-pc-sync.mjs! Save it in your PC project folder.")
                    } label: {
                        Label(preferences.tr("Copy Script PC Companion (3012-pc-sync.mjs)", "Copy PC Companion Script (3012-pc-sync.mjs)"), systemImage: "doc.on.doc")
                    }

                    Button {
                        if pcSync.authToken.isEmpty {
                            pcSync.authToken = activeToken
                        }
                        UIPasteboard.general.string = oneLiner
                        copiedNotice = preferences.tr("Đã copy lệnh khởi chạy PC: \(oneLiner)", "Copied launch command: \(oneLiner)")
                    } label: {
                        Label(preferences.tr("Copy lệnh chạy trên PC (bật cả 4G Tunnel)", "Copy PC Launch Command (with 4G Tunnel)"), systemImage: "terminal")
                    }

                    if let copiedNotice {
                        Text(copiedNotice)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } header: {
                    Text(preferences.tr("Cài đặt trên Máy tính (Windows / macOS / Linux)", "PC Setup (Zero Dependencies - Node 18+)"))
                } footer: {
                    Text(preferences.tr(
                        "1) Dán 3012-pc-sync.mjs vào thư mục dự án VS Code trên PC. 2) Chạy 'node 3012-pc-sync.mjs --tunnel'. 3) Copy dòng '3012sync://pair?...' trên PC dán vào ô Ghép đôi nhanh ở trên để đồng bộ tức thì cả khi ở nhà (Wi-Fi) lẫn ra ngoài (4G).",
                        "1) Save 3012-pc-sync.mjs into your PC project folder. 2) Run 'node 3012-pc-sync.mjs --tunnel'. 3) Paste the printed 3012sync://pair?... link above for instant Wi-Fi + 4G sync."
                    ))
                }

                // Live Activity Log
                if !pcSync.activityLogs.isEmpty {
                    Section(preferences.tr("Nhật ký Đồng bộ Trực tiếp", "Live Sync Activity")) {
                        ForEach(pcSync.activityLogs.prefix(20)) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.direction)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(logColor(entry.direction).opacity(0.18))
                                    .foregroundColor(logColor(entry.direction))
                                    .cornerRadius(4)
                                Text(entry.detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(preferences.tr("Đồng bộ PC <-> Mobile", "PC <-> Mobile Sync"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
        }
    }

    private func logColor(_ dir: String) -> Color {
        switch dir {
        case "IN": return .blue
        case "OUT": return .green
        case "ERR": return .red
        default: return .secondary
        }
    }

    private func runCmdOnPC() {
        let cmd = remoteCmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        isRunningRemoteCmd = true
        Task {
            let res = await pcSync.executeCommandOnPC(cmd)
            remoteCmdOutput = "[exit \(res.exitCode)]\n" + res.output
            isRunningRemoteCmd = false
        }
    }
}
