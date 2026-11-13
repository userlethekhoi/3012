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
                            Text(hasTheosProject
                                 ? preferences.tr("Đã nhận diện dự án Theos", "Theos Project Detected")
                                 : preferences.tr("Chưa có Makefile / control Theos", "No Theos Makefile / control Yet"))
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
                                Text(preferences.tr("Đang biên dịch — Bấm để huỷ", "Compiling — Tap to Cancel"))
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        Button {
                            triggerBuildWithConsentCheck()
                        } label: {
                            Label(preferences.tr("Build .deb / .dylib Ngay", "Build .deb / .dylib Now"), systemImage: "play.fill")
                                .fontWeight(.bold)
                        }
                        .disabled(!hasTheosProject && theosService.buildMode != .offlineExport)
                    }
                } header: {
                    Text(preferences.tr("Trình Biên Dịch Theos (Không Cần Máy Jailbreak)", "Theos Compiler (No Jailbreak Required)"))
                }

                // MARK: - 2. 1-Tap Theos Tweak & Mod Menu Template Generator
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { showTemplateCreator || !hasTheosProject },
                        set: { showTemplateCreator = $0 }
                    )) {
                        Picker(preferences.tr("Loại mẫu", "Template Type"), selection: $selectedTemplate) {
                            ForEach(TheosTemplateKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }

                        Text(selectedTemplate.summary)
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField(preferences.tr("Tên Tweak (ví dụ: ModMenu3012)", "Tweak Name (e.g. ModMenu3012)"), text: $tweakNameInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField(preferences.tr("Bundle ID gói .deb", ".deb Package Bundle ID"), text: $packageIDInput)
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
                                templateCreatedNotice = preferences.tr(
                                    "Đã tạo bộ khung \(tweakNameInput) trong \(workspace.rootURL.lastPathComponent).",
                                    "Created \(tweakNameInput) scaffold in \(workspace.rootURL.lastPathComponent)."
                                )
                                theosService.refreshLocalPackages(in: workspace.rootURL)
                            }
                        } label: {
                            Label(preferences.tr("Khởi Tạo Dự Án Theos 1 Chạm", "1-Tap Scaffold Theos Project"), systemImage: "doc.badge.plus")
                                .fontWeight(.semibold)
                        }

                        if let notice = templateCreatedNotice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    } label: {
                        Label(preferences.tr("Tạo Mẫu Tweak / Mod Menu Mới", "New Tweak / Mod Menu Template"), systemImage: "plus.square.on.square")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                }

                // MARK: - 3. Package Scheme & Build Environment
                Section(preferences.tr("Kiến Trúc & Môi Trường Biên Dịch", "Package Scheme & Build Environment")) {
                    Picker(preferences.tr("Chuẩn gói (.deb)", "Package Scheme (.deb)"), selection: $theosService.packageScheme) {
                        ForEach(TheosPackageScheme.allCases) { scheme in
                            Text(scheme.title).tag(scheme)
                        }
                    }

                    Picker(preferences.tr("Phương thức build", "Build Method"), selection: $theosService.buildMode) {
                        ForEach(TheosBuildMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Text(theosService.buildMode.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if theosService.buildMode == .communityServer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preferences.tr("Địa chỉ Build Server", "Build Server URL"))
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

                                Button(preferences.tr("Kiểm tra", "Check")) {
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

                        Toggle(preferences.tr("Tôi đồng ý gửi tạm mã nguồn tới sandbox để biên dịch", "I consent to send temporary source code to sandbox for compilation"), isOn: $theosService.hasAcceptedPrivacyConsent)
                            .font(.system(size: 12.5))
                    } else if theosService.buildMode == .privateSSHVPS {
                        HStack {
                            Image(systemName: sshService.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(sshService.isConnected ? .green : .orange)
                            Text(sshService.isConnected
                                 ? preferences.tr("Đã nối SSH: \(sshService.connectedProfile?.host ?? "VPS")", "SSH Connected: \(sshService.connectedProfile?.host ?? "VPS")")
                                 : preferences.tr("Chưa kết nối SSH — mở tab Remote SSH bên trái để đăng nhập VPS", "SSH Disconnected — open Remote SSH tab on the left to sign in"))
                                .font(.system(size: 12))
                        }
                    }
                }

                // MARK: - 4. Compiled Artifacts (.deb / .dylib)
                Section(preferences.tr("Sản Phẩm Đã Biên Dịch (packages/)", "Compiled Artifacts (packages/)")) {
                    if theosService.downloadedArtifacts.isEmpty {
                        Text(preferences.tr("Chưa có file .deb hoặc .dylib nào trong thư mục packages/.", "No .deb or .dylib artifacts in packages/ yet."))
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
                                    Label(preferences.tr("Xuất", "Export"), systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                // MARK: - 5. Live Build Log
                if !theosService.buildLog.isEmpty {
                    Section(preferences.tr("Nhật Ký Biên Dịch", "Build Log")) {
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
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
            .onAppear {
                theosService.refreshLocalPackages(in: workspace.rootURL)
            }
            .alert(preferences.tr("Quyền Riêng Tư Khi Build Từ Xa", "Remote Build Privacy Notice"), isPresented: $showPrivacyAlert) {
                Button(preferences.tr("Đồng ý & Build", "Agree & Build")) {
                    theosService.hasAcceptedPrivacyConsent = true
                    executeBuild()
                }
                Button(preferences.tr("Chuyển sang Offline .zip", "Switch to Offline .zip"), role: .cancel) {
                    theosService.buildMode = .offlineExport
                }
            } message: {
                Text(preferences.tr(
                    "Mã nguồn dự án Theos của bạn sẽ được nén tạm thời và gửi qua HTTPS tới container Docker cách ly (--network none, không có Internet, tự xoá hoàn toàn sau khi biên dịch và giữ kết quả tối đa 15 phút). Bạn có thể chuyển sang VPS SSH cá nhân hoặc Offline GitHub Actions bất kỳ lúc nào.",
                    "Your Theos project source will be temporarily archived and sent over HTTPS to an isolated Docker container (--network none, no Internet access, source deleted immediately after build, artifacts auto-expire in 15 minutes). You can switch to Private SSH VPS or Offline GitHub Actions anytime."
                ))
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
