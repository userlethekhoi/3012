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
                        Text("System").tag("system")
                        Text("English").tag("en")
                        Text("Tiếng Việt").tag("vi")
                        Text("简体中文").tag("zh-Hans")
                    }
                }

                Section("Updates") {
                    Picker("Catalog Channel", selection: $catalogChannel) {
                        Text("Stable").tag("stable")
                        Text("Beta").tag("beta")
                    }
                    LabeledContent("Catalog Trust", value: "Not Configured")
                    LabeledContent("Background Downloads", value: "Available")
                }

                Section("3012") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
                    )
                    if let repositoryURL = URL(string: "https://github.com/userlethekhoi/3012") {
                        Link("Source Code", destination: repositoryURL)
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
