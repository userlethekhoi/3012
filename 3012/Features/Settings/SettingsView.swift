import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @AppStorage("catalog.channel") private var catalogChannel = "stable"
    @AppStorage("app.language") private var appLanguage = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Mode", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Picker("Language", selection: $appLanguage) {
                        Text("Follow System").tag("system")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Tiếng Việt").tag("vi")
                        Text(verbatim: "简体中文").tag("zh-Hans")
                    }
                }

                Section("Updates") {
                    Picker("Catalog Channel", selection: $catalogChannel) {
                        Text("Stable").tag("stable")
                        Text("Beta").tag("beta")
                    }
                    LabeledContent("Catalog Trust") { Text("Not Configured") }
                    LabeledContent("Background Downloads") { Text("Available") }
                }

                Section("3012") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    )
                    LabeledContent("Author") { Text(verbatim: "Le The Khoi") }
                    if let telegramURL = URL(string: "https://t.me/coder_009") {
                        Link(destination: telegramURL) {
                            LabeledContent("Telegram", value: "@coder_009")
                        }
                    }
                    Text("3012 does not include advertising, telemetry, or an AI runtime.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
