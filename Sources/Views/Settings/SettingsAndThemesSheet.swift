import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct SettingsAndThemesSheet: View {
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var runner: CodeRunnerService
    @Environment(\.dismiss) private var dismiss

    @State private var showJSONImporter: Bool = false
    @State private var copiedBanner: Bool = false

    public init(
        preferences: EditorPreferences,
        liveServer: LiveServerService,
        runner: CodeRunnerService
    ) {
        self.preferences = preferences
        self.liveServer = liveServer
        self.runner = runner
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Giao diện & Theme Chuẩn VS Code") {
                    Picker("Theme màu", selection: $preferences.selectedThemeID) {
                        ForEach(preferences.allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label("Import File Theme .json từ VS Code", systemImage: "square.and.arrow.down")
                    }
                }

                Section("Font Chữ & Hiển Thị Vùng Code") {
                    Picker("Font chữ", selection: $preferences.fontName) {
                        ForEach(EditorPreferences.availableFonts, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Cỡ chữ (Hỗ trợ Pinch-to-Zoom)")
                            Spacer()
                            Text("\(Int(preferences.fontSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.fontSize, in: 10...28, step: 0.5)
                    }

                    Picker("Độ rộng phím Tab", selection: $preferences.tabWidth) {
                        Text("2 Spaces").tag(2)
                        Text("4 Spaces").tag(4)
                    }

                    Toggle("Tự xuống dòng (Word Wrap)", isOn: $preferences.wordWrap)
                    Toggle("Hiện số dòng (Line Numbers)", isOn: $preferences.showLineNumbers)
                }

                Section("Live Server (:5500) & Xem Trên Safari") {
                    Toggle("Giữ localhost:5500 chạy ngầm khi mở Safari", isOn: $preferences.keepServerInBackground)
                        .onChange(of: preferences.keepServerInBackground) { _, enabled in
                            liveServer.updateBackgroundKeepAlive(enabled: enabled)
                        }

                    Text("Khi bật tuỳ chọn này, bạn có thể viết HTML/CSS/JS trong 3012 rồi chuyển sang ứng dụng Safari mở http://localhost:\(liveServer.port) mà iOS không đóng băng máy chủ.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("Zero-Config Compiler & Kết nối VPS Riêng") {
                    TextField("URL Runner trên VPS (Tuỳ chọn)", text: $runner.vpsEndpointURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("VPS Bearer Token (Tuỳ chọn)", text: $runner.vpsAuthToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button {
                        UIPasteboard.general.string = CodeRunnerService.vpsBootstrapCommand
                        copiedBanner = true
                    } label: {
                        Label(
                            copiedBanner ? "Đã copy lệnh cài Toolchain VPS!" : "Copy lệnh 1-Click cài C++/Python/Node cho VPS",
                            systemImage: copiedBanner ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                    }

                    Text("Mặc định nếu để trống VPS, 3012 vẫn tự biên dịch & chạy ngay C, C++20, Objective-C, Python, Swift, JS bằng Zero-Config Sandbox mà không cần cài MinGW hay sửa PATH.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt 3012 IDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url),
                       let imported = VSCodeThemeImporter.parse(jsonData: data, fallbackName: url.deletingPathExtension().lastPathComponent) {
                        preferences.customThemes.append(imported)
                        preferences.selectedThemeID = imported.id
                    }
                }
            }
        }
    }
}
