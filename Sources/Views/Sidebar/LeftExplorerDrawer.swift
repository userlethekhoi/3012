import SwiftUI
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
        case .explorer: return "doc.on.doc"
        case .search: return "magnifyingglass"
        case .git: return "arrow.triangle.branch"
        case .ssh: return "server.rack"
        case .extensions: return "square.grid.2x2"
        }
    }

    public var title: String {
        switch self {
        case .explorer: return L10n.tr("TRÌNH DUYỆT FILE", "EXPLORER", zh: "文件管理器", ja: "エクスプローラー", ko: "탐색기", ru: "ПРОВОДНИК", es: "EXPLORADOR")
        case .search: return L10n.tr("TÌM KIẾM", "SEARCH", zh: "搜索", ja: "検索", ko: "검색", ru: "ПОИСК", es: "BUSCAR")
        case .git: return L10n.tr("QUẢN LÝ NGUỒN (GIT)", "SOURCE CONTROL", zh: "源代码管理", ja: "ソース管理", ko: "소스 제어", ru: "СИСТЕМА ВЕРСИЙ", es: "CONTROL DE CÓDIGO")
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
    @ObservedObject var timelineService: FileTimelineAndArchiveService
    var pcSync: PCSyncService? = nil
    var onInsertSnippet: (String) -> Void
    var onOpenTheosBuilder: () -> Void
    var onOpenXtoolBuilder: () -> Void
    var onRequestOpenSingleFile: (() -> Void)?
    var onRequestOpenFolder: (() -> Void)?
    var onRequestImportZip: (() -> Void)?
    var onOpenPCSyncSheet: () -> Void = {}
    var onOpenLiveShareSheet: () -> Void = {}
    var onOpenPowerToolsSheet: () -> Void = {}
    var onOpenGitHubSheet: (Int) -> Void = { _ in }
    var onJumpToSearchHit: ((URL, Int) -> Void)? = nil
    var onOpenSettings: () -> Void
    var onCloseDrawer: () -> Void

    @ObservedObject private var githubAuth = GitHubAccountService.shared

    @State private var activeActivity: SidebarActivityTab = .explorer
    @State private var showNewFileAlert: Bool = false
    @State private var showNewFolderAlert: Bool = false
    @State private var showNewProjectAlert: Bool = false
    @State private var newItemName: String = ""
    @State private var newProjectName: String = ""
    @State private var targetParentDir: URL?
    @State private var renameTargetURL: URL?
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var exportedZipURL: URL? = nil

    // Search & Replace UI state
    @State private var showSearchReplaceInput: Bool = false
    @State private var workspaceReplaceText: String = ""
    @State private var searchCaseSensitive: Bool = false

    // Git UI state
    @State private var commitMessageInput: String = ""
    @State private var cloneRepoInput: String = ""
    @State private var selectedGitDiffText: String? = nil
    @State private var remoteBranches: [String] = []
    @State private var isLoadingBranches: Bool = false
    @State private var showCreateBranchAlert: Bool = false
    @State private var newBranchNameInput: String = ""

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
    @State private var cachedSSHPublicKey: String = ""

    // Extensions UI state
    @State private var openVSXQuery: String = "theme"

    public init(
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        liveServer: LiveServerService,
        gitService: GitService,
        sshService: SSHWorkspaceService,
        extStore: ExtensionStoreService,
        timelineService: FileTimelineAndArchiveService,
        pcSync: PCSyncService? = nil,
        onInsertSnippet: @escaping (String) -> Void,
        onOpenTheosBuilder: @escaping () -> Void = {},
        onOpenXtoolBuilder: @escaping () -> Void = {},
        onRequestOpenSingleFile: (() -> Void)? = nil,
        onRequestOpenFolder: (() -> Void)? = nil,
        onRequestImportZip: (() -> Void)? = nil,
        onOpenPCSyncSheet: @escaping () -> Void = {},
        onOpenLiveShareSheet: @escaping () -> Void = {},
        onOpenPowerToolsSheet: @escaping () -> Void = {},
        onOpenGitHubSheet: @escaping (Int) -> Void = { _ in },
        onJumpToSearchHit: ((URL, Int) -> Void)? = nil,
        onOpenSettings: @escaping () -> Void,
        onCloseDrawer: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.preferences = preferences
        self.liveServer = liveServer
        self.gitService = gitService
        self.sshService = sshService
        self.extStore = extStore
        self.timelineService = timelineService
        self.pcSync = pcSync
        self.onInsertSnippet = onInsertSnippet
        self.onOpenTheosBuilder = onOpenTheosBuilder
        self.onOpenXtoolBuilder = onOpenXtoolBuilder
        self.onRequestOpenSingleFile = onRequestOpenSingleFile
        self.onRequestOpenFolder = onRequestOpenFolder
        self.onRequestImportZip = onRequestImportZip
        self.onOpenPCSyncSheet = onOpenPCSyncSheet
        self.onOpenLiveShareSheet = onOpenLiveShareSheet
        self.onOpenPowerToolsSheet = onOpenPowerToolsSheet
        self.onOpenGitHubSheet = onOpenGitHubSheet
        self.onJumpToSearchHit = onJumpToSearchHit
        self.onOpenSettings = onOpenSettings
        self.onCloseDrawer = onCloseDrawer
    }

    private func presentLocalPicker(_ mode: WorkspaceDocumentPickerMode) {
        onCloseDrawer()
        NativeDocumentPickerPresenter.shared.presentResourcePicker(
            mode: mode,
            initialDelay: 0.28,
            onPickResources: { resources in
                switch mode {
                case .singleFile, .folderFilesCopy:
                    workspace.openExternalSingleFiles(from: resources)
                    liveServer.updateRootDirectory(workspace.rootURL)
                case .folder:
                    if let first = resources.first {
                        workspace.switchWorkspaceFolder(to: first.url, hasSecurityScope: first.hasSecurityScope)
                        liveServer.updateRootDirectory(workspace.rootURL)
                    }
                case .zip:
                    if let first = resources.first,
                       workspace.importAndOpenZip(from: first.url, hasSecurityScope: first.hasSecurityScope) {
                        liveServer.updateRootDirectory(workspace.rootURL)
                    }
                case .themeJSON:
                    break
                }
            }
        )
    }

    private func triggerOpenSingleFile() {
        onCloseDrawer()
        if let onRequestOpenSingleFile {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                onRequestOpenSingleFile()
            }
        } else {
            presentLocalPicker(.singleFile)
        }
    }

    private func triggerOpenFolder() {
        onCloseDrawer()
        if let onRequestOpenFolder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                onRequestOpenFolder()
            }
        } else {
            presentLocalPicker(.folder)
        }
    }

    private func triggerImportZip() {
        onCloseDrawer()
        if let onRequestImportZip {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                onRequestImportZip()
            }
        } else {
            presentLocalPicker(.zip)
        }
    }

    @ViewBuilder
    private func starterTemplatesSubmenu() -> some View {
        Menu {
            Button {
                _ = workspace.scaffoldStarterTemplate(kind: .modernWebLanding)
                liveServer.updateRootDirectory(workspace.rootURL)
            } label: {
                Label("Web HTML/CSS/JS Live", systemImage: "globe")
            }
            Button {
                _ = workspace.scaffoldStarterTemplate(kind: .cppCompetitive)
                liveServer.updateRootDirectory(workspace.rootURL)
            } label: {
                Label("C++20 Competitive", systemImage: "cpu")
            }
            Button {
                _ = workspace.scaffoldStarterTemplate(kind: .pythonAutomation)
                liveServer.updateRootDirectory(workspace.rootURL)
            } label: {
                Label("Python 3.12 Automation", systemImage: "terminal")
            }
            Button {
                _ = workspace.scaffoldStarterTemplate(kind: .markdownDocs)
                liveServer.updateRootDirectory(workspace.rootURL)
            } label: {
                Label("Markdown + Mermaid Docs", systemImage: "doc.richtext")
            }
        } label: {
            Label(preferences.tr("Tạo từ Mẫu (Starter Templates)", "Starter Templates"), systemImage: "rectangle.stack.badge.plus")
        }
    }

    public var body: some View {
        let palette = preferences.activePalette

        HStack(spacing: 0) {
            // VS Code Slim Activity Bar (42pt)
            VStack(spacing: 12) {
                Button {
                    onOpenSettings()
                } label: {
                    IDECodeMarkVector(size: 26)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.bottom, 2)

                ForEach(SidebarActivityTab.allCases) { tab in
                    Button {
                        activeActivity = tab
                        if tab == .git {
                            Task {
                                await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService)
                                if !sshService.isConnected && !gitService.remoteOriginURL.isEmpty {
                                    await gitService.refreshRemoteDivergence(workspaceRoot: workspace.rootURL)
                                }
                            }
                        } else if tab == .extensions && extStore.searchResults.isEmpty {
                            Task { await extStore.searchOpenVSX(query: openVSXQuery) }
                        }
                    } label: {
                        ZStack(alignment: .leading) {
                            if activeActivity == tab {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(hex: palette.accent))
                                    .frame(width: 2.5, height: 20)
                            }

                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 15.5, weight: activeActivity == tab ? .semibold : .regular))
                                    .foregroundColor(activeActivity == tab ? Color(hex: palette.foreground) : Color(hex: palette.gutterForeground))
                                    .frame(width: 40, height: 34)

                                if tab == .ssh && sshService.isConnected {
                                    Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: -5, y: 3)
                                } else if tab == .git && workspace.totalDecoratedFilesCount > 0 {
                                    Circle().fill(Color(hex: palette.accent)).frame(width: 7, height: 7).offset(x: -5, y: 3)
                                }
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .symbolRenderingMode(.hierarchical)
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

                // Bottom Status Strip (Open Folder / Import-Export .zip / Go Live)
                HStack(spacing: 6) {
                    Menu {
                        Button {
                            triggerOpenFolder()
                        } label: {
                            Label(preferences.tr("Mở Thư mục trên máy (Folder)", "Open Device Folder (Folder)"), systemImage: "folder")
                        }
                        Button {
                            triggerImportZip()
                        } label: {
                            Label(preferences.tr("Nhập & Tự giải nén .zip", "Import & Auto-Extract .zip"), systemImage: "arrow.down.doc")
                        }
                        Button {
                            newProjectName = ""
                            showNewProjectAlert = true
                        } label: {
                            Label(preferences.tr("Tạo Project Mới...", "New Project Workspace..."), systemImage: "folder.badge.plus")
                        }
                        starterTemplatesSubmenu()
                        Button {
                            exportedZipURL = timelineService.exportProjectZip(workspaceRoot: workspace.rootURL)
                        } label: {
                            Label(preferences.tr("Đóng gói Dự án ra .zip", "Export Project as .zip"), systemImage: "doc.zipper")
                        }
                        Divider()
                        Button {
                            onOpenTheosBuilder()
                        } label: {
                            Label(preferences.tr("Theos Tweak / Mod Menu (.deb/.dylib)", "Theos Tweak / Mod Menu (.deb/.dylib)"), systemImage: "hammer.fill")
                        }
                        Button {
                            onOpenXtoolBuilder()
                        } label: {
                            Label(preferences.tr("xtool Studio (.ipa / Dylib Injector)", "xtool Studio (.ipa / Dylib Injector)"), systemImage: "cube.transparent.fill")
                        }
                    } label: {
                        Label(preferences.tr("Dự án / .zip", "Project / .zip"), systemImage: "folder.badge.plus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Color(hex: palette.foreground))
                    }

                    if let zipURL = exportedZipURL {
                        CompatibleFileShareButton(item: zipURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(Color(hex: palette.accent))
                        }
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
        .compatibleTextInputAlert(
            preferences.tr("Tạo File Mới", "New File"),
            isPresented: $showNewFileAlert,
            text: $newItemName,
            placeholder: preferences.tr("Ví dụ: main.cpp, index.html, app.py", "e.g. main.cpp, index.html, app.py"),
            confirmTitle: preferences.tr("Tạo", "Create"),
            cancelTitle: preferences.tr("Hủy", "Cancel")
        ) {
            let created = workspace.createFile(named: newItemName, in: targetParentDir)
            newItemName = ""
            targetParentDir = nil
            if created != nil {
                onCloseDrawer()
            }
        }
        .compatibleTextInputAlert(
            preferences.tr("Tạo Thư Mục Mới", "New Folder"),
            isPresented: $showNewFolderAlert,
            text: $newItemName,
            placeholder: preferences.tr("Tên thư mục", "Folder name"),
            confirmTitle: preferences.tr("Tạo", "Create"),
            cancelTitle: preferences.tr("Hủy", "Cancel")
        ) {
            workspace.createFolder(named: newItemName, in: targetParentDir)
            newItemName = ""
            targetParentDir = nil
        }
        .compatibleTextInputAlert(
            preferences.tr("Đổi Tên", "Rename"),
            isPresented: $showRenameAlert,
            text: $renameText,
            placeholder: preferences.tr("Tên mới", "New name"),
            confirmTitle: preferences.tr("Lưu", "Save"),
            cancelTitle: preferences.tr("Hủy", "Cancel")
        ) {
            if let url = renameTargetURL {
                workspace.renameItem(at: url, to: renameText)
            }
            renameTargetURL = nil
            showRenameAlert = false
        }
        .onChange(of: showRenameAlert) { presented in
            if !presented {
                DispatchQueue.main.async {
                    renameTargetURL = nil
                }
            }
        }
        .compatibleTextInputAlert(
            "Tạo File Trên VPS (SFTP)",
            isPresented: $showNewRemoteFileAlert,
            text: $remoteNewName,
            placeholder: "Ví dụ: server.cpp, app.py",
            confirmTitle: "Tạo & Mở",
            cancelTitle: "Hủy"
        ) {
            let name = remoteNewName
            remoteNewName = ""
            Task {
                if let localMirror = await sshService.createRemoteFile(named: name) {
                    workspace.openFile(at: localMirror)
                    onCloseDrawer()
                }
            }
        }
        .compatibleTextInputAlert(
            "Tạo Thư Mục Trên VPS",
            isPresented: $showNewRemoteFolderAlert,
            text: $remoteNewName,
            placeholder: "Tên thư mục trên VPS",
            confirmTitle: "Tạo",
            cancelTitle: "Hủy"
        ) {
            let name = remoteNewName
            remoteNewName = ""
            Task { await sshService.createRemoteFolder(named: name) }
        }
        .compatibleTextInputAlert(
            preferences.tr("Tạo Project Mới", "New Project Workspace"),
            isPresented: $showNewProjectAlert,
            text: $newProjectName,
            placeholder: preferences.tr("Tên dự án (ví dụ: MyWebApp)", "Project name (e.g. MyWebApp)"),
            confirmTitle: preferences.tr("Tạo & Mở", "Create & Open"),
            cancelTitle: preferences.tr("Hủy", "Cancel")
        ) {
            workspace.createNewProjectWorkspace(named: newProjectName)
            liveServer.updateRootDirectory(workspace.rootURL)
            newProjectName = ""
        }
        .compatibleTextInputAlert(
            preferences.tr("Tạo Nhánh Mới (Git Branch)", "Create New Git Branch"),
            isPresented: $showCreateBranchAlert,
            text: $newBranchNameInput,
            placeholder: "feature/my-feature",
            confirmTitle: preferences.tr("Tạo & Chuyển", "Create & Switch"),
            cancelTitle: preferences.tr("Hủy", "Cancel")
        ) {
            let branch = newBranchNameInput
            newBranchNameInput = ""
            Task {
                _ = await gitService.createAndCheckoutBranch(name: branch, workspaceRoot: workspace.rootURL)
            }
        }
        .sheet(isPresented: $showAddVPSSheet) {
            vpsEditorSheet()
                .onAppear {
                    cachedSSHPublicKey = KeychainVault.generateOrLoadDeviceEd25519Key().publicKeyAuthorizedLine
                }
        }
    }

    // MARK: - 1. Explorer Section
    @ViewBuilder
    private func explorerSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 0) {
            // Project Switcher + Quick File/Folder Actions
            HStack(spacing: 6) {
                Menu {
                    if !workspace.availableWorkspaces.isEmpty {
                        Section(preferences.tr("Dự án trên máy", "Device Projects")) {
                            ForEach(workspace.availableWorkspaces, id: \.self) { folderURL in
                                Button {
                                    workspace.switchWorkspaceFolder(to: folderURL)
                                    liveServer.updateRootDirectory(workspace.rootURL)
                                } label: {
                                    if folderURL.standardizedFileURL == workspace.rootURL.standardizedFileURL {
                                        Label(folderURL.lastPathComponent, systemImage: "checkmark")
                                    } else {
                                        Label(folderURL.lastPathComponent, systemImage: "folder")
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                    Button {
                        triggerOpenSingleFile()
                    } label: {
                        Label(preferences.tr("Mở File lẻ trên máy (File)...", "Open File on Device (File)..."), systemImage: "arrow.up.doc")
                    }
                    Button {
                        triggerOpenFolder()
                    } label: {
                        Label(preferences.tr("Mở Thư mục trên máy (Folder)...", "Open Folder on Device (Folder)..."), systemImage: "folder.badge.plus")
                    }
                    Button {
                        triggerImportZip()
                    } label: {
                        Label(preferences.tr("Nhập & Tự giải nén .zip...", "Import & Auto-Extract .zip..."), systemImage: "doc.zipper")
                    }
                    Button {
                        newProjectName = ""
                        showNewProjectAlert = true
                    } label: {
                        Label(preferences.tr("Tạo Project Mới...", "Create New Project..."), systemImage: "plus.rectangle.on.folder")
                    }
                    starterTemplatesSubmenu()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: palette.accent))
                        Text(workspace.workspaceDisplayName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: palette.accent))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: palette.currentLineBackground))
                    .cornerRadius(5)
                }

                Spacer()

                if workspace.totalDecoratedFilesCount > 0 {
                    Button {
                        workspace.resetDiffBaselineToCurrentDisk()
                    } label: {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                    }
                    .help("Đặt trạng thái hiện tại làm mốc chuẩn (Xóa dấu U/A/M/D)")
                }
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
                    onOpenTheosBuilder()
                } label: {
                    Image(systemName: "hammer").font(.system(size: 12)).foregroundColor(Color(hex: palette.accent))
                }
                Button {
                    onOpenXtoolBuilder()
                } label: {
                    Image(systemName: "cube.transparent").font(.system(size: 12)).foregroundColor(.blue)
                }
                Button {
                    workspace.reloadTree()
                    workspace.refreshAvailableWorkspaces()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11.5)).foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Prominent 1-Tap Open File / Open Folder / Import Zip Strip
            HStack(spacing: 5) {
                Button {
                    triggerOpenSingleFile()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(preferences.tr("Mở File", "Open File"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(hex: palette.accent).opacity(0.16))
                    .foregroundColor(Color(hex: palette.accent))
                    .cornerRadius(6)
                }

                Button {
                    triggerOpenFolder()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .semibold))
                        Text(preferences.tr("Folder", "Folder"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(6)
                }

                Button {
                    triggerImportZip()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 10, weight: .semibold))
                        Text(preferences.tr(".zip", ".zip"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)

            // Quick Strip: PC Sync (Wi-Fi/4G) + Share :5500 + Developer Power Tools
            HStack(spacing: 5) {
                Button {
                    onCloseDrawer()
                    onOpenPCSyncSheet()
                } label: {
                    HStack(spacing: 4) {
                        if pcSync?.isConnected == true {
                            Circle().fill(Color.green).frame(width: 5.5, height: 5.5)
                        } else {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        Text(pcSync?.isConnected == true
                             ? (pcSync?.transportMode == .wifiLAN ? "Wi-Fi" : "4G/5G")
                             : "PC Sync")
                            .font(.system(size: 9.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4.5)
                    .background((pcSync?.isConnected == true) ? Color.green.opacity(0.18) : Color(hex: palette.currentLineBackground))
                    .foregroundColor((pcSync?.isConnected == true) ? .green : Color(hex: palette.foreground))
                    .cornerRadius(6)
                }

                Button {
                    onCloseDrawer()
                    onOpenLiveShareSheet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(liveServer.isShareLinkEnabled ? "Share (\(liveServer.sharedViewerCount))" : "Share :\(liveServer.port)")
                            .font(.system(size: 9.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4.5)
                    .background(liveServer.isShareLinkEnabled ? Color.green.opacity(0.18) : Color(hex: palette.currentLineBackground))
                    .foregroundColor(liveServer.isShareLinkEnabled ? .green : Color(hex: palette.foreground))
                    .cornerRadius(6)
                }

                Button {
                    onCloseDrawer()
                    onOpenPowerToolsSheet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Tools")
                            .font(.system(size: 9.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4.5)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.accent))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            if let banner = workspace.statusBannerMessage, !banner.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(.green)
                    Text(banner)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        workspace.statusBannerMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.14))
                .cornerRadius(6)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(workspace.fileTree) { node in
                        FileNodeRow(
                            node: node,
                            depth: 0,
                            workspace: workspace,
                            activeURL: workspace.activeTabID,
                            palette: palette,
                            onSelectFile: { url in
                                if url.pathExtension.lowercased() == "zip" {
                                    workspace.extractZipAtURL(url)
                                } else {
                                    workspace.openFile(at: url)
                                    onCloseDrawer()
                                }
                            },
                            onExtractZip: { url in
                                workspace.extractZipAtURL(url)
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
                                showRenameAlert = true
                            },
                            onDelete: { url in
                                workspace.deleteItem(at: url)
                            },
                            onRestoreDeleted: { url in
                                workspace.restoreDeletedFile(at: url)
                            },
                            onDismissDeleted: { url in
                                workspace.dismissDeletedGhost(at: url)
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - 2. Search & Replace Section
    @ViewBuilder
    private func searchSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: palette.gutterForeground))
                TextField(preferences.tr("Tìm nội dung toàn dự án...", "Search across workspace..."), text: $workspace.searchQuery)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: workspace.searchQuery) { q in
                        workspace.performWorkspaceSearch(q, caseSensitive: searchCaseSensitive)
                    }

                Button {
                    searchCaseSensitive.toggle()
                    workspace.performWorkspaceSearch(workspace.searchQuery, caseSensitive: searchCaseSensitive)
                } label: {
                    Text("Aa")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(searchCaseSensitive ? Color(hex: palette.accent) : Color(hex: palette.currentLineBackground))
                        .foregroundColor(searchCaseSensitive ? .white : Color(hex: palette.gutterForeground))
                        .cornerRadius(4)
                }

                Button {
                    showSearchReplaceInput.toggle()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(showSearchReplaceInput ? Color(hex: palette.accent).opacity(0.22) : Color(hex: palette.currentLineBackground))
                        .foregroundColor(showSearchReplaceInput ? Color(hex: palette.accent) : Color(hex: palette.gutterForeground))
                        .cornerRadius(4)
                }
            }
            .padding(7)
            .background(Color(hex: palette.editorBackground))
            .cornerRadius(7)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if showSearchReplaceInput {
                VStack(spacing: 6) {
                    TextField(preferences.tr("Thay thế bằng...", "Replace with..."), text: $workspaceReplaceText)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: palette.foreground))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(7)
                        .background(Color(hex: palette.editorBackground))
                        .cornerRadius(7)

                    Button {
                        let res = workspace.performWorkspaceReplace(
                            query: workspace.searchQuery,
                            replacement: workspaceReplaceText,
                            caseSensitive: searchCaseSensitive
                        )
                        workspace.statusBannerMessage = preferences.tr(
                            "Đã thay thế \(res.replacements) vị trí trong \(res.filesUpdated) file",
                            "Replaced \(res.replacements) occurrences in \(res.filesUpdated) file(s)"
                        )
                    } label: {
                        Label(preferences.tr("Thay thế toàn dự án", "Replace All in Workspace"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color(hex: palette.accent))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .disabled(workspace.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 10)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(workspace.searchResults.enumerated()), id: \.offset) { _, hit in
                        Button {
                            if let onJumpToSearchHit {
                                onJumpToSearchHit(hit.url, hit.line)
                            } else {
                                workspace.openFile(at: hit.url)
                                onCloseDrawer()
                            }
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
                // GitHub Account Status & Quick Hub
                VStack(alignment: .leading, spacing: 6) {
                    if let acc = githubAuth.activeAccount {
                        HStack(spacing: 8) {
                            Image(systemName: acc.hasPrivateRepoAccess ? "checkmark.shield.fill" : "person.crop.circle.badge.checkmark")
                                .font(.system(size: 15))
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(acc.login)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(hex: palette.foreground))
                                Text(acc.hasPrivateRepoAccess
                                     ? preferences.tr("Private & Public Repo • \(acc.scopesSummary)", "Private & Public Repos • \(acc.scopesSummary)")
                                     : preferences.tr("Public Repo only (\(acc.scopesSummary))", "Public Repos only (\(acc.scopesSummary))"))
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.green)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                onOpenGitHubSheet(0)
                            } label: {
                                Text(preferences.tr("Đổi", "Switch"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: palette.editorBackground))
                                    .foregroundColor(Color(hex: palette.foreground))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 6) {
                            Button {
                                onOpenGitHubSheet(1)
                            } label: {
                                Label(preferences.tr("Kho Repo", "Repos"), systemImage: "folder.badge.person.crop")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.22))
                                    .foregroundColor(.purple)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            Button {
                                onOpenGitHubSheet(2)
                            } label: {
                                Label(preferences.tr("Publish / PR", "Publish / PR"), systemImage: "arrow.up.forward.app")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: palette.editorBackground))
                                    .foregroundColor(Color(hex: palette.accent))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button {
                            onOpenGitHubSheet(0)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(preferences.tr("Kết nối Tài khoản GitHub", "Connect GitHub Account"))
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(Color(hex: palette.foreground))
                                    Text(preferences.tr("1-chạm để đọc Private Repo, Pull & Push", "1-tap for Private Repos, Pull & Push"))
                                        .font(.system(size: 9.5))
                                        .foregroundColor(Color(hex: palette.gutterForeground))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: palette.gutterForeground))
                            }
                            .padding(8)
                            .background(Color.purple.opacity(0.14))
                            .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(Color(hex: palette.currentLineBackground))
                .cornerRadius(7)

                if !gitService.statusBanner.isEmpty {
                    Text(gitService.statusBanner)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: palette.accent))
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: palette.currentLineBackground))
                        .cornerRadius(6)
                }

                // Commit, Pull & Push Box
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Menu {
                            if !remoteBranches.isEmpty {
                                Section(preferences.tr("Nhánh GitHub Remote", "GitHub Remote Branches")) {
                                    ForEach(remoteBranches, id: \.self) { branch in
                                        Button {
                                            gitService.selectBranch(branch, workspaceRoot: workspace.rootURL)
                                        } label: {
                                            if branch == gitService.currentBranch {
                                                Label(branch, systemImage: "checkmark")
                                            } else {
                                                Text(branch)
                                            }
                                        }
                                    }
                                }
                                Divider()
                            }
                            Button {
                                isLoadingBranches = true
                                Task {
                                    remoteBranches = await gitService.fetchRemoteBranches()
                                    isLoadingBranches = false
                                }
                            } label: {
                                Label(preferences.tr("Tải danh sách Branch từ GitHub", "Fetch Branches from GitHub"), systemImage: "arrow.clockwise")
                            }
                            Button {
                                newBranchNameInput = ""
                                showCreateBranchAlert = true
                            } label: {
                                Label(preferences.tr("Tạo Branch mới...", "Create New Branch..."), systemImage: "plus.circle")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Label("Branch: \(gitService.currentBranch)", systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: palette.foreground))
                                if isLoadingBranches {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(Color(hex: palette.gutterForeground))
                                }
                            }
                        }

                        Spacer()

                        if gitService.aheadCount > 0 || gitService.behindCount > 0 {
                            HStack(spacing: 4) {
                                if gitService.aheadCount > 0 {
                                    Text("↑\(gitService.aheadCount)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                                if gitService.behindCount > 0 {
                                    Text("↓\(gitService.behindCount)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                        }

                        Button {
                            Task {
                                await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService)
                                if !sshService.isConnected && !gitService.remoteOriginURL.isEmpty {
                                    await gitService.refreshRemoteDivergence(workspaceRoot: workspace.rootURL)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11))
                        }
                    }

                    if !gitService.remoteOriginURL.isEmpty {
                        Text(gitService.remoteOriginURL)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    TextField("Commit message...", text: $commitMessageInput)
                        .font(.system(size: 12))
                        .padding(7)
                        .background(Color(hex: palette.editorBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(6)

                    HStack(spacing: 5) {
                        Button {
                            let msg = commitMessageInput
                            commitMessageInput = ""
                            workspace.saveAllTabs()
                            Task {
                                await gitService.commitAll(message: msg, workspaceRoot: workspace.rootURL, sshService: sshService)
                                workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                            }
                        } label: {
                            Label("Commit All", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color(hex: palette.accent))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                if sshService.isConnected {
                                    let res = await sshService.executeGitCommandOnVPS(
                                        ["pull", "--rebase"],
                                        in: sshService.currentRemoteDirectory,
                                        githubToken: githubAuth.activeToken
                                    )
                                    gitService.statusBanner = res.output
                                } else {
                                    let ok = await gitService.pullFromGitHub(into: workspace.rootURL)
                                    if ok {
                                        workspace.reloadTree()
                                        workspace.reloadOpenTabsFromDisk()
                                        workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                                    }
                                }
                            }
                        } label: {
                            Label("Pull", systemImage: "icloud.and.arrow.down")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(hex: palette.currentLineBackground))
                                .foregroundColor(Color(hex: palette.foreground))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button {
                            let msg = commitMessageInput
                            workspace.saveAllTabs()
                            Task {
                                if sshService.isConnected {
                                    let escapedDir = sshService.currentRemoteDirectory.replacingOccurrences(of: "'", with: "'\"'\"'")
                                    let trimmedMsg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmedMsg.isEmpty {
                                        let escapedMsg = trimmedMsg.replacingOccurrences(of: "'", with: "'\"'\"'")
                                        _ = await sshService.executeCommandOnVPS("cd '\(escapedDir)' && git add -A && (git commit -m '\(escapedMsg)' || true) 2>&1")
                                        commitMessageInput = ""
                                    }
                                    let res = await sshService.executeGitCommandOnVPS(
                                        ["push"],
                                        in: sshService.currentRemoteDirectory,
                                        githubToken: githubAuth.activeToken
                                    )
                                    gitService.statusBanner = res.output
                                } else {
                                    let ok = await gitService.pushToGitHubREST(workspaceRoot: workspace.rootURL, commitMessage: msg)
                                    if ok {
                                        if !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            commitMessageInput = ""
                                        }
                                        workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                                    }
                                }
                            }
                        } label: {
                            Label("Push", systemImage: "arrow.up.to.line")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.85))
                                .foregroundColor(.black)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    if gitService.lastPushRejectedNonFastForward && !sshService.isConnected {
                        HStack(spacing: 6) {
                            Button {
                                Task {
                                    let ok = await gitService.pullFromGitHub(into: workspace.rootURL)
                                    if ok {
                                        workspace.reloadTree()
                                        workspace.reloadOpenTabsFromDisk()
                                        workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                                    }
                                }
                            } label: {
                                Label(preferences.tr("Pull Trước", "Pull First"), systemImage: "icloud.and.arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.22))
                                    .foregroundColor(.orange)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)

                            Button {
                                let msg = commitMessageInput
                                workspace.saveAllTabs()
                                Task {
                                    let ok = await gitService.pushToGitHubREST(workspaceRoot: workspace.rootURL, commitMessage: msg, force: true)
                                    if ok {
                                        commitMessageInput = ""
                                        workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                                    }
                                }
                            } label: {
                                Label("Force Push", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.22))
                                    .foregroundColor(.red)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Changed Files List
                Text("THAY ĐỔI (\(gitService.changedFiles.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: palette.gutterForeground))

                ForEach(gitService.changedFiles) { item in
                    let statusColor: Color = {
                        if let hex = item.diffKind.colorHex(isDark: palette.isDark) {
                            return Color(hex: hex)
                        }
                        return Color(hex: palette.foreground)
                    }()

                    HStack(spacing: 6) {
                        Text(item.statusBadge)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(statusColor)
                            .frame(width: 15)

                        Button {
                            selectedGitDiffText = gitService.diffPreview(for: item.relativePath, workspaceRoot: workspace.rootURL)
                        } label: {
                            Text(item.relativePath)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundColor(statusColor)
                                .strikethrough(item.diffKind.isStrikethrough, color: statusColor)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if item.addedLines > 0 || item.removedLines > 0 {
                            HStack(spacing: 3) {
                                if item.addedLines > 0 {
                                    Text("+\(item.addedLines)")
                                        .foregroundColor(Color(hex: palette.isDark ? "#73C991" : "#1A7F37"))
                                }
                                if item.removedLines > 0 {
                                    Text("-\(item.removedLines)")
                                        .foregroundColor(Color(hex: palette.isDark ? "#F14C4C" : "#CF222E"))
                                }
                            }
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        }

                        Button {
                            Task {
                                if item.diffKind == .deleted {
                                    workspace.restoreDeletedFile(at: workspace.rootURL.appendingPathComponent(item.relativePath))
                                    await gitService.refreshStatus(workspaceRoot: workspace.rootURL, sshService: sshService)
                                } else {
                                    await gitService.discardChanges(for: item.relativePath, workspaceRoot: workspace.rootURL)
                                    let targetURL = workspace.rootURL.appendingPathComponent(item.relativePath)
                                    let targetCanon = WorkspaceManager.canonicalPath(targetURL)
                                    if FileManager.default.fileExists(atPath: targetURL.path) {
                                        if let tabIdx = workspace.openTabs.firstIndex(where: { WorkspaceManager.canonicalPath($0.fileURL) == targetCanon }),
                                           let reloaded = try? String(contentsOf: targetURL, encoding: .utf8) {
                                            workspace.openTabs[tabIdx].content = reloaded
                                            workspace.openTabs[tabIdx].savedContent = reloaded
                                            workspace.openTabs[tabIdx].selectedRangeLocation = min(
                                                workspace.openTabs[tabIdx].selectedRangeLocation,
                                                (reloaded as NSString).length
                                            )
                                            workspace.openTabs[tabIdx].selectedRangeLength = 0
                                        }
                                    } else if let tabIdx = workspace.openTabs.firstIndex(where: { WorkspaceManager.canonicalPath($0.fileURL) == targetCanon }) {
                                        workspace.openTabs[tabIdx].savedContent = workspace.openTabs[tabIdx].content
                                        let tabID = workspace.openTabs[tabIdx].id
                                        workspace.closeTab(tabID)
                                    }
                                    workspace.clearDeletedGhostEntry(relativePath: item.relativePath)
                                    workspace.reloadTree()
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10.5))
                                .foregroundColor(statusColor)
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

                // Clone GitHub Repo (Auth handled automatically via GitHubAccountService)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CLONE TỪ GITHUB")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                        Spacer()
                        Button {
                            onOpenGitHubSheet(1)
                        } label: {
                            Text(preferences.tr("Chọn từ Kho Repo ↗", "Browse Repos ↗"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.purple)
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("owner/repo hoặc link GitHub...", text: $cloneRepoInput)
                        .font(.system(size: 11.5))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(6)
                        .background(Color(hex: palette.editorBackground))
                        .foregroundColor(Color(hex: palette.foreground))
                        .cornerRadius(6)

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
                    .buttonStyle(.plain)
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
                            isProvisioningVPS ? "Đang cài g++/python3/node trên VPS..." : "1-Click Cài C++/Python/Node cho VPS",
                            systemImage: "wrench.and.screwdriver"
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

                    IDEActionButton(prominence: .secondary, tint: .green, compact: true) {
                        Task {
                            if await sshService.mountRemoteProjectDirectory(
                                remotePath: sshService.currentRemoteDirectory,
                                into: workspace
                            ) != nil {
                                onCloseDrawer()
                            }
                        }
                    } label: {
                        Image(systemName: "folder.fill")
                        Text(sshService.isMountingRemoteProject
                             ? preferences.tr("Đang gắn dự án từ VPS...", "Mounting VPS project...")
                             : preferences.tr("Mở Thư Mục VPS Này Làm Dự Án (0 Upload)", "Open This VPS Folder as Project (0 Upload)"))
                    }
                    .disabled(sshService.isMountingRemoteProject)

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
                                if entry.isDirectory {
                                    Image(systemName: "folder")
                                        .symbolRenderingMode(.hierarchical)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundColor(Color(hex: palette.accent))
                                } else {
                                    FileLanguageIconView(language: CodeLanguage.detect(from: URL(fileURLWithPath: entry.name)), size: 12)
                                }
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
        CompatibleNavigationContainer {
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Public Key Ed25519 của thiết bị (Dán vào ~/.ssh/authorized_keys trên VPS):")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text(cachedSSHPublicKey.isEmpty ? KeychainVault.generateOrLoadDeviceEd25519Key().publicKeyAuthorizedLine : cachedSSHPublicKey)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(3)
                            Button {
                                let pubKey = cachedSSHPublicKey.isEmpty ? KeychainVault.generateOrLoadDeviceEd25519Key().publicKeyAuthorizedLine : cachedSSHPublicKey
                                UIPasteboard.general.string = pubKey
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
    @ObservedObject var workspace: WorkspaceManager
    let activeURL: URL?
    let palette: IDEColorPalette
    let onSelectFile: (URL) -> Void
    let onExtractZip: (URL) -> Void
    let onNewFileInDir: (URL) -> Void
    let onNewFolderInDir: (URL) -> Void
    let onRename: (URL) -> Void
    let onDelete: (URL) -> Void
    let onRestoreDeleted: (URL) -> Void
    let onDismissDeleted: (URL) -> Void

    @State private var isExpanded: Bool = true

    private var itemDiffStatus: WorkspaceFileDiffStatus {
        if node.isDirectory {
            return workspace.folderDiffStatus(for: node)
        }
        return workspace.diffStatus(for: node.url, isDeletedGhost: node.isDeletedGhost)
    }

    private var itemTitleColor: Color {
        if let hex = itemDiffStatus.colorHex(isDark: palette.isDark) {
            return Color(hex: hex)
        }
        return Color(hex: palette.foreground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } else if node.isDeletedGhost {
                    onRestoreDeleted(node.url)
                } else {
                    onSelectFile(node.url)
                }
            } label: {
                HStack(spacing: 6) {
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color(hex: palette.gutterForeground))
                            .frame(width: 12)
                        Image(systemName: "folder")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: palette.accent))
                    } else {
                        Spacer().frame(width: 12)
                        FileLanguageIconView(language: node.language, fileName: node.name, size: 12.5)
                            .opacity(node.isDeletedGhost ? 0.55 : 1.0)
                    }

                    Text(node.name)
                        .font(.system(size: 12.5, weight: activeURL == node.url ? .bold : .regular))
                        .foregroundColor(itemTitleColor)
                        .strikethrough(itemDiffStatus.isStrikethrough, color: itemTitleColor)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if node.isDirectory {
                        if let hex = itemDiffStatus.colorHex(isDark: palette.isDark) {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 6, height: 6)
                                .padding(.trailing, 2)
                        }
                    } else {
                        if node.isDeletedGhost {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(itemTitleColor)
                        }

                        if let badge = itemDiffStatus.badgeText {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(itemTitleColor)
                                .frame(minWidth: 12, alignment: .trailing)
                        }
                    }
                }
                .padding(.leading, CGFloat(depth * 13))
                .padding(.vertical, 5)
                .padding(.horizontal, 5)
                .background(activeURL == node.url ? Color(hex: palette.currentLineBackground) : Color.clear)
                .cornerRadius(6)
            }
            .contextMenu {
                if node.isDeletedGhost {
                    Button { onRestoreDeleted(node.url) } label: {
                        Label("Khôi phục File vừa xóa", systemImage: "arrow.uturn.backward")
                    }
                    Button { onDismissDeleted(node.url) } label: {
                        Label("Ẩn khỏi danh sách xóa", systemImage: "eye.slash")
                    }
                } else {
                    if node.isDirectory {
                        Button { onNewFileInDir(node.url) } label: { Label("Tạo File trong này", systemImage: "doc.badge.plus") }
                        Button { onNewFolderInDir(node.url) } label: { Label("Tạo Thư mục con", systemImage: "folder.badge.plus") }
                    } else if node.url.pathExtension.lowercased() == "zip" {
                        Button { onExtractZip(node.url) } label: { Label("Giải nén .zip tại đây", systemImage: "archivebox.fill") }
                    }
                    Button { onRename(node.url) } label: { Label("Đổi tên", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete(node.url) } label: { Label("Xóa", systemImage: "trash") }
                }
            }

            if node.isDirectory, isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        depth: depth + 1,
                        workspace: workspace,
                        activeURL: activeURL,
                        palette: palette,
                        onSelectFile: onSelectFile,
                        onExtractZip: onExtractZip,
                        onNewFileInDir: onNewFileInDir,
                        onNewFolderInDir: onNewFolderInDir,
                        onRename: onRename,
                        onDelete: onDelete,
                        onRestoreDeleted: onRestoreDeleted,
                        onDismissDeleted: onDismissDeleted
                    )
                }
            }
        }
    }
}
