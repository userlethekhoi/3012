import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct SettingsAndThemesSheet: View {
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var runner: CodeRunnerService
    @Environment(\.dismiss) private var dismiss

    @State private var showJSONImporter: Bool = false
    @State private var showThemeStudio: Bool = false
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
                // MARK: - 0. 3012 Developer Brand Identity Header
                Section {
                    HStack(spacing: 14) {
                        IDECodeMarkVector(size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .center, spacing: 10) {
                                Brand3012WordmarkView(height: 19, inkColor: .primary)
                                Text("v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "3.5.0"))
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.16))
                                    .foregroundColor(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255))
                                    .cornerRadius(4)
                            }
                            Text("Native Code Editor & Remote Workstation")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Runestone 120Hz • 48 Tree-sitter AST • SSH/SFTP")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - 1. Code Intelligence, Auto-Format & Inline Diagnostics Toggles
                Section {
                    Toggle("Bật gợi ý code thông minh như VS Code (IntelliSense)", isOn: $preferences.enableCodeCompletion)
                    Toggle("Bật tô sáng & báo lỗi trực tiếp (Inline Diagnostics)", isOn: $preferences.enableLiveDiagnostics)
                    Toggle("Tự động Format Code theo ngôn ngữ khi Lưu / Chạy", isOn: $preferences.formatOnSave)
                    Toggle("Tự động thụt lề thông minh khi nhấn Enter", isOn: $preferences.autoIndentOnReturn)
                    Toggle("Tự động lưu & ghi lịch sử phiên bản (Auto-Save)", isOn: $preferences.enableAutoSave)
                    Toggle("Hiện thanh đường dẫn & danh sách hàm (Breadcrumbs)", isOn: $preferences.showBreadcrumbs)
                    Toggle("Cho phép gập/mở khối code (Code Folding)", isOn: $preferences.enableCodeFolding)
                } header: {
                    Text("Gợi Ý Code Thông Minh, Format & Báo Lỗi Trực Tiếp")
                } footer: {
                    Text("Hỗ trợ nhận diện 64 ngôn ngữ lập trình, gợi ý Fuzzy/CamelCase, gợi ý thành phần sau dấu chấm (./::/->), gõ tắt Emmet HTML và tự động căn chỉnh định dạng code chuẩn theo từng ngôn ngữ.")
                }

                // MARK: - 2. Full Syntax Color & App Theme Gallery + Theme Studio
                Section("Bộ Sưu Tập Theme Màu Code & Giao Diện App") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(preferences.allThemes) { theme in
                                themePreviewCard(theme)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Picker("Chọn nhanh Theme", selection: $preferences.selectedThemeID) {
                        ForEach(preferences.allThemes) { theme in
                            Text(theme.name).tag(theme.id)
                        }
                    }

                    // App Accent Swatch Bar
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Màu nhấn ứng dụng (App Accent)")
                                .font(.subheadline)
                            Spacer()
                            Text(preferences.customAccentHex.isEmpty ? "Theo Theme" : preferences.customAccentHex)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(EditorPreferences.appAccentPresets, id: \.name) { preset in
                                    let isSelected = (preferences.customAccentHex == preset.hex)
                                    Button {
                                        preferences.customAccentHex = preset.hex
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(preset.hex.isEmpty ? Color(hex: preferences.activePalette.accent) : Color(hex: preset.hex))
                                                .frame(width: 14, height: 14)
                                            Text(preset.name)
                                                .font(.system(size: 11.5, weight: isSelected ? .bold : .regular))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        showThemeStudio = true
                    } label: {
                        Label("Mở Theme Studio (Tự chỉnh màu Code & Nền App)", systemImage: "slider.horizontal.below.square.filled.and.square")
                            .fontWeight(.semibold)
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label("Import File Theme .json từ VS Code", systemImage: "square.and.arrow.down")
                    }
                }

                // MARK: - 3. Font & Editor Layout
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

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Giãn dòng (Line Height)")
                            Spacer()
                            Text(String(format: "%.2fx", preferences.lineHeightMultiplier))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $preferences.lineHeightMultiplier, in: 1.0...1.65, step: 0.05)
                    }

                    Picker("Độ rộng phím Tab", selection: $preferences.tabWidth) {
                        Text("2 Spaces").tag(2)
                        Text("4 Spaces").tag(4)
                    }

                    Toggle("Tự xuống dòng (Word Wrap)", isOn: $preferences.wordWrap)
                    Toggle("Hiện số dòng (Line Numbers)", isOn: $preferences.showLineNumbers)
                    Toggle("Hiện ký tự khoảng trắng ẩn", isOn: $preferences.showInvisibleCharacters)
                }

                // MARK: - 4. Live Server & Safari
                Section("Live Server (:5500) & Xem Trên Safari") {
                    Toggle("Giữ localhost:5500 chạy ngầm khi mở Safari", isOn: $preferences.keepServerInBackground)
                        .onChange(of: preferences.keepServerInBackground) { _, enabled in
                            liveServer.updateBackgroundKeepAlive(enabled: enabled)
                        }

                    Text("Khi bật tùy chọn này, bạn có thể viết HTML/CSS/JS trong 3012 rồi chuyển sang Safari mở http://localhost:\(liveServer.port) mà iOS không đóng băng máy chủ.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                // MARK: - 5. Zero-Config Compiler & VPS
                Section("Zero-Config Compiler & Kết nối VPS Riêng") {
                    TextField("URL Runner trên VPS (Tùy chọn)", text: $runner.vpsEndpointURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("VPS Bearer Token (Tùy chọn)", text: $runner.vpsAuthToken)
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

                // MARK: - 6. Hardware Keyboard Shortcuts Reference
                Section("Phím Tắt Bàn Phím Bluetooth / Magic Keyboard") {
                    shortcutRow("Cmd + S", "Lưu file & tự động Format (nếu bật)")
                    shortcutRow("Cmd + Shift + F", "Format Code theo ngôn ngữ hiện tại")
                    shortcutRow("Cmd + R", "Chạy file hiện tại (Smart Run 30+ ngôn ngữ)")
                    shortcutRow("Cmd + P", "Mở Command Palette & tìm nhanh file")
                    shortcutRow("Cmd + /", "Bật/tắt chú thích dòng (Toggle Comment)")
                    shortcutRow("Cmd + B", "Đóng/mở thanh Explorer bên trái")
                    shortcutRow("Cmd + I", "Đóng/mở khung Coding Agent")
                    shortcutRow("Cmd + J", "Đóng/mở bảng Terminal / Problems / Web F12")
                }
            }
            .navigationTitle("Cài đặt 3012 IDE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .sheet(isPresented: $showThemeStudio) {
                ThemeStudioEditorSheet(preferences: preferences)
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
                        preferences.upsertCustomTheme(imported)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func themePreviewCard(_ theme: IDEColorPalette) -> some View {
        let isSelected = (preferences.selectedThemeID == theme.id)
        Button {
            preferences.selectedThemeID = theme.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: theme.keyword)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.function)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.string)).frame(width: 8, height: 8)
                    Circle().fill(Color(hex: theme.number)).frame(width: 8, height: 8)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: theme.accent))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("fn ")
                            .foregroundColor(Color(hex: theme.keyword))
                        Text("main")
                            .foregroundColor(Color(hex: theme.function))
                        Text("()")
                            .foregroundColor(Color(hex: theme.foreground))
                    }
                    Text("\"3012 IDE\"")
                        .foregroundColor(Color(hex: theme.string))
                }
                .font(.system(size: 10.5, design: .monospaced))

                Text(theme.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: theme.foreground))
                    .lineLimit(1)
            }
            .padding(9)
            .frame(width: 132, alignment: .leading)
            .background(Color(hex: theme.editorBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color(hex: theme.accent) : Color.secondary.opacity(0.28), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(desc)
                .font(.system(size: 13))
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(5)
        }
    }
}
