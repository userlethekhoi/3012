import SwiftUI
import UIKit

public struct LiveServerShareSheet: View {
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var copiedLinkNotice: String? = nil

    public init(
        liveServer: LiveServerService,
        workspace: WorkspaceManager,
        preferences: EditorPreferences
    ) {
        self.liveServer = liveServer
        self.workspace = workspace
        self.preferences = preferences
    }

    public var body: some View {
        CompatibleNavigationContainer {
            Form {
                // Status + Kill Switch
                Section {
                    Toggle(isOn: $liveServer.isShareLinkEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preferences.tr("Cho phép người khác xem Preview", "Allow Others to View Live Preview"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(liveServer.isShareLinkEnabled
                                 ? preferences.tr("ĐANG MỞ — Ai có link (& PIN nếu đặt) đều xem được.", "LIVE — Shared link is active.")
                                 : preferences.tr("ĐANG TẮT — Mọi IP ngoài bị chặn (403 Forbidden).", "OFF — External viewers blocked immediately (403)."))
                                .font(.caption)
                                .foregroundColor(liveServer.isShareLinkEnabled ? .green : .secondary)
                        }
                    }
                    .tint(.green)

                    if liveServer.isShareLinkEnabled {
                        HStack {
                            Label(preferences.tr("Khách đang xem", "Active Viewers"), systemImage: "person.2.fill")
                            Spacer()
                            Text("\(liveServer.sharedViewerCount)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.18))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }
                } header: {
                    Text("Live Server :\(liveServer.port)")
                }

                // Local Wi-Fi LAN Share Link + QR Code
                if liveServer.isShareLinkEnabled {
                    Section(preferences.tr("Link Wi-Fi cùng mạng (Có cổng :\(liveServer.port))", "Same-WiFi Share Link (with Port :\(liveServer.port))")) {
                        if let lanURL = liveServer.shareableLANURLString {
                            HStack {
                                Text(lanURL)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .textSelection(.enabled)
                                Spacer()
                                IDEPillButton(prominence: .secondary, tint: .blue) {
                                    UIPasteboard.general.string = lanURL
                                    copiedLinkNotice = preferences.tr("Đã copy link \(lanURL)", "Copied \(lanURL)")
                                } label: {
                                    Text(preferences.tr("Copy", "Copy"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }

                            if let qr = LiveServerService.generateQRCodeImage(from: lanURL) {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 6) {
                                        Image(uiImage: qr)
                                            .interpolation(.none)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 150, height: 150)
                                            .padding(8)
                                            .background(Color.white)
                                            .cornerRadius(12)
                                        Text(preferences.tr("Quét mã QR từ điện thoại khác", "Scan QR from another device"))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                        } else {
                            HStack {
                                Text(preferences.tr("Không tìm thấy IP Wi-Fi (hãy bật Wi-Fi)", "No Wi-Fi IP detected"))
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(preferences.tr("Quét lại", "Refresh")) {
                                    liveServer.refreshLANAddress()
                                }
                            }
                        }
                    }

                    // Security PIN Gate
                    Section {
                        TextField(preferences.tr("Mã PIN 4 số (để trống = không khóa)", "Optional 4-Digit PIN"), text: $liveServer.sharePinCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    } header: {
                        Text(preferences.tr("Bảo mật mã PIN khi chia sẻ", "Optional Viewer PIN Lock"))
                    } footer: {
                        Text(preferences.tr(
                            "Bạn luôn xem được trực tiếp trên localhost:\(liveServer.port) mà không cần nhập PIN. Tắt công tắc ở trên bất cứ lúc nào để khóa link ngay lập tức.",
                            "Local 127.0.0.1 owner preview never requires a PIN. Flipping the switch OFF revokes all viewers immediately."
                        ))
                    }

                    if let copiedLinkNotice {
                        Section {
                            Text(copiedLinkNotice)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    Section {
                        Text(preferences.tr(
                            "Chỉ riêng bạn xem được tại http://127.0.0.1:\(liveServer.port). Bật công tắc phía trên để lấy Link kèm Port (hoặc QR Code) gửi cho người khác xem bản dựng web của bạn — khi tắt đi mọi kết nối ngoài sẽ bị ngắt ngay.",
                            "Currently restricted to local 127.0.0.1:\(liveServer.port). Turn sharing ON above to generate a shareable link with port and QR code."
                        ))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(preferences.tr("Chia sẻ Live Server", "Share Live Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
            .onAppear {
                liveServer.refreshLANAddress()
                if !liveServer.isRunning {
                    liveServer.start(serving: workspace.rootURL, preferredPort: 5500, keepAliveInBackground: preferences.keepServerInBackground)
                }
            }
        }
    }
}
