import SwiftUI
import UIKit

public struct LocalDaemonManagerSheet: View {
    @ObservedObject var daemonService: LocalDaemonService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var telegramTokenInput: String = ""
    @State private var revealToken: Bool = false
    @State private var selectedLogPID: Int? = nil
    @State private var copiedLogsPID: Int? = nil

    public init(
        daemonService: LocalDaemonService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences
    ) {
        self.daemonService = daemonService
        self.workspace = workspace
        self.preferences = preferences
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: - 1. Local On-Device Runtime & Live Hardware Status
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: daemonService.isKeepAliveActive ? "bolt.shield.fill" : "terminal.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(daemonService.isKeepAliveActive ? .green : .orange)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(daemonService.isKeepAliveActive
                                     ? preferences.tr("Đang giữ chạy ngầm 24/7 trên máy", "24/7 On-Device Keep-Alive Active")
                                     : preferences.tr("Chế độ chạy ngầm đang tắt", "Background Keep-Alive Off"))
                                    .font(.system(size: 14, weight: .bold))

                                Text(preferences.tr(
                                    "Chạy trực tiếp trên iPhone/iPad của bạn — không dùng VPS ngoài, tắt màn hình vẫn hoạt động miễn còn pin & mạng.",
                                    "Runs 100% locally on your own iPhone/iPad — zero external VPS needed; stays alive while screen is off as long as battery & network hold."
                                ))
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            statusBadge(
                                icon: daemonService.networkOnline ? "wifi" : "wifi.slash",
                                text: daemonService.networkOnline ? "Online" : "Offline",
                                color: daemonService.networkOnline ? .green : .red
                            )
                            statusBadge(
                                icon: daemonService.isCharging ? "battery.100.bolt" : "battery.75",
                                text: "\(daemonService.batteryPercentage)%",
                                color: daemonService.batteryPercentage <= 15 ? .red : .blue
                            )
                            statusBadge(
                                icon: "cpu",
                                text: "\(daemonService.runningJobsCount) " + preferences.tr("đang chạy", "running"),
                                color: daemonService.runningJobsCount > 0 ? .green : .secondary
                            )
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(preferences.tr("Terminal Ngầm Trên Chính Máy (On-Device Daemon)", "On-Device Background Terminal & Bot Runtime"))
                }

                // MARK: - 2. Background Keep-Alive Controls
                Section {
                    Toggle(
                        preferences.tr(
                            "Chạy ngầm Terminal & Bot khi tắt màn hình (24/7 Keep-Alive)",
                            "Keep Terminal & Bots Running When Screen Off (24/7)"
                        ),
                        isOn: $daemonService.keepTerminalAliveInBackground
                    )

                    Toggle(
                        preferences.tr(
                            "Tự động thử lại kết nối khi mạng gián đoạn",
                            "Auto-Retry Network Connections on Drop"
                        ),
                        isOn: $daemonService.autoRestartOnError
                    )

                    Toggle(
                        preferences.tr(
                            "Giữ sáng màn hình khi đang mở app (Chống khóa máy)",
                            "Prevent Screen Auto-Lock While App Open"
                        ),
                        isOn: $daemonService.preventScreenSleep
                    )
                } header: {
                    Text(preferences.tr("Tùy Chọn Chạy Ngầm", "Background Execution Settings"))
                } footer: {
                    Text(preferences.tr(
                        "Bật 24/7 Keep-Alive giúp iOS không đóng băng tiến trình và socket mạng khi bạn khóa màn hình hoặc chuyển sang app khác. Hãy cắm sạc nếu treo bot liên tục nhiều giờ.",
                        "24/7 Keep-Alive prevents iOS from suspending running scripts and network sockets when you lock the screen or switch apps. Plug in power for overnight bot hosting."
                    ))
                }

                // MARK: - 3. 1-Tap Telegram Bot & Active Script Runner
                Section {
                    HStack {
                        Group {
                            if revealToken {
                                TextField("TELEGRAM_BOT_TOKEN (123456:ABC...)", text: $telegramTokenInput)
                            } else {
                                SecureField("TELEGRAM_BOT_TOKEN (123456:ABC...)", text: $telegramTokenInput)
                            }
                        }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 12.5, design: .monospaced))

                        Button {
                            revealToken.toggle()
                        } label: {
                            Image(systemName: revealToken ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    Button {
                        daemonService.keepTerminalAliveInBackground = true
                        let botURL = daemonService.scaffoldTelegramBot(
                            botToken: telegramTokenInput,
                            in: workspace,
                            startImmediately: true
                        )
                        if let latest = daemonService.jobs.first(where: { $0.name == botURL.lastPathComponent }) {
                            selectedLogPID = latest.pid
                        }
                    } label: {
                        Label(
                            preferences.tr("Tạo & Treo Bot Telegram Ngầm Ngay", "Create & Run Telegram Bot in Background"),
                            systemImage: "paperplane.circle.fill"
                        )
                        .fontWeight(.bold)
                    }

                    if let active = workspace.activeTab {
                        Button {
                            workspace.saveActiveTab()
                            daemonService.keepTerminalAliveInBackground = true
                            let job = daemonService.startJob(fileURL: active.fileURL, workspaceRoot: workspace.rootURL)
                            selectedLogPID = job.pid
                        } label: {
                            Label(
                                preferences.tr("Chạy Ngầm File Đang Mở (\(active.title))", "Run Active File as Background Daemon (\(active.title))"),
                                systemImage: "play.circle.fill"
                            )
                            .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text(preferences.tr("Treo Bot Telegram & Script 1 Chạm", "1-Tap Telegram Bot & Script Launcher"))
                } footer: {
                    Text(preferences.tr(
                        "Token được lưu vào tệp .env trong dự án của bạn và chỉ gửi trực tiếp tới api.telegram.org từ chính thiết bị này.",
                        "Token is saved locally to .env in your workspace and connects directly from this device to api.telegram.org."
                    ))
                }

                // MARK: - 4. Running Daemons & Live Logs
                Section {
                    if daemonService.jobs.isEmpty {
                        Text(preferences.tr(
                            "Chưa có tiến trình ngầm nào. Bấm nút ở trên hoặc gõ 'node <file.js>' / 'bot new <token>' trong Terminal.",
                            "No background daemons yet. Tap above or run 'node <file.js>' / 'bot new <token>' in Terminal."
                        ))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    } else {
                        ForEach(daemonService.jobs) { job in
                            daemonJobRow(job)
                        }
                    }
                } header: {
                    HStack {
                        Text(preferences.tr("Tiến Trình Đang Treo Trên Máy", "On-Device Background Processes"))
                        Spacer()
                        if daemonService.jobs.contains(where: { !$0.isRunning }) {
                            Button(preferences.tr("Dọn đã dừng", "Clear Stopped")) {
                                daemonService.removeStoppedJobs()
                            }
                            .font(.caption)
                        }
                        if daemonService.runningJobsCount > 0 {
                            Button(preferences.tr("Dừng tất cả", "Stop All"), role: .destructive) {
                                daemonService.stopAllJobs()
                            }
                            .font(.caption)
                        }
                    }
                }

                // MARK: - 5. Selected Job Console Log Viewer
                if let pid = selectedLogPID,
                   let selectedJob = daemonService.jobs.first(where: { $0.pid == pid }) {
                    Section {
                        ScrollView {
                            Text(selectedJob.logs.isEmpty ? "(No logs yet)" : selectedJob.logs.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 150, maxHeight: 260)

                        HStack {
                            Button {
                                UIPasteboard.general.string = selectedJob.logs.joined(separator: "\n")
                                copiedLogsPID = selectedJob.pid
                            } label: {
                                Label(
                                    copiedLogsPID == selectedJob.pid
                                        ? preferences.tr("Đã chép Log!", "Logs Copied!")
                                        : preferences.tr("Chép Log", "Copy Logs"),
                                    systemImage: copiedLogsPID == selectedJob.pid ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                            }
                            Spacer()
                            Button(role: .destructive) {
                                daemonService.clearLogs(pid: selectedJob.pid)
                            } label: {
                                Label(preferences.tr("Xoá Log", "Clear Logs"), systemImage: "trash")
                            }
                        }
                        .font(.caption.weight(.semibold))
                    } header: {
                        Text("Logs — PID \(selectedJob.pid) (\(selectedJob.name))")
                    }
                }
            }
            .navigationTitle(preferences.tr("Chạy Ngầm & Treo Bot", "Background Terminal & Bots"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
            .onAppear {
                if telegramTokenInput.isEmpty {
                    telegramTokenInput = LocalDaemonService.savedTelegramToken(in: workspace.rootURL)
                }
                if selectedLogPID == nil {
                    selectedLogPID = daemonService.jobs.first?.pid
                }
            }
        }
    }

    @ViewBuilder
    private func daemonJobRow(_ job: LocalDaemonJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(job.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("PID \(job.pid) • \(job.name)")
                    .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                Spacer()
                Text(job.isRunning ? "RUNNING • \(job.uptimeFormatted)" : "STOPPED")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(job.isRunning ? Color.green.opacity(0.16) : Color.secondary.opacity(0.16))
                    .foregroundColor(job.isRunning ? .green : .secondary)
                    .cornerRadius(4)
            }

            if let lastLine = job.logs.last {
                Text(lastLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    selectedLogPID = (selectedLogPID == job.pid) ? nil : job.pid
                } label: {
                    Label(preferences.tr("Xem Log", "Logs"), systemImage: "text.alignleft")
                }
                .buttonStyle(.bordered)

                Button {
                    daemonService.restartJob(pid: job.pid, workspaceRoot: workspace.rootURL)
                    selectedLogPID = job.pid
                } label: {
                    Label(preferences.tr("Chạy lại", "Restart"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Spacer()

                if job.isRunning {
                    Button(role: .destructive) {
                        daemonService.stopJob(pid: job.pid)
                    } label: {
                        Label(preferences.tr("Dừng", "Kill"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}
