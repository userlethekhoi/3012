import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @AppStorage("catalog.channel") private var catalogChannel = "stable"

    var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện") {
                    Picker("Chế độ", selection: $appearanceMode) {
                        Text("Hệ thống").tag("system")
                        Text("Sáng").tag("light")
                        Text("Tối").tag("dark")
                    }
                }

                Section("Cập nhật") {
                    Picker("Kênh catalog", selection: $catalogChannel) {
                        Text("Ổn định").tag("stable")
                        Text("Thử nghiệm").tag("beta")
                    }
                    LabeledContent("Xác minh catalog", value: "Chưa cấu hình")
                    LabeledContent("Tải nền", value: "Đang phát triển")
                }

                Section("3012") {
                    LabeledContent("Phiên bản", value: "0.1.0-dev")
                    if let repositoryURL = URL(string: "https://github.com/userlethekhoi/3012") {
                        Link("Mã nguồn", destination: repositoryURL)
                    }
                    Text("3012 không tích hợp AI runtime, quảng cáo hoặc telemetry trong baseline hiện tại.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
        }
    }
}
}
