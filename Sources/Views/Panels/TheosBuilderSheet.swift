import SwiftUI
import UIKit

public struct TheosBuilderSheet: View {
    @ObservedObject var theosService: TheosBuildService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: TheosTemplateKind = .modMenuDylib
    @State private var tweakNameInput: String = "ModMenu3012"
    @State private var packageIDInput: String = "com.dev.modmenu3012"
    @State private var bundleFilterInput: String = "com.apple.springboard"
    @State private var showTemplateCreator: Bool = false
    @State private var showPrivacyAlert: Bool = false
    @State private var templateCreatedNotice: String? = nil

    public init(
        theosService: TheosBuildService,
        workspace: WorkspaceManager,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        preferences: EditorPreferences
    ) {
        self.theosService = theosService
        self.workspace = workspace
        self.sshService = sshService
        self.runner = runner
        self.preferences = preferences
    }

    public var body: some View {
        let hasTheosProject = theosService.isTheosWorkspace(workspace.rootURL)

        NavigationStack {
            Form {
                // MARK: - 1. Workspace Status & Action
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: hasTheosProject ? "hammer.circle.fill" : "shippingbox")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(hasTheosProject ? .green : .orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(hasTheosProject ? "Đã nhận diện dự án Theos" : "Chưa có Makefile / control Theos")
                                .font(.system(size: 14, weight: .bold))
                            Text(theosService.buildStatusText)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if theosService.isBuilding {
                        Button(role: .destructive) {
                            theosService.cancelBuild()
                        } label: {
                            HStack {
                                ProgressView().padding(.trailing, 4)
                                Text("Đang biên dịch — Bấm để huỷ")
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        Button {
                            triggerBuildWithConsentCheck()
                        } label: {
                            Label("Build .deb / .dylib Ngay", systemImage: "play.fill")
                                .fontWeight(.bold)
                        }
                        .disabled(!hasTheosProject && theosService.buildMode != .offlineExport)
                    }
                } header: {
                    Text("Trình Biên Dịch Theos (Không Cần Máy Jailbreak)")
                }

                // MARK: - 2. 1-Tap Theos Tweak & Mod Menu Template Generator
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { showTemplateCreator || !hasTheosProject },
                        set: { showTemplateCreator = $0 }
                    )) {
                        Picker("Loại mẫu", selection: $selectedTemplate) {
                            ForEach(TheosTemplateKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }

                        Text(selectedTemplate.summary)
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField("Tên Tweak (ví dụ: ModMenu3012)", text: $tweakNameInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Bundle ID gói .deb", text: $packageIDInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Target Filter Bundle ID", text: $bundleFilterInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            workspace.saveAllTabs()
                            let opened = theosService.scaffoldTemplate(
                                kind: selectedTemplate,
                                tweakName: tweakNameInput,
                                packageID: packageIDInput,
                                bundleFilter: bundleFilterInput,
                                in: workspace
                            )
                            if opened != nil {
                                templateCreatedNotice = "Đã tạo bộ khung \(tweakNameInput) trong \(workspace.rootURL.lastPathComponent)."
                                theosService.refreshLocalPackages(in: workspace.rootURL)
                            }
                        } label: {
                            Label("Khởi Tạo Dự Án Theos 1 Chạm", systemImage: "doc.badge.plus")
                                .fontWeight(.semibold)
                        }

                        if let notice = templateCreatedNotice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    } label: {
                        Label("Tạo Mẫu Tweak / Mod Menu Mới", systemImage: "plus.square.on.square")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                }

                // MARK: - 3. Package Scheme & Build Environment
                Section("Kiến Trúc & Môi Trường Biên Dịch") {
                    Picker("Chuẩn gói (.deb)", selection: $theosService.packageScheme) {
                        ForEach(TheosPackageScheme.allCases) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }

                    Picker("Phương thức build", selection: $theosService.buildMode) {
                        ForEach(TheosBuildMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Text(theosService.buildMode.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if theosService.buildMode == .communityServer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Địa chỉ Build Server")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("https://build.kaydus.xyz", text: $theosService.serverURL)
                                .font(.system(size: 13, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)

                            HStack(spacing: 8) {
                                Button("build.kaydus.xyz") {
                                    theosService.serverURL = TheosBuildService.defaultServerURL
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .buttonStyle(.bordered)

                                Button("kaydus.xyz") {
                                    theosService.serverURL = TheosBuildService.alternateServerURL
                                }
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .buttonStyle(.bordered)

                                Spacer()

                                Button("Kiểm tra") {
                                    Task { await theosService.checkServerHealth() }
                                }
                                .font(.system(size: 11.5, weight: .bold))
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if let health = theosService.serverHealthSummary {
                            Text(health)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(health.hasPrefix("Online") ? .green : .orange)
                        }

                        Toggle("Tôi đồng ý gửi tạm mã nguồn tới sandbox để biên dịch", isOn: $theosService.hasAcceptedPrivacyConsent)
                            .font(.system(size: 12.5))
                    } else if theosService.buildMode == .privateSSHVPS {
                        HStack {
                            Image(systemName: sshService.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(sshService.isConnected ? .green : .orange)
                            Text(sshService.isConnected
                                 ? "Đã nối SSH: \(sshService.connectedProfile?.host ?? "VPS")"
                                 : "Chưa kết nối SSH — mở tab Remote SSH bên trái để đăng nhập VPS")
                                .font(.system(size: 12))
                        }
                    }
                }

                // MARK: - 4. Compiled Artifacts (.deb / .dylib)
                Section("Sản Phẩm Đã Biên Dịch (packages/)") {
                    if theosService.downloadedArtifacts.isEmpty {
                        Text("Chưa có file .deb hoặc .dylib nào trong thư mục packages/.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(theosService.downloadedArtifacts) { item in
                            HStack {
                                Image(systemName: item.name.hasSuffix(".deb") ? "shippingbox.fill" : "cpu")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    Text(item.formattedSize)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                ShareLink(item: item.localURL) {
                                    Label("Xuất", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                // MARK: - 5. Live Build Log
                if !theosService.buildLog.isEmpty {
                    Section("Nhật Ký Biên Dịch") {
                        ScrollView {
                            Text(theosService.buildLog)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 140, maxHeight: 240)
                    }
                }
            }
            .navigationTitle("Theos Tweak & Mod Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                theosService.refreshLocalPackages(in: workspace.rootURL)
            }
            .alert("Quyền Riêng Tư Khi Build Từ Xa", isPresented: $showPrivacyAlert) {
                Button("Đồng ý & Build") {
                    theosService.hasAcceptedPrivacyConsent = true
                    executeBuild()
                }
                Button("Chuyển sang Offline .zip", role: .cancel) {
                    theosService.buildMode = .offlineExport
                }
            } message: {
                Text("Mã nguồn dự án Theos của bạn sẽ được nén tạm thời và gửi qua HTTPS tới container Docker cách ly (--network none, không có Internet, tự xoá hoàn toàn sau khi biên dịch và giữ kết quả tối đa 15 phút). Bạn có thể chuyển sang VPS SSH cá nhân hoặc Offline GitHub Actions bất kỳ lúc nào.")
            }
        }
    }

    private func triggerBuildWithConsentCheck() {
        if theosService.buildMode == .communityServer && !theosService.hasAcceptedPrivacyConsent {
            showPrivacyAlert = true
        } else {
            executeBuild()
        }
    }

    private func executeBuild() {
        workspace.saveAllTabs()
        theosService.startBuild(
            workspaceRoot: workspace.rootURL,
            sshService: sshService,
            runner: runner,
            onWorkspaceChanged: { [weak workspace] in
                workspace?.reloadTree()
            }
        )
    }
}
