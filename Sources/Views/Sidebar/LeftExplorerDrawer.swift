import SwiftUI
import UniformTypeIdentifiers
import UIKit

public enum SidebarActivityTab: Int, CaseIterable, Identifiable {
    case explorer = 0
    case search = 1
    case git = 2
    case ssh = 3
    case extensions = 4

    public var id: Int { rawValue }

    public var icon: String {
        switch self {
        case .explorer: return "folder.fill"
        case .search: return "magnifyingglass"
        case .git: return "point.3.connected.trianglepath.dotted"
        case .ssh: return "server.rack"
        case .extensions: return "puzzlepiece.extension.fill"
        }
    }

    public var title: String {
        switch self {
        case .explorer: return "EXPLORER"
        case .search: return "SEARCH"
        case .git: return "SOURCE CONTROL"
        case .ssh: return "REMOTE - SSH & SFTP"
        case .extensions: return "OPEN VSX EXTENSIONS"
        }
    }
}

public struct LeftExplorerDrawer: View {
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var gitService: GitService
    @ObservedObject var sshService: SSHWorkspaceService
    @ObservedObject var extStore: ExtensionStoreService
    var onInsertSnippet: (String) -> Void
    var onOpenSettings: () -> Void
    var onCloseDrawer: () -> Void

    @State private var activeActivity: SidebarActivityTab = .explorer
    @State private var showNewFileAlert: Bool = false
    @State private var showNewFolderAlert: Bool = false
    @State private var newItemName: String = ""
    @State private var targetParentDir: URL?
    @State private var renameTargetURL: URL?
    @State private var renameText: String = ""
    @State private var showFolderPicker: Bool = false

    // Git UI state
    @State private var commitMessageInput: String = ""
    @State private var cloneRepoInput: String = ""
    @State private var githubTokenInput: String = ""
    @State private var selectedGitDiffText: String? = nil

    // SSH UI state
    @State private var showAddVPSSheet: Bool = false
    @State private var draftVPS = VPSHostProfile()
    @State private var draftVPSPassword: String = ""
    @State private var showNewRemoteFileAlert: Bool = false
    @State private var showNewRemoteFolderAlert: Bool = false
    @State private var remoteNewName: String = ""
    @State private var tunnelPortString: String = "3000"
    @State private var isProvisioningVPS: Bool = false
    @State private var provisionOutputText: String? = nil

    // Extensions UI state
    @State private var openVSXQuery: String = "theme"

    public init(
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        liveServer: LiveServerService,
        gitService: GitService,
        sshService: SSHWorkspaceService,
        extStore: ExtensionStoreService,
        onInsertSnippet: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        onCloseDrawer: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.preferences = preferences
        self.liveServer = liveServer
        self.gitService = gitService
        self.sshService = sshService
        self.extStore = extStore
        self.onInsertSnippet = onInsertSnippet
        self.onOpenSettings = onOpenSettings
        self.onCloseDrawer = onCloseDrawer
    }

    public var body: some View {
        let palette = preferences.activePalette

        HStack(spacing: 0) {
            // VS Code Slim Activity Bar (42pt)
            VStack(spacing: 14) {
                Text("30")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: palette.accent))
                    .padding(.top, 10)

                ForEach(SidebarActivityTab.allCases) { tab in
                    Button {
                        activeActivity = tab
                        if tab == .git {
                            githubTokenInput = gitService.githubToken
                            Task { await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService) }
                        } else if tab == .extensions && extStore.searchResults.isEmpty {
                            Task { await extStore.searchOpenVSX(query: openVSXQuery) }
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: activeActivity == tab ? .bold : .regular))
                                .foregroundColor(activeActivity == tab ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                                .frame(width: 34, height: 34)

                            if tab == .ssh && sshService.isConnected {
                                Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: -2, y: 2)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                        .frame(width: 34, height: 34)
                }
                .padding(.bottom, 10)
            }
            .frame(width: 42)
            .background(Color(hex: palette.headerBackground))

            Divider().overlay(Color.white.opacity(0.08))

            // Main Sidebar Content Area
            VStack(spacing: 0) {
                HStack {
                    Text(activeActivity.title)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                    Spacer()
                    Button {
                        onCloseDrawer()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(hex: palette.headerBackground))

                Group {
                    switch activeActivity {
                    case .explorer:
                        explorerSection(palette: palette)
                    case .search:
                        searchSection(palette: palette)
                    case .git:
                        gitSourceControlSection(palette: palette)
                    case .ssh:
                        remoteSSHSection(palette: palette)
                    case .extensions:
                        extensionsMarketplaceSection(palette: palette)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Bottom Status Strip
                HStack(spacing: 6) {
                    Button {
                        showFolderPicker = true
                    } label: {
                        Label("Mở Folder", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Color(hex: palette.foreground))
                    }

                    Spacer()

                    Button {
                        if liveServer.isRunning {
                            liveServer.stop()
                        } else {
                            liveServer.start(
                                serving: workspace.rootURL,
                                keepAliveInBackground: preferences.keepServerInBackground
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(liveServer.isRunning ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(liveServer.isRunning ? "Live :\(liveServer.port)" : "Go Live")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: palette.currentLineBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(5)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(hex: palette.headerBackground))
            }
            .background(Color(hex: palette.sidebarBackground))
        }
        // Alerts & Sheets
        .alert("Tạo File Mới", isPresented: $showNewFileAlert) {
            TextField("Ví dụ: main.cpp, index.html, app.py", text: $newItemName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Tạo") {
                workspace.createFile(named: newItemName, in: targetParentDir)
                newItemName = ""
                onCloseDrawer()
            }
            Button("Hủy", role: .cancel) { newItemName = "" }
        }
        .alert("Tạo Thư Mục Mới", isPresented: $showNewFolderAlert) {
            TextField("Tên thư mục", text: $newItemName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Tạo") {
                workspace.createFolder(named: newItemName, in: targetParentDir)
                newItemName = ""
            }
            Button("Hủy", role: .cancel) { newItemName = "" }
        }
        .alert("Đổi Tên", isPresented: Binding(
            get: { renameTargetURL != nil },
            set: { if !$0 { renameTargetURL = nil } }
        )) {
            TextField("Tên mới", text: $renameText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Lưu") {
                if let url = renameTargetURL {
                    workspace.renameItem(at: url, to: renameText)
                }
                renameTargetURL = nil
            }
            Button("Hủy", role: .cancel) { renameTargetURL = nil }
        }
        .alert("Tạo File Trên VPS (SFTP)", isPresented: $showNewRemoteFileAlert) {
            TextField("Ví dụ: server.cpp, app.py", text: $remoteNewName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Tạo & Mở") {
                let name = remoteNewName
                remoteNewName = ""
                Task {
                    if let localMirror = await sshService.createRemoteFile(named: name) {
                        workspace.openFile(at: localMirror)
                        onCloseDrawer()
                    }
                }
            }
            Button("Hủy", role: .cancel) { remoteNewName = "" }
        }
        .alert("Tạo Thư Mục Trên VPS", isPresented: $showNewRemoteFolderAlert) {
            TextField("Tên thư mục trên VPS", text: $remoteNewName)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Tạo") {
                let name = remoteNewName
                remoteNewName = ""
                Task { await sshService.createRemoteFolder(named: name) }
            }
            Button("Hủy", role: .cancel) { remoteNewName = "" }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let picked = urls.first {
                workspace.switchWorkspaceFolder(to: picked)
                liveServer.updateRootDirectory(picked)
            }
        }
        .sheet(isPresented: $showAddVPSSheet) {
            vpsEditorSheet()
        }
    }

    // MARK: - 1. Explorer Section
    @ViewBuilder
    private func explorerSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(workspace.rootURL.lastPathComponent.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: palette.accent))
                    .lineLimit(1)
                Spacer()
                Button {
                    targetParentDir = workspace.rootURL
                    newItemName = ""
                    showNewFileAlert = true
                } label: {
                    Image(systemName: "doc.badge.plus").font(.system(size: 12.5)).foregroundColor(Color(hex: palette.foreground))
                }
                Button {
                    targetParentDir = workspace.rootURL
                    newItemName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 12.5)).foregroundColor(Color(hex: palette.foreground))
                }
                Button {
                    workspace.reloadTree()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11.5)).foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(workspace.fileTree) { node in
                        FileNodeRow(
                            node: node,
                            depth: 0,
                            activeURL: workspace.activeTabID,
                            palette: palette,
                            onSelectFile: { url in
                                workspace.openFile(at: url)
                                onCloseDrawer()
                            },
                            onNewFileInDir: { dir in
                                targetParentDir = dir
                                newItemName = ""
                                showNewFileAlert = true
                            },
                            onNewFolderInDir: { dir in
                                targetParentDir = dir
                                newItemName = ""
                                showNewFolderAlert = true
                            },
                            onRename: { url in
                                renameText = url.lastPathComponent
                                renameTargetURL = url
                            },
                            onDelete: { url in
                                workspace.deleteItem(at: url)
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 2. Search Section
    @ViewBuilder
    private func searchSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: palette.gutterForeground))
                TextField("Tìm nội dung toàn dự án...", text: $workspace.searchQuery)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: workspace.searchQuery) { _, q in
                        workspace.performWorkspaceSearch(q)
                    }
            }
            .padding(7)
            .background(Color(hex: palette.editorBackground))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(workspace.searchResults.enumerated()), id: \.offset) { _, hit in
                        Button {
                            workspace.openFile(at: hit.url)
                            onCloseDrawer()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(workspace.relativePath(for: hit.url)):\(hit.line)")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: palette.accent))
                                Text(hit.preview)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(Color(hex: palette.foreground))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(Color(hex: palette.currentLineBackground))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    // MARK: - 3. Git & GitHub Source Control Section (Phase 2)
    @ViewBuilder
    private func gitSourceControlSection(palette: IDEColorPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !gitService.statusBanner.isEmpty {
                    Text(gitService.statusBanner)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: palette.accent))
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: palette.currentLineBackground))
                        .cornerRadius(6)
                }

                // Commit & Push Box
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Branch: \(gitService.currentBranch)", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: palette.foreground))
                        Spacer()
                        Button {
                            Task { await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService) }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        }
                    }

                    TextField("Commit message...", text: $commitMessageInput)
                        .font(.system(size: 12))
                        .padding(7)
                        .background(Color(hex: palette.editorBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(6)

                    HStack(spacing: 6) {
                        Button {
                            let msg = commitMessageInput
                            commitMessageInput = ""
                            Task {
                                await gitService.commitAll(message: msg, workspaceRoot: workspace.rootURL, sshService: sshService)
                            }
                        } label: {
                            Label("Commit All", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color(hex: palette.accent))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }

                        Button {
                            gitService.githubToken = githubTokenInput
                            let msg = commitMessageInput
                            Task {
                                if sshService.isConnected {
                                    let res = await sshService.executeCommandOnVPS("cd '\(sshService.currentRemoteDirectory)' && git push 2>&1")
                                    gitService.statusBanner = res
                                } else {
                                    await gitService.pushToGitHubREST(workspaceRoot: workspace.rootURL, commitMessage: msg)
                                }
                            }
                        } label: {
                            Label("Push", systemImage: "arrow.up.to.line")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.85))
                                .foregroundColor(.black)
                                .cornerRadius(6)
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Changed Files List
                Text("THAY ĐỔI (\(gitService.changedFiles.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: palette.gutterForeground))

                ForEach(gitService.changedFiles) { item in
                    HStack {
                        Text(item.statusBadge)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(item.statusBadge == "A" ? .green : (item.statusBadge == "D" ? .red : .yellow))
                            .frame(width: 16)
                        Button {
                            selectedGitDiffText = gitService.diffPreview(for: item.relativePath, workspaceRoot: workspace.rootURL)
                        } label: {
                            Text(item.relativePath)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundColor(Color(hex: palette.foreground))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            Task {
                                await gitService.discardChanges(for: item.relativePath, workspaceRoot: workspace.rootURL)
                                workspace.reloadTree()
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10.5))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 3)
                }

                if let diff = selectedGitDiffText {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Diff Preview").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: palette.accent))
                            Spacer()
                            Button("Ẩn") { selectedGitDiffText = nil }.font(.system(size: 10))
                        }
                        Text(diff)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: palette.foreground))
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Clone GitHub Repo + PAT Setup
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLONE TỪ GITHUB")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))

                    TextField("owner/repo hoặc link GitHub...", text: $cloneRepoInput)
                        .font(.system(size: 11.5))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(6)
                        .background(Color(hex: palette.editorBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(6)

                    SecureField("GitHub Token (cho Private Repo / Push)", text: $githubTokenInput)
                        .font(.system(size: 11.5))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(6)
                        .background(Color(hex: palette.editorBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(6)
                        .onChange(of: githubTokenInput) { _, val in
                            gitService.githubToken = val
                        }

                    Button {
                        let repoStr = cloneRepoInput
                        Task {
                            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            if let clonedURL = await gitService.cloneGitHubRepository(repoInput: repoStr, into: docs) {
                                workspace.switchWorkspaceFolder(to: clonedURL)
                                liveServer.updateRootDirectory(clonedURL)
                                cloneRepoInput = ""
                            }
                        }
                    } label: {
                        Label(gitService.isBusy ? "Đang tải..." : "Clone & Mở Project", systemImage: "icloud.and.arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(hex: palette.currentLineBackground))
                            .foregroundColor(Color(hex: palette.foreground))
                            .cornerRadius(6)
                    }
                    .disabled(gitService.isBusy || cloneRepoInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
        }
    }

    // MARK: - 4. Remote SSH, SFTP & Port Tunneling Section (Phase 3)
    @ViewBuilder
    private func remoteSSHSection(palette: IDEColorPalette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(sshService.statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(sshService.isConnected ? .green : Color(hex: palette.foreground))
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(6)

                // Saved Hosts + Add Button
                HStack {
                    Text("DANH SÁCH VPS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                    Spacer()
                    Button {
                        draftVPS = VPSHostProfile()
                        draftVPSPassword = ""
                        showAddVPSSheet = true
                    } label: {
                        Label("Thêm VPS", systemImage: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: palette.accent))
                    }
                }

                ForEach(sshService.savedProfiles) { prof in
                    let active = (sshService.connectedProfile?.id == prof.id)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prof.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: palette.foreground))
                            Text("\(prof.username)@\(prof.host):\(prof.port)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(hex: palette.gutterForeground))
                        }
                        Spacer()
                        if active {
                            Button("Ngắt") {
                                Task { await sshService.disconnect() }
                            }
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.red)
                        } else {
                            Button("Kết nối") {
                                Task { await sshService.connect(to: prof) }
                            }
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: palette.accent))
                            .foregroundColor(.white)
                            .cornerRadius(5)
                        }
                    }
                    .padding(7)
                    .background(Color(hex: palette.editorBackground))
                    .cornerRadius(7)
                    .contextMenu {
                        Button(role: .destructive) {
                            sshService.deleteProfile(prof)
                        } label: {
                            Label("Xóa VPS này", systemImage: "trash")
                        }
                    }
                }

                if sshService.isConnected {
                    Divider().overlay(Color.white.opacity(0.08))

                    // 1-Click Auto Provision Toolchain on VPS
                    Button {
                        isProvisioningVPS = true
                        Task {
                            let res = await sshService.provisionVPSToolchain()
                            provisionOutputText = res
                            isProvisioningVPS = false
                        }
                    } label: {
                        Label(
                            isProvisioningVPS ? "Đang cài g++/python3/node trên VPS..." : "⚡ 1-Click Cài C++/Python/Node cho VPS",
                            systemImage: "wrench.and.screwdriver.fill"
                        )
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.85))
                        .foregroundColor(.black)
                        .cornerRadius(6)
                    }
                    .disabled(isProvisioningVPS)

                    if let prov = provisionOutputText {
                        Text(prov)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.green)
                            .lineLimit(5)
                    }

                    // SSH Port Forwarding (VPS -> iPhone localhost -> Safari!)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SSH PORT FORWARDING (XEM WEB VPS TRÊN SAFARI)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))

                        HStack(spacing: 6) {
                            TextField("Cổng (vd: 3000)", text: $tunnelPortString)
                                .keyboardType(.numberPad)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(6)
                                .background(Color(hex: palette.editorBackground))
                                .foregroundColor(Color(hex: palette.foreground))
                                .cornerRadius(6)

                            Button("Forward") {
                                if let p = UInt16(tunnelPortString) {
                                    sshService.startLocalPortForward(localPort: p, remotePort: p)
                                    liveServer.updateBackgroundKeepAlive(enabled: true)
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        }

                        ForEach(sshService.activeTunnels) { t in
                            HStack {
                                Text("localhost:\(t.localPort) ⇄ VPS:\(t.remotePort)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Spacer()
                                Button("Safari") {
                                    if let u = URL(string: "http://localhost:\(t.localPort)") {
                                        UIApplication.shared.open(u)
                                    }
                                }
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)

                                Button {
                                    sshService.stopLocalPortForward(localPort: t.localPort)
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                }
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    // Live SFTP File Browser
                    HStack {
                        Button {
                            Task { await sshService.navigateUpRemoteDirectory() }
                        } label: {
                            Image(systemName: "arrow.up.doc").font(.system(size: 12)).foregroundColor(Color(hex: palette.accent))
                        }
                        Text(sshService.currentRemoteDirectory)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: palette.foreground))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            remoteNewName = ""
                            showNewRemoteFileAlert = true
                        } label: {
                            Image(systemName: "doc.badge.plus").font(.system(size: 12)).foregroundColor(Color(hex: palette.foreground))
                        }
                        Button {
                            remoteNewName = ""
                            showNewRemoteFolderAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus").font(.system(size: 12)).foregroundColor(Color(hex: palette.foreground))
                        }
                        Button {
                            Task { await sshService.refreshRemoteDirectory() }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11.5)).foregroundColor(Color(hex: palette.gutterForeground))
                        }
                    }

                    ForEach(sshService.remoteEntries) { entry in
                        Button {
                            if entry.isDirectory {
                                Task { await sshService.refreshRemoteDirectory(at: entry.fullPath) }
                            } else {
                                Task {
                                    if let localMirror = await sshService.downloadRemoteFileToLocalCache(remotePath: entry.fullPath) {
                                        workspace.openFile(at: localMirror)
                                        onCloseDrawer()
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                    .font(.system(size: 12))
                                    .foregroundColor(entry.isDirectory ? Color(hex: palette.accent) : .cyan)
                                Text(entry.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: palette.foreground))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await sshService.deleteRemoteItem(entry) }
                            } label: {
                                Label("Xóa trên VPS", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - 5. Open VSX Extensions & Snippets Section (Phase 4)
    @ViewBuilder
    private func extensionsMarketplaceSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Tìm trên Open VSX (vd: dracula, catppuccin, snippets)...", text: $openVSXQuery)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        Task { await extStore.searchOpenVSX(query: openVSXQuery) }
                    }
                Button {
                    Task { await extStore.searchOpenVSX(query: openVSXQuery) }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: palette.accent))
                }
            }
            .padding(7)
            .background(Color(hex: palette.editorBackground))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Text(extStore.storeMessage)
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: palette.gutterForeground))
                .padding(.horizontal, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Quick Snippets Bar
                    Text("CHÈN NHANH CODE SNIPPETS / EMMET")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(extStore.snippets.prefix(16)) { snip in
                                Button {
                                    onInsertSnippet(snip.body)
                                    onCloseDrawer()
                                } label: {
                                    Text(snip.prefix)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: palette.currentLineBackground))
                                        .foregroundColor(Color(hex: palette.accent))
                                        .cornerRadius(5)
                                }
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    Text("CHỢ EXTENSION OPEN VSX (.VSIX)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(hex: palette.gutterForeground))

                    if extStore.isSearching {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Đang tìm trên open-vsx.org...").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }

                    ForEach(extStore.searchResults) { ext in
                        let isInstalled = extStore.installedExtensionIDs.contains(ext.id)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ext.displayName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color(hex: palette.foreground))
                                        .lineLimit(1)
                                    Text("\(ext.namespace) • v\(ext.version)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color(hex: palette.gutterForeground))
                                }
                                Spacer()
                                Button {
                                    Task { await extStore.installVSIXExtension(ext, into: preferences) }
                                } label: {
                                    if extStore.installingID == ext.id {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Text(isInstalled ? "Đã cài" : "Cài .vsix")
                                            .font(.system(size: 10.5, weight: .bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(isInstalled ? Color.green.opacity(0.25) : Color(hex: palette.accent))
                                            .foregroundColor(isInstalled ? .green : .white)
                                            .cornerRadius(5)
                                    }
                                }
                                .disabled(extStore.installingID != nil)
                            }
                            if !ext.description.isEmpty {
                                Text(ext.description)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                                    .lineLimit(2)
                            }
                        }
                        .padding(8)
                        .background(Color(hex: palette.editorBackground))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func vpsEditorSheet() -> some View {
        NavigationStack {
            Form {
                Section("Thông tin Máy Chủ VPS (SSH & SFTP)") {
                    TextField("Tên gợi nhớ (vd: Ubuntu VPS)", text: $draftVPS.label)
                    TextField("IP hoặc Domain (vd: 103.x.x.x)", text: $draftVPS.host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port SSH", value: $draftVPS.port, format: .number)
                        .keyboardType(.numberPad)
                    TextField("Username (vd: root, ubuntu)", text: $draftVPS.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Thư mục mặc định (vd: . hoặc /root)", text: $draftVPS.initialRemotePath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Phương thức Xác Thực (Lưu trong iOS Keychain)") {
                    Picker("Loại xác thực", selection: $draftVPS.authKind) {
                        ForEach(VPSHostProfile.AuthKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }

                    if draftVPS.authKind == .password {
                        SecureField("Mật khẩu SSH", text: $draftVPSPassword)
                    } else {
                        let keyInfo = KeychainVault.generateOrLoadDeviceEd25519Key()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Public Key Ed25519 của thiết bị (Dán vào ~/.ssh/authorized_keys trên VPS):")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text(keyInfo.publicKeyAuthorizedLine)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(3)
                            Button {
                                UIPasteboard.general.string = keyInfo.publicKeyAuthorizedLine
                            } label: {
                                Label("Copy SSH Public Key", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Thêm Kết Nối VPS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showAddVPSSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu & Kết nối") {
                        let saved = draftVPS
                        let pwd = draftVPSPassword
                        sshService.saveOrUpdateProfile(saved, password: pwd)
                        showAddVPSSheet = false
                        Task { await sshService.connect(to: saved, passwordOverride: pwd.isEmpty ? nil : pwd) }
                    }
                }
            }
        }
    }
}

private struct FileNodeRow: View {
    let node: FileNode
    let depth: Int
    let activeURL: URL?
    let palette: IDEColorPalette
    let onSelectFile: (URL) -> Void
    let onNewFileInDir: (URL) -> Void
    let onNewFolderInDir: (URL) -> Void
    let onRename: (URL) -> Void
    let onDelete: (URL) -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } else {
                    onSelectFile(node.url)
                }
            } label: {
                HStack(spacing: 6) {
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .frame(width: 12)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: palette.accent))
                    } else {
                        Spacer().frame(width: 12)
                        Image(systemName: node.language.systemIcon)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: palette.accent))
                    }

                    Text(node.name)
                        .font(.system(size: 12.5, weight: activeURL == node.url ? .bold : .regular))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, CGFloat(depth * 13))
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
                .background(activeURL == node.url ? Color(hex: palette.currentLineBackground) : Color.clear)
                .cornerRadius(6)
            }
            .contextMenu {
                if node.isDirectory {
                    Button { onNewFileInDir(node.url) } label: { Label("Tạo File trong này", systemImage: "doc.badge.plus") }
                    Button { onNewFolderInDir(node.url) } label: { Label("Tạo Thư mục con", systemImage: "folder.badge.plus") }
                }
                Button { onRename(node.url) } label: { Label("Đổi tên", systemImage: "pencil") }
                Button(role: .destructive) { onDelete(node.url) } label: { Label("Xóa", systemImage: "trash") }
            }

            if node.isDirectory, isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        activeURL: activeURL,
                        palette: palette,
                        onSelectFile: onSelectFile,
                        onNewFileInDir: onNewFileInDir,
                        onNewFolderInDir: onNewFolderInDir,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
            }
        }
    }
}
