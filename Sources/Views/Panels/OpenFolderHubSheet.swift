import SwiftUI

public struct OpenFolderHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject private var githubAuth = GitHubAccountService.shared
    public var onRequestReopenHub: (() -> Void)?
    public var onOpenGitHubRepos: (() -> Void)?

    @State private var importFolderName: String = ""
    @State private var showCreateFolderAlert = false
    @State private var newFolderNameInput = ""

    public init(
        workspace: WorkspaceManager,
        onRequestReopenHub: (() -> Void)? = nil,
        onOpenGitHubRepos: (() -> Void)? = nil
    ) {
        self.workspace = workspace
        self.onRequestReopenHub = onRequestReopenHub
        self.onOpenGitHubRepos = onOpenGitHubRepos
    }

    public var body: some View {
        CompatibleNavigationContainer {
            List {
                if let errMsg = workspace.lastFolderOpenError, !errMsg.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(L10n.tr("Không thể mở trực tiếp thư mục ngoài", "Cannot open external folder directly"))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(errMsg)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                IDEPillButton(prominence: .prominent, tint: .blue) {
                                    startFolderFilesImport()
                                } label: {
                                    Label(L10n.tr("Chọn File vào Dự án", "Pick Folder Files"), systemImage: "doc.on.doc.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }

                                IDEPillButton(prominence: .secondary, tint: .accentColor) {
                                    startZipImport()
                                } label: {
                                    Label(L10n.tr("Nhập .zip", "Import .zip"), systemImage: "archivebox.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    ForEach(workspace.availableWorkspaces, id: \.path) { folderURL in
                        let isActive = folderURL.standardizedFileURL.path == workspace.rootURL.standardizedFileURL.path
                        Button {
                            workspace.switchWorkspaceFolder(to: folderURL, hasSecurityScope: false)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isActive ? "folder.fill.badge.person.crop" : "folder.fill")
                                    .foregroundColor(isActive ? .green : .blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folderURL.lastPathComponent)
                                        .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                                        .foregroundColor(.primary)
                                    Text(L10n.tr("Trên iPhone -> 3012 -> \(folderURL.lastPathComponent)", "On My iPhone -> 3012 -> \(folderURL.lastPathComponent)"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }

                    Button {
                        newFolderNameInput = ""
                        showCreateFolderAlert = true
                    } label: {
                        Label(L10n.tr("Tạo Thư mục Dự án Mới...", "Create New Project Folder..."), systemImage: "folder.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                } header: {
                    Text(L10n.tr("Thư mục trên Máy (On My iPhone -> 3012)", "On My iPhone -> 3012 (100% Native R/W)"))
                } footer: {
                    Text(L10n.tr(
                        "Mọi thư mục đặt trong Files -> On My iPhone -> 3012 đều mở 1 chạm không bị giới hạn chứng chỉ .p12.",
                        "Folders inside Files -> On My iPhone -> 3012 open with full read/write access under any certificate."
                    ))
                }

                if onOpenGitHubRepos != nil {
                    Section {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                                onOpenGitHubRepos?()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 17))
                                    .foregroundColor(.purple)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.tr("Clone từ Tài khoản GitHub (Private & Public)", "Clone from GitHub Account (Private & Public)"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    if let acc = githubAuth.activeAccount {
                                        Text("@\(acc.login) — \(L10n.tr("Mở danh sách repo của bạn", "Browse your connected repositories"))")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.green)
                                    } else {
                                        Text(L10n.tr("Đăng nhập 1-chạm để kéo Private/Public Repo vào máy", "1-tap sign in to clone private & public repos"))
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text(L10n.tr("GitHub (Private & Public Repo)", "GitHub (Private & Public Repos)"))
                    }
                }

                Section {
                    TextField(
                        L10n.tr("Tên thư mục nhận (để trống = tự đặt tên)", "Target folder name (blank = auto)"),
                        text: $importFolderName
                    )
                    .font(.system(size: 13))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

                    Button {
                        startFolderFilesImport()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Chọn nhiều File trong thư mục ngoài", "Pick Multiple Files From Any Folder"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(L10n.tr("Khuyên dùng khi ký .p12: chọn file bên trong thư mục bất kỳ -> tự tạo project hoàn chỉnh.", "Reliable under .p12 sideload: copies selected files into a full editable workspace."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        startZipImport()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox.fill")
                                .foregroundColor(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Nhập cả thư mục nén .zip", "Import Project .zip Archive"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(L10n.tr("Tự giải nén toàn bộ cấu trúc thư mục con & mở ngay.", "Extracts full folder hierarchy automatically and opens project."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.tr("Nhập Dự án Ngoài (Chống Lỗi Chứng Chỉ .p12)", "Import External Files / Zip (.p12-Proof)"))
                }

                Section {
                    Button {
                        startExternalSystemFolderPicker()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("Mở Thư mục Hệ thống (Files.app / iCloud)", "Open System Folder (Files.app / iCloud)"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(L10n.tr("Đồng bộ 2 chiều trực tiếp nếu chứng chỉ/App Group được cấp phép.", "Opens and mirrors external folder directly when allowed by signing profile."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(L10n.tr("Thư mục Hệ thống iOS", "System Folder Picker"))
                }
            }
            .navigationTitle(L10n.tr("Mở Thư Mục / Dự Án", "Open Folder / Project"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.tr("Đóng", "Close")) {
                        dismiss()
                    }
                }
            }
            .compatibleTextInputAlert(
                L10n.tr("Tạo Thư mục Dự án Mới", "Create New Project Folder"),
                isPresented: $showCreateFolderAlert,
                text: $newFolderNameInput,
                placeholder: L10n.tr("Ví dụ: MyWebApp", "e.g. MyWebApp"),
                confirmTitle: L10n.tr("Tạo & Mở", "Create & Open")
            ) {
                let name = newFolderNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    workspace.createNewProjectWorkspace(named: name)
                    dismiss()
                }
            }
            .onAppear {
                _ = workspace.listInternalProjectFolders()
            }
        }
    }

    private func startFolderFilesImport() {
        let targetName = importFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
        NativeDocumentPickerPresenter.shared.presentResourcePicker(mode: .folderFilesCopy, initialDelay: 0.32) { resources in
            _ = workspace.importCopiedItemsIntoProjectFolder(folderName: targetName, resources: resources)
        }
    }

    private func startZipImport() {
        dismiss()
        NativeDocumentPickerPresenter.shared.presentResourcePicker(mode: .zip, initialDelay: 0.32) { resources in
            if let first = resources.first {
                _ = workspace.importAndOpenZip(from: first.url, hasSecurityScope: first.hasSecurityScope)
            }
        }
    }

    private func startExternalSystemFolderPicker() {
        let reopen = onRequestReopenHub
        dismiss()
        NativeDocumentPickerPresenter.shared.presentResourcePicker(mode: .folder, initialDelay: 0.32) { resources in
            guard let first = resources.first else { return }
            workspace.switchWorkspaceFolder(to: first.url, hasSecurityScope: first.hasSecurityScope)
            if !workspace.lastFolderOpenSucceeded && workspace.lastFolderOpenError != nil {
                reopen?()
            }
        }
    }
}
