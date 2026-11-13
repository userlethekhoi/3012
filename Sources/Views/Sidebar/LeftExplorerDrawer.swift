import SwiftUI
import UniformTypeIdentifiers

public struct LeftExplorerDrawer: View {
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var liveServer: LiveServerService
    var onOpenSettings: () -> Void
    var onCloseDrawer: () -> Void

    @State private var sidebarMode: Int = 0 // 0 = Files, 1 = Search
    @State private var showNewFileAlert: Bool = false
    @State private var showNewFolderAlert: Bool = false
    @State private var newItemName: String = ""
    @State private var targetParentDir: URL?
    @State private var renameTargetURL: URL?
    @State private var renameText: String = ""
    @State private var showFolderPicker: Bool = false

    public init(
        workspace: WorkspaceManager,
        preferences: EditorPreferences,
        liveServer: LiveServerService,
        onOpenSettings: @escaping () -> Void,
        onCloseDrawer: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.preferences = preferences
        self.liveServer = liveServer
        self.onOpenSettings = onOpenSettings
        self.onCloseDrawer = onCloseDrawer
    }

    public var body: some View {
        let palette = preferences.activePalette

        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 10) {
                Text("3012")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(Color(hex: palette.accent))

                Picker("", selection: $sidebarMode) {
                    Image(systemName: "folder.fill").tag(0)
                    Image(systemName: "magnifyingglass").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)

                Spacer()

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: palette.foreground))
                }

                Button {
                    onCloseDrawer()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: palette.headerBackground))

            if sidebarMode == 0 {
                explorerSection(palette: palette)
            } else {
                searchSection(palette: palette)
            }

            Divider().overlay(Color.white.opacity(0.08))

            // Footer: Live Server Status + External Folder
            HStack(spacing: 8) {
                Button {
                    showFolderPicker = true
                } label: {
                    Label("Mở Folder", systemImage: "externaldrive.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
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
                            .frame(width: 7, height: 7)
                        Text(liveServer.isRunning ? "Port :\(liveServer.port)" : "Go Live")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: palette.currentLineBackground))
                    .foregroundColor(Color(hex: palette.foreground))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: palette.headerBackground))
        }
        .background(Color(hex: palette.sidebarBackground))
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
        } message: {
            Text("Nhập tên file kèm đuôi (.html, .css, .js, .py, .cpp, .c, .m, .swift) để tự tạo code mẫu.")
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
    }

    @ViewBuilder
    private func explorerSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(workspace.rootURL.lastPathComponent.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(Color(hex: palette.gutterForeground))
                    .lineLimit(1)

                Spacer()

                Button {
                    targetParentDir = workspace.rootURL
                    newItemName = ""
                    showNewFileAlert = true
                } label: {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: palette.foreground))
                }

                Button {
                    targetParentDir = workspace.rootURL
                    newItemName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: palette.foreground))
                }

                Button {
                    workspace.reloadTree()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: palette.gutterForeground))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

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
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func searchSection(palette: IDEColorPalette) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(hex: palette.gutterForeground))
                TextField("Tìm trong toàn dự án...", text: $workspace.searchQuery)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: palette.foreground))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: workspace.searchQuery) { _, q in
                        workspace.performWorkspaceSearch(q)
                    }
            }
            .padding(8)
            .background(Color(hex: palette.editorBackground))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(workspace.searchResults.enumerated()), id: \.offset) { _, hit in
                        Button {
                            workspace.openFile(at: hit.url)
                            onCloseDrawer()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(workspace.relativePath(for: hit.url)):\(hit.line)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: palette.accent))
                                Text(hit.preview)
                                    .font(.system(size: 11, design: .monospaced))
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
                        .font(.system(size: 13, weight: activeURL == node.url ? .bold : .regular))
                        .foregroundColor(Color(hex: palette.foreground))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.leading, CGFloat(depth * 14))
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(activeURL == node.url ? Color(hex: palette.currentLineBackground) : Color.clear)
                .cornerRadius(6)
            }
            .contextMenu {
                if node.isDirectory {
                    Button {
                        onNewFileInDir(node.url)
                    } label: {
                        Label("Tạo File trong này", systemImage: "doc.badge.plus")
                    }
                    Button {
                        onNewFolderInDir(node.url)
                    } label: {
                        Label("Tạo Thư mục con", systemImage: "folder.badge.plus")
                    }
                }
                Button {
                    onRename(node.url)
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete(node.url)
                } label: {
                    Label("Xóa", systemImage: "trash")
                }
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
