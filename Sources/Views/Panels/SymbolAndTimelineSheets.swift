import SwiftUI
import UIKit

// MARK: - 1. Symbol Outline Sheet (1-Tap Jump to Function / Class / Section)
public struct SymbolOutlineSheet: View {
    public let fileName: String
    public let symbols: [DocumentSymbolItem]
    public let palette: IDEColorPalette
    public var onSelectLine: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    public init(
        fileName: String,
        symbols: [DocumentSymbolItem],
        palette: IDEColorPalette,
        onSelectLine: @escaping (Int) -> Void
    ) {
        self.fileName = fileName
        self.symbols = symbols
        self.palette = palette
        self.onSelectLine = onSelectLine
    }

    private var filteredSymbols: [DocumentSymbolItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return symbols }
        return symbols.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q) }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm hàm, class, struct, heading...", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(9)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if filteredSymbols.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text(symbols.isEmpty ? "Chưa tìm thấy hàm hoặc class nào trong \(fileName)." : "Không có kết quả khớp từ khóa.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(filteredSymbols) { sym in
                        Button {
                            onSelectLine(sym.line)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: sym.systemIcon)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: palette.accent))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sym.name)
                                        .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Text(sym.detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(":\(sym.line)")
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Outline — \(fileName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 2. Local File Version Timeline Sheet (Offline Snapshot History & 1-Tap Restore)
public struct FileTimelineSheet: View {
    public let fileURL: URL
    public let currentContent: String
    @ObservedObject public var timelineService: FileTimelineAndArchiveService
    public var onRestoreContent: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        fileURL: URL,
        currentContent: String,
        timelineService: FileTimelineAndArchiveService,
        onRestoreContent: @escaping (String) -> Void
    ) {
        self.fileURL = fileURL
        self.currentContent = currentContent
        self.timelineService = timelineService
        self.onRestoreContent = onRestoreContent
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss • dd/MM/yyyy"
        return df
    }()

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Tự động lưu tối đa 20 mốc lịch sử cục bộ cho \(fileURL.lastPathComponent).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        timelineService.recordSnapshot(for: fileURL, content: currentContent, label: "Manual Checkpoint")
                    } label: {
                        Label("Tạo mốc ngay", systemImage: "plus.circle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground))

                if timelineService.activeFileSnapshots.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Chưa có mốc lịch sử nào cho file này.\nBấm \"Tạo mốc ngay\" hoặc sửa file để tự động lưu.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    List(timelineService.activeFileSnapshots) { snap in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(snap.label, systemImage: "clock")
                                    .font(.system(size: 12.5, weight: .bold))
                                Spacer()
                                Text(Self.dateFormatter.string(from: snap.timestamp))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Text("\(snap.lineCount) dòng • \(snap.content.count) ký tự")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text(String(snap.content.prefix(180)).replacingOccurrences(of: "\n", with: " ↵ "))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .lineLimit(2)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(6)

                            HStack {
                                Spacer()
                                Button {
                                    onRestoreContent(snap.content)
                                    dismiss()
                                } label: {
                                    Label("Khôi phục bản này", systemImage: "arrow.counterclockwise")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Lịch sử File — \(fileURL.lastPathComponent)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                timelineService.loadSnapshots(for: fileURL)
            }
        }
    }
}

// MARK: - 3. Interactive Theme Studio Sheet (Customize Every Code Color & App Surface)
public struct ThemeStudioEditorSheet: View {
    @ObservedObject public var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var draft: IDEColorPalette

    public init(preferences: EditorPreferences) {
        self.preferences = preferences
        var seed = preferences.activePalette
        if !seed.id.hasPrefix("studio-") {
            seed.id = "studio-\(UUID().uuidString.prefix(6))"
            seed.name = "\(seed.name) Custom"
        }
        self._draft = State(initialValue: seed)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Xem Trước Trực Tiếp Màu Code & Giao Diện") {
                    liveCodePreviewCard
                        .listRowInsets(EdgeInsets())
                }

                Section("Thông Tin Theme") {
                    TextField("Tên Theme", text: $draft.name)
                        .autocorrectionDisabled()
                    Toggle("Giao diện tối (Dark Mode)", isOn: $draft.isDark)
                }

                Section("Màu Nền & Khung Ứng Dụng (App Surfaces)") {
                    hexColorRow("Nền vùng Code (Editor)", hex: $draft.editorBackground)
                    hexColorRow("Nền Sidebar & Drawer", hex: $draft.sidebarBackground)
                    hexColorRow("Nền Thanh Header", hex: $draft.headerBackground)
                    hexColorRow("Dòng con trỏ hiện tại", hex: $draft.currentLineBackground)
                    hexColorRow("Vùng bôi đen (Selection)", hex: $draft.selectionBackground)
                    hexColorRow("Chữ mặc định (Foreground)", hex: $draft.foreground)
                    hexColorRow("Số dòng (Line Numbers)", hex: $draft.gutterForeground)
                    hexColorRow("Màu nhấn chủ đạo (Accent)", hex: $draft.accent)
                }

                Section("Màu Cú Pháp Code (Syntax Highlighting)") {
                    hexColorRow("Từ khóa (Keyword: if, return, struct)", hex: $draft.keyword)
                    hexColorRow("Tên hàm (Function / Method)", hex: $draft.function)
                    hexColorRow("Kiểu dữ liệu (Class / Struct / Type)", hex: $draft.typeName)
                    hexColorRow("Chuỗi ký tự (String)", hex: $draft.string)
                    hexColorRow("Số & Hằng số (Number / Constant)", hex: $draft.number)
                    hexColorRow("Biến & Tham số (Variable)", hex: $draft.variable)
                    hexColorRow("Thuộc tính (Property / Attribute)", hex: $draft.property)
                    hexColorRow("Thẻ HTML / JSX (Tag)", hex: $draft.tag)
                    hexColorRow("Toán tử (Operator)", hex: $draft.operatorToken)
                    hexColorRow("Chú thích (Comment)", hex: $draft.comment)
                }

                Section {
                    Button {
                        if let json = exportThemeJSON() {
                            UIPasteboard.general.string = json
                        }
                    } label: {
                        Label("Copy mã JSON của Theme vào Clipboard", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Theme Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu & Áp dụng") {
                        preferences.customAccentHex = ""
                        preferences.upsertCustomTheme(draft)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    @ViewBuilder
    private var liveCodePreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: draft.accent)).frame(width: 8, height: 8)
                Text(draft.name)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(Color(hex: draft.foreground))
                Spacer()
                Text("main.cpp")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: draft.gutterForeground))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: draft.headerBackground))

            VStack(alignment: .leading, spacing: 4) {
                codePreviewLine(num: "1", segments: [
                    ("// 3012 Theme Studio Live Preview", draft.comment)
                ], highlighted: false)
                codePreviewLine(num: "2", segments: [
                    ("struct ", draft.keyword),
                    ("Engine ", draft.typeName),
                    ("{", draft.foreground)
                ], highlighted: false)
                codePreviewLine(num: "3", segments: [
                    ("  int ", draft.keyword),
                    ("run", draft.function),
                    ("(", draft.foreground),
                    ("const ", draft.keyword),
                    ("std::string& ", draft.typeName),
                    ("target", draft.variable),
                    (") {", draft.foreground)
                ], highlighted: true)
                codePreviewLine(num: "4", segments: [
                    ("    auto ", draft.keyword),
                    ("port ", draft.property),
                    ("= ", draft.operatorToken),
                    ("5500", draft.number),
                    (";", draft.foreground)
                ], highlighted: false)
                codePreviewLine(num: "5", segments: [
                    ("    return ", draft.keyword),
                    ("\"http://localhost\"", draft.string),
                    (".size();", draft.function)
                ], highlighted: false)
                codePreviewLine(num: "6", segments: [
                    ("  }", draft.foreground)
                ], highlighted: false)
                codePreviewLine(num: "7", segments: [
                    ("};", draft.foreground)
                ], highlighted: false)
            }
            .padding(.vertical, 10)
            .background(Color(hex: draft.editorBackground))
        }
    }

    @ViewBuilder
    private func codePreviewLine(num: String, segments: [(String, String)], highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(num)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(Color(hex: draft.gutterForeground))
                .frame(width: 18, alignment: .trailing)

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Text(seg.0)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: seg.1))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(highlighted ? Color(hex: draft.currentLineBackground) : Color.clear)
    }

    @ViewBuilder
    private func hexColorRow(_ title: String, hex: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
            Spacer()
            Text(hex.wrappedValue.uppercased())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hex.wrappedValue) },
                    set: { newColor in hex.wrappedValue = newColor.toHexString() }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    private func exportThemeJSON() -> String? {
        guard let data = try? JSONEncoder().encode(draft) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 4. VS Code Select Language Mode Sheet (64 Languages + Auto-Detect)
public struct LanguageModePickerSheet: View {
    public let fileName: String
    public let autoDetectedLanguage: CodeLanguage
    public let currentOverride: CodeLanguage?
    public let palette: IDEColorPalette
    public var onSelectOverride: (CodeLanguage?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    public init(
        fileName: String,
        autoDetectedLanguage: CodeLanguage,
        currentOverride: CodeLanguage?,
        palette: IDEColorPalette,
        onSelectOverride: @escaping (CodeLanguage?) -> Void
    ) {
        self.fileName = fileName
        self.autoDetectedLanguage = autoDetectedLanguage
        self.currentOverride = currentOverride
        self.palette = palette
        self.onSelectOverride = onSelectOverride
    }

    private var filteredLanguages: [CodeLanguage] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return CodeLanguage.allCases }
        return CodeLanguage.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(q)
                || $0.shortBadgeName.localizedCaseInsensitiveContains(q)
                || $0.defaultExtension.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Tìm ngôn ngữ lập trình (C++, Rust, Python, TSX, SQL...)", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(9)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                List {
                    Section("Nhận diện thông minh (Auto-Detect)") {
                        Button {
                            onSelectOverride(nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                FileLanguageIconView(language: autoDetectedLanguage, size: 14)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tự động nhận diện — \(autoDetectedLanguage.rawValue)")
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Quét từ tên file (\(fileName)), đuôi mở rộng & nội dung shebang/cú pháp")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if currentOverride == nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: palette.accent))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section("Tất cả \(CodeLanguage.allCases.count) Ngôn ngữ hỗ trợ (\(filteredLanguages.count))") {
                        ForEach(filteredLanguages) { lang in
                            let isSelected = (currentOverride == lang)
                            Button {
                                onSelectOverride(lang)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    FileLanguageIconView(language: lang, size: 14)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lang.rawValue)
                                            .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(.primary)
                                        Text(".\(lang.defaultExtension) • \(lang.treeSitterLanguage != nil ? "Tree-sitter AST" : "Syntax Engine")")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color(hex: palette.accent))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Chọn Ngôn Ngữ — \(fileName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
