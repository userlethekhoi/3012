import SwiftUI
import UIKit

/// Generic AI provider manager: users add any number of providers (online or offline),
/// store keys in the Keychain and let 3012 track each provider's newest model automatically.
public struct AIProviderSettingsSheet: View {
    @ObservedObject var aiService: AIAgentService
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfileID: UUID?

    public init(aiService: AIAgentService) {
        self.aiService = aiService
    }

    public var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    if aiService.profiles.isEmpty {
                        Text("Chưa có cấu hình AI nào. Thêm nhà cung cấp bên dưới — 3012 sẽ tự tải danh sách model mới nhất trực tiếp từ nhà cung cấp đó.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    ForEach(aiService.profiles) { profile in
                        profileRow(profile)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { aiService.profiles[$0].id }
                        ids.forEach { aiService.deleteProfile(id: $0) }
                    }
                } header: {
                    Text("Cấu hình AI của bạn")
                } footer: {
                    if !aiService.profiles.isEmpty {
                        Text("Chạm để chọn dùng • Chạm biểu tượng (i) để chỉnh sửa • Vuốt trái để xoá.")
                    }
                }

                Section("Thêm nhà cung cấp — Online") {
                    ForEach(AIProviderPreset.all.filter { !$0.isLocal }) { preset in
                        presetButton(preset)
                    }
                }

                Section {
                    ForEach(AIProviderPreset.all.filter { $0.isLocal }) { preset in
                        presetButton(preset)
                    }
                } header: {
                    Text("Thêm nhà cung cấp — Offline")
                } footer: {
                    Text("Apple On-Device chạy hoàn toàn trên iPhone. Ollama / LM Studio chạy trên máy tính hoặc server cùng mạng Wi-Fi, không cần Internet.")
                }

                Section("Quyền riêng tư") {
                    Text("API Key chỉ lưu trong iOS Keychain trên máy này. 3012 không có máy chủ trung gian: code và câu hỏi được gửi trực tiếp từ iPhone tới nhà cung cấp bạn chọn (hoặc xử lý ngay trên máy với cấu hình Offline).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cấu hình AI Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .compatibleNavigationDestination(
                isPresented: Binding(
                    get: { editingProfileID != nil },
                    set: { if !$0 { editingProfileID = nil } }
                )
            ) {
                if let profileID = editingProfileID {
                    AIProviderProfileEditor(aiService: aiService, profileID: profileID)
                }
            }
        }
    }

    private func profileRow(_ profile: AIProviderProfile) -> some View {
        let isActive = aiService.activeProfile?.id == profile.id
        let model = profile.resolvedModelID
        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .secondary)
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(profile.selectionMode.title) • \(model.isEmpty ? "chưa chọn model" : model)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                editingProfileID = profile.id
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17))
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            aiService.setActiveProfile(profile.id)
        }
    }

    private func presetButton(_ preset: AIProviderPreset) -> some View {
        Button {
            editingProfileID = aiService.addProfile(preset: preset)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: preset.symbol)
                    .frame(width: 22)
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .foregroundColor(.primary)
                    Text(preset.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

struct AIProviderProfileEditor: View {
    @ObservedObject var aiService: AIAgentService
    let profileID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var apiKeyInput: String = ""
    @State private var revealKey: Bool = false
    @State private var modelSearch: String = ""
    @State private var showAllModels: Bool = false
    @State private var showCurlImportSheet: Bool = false
    @State private var curlImportText: String = ""
    @State private var curlImportAutoPlaceholders: Bool = true
    @State private var curlImportError: String? = nil
    @State private var showCustomPostInspector: Bool = false
    @State private var templateNotice: String? = nil

    private let templateTokens: [String] = [
        "{{model}}",
        "{{messages}}",
        "{{responses_input}}",
        "{{gemini_contents}}",
        "{{prompt}}",
        "{{system}}",
        "{{stream}}",
        "{{api_key}}"
    ]

    var body: some View {
        Form {
            if let binding = profileBinding {
                editorContent(binding)
            } else {
                Text("Cấu hình này đã bị xoá.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(aiService.profile(id: profileID)?.name ?? "Cấu hình")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let profile = aiService.profile(id: profileID) {
                apiKeyInput = aiService.apiKey(for: profile)
            }
        }
        .onChange(of: apiKeyInput) { newValue in
            aiService.setAPIKey(newValue, for: profileID)
        }
        .task {
            guard let profile = aiService.profile(id: profileID),
                  profile.format != .customPost,
                  profile.cachedModels.isEmpty else { return }
            if !profile.requiresAPIKey || !aiService.apiKey(for: profile).isEmpty {
                await aiService.refreshModels(for: profileID, announceChanges: false)
            }
        }
        .sheet(isPresented: $showCurlImportSheet) {
            curlImportModal
        }
        .sheet(isPresented: $showCustomPostInspector) {
            if let rawProfile = aiService.profile(id: profileID) {
                let hydrated = aiService.hydratedProfile(rawProfile)
                let cfg = hydrated.customPostConfig ?? AICustomPostConfig(endpointURL: hydrated.baseURL)
                AICustomPostInspectorSheet(
                    config: cfg,
                    apiKey: apiKeyInput,
                    model: hydrated.resolvedModelID,
                    temperature: hydrated.useCustomTemperature ? hydrated.temperature : nil,
                    maxOutputTokens: hydrated.maxOutputTokens,
                    autoRunOnAppear: true
                )
            }
        }
    }

    /// Binds directly to the service so background model refreshes are never overwritten by a stale copy.
    private var profileBinding: Binding<AIProviderProfile>? {
        guard let snapshot = aiService.profile(id: profileID) else { return nil }
        return Binding(
            get: { aiService.profile(id: profileID) ?? snapshot },
            set: { aiService.updateProfile($0) }
        )
    }

    private func formatBinding(_ p: Binding<AIProviderProfile>) -> Binding<AIAPIFormat> {
        Binding(
            get: { p.wrappedValue.format },
            set: { newFormat in
                var updated = p.wrappedValue
                updated.format = newFormat
                if newFormat == .customPost {
                    if updated.customPostConfig == nil {
                        updated.customPostConfig = AICustomPostConfig(endpointURL: updated.baseURL)
                    }
                    if updated.fixedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updated.selectionMode = .fixed
                    }
                }
                p.wrappedValue = updated
            }
        )
    }

    private func customPostConfigBinding(_ p: Binding<AIProviderProfile>) -> Binding<AICustomPostConfig> {
        Binding(
            get: { p.wrappedValue.customPostConfig ?? AICustomPostConfig(endpointURL: p.wrappedValue.baseURL) },
            set: { newCfg in
                var updated = p.wrappedValue
                updated.customPostConfig = newCfg
                let cleanURL = newCfg.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanURL.isEmpty {
                    updated.baseURL = cleanURL
                }
                p.wrappedValue = updated
            }
        )
    }

    private func headerStringBinding(
        _ cfg: Binding<AICustomPostConfig>,
        id: UUID,
        keyPath: WritableKeyPath<AICustomHeaderItem, String>
    ) -> Binding<String> {
        Binding(
            get: { cfg.wrappedValue.headers.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { newValue in
                var copy = cfg.wrappedValue
                if let idx = copy.headers.firstIndex(where: { $0.id == id }) {
                    copy.headers[idx][keyPath: keyPath] = newValue
                    cfg.wrappedValue = copy
                }
            }
        )
    }

    private func headerBoolBinding(
        _ cfg: Binding<AICustomPostConfig>,
        id: UUID,
        keyPath: WritableKeyPath<AICustomHeaderItem, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { cfg.wrappedValue.headers.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { newValue in
                var copy = cfg.wrappedValue
                if let idx = copy.headers.firstIndex(where: { $0.id == id }) {
                    copy.headers[idx][keyPath: keyPath] = newValue
                    cfg.wrappedValue = copy
                }
            }
        )
    }

    @ViewBuilder
    private func editorContent(_ p: Binding<AIProviderProfile>) -> some View {
        let profile = p.wrappedValue
        let isApple = profile.format == .appleOnDevice
        let isCustomPost = profile.format == .customPost

        Section("Kết nối") {
            TextField("Tên hiển thị", text: p.name)

            if isApple {
                let status = AIProviderClient.appleOnDeviceStatus()
                Label(status.detail, systemImage: status.available ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundColor(status.available ? .green : .orange)
            } else {
                if !isCustomPost {
                    TextField("Base URL", text: p.baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 13, design: .monospaced))
                }

                Picker("Định dạng API", selection: formatBinding(p)) {
                    ForEach(AIAPIFormat.allCases.filter { $0 != .appleOnDevice }) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                HStack {
                    Group {
                        if revealKey {
                            TextField(
                                isCustomPost ? "API Key (biến {{api_key}}, tùy chọn)" : (profile.requiresAPIKey ? "API Key" : "API Key (không bắt buộc)"),
                                text: $apiKeyInput
                            )
                        } else {
                            SecureField(
                                isCustomPost ? "API Key (biến {{api_key}}, tùy chọn)" : (profile.requiresAPIKey ? "API Key" : "API Key (không bắt buộc)"),
                                text: $apiKeyInput
                            )
                        }
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13, design: .monospaced))

                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        if isCustomPost {
            customPostSections(p)
        }

        if !isApple && !isCustomPost {
            modelManagementSections(p, profile: profile)
        }

        if !isApple {
            if isCustomPost {
                Section {
                    DisclosureGroup("Tuỳ chọn lấy danh sách model (/models)") {
                        modelControlsOnly(p, profile: profile)
                    }
                }
            }

            Section("Nâng cao") {
                Toggle("Tuỳ chỉnh temperature", isOn: p.useCustomTemperature)
                if profile.useCustomTemperature {
                    HStack {
                        Slider(value: p.temperature, in: 0...2, step: 0.1)
                        Text(String(format: "%.1f", profile.temperature))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 32)
                    }
                }
                Stepper("Max output tokens: \(profile.maxOutputTokens)", value: p.maxOutputTokens, in: 1024...128_000, step: 1024)
            }
        }

        Section {
            IDEActionButton(prominence: .prominent, tint: .blue, fullWidth: true) {
                aiService.setActiveProfile(profileID)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text("Dùng cấu hình này")
                }
            }
            .padding(.vertical, 2)

            IDEActionButton(prominence: .destructive, tint: .red, fullWidth: true, compact: true) {
                aiService.deleteProfile(id: profileID)
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Xoá cấu hình")
                }
            }
        }
    }

    @ViewBuilder
    private func customPostSections(_ p: Binding<AIProviderProfile>) -> some View {
        let cfg = customPostConfigBinding(p)

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Endpoint URL (POST)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                TextField("https://api.example.com/v1/chat/completions", text: cfg.endpointURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 12.5, design: .monospaced))
            }
            .padding(.vertical, 2)

            HStack(spacing: 8) {
                IDEActionButton(prominence: .secondary, tint: .blue, fullWidth: true, compact: true) {
                    curlImportError = nil
                    showCurlImportSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.doc")
                        Text("Import cURL / HTTP")
                    }
                }

                IDEActionButton(prominence: .prominent, tint: .green, fullWidth: true, compact: true) {
                    showCustomPostInspector = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                        Text("Test & Inspect")
                    }
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Custom POST Endpoint")
        } footer: {
            Text("Tự cấu hình trực tiếp request POST của bạn (URL, Header, Body JSON). 3012 chỉ gửi đúng thông tin bạn cấu hình và dùng User-Agent trung thực, không giả mạo ứng dụng khác.")
        }

        Section {
            ForEach(cfg.wrappedValue.headers) { header in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: headerBoolBinding(cfg, id: header.id, keyPath: \.isEnabled))
                            .labelsHidden()
                        TextField("Header Name (vd: Authorization)", text: headerStringBinding(cfg, id: header.id, keyPath: \.key))
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            var copy = cfg.wrappedValue
                            if let idx = copy.headers.firstIndex(where: { $0.id == header.id }) {
                                copy.headers[idx].isSecret.toggle()
                                cfg.wrappedValue = copy
                            }
                        } label: {
                            Image(systemName: header.isSecret ? "lock.fill" : "lock.open")
                                .font(.system(size: 13))
                                .foregroundColor(header.isSecret ? .green : .secondary)
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            var copy = cfg.wrappedValue
                            copy.headers.removeAll { $0.id == header.id }
                            cfg.wrappedValue = copy
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }

                    if header.isSecret {
                        SecureField("Secret Value (lưu trong Keychain)", text: headerStringBinding(cfg, id: header.id, keyPath: \.value))
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        TextField("Value (hỗ trợ {{api_key}})", text: headerStringBinding(cfg, id: header.id, keyPath: \.value))
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
                .padding(.vertical, 3)
            }

            HStack(spacing: 8) {
                IDEPillButton(prominence: .secondary, tint: .blue) {
                    var copy = cfg.wrappedValue
                    copy.headers.append(AICustomHeaderItem(key: "X-Custom-Header", value: "", isSecret: false, isEnabled: true))
                    cfg.wrappedValue = copy
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Thêm Header")
                    }
                }

                Spacer()

                if cfg.wrappedValue.headers.contains(where: { $0.isSecret }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                        Text("Secret lưu Keychain")
                    }
                    .font(.caption2)
                    .foregroundColor(.green)
                }
            }
        } header: {
            Text("Headers HTTP")
        }

        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    IDEPillButton(prominence: .prominent, tint: .blue) {
                        var copy = cfg.wrappedValue
                        var detected = ""
                        copy.bodyTemplate = AICurlAndRawRequestParser.injectTemplatePlaceholders(
                            in: copy.bodyTemplate,
                            detectedModel: &detected
                        )
                        if !detected.isEmpty && copy.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            copy.defaultModel = detected
                        }
                        cfg.wrappedValue = copy
                        if !detected.isEmpty && p.wrappedValue.fixedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            var updated = p.wrappedValue
                            updated.fixedModelID = detected
                            updated.selectionMode = .fixed
                            p.wrappedValue = updated
                        }
                        templateNotice = "Đã tự gắn biến {{...}} vào JSON Body."
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "curlybraces")
                            Text("Tự gắn biến {{...}}")
                        }
                    }

                    ForEach(templateTokens, id: \.self) { token in
                        IDEPillButton(prominence: .secondary, tint: .accentColor) {
                            UIPasteboard.general.string = token
                            templateNotice = "Đã copy \(token) — chạm vào Body để dán."
                        } label: {
                            Text(token)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let notice = templateNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            TextEditor(text: cfg.bodyTemplate)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: 160)
                .padding(4)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.75)
                )

            HStack {
                IDEPillButton(prominence: .secondary, tint: .secondary) {
                    var copy = cfg.wrappedValue
                    copy.bodyTemplate = AICustomPostConfig.defaultBodyTemplate
                    cfg.wrappedValue = copy
                    templateNotice = "Đã khôi phục Body JSON mặc định."
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Mẫu mặc định")
                    }
                }
                Spacer()
            }
        } header: {
            Text("Body JSON Template")
        } footer: {
            Text("Chạm 'Tự gắn biến' để tự đổi model/messages/input/contents/stream thành placeholder động, hoặc chạm từng biến để copy.")
        }

        Section {
            TextField("Model ID mặc định (khi trống)", text: manualModelBinding(p))
                .font(.system(size: 13, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            TextField("Default Model fallback", text: cfg.defaultModel)
                .font(.system(size: 12.5, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Toggle("Server-Sent Events (SSE Streaming)", isOn: cfg.useSSEResponse)
            Toggle("Cho phép gửi dù chưa điền Model ID", isOn: cfg.allowEmptyModel)

            VStack(alignment: .leading, spacing: 4) {
                Text("Stream Delta Path")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("choices.0.delta.content", text: cfg.streamDeltaPath)
                    .font(.system(size: 12.5, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Fallback Delta Path")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("delta", text: cfg.streamEventTextFallback)
                    .font(.system(size: 12.5, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Non-stream Response Path")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("choices.0.message.content", text: cfg.responsePath)
                    .font(.system(size: 12.5, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Phân tích Response & Streaming")
        } footer: {
            Text("Đường dẫn dot-path ngăn cách bằng dấu chấm, ví dụ: choices.0.delta.content, output_text, candidates.0.content.parts.0.text, hoặc content.0.text.")
        }
    }

    @ViewBuilder
    private func modelManagementSections(_ p: Binding<AIProviderProfile>, profile: AIProviderProfile) -> some View {
        Section {
            modelControlsOnly(p, profile: profile)
        } header: {
            Text("Model")
        } footer: {
            Text("Mới nhất: 3012 tự tải danh sách model trực tiếp từ nhà cung cấp (mỗi 6 giờ hoặc khi bạn bấm kiểm tra) và luôn dùng model mới nhất — khi nhà cung cấp ra model mới, app tự chuyển sang mà không cần cập nhật app. Cố định: luôn dùng đúng model bạn chọn.")
        }

        Section {
            TextField("Tìm model...", text: $modelSearch)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            TextField("Hoặc nhập tay model ID", text: manualModelBinding(p))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 13, design: .monospaced))

            Toggle("Hiện cả model không phải chat", isOn: $showAllModels)

            let models = visibleModels(profile)
            if models.isEmpty {
                Text(profile.cachedModels.isEmpty ? "Chưa có danh sách — nhập API Key rồi bấm kiểm tra model." : "Không có model nào khớp bộ lọc.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(models.prefix(200)) { model in
                Button {
                    aiService.selectFixedModel(model.id, for: profileID)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.id)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundColor(.primary)
                            if model.displayName != model.id || model.contextWindow != nil {
                                Text(modelSubtitle(model))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if profile.selectionMode == .fixed && profile.fixedModelID == model.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else if profile.selectionMode != .fixed && profile.resolvedModelID == model.id {
                            Text("Auto")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        } header: {
            Text("Danh sách model từ nhà cung cấp")
        } footer: {
            Text("Sắp xếp từ mới nhất đến cũ nhất. Chạm một model để cố định dùng model đó.")
        }
    }

    @ViewBuilder
    private func modelControlsOnly(_ p: Binding<AIProviderProfile>, profile: AIProviderProfile) -> some View {
        Picker("Chế độ", selection: p.selectionMode) {
            ForEach(AIModelSelectionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        HStack {
            Text("Đang dùng")
            Spacer()
            Text(profile.resolvedModelID.isEmpty ? "chưa chọn" : profile.resolvedModelID)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(profile.resolvedModelID.isEmpty ? .orange : .green)
                .lineLimit(1)
                .truncationMode(.middle)
        }

        TextField("Lọc model (vd: claude, gpt, openai/)", text: p.modelFilter)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.system(size: 13, design: .monospaced))

        Button {
            Task { await aiService.refreshModels(for: profileID) }
        } label: {
            HStack {
                Label("Kiểm tra & tải model mới nhất", systemImage: "arrow.clockwise")
                Spacer()
                if aiService.isRefreshing(profileID) {
                    ProgressView()
                }
            }
        }
        .disabled(aiService.isRefreshing(profileID))

        if let message = aiService.lastRefreshMessage[profileID] {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        if let date = profile.lastModelRefresh {
            Text("Cập nhật lần cuối: \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var curlImportModal: some View {
        CompatibleNavigationContainer {
            Form {
                Section {
                    TextEditor(text: $curlImportText)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 220)
                } header: {
                    Text("Dán lệnh cURL hoặc Raw HTTP POST")
                } footer: {
                    Text("Hỗ trợ lệnh curl (-X POST, -H, -d, --data-raw) hoặc Raw HTTP captured request (POST /v1/... HTTP/1.1 + Headers + JSON Body).")
                }

                Section {
                    Toggle("Tự gắn {{model}}, {{messages}}, {{stream}}...", isOn: $curlImportAutoPlaceholders)
                }

                if let err = curlImportError {
                    Section {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    IDEActionButton(prominence: .prominent, tint: .blue, fullWidth: true) {
                        applyCurlImport()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "curlybraces")
                            Text("Phân tích & Áp dụng Request")
                        }
                    }
                    .disabled(curlImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Import cURL / Raw HTTP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showCurlImportSheet = false }
                }
            }
        }
    }

    private func applyCurlImport() {
        guard let parsed = AICurlAndRawRequestParser.parse(curlImportText, injectPlaceholders: curlImportAutoPlaceholders) else {
            curlImportError = "Không đọc được lệnh curl hoặc raw HTTP POST. Kiểm tra lại cú pháp và thử dán lại."
            return
        }
        guard var current = aiService.profile(id: profileID) else {
            showCurlImportSheet = false
            return
        }
        current.format = .customPost
        current.customPostConfig = parsed.config
        current.baseURL = parsed.config.endpointURL
        if !parsed.detectedModel.isEmpty {
            current.fixedModelID = parsed.detectedModel
            current.selectionMode = .fixed
        }
        aiService.updateProfile(current)
        curlImportError = nil
        templateNotice = "Đã import request từ \(parsed.config.endpointURL)"
        showCurlImportSheet = false
    }

    private func manualModelBinding(_ p: Binding<AIProviderProfile>) -> Binding<String> {
        Binding(
            get: { p.wrappedValue.fixedModelID },
            set: { newValue in
                var updated = p.wrappedValue
                updated.fixedModelID = newValue
                if !newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    updated.selectionMode = .fixed
                }
                p.wrappedValue = updated
            }
        )
    }

    private func visibleModels(_ profile: AIProviderProfile) -> [AIModelInfo] {
        let base: [AIModelInfo]
        if showAllModels {
            base = profile.cachedModels.sorted { AIModelRanker.isNewer($0, than: $1) }
        } else {
            base = AIModelRanker.rankedCandidates(
                from: profile.cachedModels,
                presetID: profile.presetID,
                filter: profile.modelFilter,
                format: profile.format
            )
        }
        let query = modelSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { ($0.id + " " + $0.displayName).lowercased().contains(query) }
    }

    private func modelSubtitle(_ model: AIModelInfo) -> String {
        var parts: [String] = []
        if model.displayName != model.id { parts.append(model.displayName) }
        if let ctx = model.contextWindow { parts.append("\(ctx / 1000)K context") }
        if let date = model.createdAt { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " • ")
    }
}
