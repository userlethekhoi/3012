import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct XtoolBuilderSheet: View {
    @ObservedObject var xtoolService: XtoolBuildService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: XtoolTemplateKind = .swiftUIApp
    @State private var appNameInput: String = "SampleXtoolApp"
    @State private var bundleIDInput: String = "com.example.samplextoolapp"
    @State private var showTemplateCreator: Bool = false
    @State private var templateNotice: String? = nil
    @State private var syncNotice: String? = nil

    // On-device IPA + Dylib Injection state
    @State private var pickedIPAURL: URL? = nil
    @State private var pickedDylibURL: URL? = nil
    @State private var injectNotice: String? = nil

    public init(
        xtoolService: XtoolBuildService,
        workspace: WorkspaceManager,
        sshService: SSHWorkspaceService,
        runner: CodeRunnerService,
        preferences: EditorPreferences
    ) {
        self.xtoolService = xtoolService
        self.workspace = workspace
        self.sshService = sshService
        self.runner = runner
        self.preferences = preferences
    }

    public var body: some View {
        let isXtoolProject = xtoolService.isXtoolWorkspace(workspace.rootURL)
        let manifest = xtoolService.inspectWorkspace(workspace.rootURL)

        CompatibleNavigationContainer {
            Form {
                // MARK: - 1. xtool Workspace Status & Build Action
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: isXtoolProject ? "cube.transparent.fill" : "shippingbox")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(isXtoolProject ? .blue : .orange)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(isXtoolProject
                                 ? preferences.tr("Đã nhận diện dự án xtool / SwiftPM", "xtool / SwiftPM Project Detected")
                                 : preferences.tr("Chưa có xtool.yml / Package.swift iOS", "No xtool.yml / iOS Package.swift Yet"))
                                .font(.system(size: 14, weight: .bold))

                            if isXtoolProject && !manifest.productName.isEmpty {
                                Text("\(manifest.productName) • \(manifest.bundleID.isEmpty ? "no bundleID" : manifest.bundleID)\(manifest.extensionsCount > 0 ? " • \(manifest.extensionsCount) ext" : "")")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.blue)
                            }

                            Text(xtoolService.buildStatusText)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if xtoolService.isBuilding {
                        Button(role: .destructive) {
                            xtoolService.cancelBuild()
                        } label: {
                            HStack {
                                ProgressView().padding(.trailing, 4)
                                Text(preferences.tr("Đang chạy xtool — Bấm để huỷ", "Running xtool — Tap to Cancel"))
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        Button {
                            executeXtoolBuild()
                        } label: {
                            Label(
                                xtoolService.buildMode == .privateSSHVPS
                                    ? preferences.tr("Build .ipa Qua SSH VPS (xtool dev)", "Build .ipa via SSH VPS (xtool dev)")
                                    : preferences.tr("Xuất GitHub Actions + .zip (Build .ipa)", "Export GitHub Actions + .zip (.ipa)"),
                                systemImage: "play.fill"
                            )
                            .font(.body.weight(.bold))
                        }
                        .disabled(!isXtoolProject && xtoolService.buildMode == .privateSSHVPS)
                    }
                } header: {
                    Text(preferences.tr("xtool — Build SwiftUI & Non-JB .ipa Không Cần Xcode", "xtool — Build SwiftUI & Non-JB .ipa Without Xcode"))
                }

                // MARK: - 2. 1-Tap xtool Project Generator
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { showTemplateCreator || !isXtoolProject },
                        set: { showTemplateCreator = $0 }
                    )) {
                        Picker(preferences.tr("Loại mẫu xtool", "xtool Template"), selection: $selectedTemplate) {
                            ForEach(XtoolTemplateKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }

                        Text(selectedTemplate.summary)
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField(preferences.tr("Tên App (ví dụ: SampleXtoolApp)", "App Name (e.g. SampleXtoolApp)"), text: $appNameInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        TextField("Bundle ID (com.example.samplextoolapp)", text: $bundleIDInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            workspace.saveAllTabs()
                            let opened = xtoolService.scaffoldTemplate(
                                kind: selectedTemplate,
                                appName: appNameInput,
                                bundleID: bundleIDInput,
                                in: workspace
                            )
                            if opened != nil {
                                templateNotice = preferences.tr(
                                    "Đã tạo dự án xtool '\(appNameInput)' trong \(workspace.rootURL.lastPathComponent).",
                                    "Created xtool project '\(appNameInput)' in \(workspace.rootURL.lastPathComponent)."
                                )
                                xtoolService.refreshLocalPackages(in: workspace.rootURL)
                            }
                        } label: {
                            Label(preferences.tr("Khởi Tạo Dự Án xtool 1 Chạm", "1-Tap Scaffold xtool Project"), systemImage: "doc.badge.plus")
                                .font(.body.weight(.semibold))
                        }

                        if let notice = templateNotice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    } label: {
                        Label(preferences.tr("Tạo Ứng Dụng SwiftUI / xtool Mới", "New SwiftUI / xtool App Template"), systemImage: "plus.square.on.square")
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                }

                // MARK: - 3. Build Method & Manifest Sync
                Section(preferences.tr("Cấu Hình Build & Đồng Bộ Manifest", "Build Environment & Manifest Sync")) {
                    Picker(preferences.tr("Chế độ build", "Build Mode"), selection: $xtoolService.buildMode) {
                        ForEach(XtoolBuildMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Text(xtoolService.buildMode.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if xtoolService.buildMode == .privateSSHVPS {
                        HStack {
                            Image(systemName: sshService.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(sshService.isConnected ? .green : .orange)
                            Text(sshService.isConnected
                                 ? preferences.tr("Đã nối SSH: \(sshService.connectedProfile?.host ?? "VPS")", "SSH Connected: \(sshService.connectedProfile?.host ?? "VPS")")
                                 : preferences.tr("Chưa kết nối SSH — mở tab Remote SSH bên trái để đăng nhập VPS", "SSH Disconnected — open Remote SSH tab on the left to sign in"))
                                .font(.system(size: 12))
                        }
                    }

                    Button {
                        workspace.saveAllTabs()
                        syncNotice = xtoolService.syncXtoolManifests(
                            in: workspace,
                            isEnglish: preferences.appLanguage != .vietnamese
                        )
                    } label: {
                        Label(
                            preferences.tr("Đồng bộ Package.swift <-> xtool.yml", "Sync Package.swift <-> xtool.yml"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.body.weight(.semibold))
                    }
                    .disabled(!manifest.hasPackageSwift)

                    HStack(spacing: 12) {
                        if manifest.hasXtoolYML {
                            Button(preferences.tr("Mở xtool.yml", "Open xtool.yml")) {
                                workspace.openFile(at: workspace.rootURL.appendingPathComponent("xtool.yml"))
                                dismiss()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.borderless)
                        }
                        if manifest.hasPackageSwift {
                            Button(preferences.tr("Mở Package.swift", "Open Package.swift")) {
                                workspace.openFile(at: workspace.rootURL.appendingPathComponent("Package.swift"))
                                dismiss()
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.borderless)
                        }
                    }

                    if let syncNotice {
                        Text(syncNotice)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }

                // MARK: - 4. On-Device .dylib -> Non-JB .ipa Injector
                Section {
                    Text(preferences.tr(
                        "Nhúng thẳng file .dylib (Mod Menu / Tweak vừa build từ Theos) vào .ipa ngay trên thiết bị không cần PC hay máy chủ (tự chèn LC_LOAD_DYLIB vào Mach-O 64-bit).",
                        "Embed any .dylib directly into an .ipa on-device (copies to Frameworks/ and patches 64-bit Mach-O with LC_LOAD_DYLIB)."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)

                    Button {
                        NativeDocumentPickerPresenter.shared.presentCustomFilePicker(allowedExtensions: ["ipa", "zip"]) { url in
                            pickedIPAURL = url
                        }
                    } label: {
                        HStack {
                            Label(preferences.tr("Chọn file .ipa nguồn", "Select Source .ipa"), systemImage: "shippingbox.fill")
                            Spacer()
                            Text(pickedIPAURL?.lastPathComponent ?? preferences.tr("Chưa chọn", "None"))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(pickedIPAURL == nil ? .secondary : .blue)
                                .lineLimit(1)
                        }
                    }

                    Button {
                        NativeDocumentPickerPresenter.shared.presentCustomFilePicker(allowedExtensions: ["dylib"]) { url in
                            pickedDylibURL = url
                        }
                    } label: {
                        HStack {
                            Label(preferences.tr("Chọn file .dylib cần nhúng", "Select .dylib to Inject"), systemImage: "cpu")
                            Spacer()
                            Text(pickedDylibURL?.lastPathComponent ?? preferences.tr("Chưa chọn", "None"))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(pickedDylibURL == nil ? .secondary : .green)
                                .lineLimit(1)
                        }
                    }

                    let workspaceDylibs = discoverWorkspaceFiles(withExtension: "dylib")
                    if !workspaceDylibs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Text(preferences.tr("Có sẵn:", "In project:"))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ForEach(workspaceDylibs, id: \.path) { url in
                                    Button(url.lastPathComponent) {
                                        pickedDylibURL = url
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    TextField(preferences.tr("Đổi Bundle ID (tuỳ chọn)", "Override Bundle ID (optional)"), text: $xtoolService.overrideBundleID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 12.5, design: .monospaced))

                    TextField(preferences.tr("Đổi tên hiển thị App (tuỳ chọn)", "Override App Display Name (optional)"), text: $xtoolService.overrideDisplayName)
                        .autocorrectionDisabled()
                        .font(.system(size: 12.5))

                    Toggle(
                        preferences.tr("Xoá _CodeSignature cũ để sẵn sàng re-sign", "Strip old _CodeSignature for clean re-signing"),
                        isOn: $xtoolService.stripOldCodeSignature
                    )
                    .font(.system(size: 12.5))

                    Button {
                        guard let ipaURL = pickedIPAURL, let dylibURL = pickedDylibURL else { return }
                        injectNotice = nil
                        Task {
                            let resultURL = await xtoolService.injectDylibIntoIPA(
                                ipaURL: ipaURL,
                                dylibURL: dylibURL,
                                workspaceRoot: workspace.rootURL,
                                options: XtoolInjectionOptions(
                                    bundleIDOverride: xtoolService.overrideBundleID,
                                    displayNameOverride: xtoolService.overrideDisplayName,
                                    stripOldCodeSignature: xtoolService.stripOldCodeSignature
                                ),
                                runner: runner
                            )
                            workspace.reloadTree()
                            if let resultURL {
                                injectNotice = preferences.tr(
                                    "Đã xuất \(resultURL.lastPathComponent) vào packages/!",
                                    "Packaged \(resultURL.lastPathComponent) in packages/!"
                                )
                            }
                        }
                    } label: {
                        if xtoolService.isInjecting {
                            HStack {
                                ProgressView().padding(.trailing, 4)
                                Text(preferences.tr("Đang patch Mach-O & nén .ipa...", "Patching Mach-O & repacking .ipa..."))
                            }
                        } else {
                            Label(
                                preferences.tr("Nhúng .dylib & Đóng Gói .ipa", "Inject .dylib & Repack .ipa"),
                                systemImage: "bandage.fill"
                            )
                            .font(.body.weight(.bold))
                        }
                    }
                    .disabled(pickedIPAURL == nil || pickedDylibURL == nil || xtoolService.isInjecting)

                    if let injectNotice {
                        Text(injectNotice)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } header: {
                    Text(preferences.tr("Tiện Ích Non-JB: Nhúng .dylib Vào .ipa (Offline)", "Non-JB Toolkit: .dylib -> .ipa Injector (Offline)"))
                }

                // MARK: - 5. Output Artifacts (.ipa / .zip / .dylib)
                Section(preferences.tr("Sản Phẩm Đã Đóng Gói (packages/)", "Packaged Artifacts (packages/)")) {
                    if xtoolService.downloadedArtifacts.isEmpty {
                        Text(preferences.tr("Chưa có file .ipa hoặc .zip nào trong packages/.", "No .ipa or .zip files in packages/ yet."))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(xtoolService.downloadedArtifacts) { item in
                            HStack {
                                Image(systemName: item.name.hasSuffix(".ipa") ? "shippingbox.fill" : "doc.zipper")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    Text(item.formattedSize)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if item.name.lowercased().hasSuffix(".ipa") {
                                    Button(preferences.tr("Chọn", "Use")) {
                                        pickedIPAURL = item.localURL
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                                    .buttonStyle(.borderless)
                                }
                                CompatibleFileShareButton(item: item.localURL) {
                                    Label(preferences.tr("Xuất", "Export"), systemImage: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                // MARK: - 6. Live Build & Patch Log
                if !xtoolService.buildLog.isEmpty {
                    Section(preferences.tr("Nhật Ký xtool & Mach-O Patcher", "xtool & Mach-O Patcher Log")) {
                        ScrollView {
                            Text(xtoolService.buildLog)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 130, maxHeight: 230)
                    }
                }
            }
            .navigationTitle("xtool Studio & .ipa Injector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Done")) { dismiss() }
                }
            }
            .onAppear {
                xtoolService.refreshLocalPackages(in: workspace.rootURL)
                if pickedIPAURL == nil {
                    pickedIPAURL = discoverWorkspaceFiles(withExtension: "ipa").first
                }
                if pickedDylibURL == nil {
                    pickedDylibURL = discoverWorkspaceFiles(withExtension: "dylib").first
                }
            }
        }
    }

    private func executeXtoolBuild() {
        workspace.saveAllTabs()
        xtoolService.startBuild(
            workspaceRoot: workspace.rootURL,
            sshService: sshService,
            runner: runner,
            onWorkspaceChanged: { [weak workspace] in
                workspace?.reloadTree()
            }
        )
    }

    private func discoverWorkspaceFiles(withExtension ext: String) -> [URL] {
        let fm = FileManager.default
        let targetExt = ext.lowercased()
        let searchDirs = [
            workspace.rootURL.appendingPathComponent("packages", isDirectory: true),
            workspace.rootURL
        ]
        var found: [URL] = []
        var seenPaths = Set<String>()
        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for item in items where item.pathExtension.lowercased() == targetExt {
                let std = item.standardizedFileURL.path
                if seenPaths.insert(std).inserted {
                    found.append(item)
                }
            }
        }
        return found
    }
}
