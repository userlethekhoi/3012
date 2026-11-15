import SwiftUI
import UIKit

public struct SSHQuickTerminalSheet: View {
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var theosService: TheosBuildService
    @ObservedObject var runner: CodeRunnerService
    @ObservedObject var preferences: EditorPreferences
    var onOpenTerminalTab: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showAddForm: Bool = false
    @State private var draftProfile = VPSHostProfile(
        label: "Linux VPS",
        host: "",
        port: 22,
        username: "root",
        authKind: .password,
        initialRemotePath: "~"
    )
    @State private var draftPassword: String = ""
    @State private var provisionOutput: String = ""
    @State private var isInstallingCompiler: Bool = false

    public init(
        sshService: SSHWorkspaceService,
        workspace: WorkspaceManager,
        theosService: TheosBuildService,
        runner: CodeRunnerService,
        preferences: EditorPreferences,
        onOpenTerminalTab: @escaping () -> Void
    ) {
        self.sshService = sshService
        self.workspace = workspace
        self.theosService = theosService
        self.runner = runner
        self.preferences = preferences
        self.onOpenTerminalTab = onOpenTerminalTab
    }

    private var effectiveProjectRoot: URL {
        theosService.resolveTheosProjectRoot(
            activeFileURL: workspace.activeTab?.fileURL,
            workspaceRoot: workspace.rootURL
        ) ?? workspace.rootURL
    }

    public var body: some View {
        CompatibleNavigationContainer {
            Form {
                if let active = sshService.connectedProfile {
                    liveVPSTerminalSection(active: active)
                    remoteFolderMountSection
                    vpsToolchainSection
                } else {
                    disconnectedNoticeSection
                }

                savedProfilesSection
                addNewVPSSection
            }
            .navigationTitle(preferences.tr("Terminal Linux VPS & SSH", "Linux VPS Terminal & SSH"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(preferences.tr("Đóng", "Close")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                sshService.refreshActiveMountedStatus(for: workspace.rootURL)
                if !sshService.isConnected && sshService.savedProfiles.isEmpty {
                    showAddForm = true
                }
            }
        }
    }

    private var disconnectedNoticeSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preferences.tr("Chưa gắn Linux VPS SSH", "No Linux VPS Connected"))
                        .font(.system(size: 14, weight: .bold))
                    Text(preferences.tr("Đăng nhập VPS một lần để mở shell Ubuntu/Debian ngay trong 3012 và chạy make trực tiếp không cần gửi lại zip.", "Sign in once to attach a live Ubuntu/Debian shell inside 3012 and run make without re-uploading zips."))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
            }
            if !sshService.statusMessage.isEmpty {
                Text(sshService.statusMessage)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(sshService.isConnecting ? .accentColor : .secondary)
            }
        }
    }

    @ViewBuilder
    private func liveVPSTerminalSection(active: VPSHostProfile) -> some View {
        let projectRoot = effectiveProjectRoot
        let hasTheos = theosService.isTheosWorkspace(projectRoot)
        let mountedRemote = sshService.remoteDirectoryBound(to: projectRoot) ?? sshService.activeMountedRemoteProjectPath

        Section(preferences.tr("Terminal VPS Trực Tiếp", "Live VPS Terminal")) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(active.username)@\(active.host):\(active.port)")
                        .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                    Text(sshService.isPTYReady
                         ? preferences.tr("Shell Linux PTY đang hoạt động", "Interactive Linux PTY active")
                         : preferences.tr("Đang khởi tạo SSH PTY...", "Starting SSH PTY..."))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                IDEPillButton(prominence: .destructive) {
                    Task { await sshService.disconnect() }
                } label: {
                    Text(preferences.tr("Ngắt", "Disconnect"))
                }
            }

            if let mountedRemote {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundColor(.green)
                    Text(preferences.tr("Dự án đang mở live trên VPS: \(mountedRemote) (0 KB zip upload)", "Project mounted live from VPS: \(mountedRemote) (0 KB zip upload)"))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            IDEActionButton(prominence: .prominent, tint: .accentColor) {
                if sshService.isConnected && !sshService.isPTYReady {
                    sshService.startInteractivePTYShell()
                }
                dismiss()
                onOpenTerminalTab()
            } label: {
                Image(systemName: "terminal")
                Text(preferences.tr("Mở Terminal Linux VPS Ngay", "Open Live VPS Terminal Now"))
            }

            IDEActionButton(prominence: .secondary, tint: .green) {
                if hasTheos {
                    theosService.buildMode = .directVPSTerminal
                    dismiss()
                    onOpenTerminalTab()
                    theosService.startBuild(
                        workspaceRoot: projectRoot,
                        sshService: sshService,
                        runner: runner,
                        workspace: workspace
                    ) {
                        workspace.reloadTree()
                    }
                } else {
                    let targetDir = sshService.currentRemoteDirectory
                    let schemeEnv = theosService.packageScheme == .rootful ? "" : " THEOS_PACKAGE_SCHEME=\(theosService.packageScheme.rawValue)"
                    let cmd = "cd \(SSHWorkspaceService.shellQuote(targetDir)) && ( [ -n \"$THEOS\" ] || for _t in \"$HOME/theos\" /opt/theos /var/theos /usr/local/theos; do [ -d \"$_t/makefiles\" ] && export THEOS=\"$_t\" && break; done ) && make -j2 package FINALPACKAGE=1\(schemeEnv)"
                    dismiss()
                    onOpenTerminalTab()
                    sshService.sendPTYCommand(cmd)
                }
            } label: {
                Image(systemName: "hammer.fill")
                Text(hasTheos
                     ? preferences.tr("Chạy make package Trong Terminal VPS", "Run make package in VPS Terminal")
                     : preferences.tr("Chạy make Tại Thư Mục VPS Đang Chọn", "Run make in Current VPS Folder"))
            }

            if hasTheos || theosService.lastRemoteBuildDir != nil || mountedRemote != nil {
                IDEActionButton(prominence: .secondary, tint: .blue) {
                    Task {
                        await theosService.pullCompiledArtifactsFromVPS(
                            remoteProjectDir: mountedRemote ?? theosService.lastRemoteBuildDir ?? sshService.currentRemoteDirectory,
                            localWorkspaceRoot: projectRoot,
                            sshService: sshService,
                            runner: runner
                        ) {
                            workspace.reloadTree()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(preferences.tr("Lấy .deb / .dylib Từ VPS Về packages/", "Pull .deb / .dylib From VPS to packages/"))
                }
            }
        }
    }

    private var remoteFolderMountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sshService.currentRemoteDirectory)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    IDEPillButton(prominence: .secondary) {
                        Task { await sshService.navigateUpRemoteDirectory() }
                    } label: {
                        Image(systemName: "arrow.uturn.up")
                        Text("..")
                    }
                    IDEPillButton(prominence: .secondary) {
                        Task { await sshService.refreshRemoteDirectory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                IDEActionButton(prominence: .prominent, tint: .green) {
                    Task {
                        if await sshService.mountRemoteProjectDirectory(
                            remotePath: sshService.currentRemoteDirectory,
                            into: workspace
                        ) != nil {
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "folder.fill")
                    Text(sshService.isMountingRemoteProject
                         ? preferences.tr("Đang gắn dự án từ VPS...", "Mounting VPS project...")
                         : preferences.tr("Mở Thư Mục VPS Này Làm Dự Án (0 Upload)", "Open This VPS Folder as Project (0 Upload)"))
                }
                .disabled(sshService.isMountingRemoteProject)

                IDEActionButton(prominence: .secondary, tint: .accentColor) {
                    sshService.sendPTYCommand("cd \(SSHWorkspaceService.shellQuote(sshService.currentRemoteDirectory))")
                    dismiss()
                    onOpenTerminalTab()
                } label: {
                    Image(systemName: "play.fill")
                    Text(preferences.tr("cd Vào Thư Mục Này Trong Terminal", "cd Into This Folder in Terminal"))
                }
            }

            let subfolders = sshService.remoteEntries.filter(\.isDirectory)
            if subfolders.isEmpty {
                Text(preferences.tr("Không có thư mục con nào tại đường dẫn này (\(sshService.remoteEntries.count) file).", "No subfolders here (\(sshService.remoteEntries.count) files)."))
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            } else {
                ForEach(subfolders) { folder in
                    Button {
                        Task { await sshService.refreshRemoteDirectory(at: folder.fullPath) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(folder.name)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(preferences.tr("Duyệt & Gắn Code Trực Tiếp Trên VPS", "Browse & Mount VPS Project Directly"))
        } footer: {
            Text(preferences.tr("Khi mở thư mục VPS trong 3012, mọi lần Lưu tự đồng bộ ngay file vừa sửa lên VPS qua SFTP và giữ nguyên cache .theos — không bao giờ phải nén gửi lại toàn bộ dự án.", "Mounted VPS projects sync only saved edits via SFTP while keeping .theos build cache intact on the VPS."))
        }
    }

    private var savedProfilesSection: some View {
        Section(preferences.tr("VPS Đã Lưu (\(sshService.savedProfiles.count))", "Saved VPS Profiles (\(sshService.savedProfiles.count))")) {
            if sshService.savedProfiles.isEmpty {
                Text(preferences.tr("Chưa có hồ sơ VPS nào. Thêm VPS ở mục bên dưới.", "No saved VPS profiles yet. Add one below."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sshService.savedProfiles) { profile in
                    let isCurrent = sshService.connectedProfile?.id == profile.id
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.label.isEmpty ? profile.host : profile.label)
                                .font(.system(size: 13.5, weight: .semibold))
                            Text("\(profile.username)@\(profile.host):\(profile.port)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if isCurrent {
                            Text(preferences.tr("Đang gắn", "Active"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        } else {
                            IDEPillButton(prominence: .prominent, tint: .accentColor) {
                                Task {
                                    await sshService.connect(to: profile)
                                    sshService.refreshActiveMountedStatus(for: workspace.rootURL)
                                }
                            } label: {
                                Text(sshService.isConnecting ? "..." : preferences.tr("Kết nối", "Connect"))
                            }
                            .disabled(sshService.isConnecting)
                        }
                        Button {
                            sshService.deleteProfile(profile)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addNewVPSSection: some View {
        Section(preferences.tr("Thêm & Kết Nối VPS Linux Mới", "Add & Connect New Linux VPS")) {
            DisclosureGroup(preferences.tr("Nhập IP / Tài khoản SSH", "Enter SSH Host / Credentials"), isExpanded: $showAddForm) {
                TextField(preferences.tr("Tên gợi nhớ (vd: Build VPS)", "Label (e.g. Build VPS)"), text: $draftProfile.label)
                TextField(preferences.tr("IP hoặc Domain (vd: 103.x.x.x)", "IP or Domain (e.g. 103.x.x.x)"), text: $draftProfile.host)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField(preferences.tr("Port SSH", "SSH Port"), value: $draftProfile.port, format: .number)
                    .keyboardType(.numberPad)
                TextField(preferences.tr("Username (vd: root, ubuntu)", "Username (e.g. root, ubuntu)"), text: $draftProfile.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField(preferences.tr("Thư mục mặc định (vd: ~ hoặc /root)", "Initial Path (e.g. ~ or /root)"), text: $draftProfile.initialRemotePath)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Picker(preferences.tr("Xác thực", "Auth"), selection: $draftProfile.authKind) {
                    ForEach(VPSHostProfile.AuthKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }

                if draftProfile.authKind == .password {
                    SecureField(preferences.tr("Mật khẩu SSH", "SSH Password"), text: $draftPassword)
                } else {
                    let pubKey = KeychainVault.generateOrLoadDeviceEd25519Key().publicKeyAuthorizedLine
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pubKey)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(3)
                        IDEActionButton(prominence: .secondary, tint: .accentColor, compact: true) {
                            UIPasteboard.general.string = pubKey
                        } label: {
                            Image(systemName: "doc.on.doc")
                            Text(preferences.tr("Sao chép Public Key Ed25519", "Copy Ed25519 Public Key"))
                        }
                    }
                }

                IDEActionButton(prominence: .prominent, tint: .accentColor) {
                    let saved = draftProfile
                    let pwd = draftPassword
                    sshService.saveOrUpdateProfile(saved, password: pwd)
                    showAddForm = false
                    Task {
                        await sshService.connect(to: saved, passwordOverride: pwd.isEmpty ? nil : pwd)
                        sshService.refreshActiveMountedStatus(for: workspace.rootURL)
                    }
                } label: {
                    Image(systemName: "play.fill")
                    Text(preferences.tr("Lưu & Kết Nối VPS Ngay", "Save & Connect VPS Now"))
                }
                .disabled(draftProfile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sshService.isConnecting)
            }
        }
    }

    private var vpsToolchainSection: some View {
        Section(preferences.tr("Cài Công Cụ Trên VPS (1-Chạm)", "Install VPS Build Tools (1-Tap)")) {
            IDEActionButton(prominence: .secondary, tint: .orange) {
                Task {
                    provisionOutput = preferences.tr("Đang cài Theos + iOS SDK trên VPS...", "Installing Theos + iOS SDK on VPS...")
                    provisionOutput = await sshService.provisionTheosOnVPS()
                }
            } label: {
                Image(systemName: "hammer.fill")
                Text(sshService.isProvisioningTheos
                     ? preferences.tr("Đang cài Theos + SDK...", "Installing Theos + SDK...")
                     : preferences.tr("Cài Theos + iOS SDK Trên VPS", "Install Theos + iOS SDK on VPS"))
            }
            .disabled(sshService.isProvisioningTheos)

            IDEActionButton(prominence: .secondary, tint: .purple) {
                Task {
                    isInstallingCompiler = true
                    provisionOutput = preferences.tr("Đang cài gcc/g++, Python3, Node.js trên VPS...", "Installing gcc/g++, Python3, Node.js on VPS...")
                    provisionOutput = await sshService.provisionVPSToolchain()
                    isInstallingCompiler = false
                }
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                Text(isInstallingCompiler
                     ? preferences.tr("Đang cài compiler...", "Installing compilers...")
                     : preferences.tr("Cài C/C++ (gcc/g++), Python3 & Node.js", "Install C/C++ (gcc/g++), Python3 & Node.js"))
            }
            .disabled(isInstallingCompiler)

            if !provisionOutput.isEmpty {
                ScrollView(.vertical) {
                    Text(provisionOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
    }
}
