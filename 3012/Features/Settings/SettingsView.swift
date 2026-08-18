import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @AppStorage("appearance.interfaceScale") private var interfaceScaleRawValue = AppInterfaceScale.standard.rawValue
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
                    interfaceScaleControl
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

    private var interfaceScale: AppInterfaceScale {
        AppInterfaceScale(rawValue: interfaceScaleRawValue) ?? .standard
    }

    private var interfaceScaleControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interface Size")
                Spacer()
                Text(verbatim: "\(interfaceScale.percentage)%")
                    .font(.technicalValue)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    interfaceScaleRawValue = max(
                        AppInterfaceScale.minimum.rawValue,
                        interfaceScaleRawValue - 1
                    )
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.borderless)
                .disabled(interfaceScale == .minimum)
                .accessibilityLabel("Smaller")

                Slider(
                    value: Binding(
                        get: { Double(interfaceScale.rawValue) },
                        set: { interfaceScaleRawValue = Int($0.rounded()) }
                    ),
                    in: Double(AppInterfaceScale.minimum.rawValue)...Double(AppInterfaceScale.maximum.rawValue),
                    step: 1
                )
                .accessibilityLabel("Interface Size")
                .accessibilityValue(Text(verbatim: "\(interfaceScale.percentage)%"))

                Button {
                    interfaceScaleRawValue = min(
                        AppInterfaceScale.maximum.rawValue,
                        interfaceScaleRawValue + 1
                    )
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.borderless)
                .disabled(interfaceScale == .maximum)
                .accessibilityLabel("Larger")
            }

            HStack {
                Text("Adjust text and controls across 3012.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if interfaceScale != .standard {
                    Button("Reset to 100%") {
                        interfaceScaleRawValue = AppInterfaceScale.standard.rawValue
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
