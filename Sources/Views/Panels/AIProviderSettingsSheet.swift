import SwiftUI

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
            .background(
                NavigationLink(
                    isActive: Binding(
                        get: { editingProfileID != nil },
                        set: { if !$0 { editingProfileID = nil } }
                    )
                ) {
                    if let profileID = editingProfileID {
                        AIProviderProfileEditor(aiService: aiService, profileID: profileID)
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            )
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
            guard let profile = aiService.profile(id: profileID), profile.cachedModels.isEmpty else { return }
            if !profile.requiresAPIKey || !aiService.apiKey(for: profile).isEmpty {
                await aiService.refreshModels(for: profileID, announceChanges: false)
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

    @ViewBuilder
    private func editorContent(_ p: Binding<AIProviderProfile>) -> some View {
        let profile = p.wrappedValue
        let isApple = profile.format == .appleOnDevice

        Section("Kết nối") {
            TextField("Tên hiển thị", text: p.name)

            if isApple {
                let status = AIProviderClient.appleOnDeviceStatus()
                Label(status.detail, systemImage: status.available ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundColor(status.available ? .green : .orange)
            } else {
                TextField("Base URL", text: p.baseURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 13, design: .monospaced))

                Picker("Định dạng API", selection: p.format) {
                    ForEach(AIAPIFormat.allCases.filter { $0 != .appleOnDevice }) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                HStack {
                    Group {
                        if revealKey {
                            TextField(profile.requiresAPIKey ? "API Key" : "API Key (không bắt buộc)", text: $apiKeyInput)
                        } else {
                            SecureField(profile.requiresAPIKey ? "API Key" : "API Key (không bắt buộc)", text: $apiKeyInput)
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

        if !isApple {
            Section {
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
                if profile.format == .anthropic {
                    Stepper("Max output tokens: \(profile.maxOutputTokens)", value: p.maxOutputTokens, in: 1024...128_000, step: 1024)
                }
            }
        }

        Section {
            Button {
                aiService.setActiveProfile(profileID)
                dismiss()
            } label: {
                Label("Dùng cấu hình này", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                aiService.deleteProfile(id: profileID)
                dismiss()
            } label: {
                Label("Xoá cấu hình", systemImage: "trash")
            }
        }
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
            base = AIModelRanker.rankedCandidates(from: profile.cachedModels, presetID: profile.presetID, filter: profile.modelFilter)
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
