import SafariServices
import SwiftUI
import UIKit

private struct GitHubSafariURLItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct InAppSafariBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private enum GitHubRepoFilterMode: Int, CaseIterable, Identifiable {
    case all = 0
    case privateOnly = 1
    case publicOnly = 2
    case orgOnly = 3
    case starred = 4

    var id: Int { rawValue }

    func title(using preferences: EditorPreferences) -> String {
        switch self {
        case .all: return preferences.tr("Tất cả", "All")
        case .privateOnly: return "Private 🔒"
        case .publicOnly: return "Public 🌐"
        case .orgOnly: return "Org 🏢"
        case .starred: return "Starred ⭐"
        }
    }
}

public struct GitHubAccountAndReposSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var githubAuth: GitHubAccountService
    @ObservedObject var gitService: GitService
    @ObservedObject var workspace: WorkspaceManager
    @ObservedObject var liveServer: LiveServerService
    @ObservedObject var preferences: EditorPreferences

    @State private var selectedTab: Int
    @State private var patInput: String = ""
    @State private var showCustomOAuthConfig: Bool = false
    @State private var safariTarget: GitHubSafariURLItem? = nil

    // Repositories Tab State
    @State private var repoSearchText: String = ""
    @State private var repoFilter: GitHubRepoFilterMode = .all
    @State private var quickCloneInput: String = ""
    @State private var selectedBranchMap: [String: String] = [:]
    @State private var repoBranchesMap: [String: [String]] = [:]
    @State private var loadingBranchesFor: String? = nil
    @State private var cloningRepoName: String? = nil

    // Publish & PR Tab State
    @State private var publishRepoName: String = ""
    @State private var publishDescription: String = ""
    @State private var publishIsPrivate: Bool = true
    @State private var publishedRepoURLString: String? = nil

    @State private var prTitleInput: String = ""
    @State private var prBodyInput: String = ""
    @State private var prBaseBranch: String = "main"
    @State private var createdPRURLString: String? = nil

    public init(
        githubAuth: GitHubAccountService,
        gitService: GitService,
        workspace: WorkspaceManager,
        liveServer: LiveServerService,
        preferences: EditorPreferences,
        initialTab: Int = 0
    ) {
        self.githubAuth = githubAuth
        self.gitService = gitService
        self.workspace = workspace
        self.liveServer = liveServer
        self.preferences = preferences
        _selectedTab = State(initialValue: min(max(0, initialTab), 2))
    }

    public var body: some View {
        CompatibleNavigationContainer {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(preferences.tr("Tài khoản", "Accounts")).tag(0)
                    Text(preferences.tr("Kho Repo", "Repositories")).tag(1)
                    Text("Publish & PR").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if selectedTab == 0 {
                    accountsTabView
                } else if selectedTab == 1 {
                    repositoriesTabView
                } else {
                    publishAndPRTabView
                }
            }
            .navigationTitle("GitHub Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(preferences.tr("Đóng", "Done")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $safariTarget) { item in
                InAppSafariBrowserView(url: item.url)
                    .ignoresSafeArea()
            }
            .onAppear {
                if publishRepoName.isEmpty {
                    let sanitized = workspace.workspaceDisplayName
                        .replacingOccurrences(of: " ", with: "-")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    publishRepoName = sanitized.isEmpty ? "my-3012-project" : sanitized
                }
                if githubAuth.isSignedIn && githubAuth.repositories.isEmpty && !githubAuth.isLoadingRepos {
                    Task { @MainActor () -> Void in
                        await githubAuth.refreshRepositories(reset: true)
                    }
                }
            }
        }
    }

    // MARK: - Tab 0: GitHub Account & OAuth / PAT
    private var accountsTabView: some View {
        Form {
            if let err = githubAuth.errorMessage, !err.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.system(size: 12.5))
                            .foregroundColor(.orange)
                    }
                }
            }

            if !githubAuth.statusMessage.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(githubAuth.statusMessage)
                            .font(.system(size: 12.5))
                            .foregroundColor(.primary)
                    }
                }
            }

            if !githubAuth.accounts.isEmpty {
                Section(preferences.tr("Tài khoản GitHub Đang Kết Nối", "Connected GitHub Accounts")) {
                    ForEach(githubAuth.accounts) { acct in
                        let isActive = (acct.id == githubAuth.activeAccount?.id)
                        HStack(spacing: 10) {
                            Button {
                                githubAuth.switchActiveAccount(to: acct.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isActive ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(isActive ? .green : .secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text("@\(acct.login)")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)

                                            Text(acct.hasPrivateRepoAccess ? "Private + Public 🔒" : "Public Only 🌐")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background((acct.hasPrivateRepoAccess ? Color.green : Color.orange).opacity(0.16))
                                                .foregroundColor(acct.hasPrivateRepoAccess ? .green : .orange)
                                                .cornerRadius(4)
                                        }

                                        if !acct.name.isEmpty && acct.name != acct.login {
                                            Text("\(acct.name) • \(acct.email)")
                                                .font(.system(size: 11.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        } else {
                                            Text(acct.email)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }

                                        Text("Scopes: \(acct.scopesSummary)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .buttonStyle(.borderless)

                            Spacer()

                            Button {
                                githubAuth.signOutAccount(id: acct.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 3)
                    }

                    Button {
                        selectedTab = 1
                    } label: {
                        Label(
                            preferences.tr("Mở Kho Repo (Private & Public)", "Browse Private & Public Repos"),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.system(size: 13.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section {
                switch githubAuth.deviceFlowState {
                case .idle:
                    Button {
                        githubAuth.startDeviceFlow()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "safari")
                            Text(preferences.tr(
                                "Đăng nhập 1-Chạm qua GitHub Browser",
                                "1-Tap Sign In via GitHub Browser"
                            ))
                            .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)

                case .requestingCode:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(preferences.tr("Đang lấy mã xác nhận từ GitHub...", "Requesting GitHub device code..."))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                case .awaitingUser(let userCode, let verificationURI, _):
                    VStack(alignment: .leading, spacing: 10) {
                        Text(preferences.tr(
                            "Bước 1: Mã đã tự copy vào Clipboard. Bước 2: Mở GitHub & dán mã để cấp quyền:",
                            "Step 1: Code copied to clipboard. Step 2: Open GitHub and enter this code:"
                        ))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                        HStack {
                            Text(userCode)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.14))
                                .cornerRadius(8)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = userCode
                            } label: {
                                Label(preferences.tr("Copy Mã", "Copy"), systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            Button {
                                if let target = URL(string: verificationURI) {
                                    safariTarget = GitHubSafariURLItem(url: target)
                                }
                            } label: {
                                Label(preferences.tr("Mở GitHub Xác nhận Ngay", "Authorize in GitHub"), systemImage: "safari")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                githubAuth.cancelDeviceFlow()
                            } label: {
                                Text(preferences.tr("Hủy", "Cancel"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.85)
                            Text(preferences.tr("Đang chờ bạn xác nhận trên trình duyệt...", "Waiting for GitHub browser authorization..."))
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                case .authorized(let login):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(preferences.tr("Đã kết nối thành công @\(login)!", "Successfully authorized @\(login)!"))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(preferences.tr("Đăng nhập thêm", "Add Another")) {
                            githubAuth.deviceFlowState = .idle
                            githubAuth.startDeviceFlow()
                        }
                        .buttonStyle(.bordered)
                    }

                case .failed(let reason):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reason)
                            .font(.system(size: 12.5))
                            .foregroundColor(.orange)
                        Button(preferences.tr("Thử lại Device Flow", "Retry Device Flow")) {
                            githubAuth.startDeviceFlow()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                DisclosureGroup(
                    preferences.tr("OAuth Client ID riêng (Tùy chọn)", "Custom OAuth Client ID (Optional)"),
                    isExpanded: $showCustomOAuthConfig
                ) {
                    TextField("Iv1... hoặc client_id GitHub OAuth App", text: $githubAuth.customOAuthClientID)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .font(.system(size: 12.5))
            } header: {
                Text(preferences.tr("Đăng nhập Nhanh (OAuth Device Flow)", "Quick Browser Login (OAuth Device Flow)"))
            } footer: {
                Text(preferences.tr(
                    "Hoạt động 100% với mọi chứng chỉ .p12 / TrollStore, không phụ thuộc redirect URI hệ thống.",
                    "Works reliably under any .p12 / TrollStore signing profile without system redirect URI restrictions."
                ))
            }

            Section {
                SecureField("ghp_... hoặc github_pat_...", text: $patInput)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                HStack(spacing: 8) {
                    Button {
                        let candidate = patInput
                        Task { @MainActor () -> Void in
                            let ok = await githubAuth.signInWithToken(candidate, authKind: "pat")
                            if ok {
                                patInput = ""
                            }
                        }
                    } label: {
                        if githubAuth.isAuthenticating {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.75)
                                Text(preferences.tr("Đang kiểm tra...", "Verifying..."))
                            }
                        } else {
                            Label(preferences.tr("Đăng nhập bằng Token", "Sign In with Token"), systemImage: "key.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(githubAuth.isAuthenticating || patInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        if let createTokenURL = URL(string: "https://github.com/settings/tokens/new?description=3012%20Mobile%20IDE&scopes=repo,read:org,user:email,workflow,gist") {
                            safariTarget = GitHubSafariURLItem(url: createTokenURL)
                        }
                    } label: {
                        Label(preferences.tr("Tạo Token 1-Chạm", "Create Token"), systemImage: "safari")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Personal Access Token (Classic & Fine-grained)")
            } footer: {
                Text(preferences.tr(
                    "Token được mã hóa an toàn trong iOS Keychain. Chọn đủ quyền 'repo' (Classic) hoặc 'Contents: Read & Write' (Fine-grained) để Clone & Push Private Repo.",
                    "Tokens are stored securely in iOS Keychain. Grant 'repo' (Classic) or 'Contents: Read & Write' (Fine-grained) for full Private Repo Clone & Push."
                ))
            }
        }
    }

    // MARK: - Tab 1: Paginated Private/Public Repo Browser + Branch Clone
    private var filteredRepos: [GitHubRepoItem] {
        let baseList: [GitHubRepoItem] = (repoFilter == .starred) ? githubAuth.starredRepositories : githubAuth.repositories
        let query = repoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return baseList.filter { item in
            switch repoFilter {
            case .all, .starred:
                break
            case .privateOnly:
                if !item.isPrivate { return false }
            case .publicOnly:
                if item.isPrivate { return false }
            case .orgOnly:
                if !item.isOrganizationRepo { return false }
            }

            if query.isEmpty { return true }
            return item.fullName.localizedCaseInsensitiveContains(query)
                || item.description.localizedCaseInsensitiveContains(query)
                || item.language.localizedCaseInsensitiveContains(query)
        }
    }

    private var repositoriesTabView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(
                            preferences.tr("Tìm repo theo tên, ngôn ngữ...", "Search repos by name, language..."),
                            text: $repoSearchText
                        )
                        .font(.system(size: 13))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                        if !repoSearchText.isEmpty {
                            Button {
                                repoSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                    if githubAuth.isSignedIn {
                        Button {
                            Task { @MainActor () -> Void in
                                await githubAuth.refreshRepositories(reset: true)
                            }
                        } label: {
                            if githubAuth.isLoadingRepos {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(githubAuth.isLoadingRepos)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(GitHubRepoFilterMode.allCases) { mode in
                            Button {
                                repoFilter = mode
                            } label: {
                                Text(mode.title(using: preferences))
                                    .font(.system(size: 11.5, weight: repoFilter == mode ? .bold : .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(repoFilter == mode ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundColor(repoFilter == mode ? .white : .primary)
                                    .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !gitService.statusBanner.isEmpty {
                    Text(gitService.statusBanner)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            List {
                if !githubAuth.isSignedIn {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preferences.tr(
                                "Kết nối Tài khoản GitHub để tự động tải toàn bộ Private & Public Repositories của bạn.",
                                "Connect your GitHub Account to automatically list all of your Private & Public Repositories."
                            ))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                            Button {
                                selectedTab = 0
                            } label: {
                                Label(
                                    preferences.tr("Kết nối Tài khoản GitHub Ngay", "Connect GitHub Account"),
                                    systemImage: "person.crop.circle.badge.checkmark"
                                )
                                .font(.system(size: 13, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(preferences.tr("Clone Nhanh Theo Link / Tên Repo", "Quick Clone by URL / owner/repo")) {
                    HStack(spacing: 8) {
                        TextField("owner/repo hoặc https://github.com/...", text: $quickCloneInput)
                            .font(.system(size: 12.5, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)

                        Button {
                            let target = quickCloneInput
                            cloningRepoName = target
                            Task { @MainActor () -> Void in
                                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                if let cloned = await gitService.cloneGitHubRepository(repoInput: target, into: docs) {
                                    workspace.switchWorkspaceFolder(to: cloned)
                                    liveServer.updateRootDirectory(cloned)
                                    dismiss()
                                }
                                cloningRepoName = nil
                            }
                        } label: {
                            Text(preferences.tr("Clone", "Clone"))
                                .font(.system(size: 12.5, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gitService.isBusy || quickCloneInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if githubAuth.isSignedIn {
                    Section(preferences.tr("Danh sách Kho Repo (\(filteredRepos.count))", "Repositories (\(filteredRepos.count))")) {
                        if githubAuth.isLoadingRepos && filteredRepos.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(preferences.tr("Đang tải toàn bộ repo từ GitHub...", "Loading repositories from GitHub..."))
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        } else if filteredRepos.isEmpty {
                            Text(preferences.tr("Không có repository nào khớp bộ lọc.", "No matching repositories found."))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(filteredRepos) { repo in
                                repoRowView(repo)
                            }

                            if repoFilter != .starred && githubAuth.hasMoreRepoPages {
                                Button {
                                    Task { @MainActor () -> Void in
                                        await githubAuth.refreshRepositories(reset: false)
                                    }
                                } label: {
                                    HStack {
                                        Spacer()
                                        if githubAuth.isLoadingRepos {
                                            ProgressView().scaleEffect(0.8)
                                        }
                                        Text(preferences.tr("Tải thêm Repository...", "Load More Repositories..."))
                                            .font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func repoRowView(_ repo: GitHubRepoItem) -> some View {
        let selectedBranch = selectedBranchMap[repo.fullName] ?? repo.defaultBranch
        let branches = repoBranchesMap[repo.fullName] ?? [repo.defaultBranch]
        let isCloningThis = (cloningRepoName == repo.fullName && gitService.isBusy)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(repo.isPrivate ? .orange : .blue)

                Text(repo.fullName)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if repo.isPrivate {
                    Text("Private")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.16))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }

            if !repo.description.isEmpty {
                Text(repo.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if !repo.language.isEmpty {
                    Text(repo.language)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if repo.stargazersCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("\(repo.stargazersCount)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Menu {
                    ForEach(branches, id: \.self) { branch in
                        Button {
                            selectedBranchMap[repo.fullName] = branch
                        } label: {
                            if branch == selectedBranch {
                                Label(branch, systemImage: "checkmark")
                            } else {
                                Text(branch)
                            }
                        }
                    }
                    Divider()
                    Button {
                        loadingBranchesFor = repo.fullName
                        Task { @MainActor () -> Void in
                            let fetched = await githubAuth.fetchBranches(owner: repo.ownerLogin, repo: repo.name)
                            if !fetched.isEmpty {
                                repoBranchesMap[repo.fullName] = fetched
                            }
                            loadingBranchesFor = nil
                        }
                    } label: {
                        Label(preferences.tr("Tải tất cả nhánh", "Load All Branches"), systemImage: "arrow.clockwise")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10.5))
                        if loadingBranchesFor == repo.fullName {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Text(selectedBranch)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)
                }
                .buttonStyle(.borderless)

                Button {
                    cloningRepoName = repo.fullName
                    Task { @MainActor () -> Void in
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        if let cloned = await gitService.cloneGitHubRepository(
                            repoInput: repo.fullName,
                            into: docs,
                            branchOverride: selectedBranch
                        ) {
                            workspace.switchWorkspaceFolder(to: cloned)
                            liveServer.updateRootDirectory(cloned)
                            dismiss()
                        }
                        cloningRepoName = nil
                    }
                } label: {
                    if isCloningThis {
                        HStack(spacing: 4) {
                            ProgressView().scaleEffect(0.7)
                            Text("Clone...")
                                .font(.system(size: 11.5, weight: .bold))
                        }
                    } else {
                        Label(preferences.tr("Clone & Mở", "Clone & Open"), systemImage: "icloud.and.arrow.down")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(gitService.isBusy)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tab 2: Publish Workspace & Quick Pull Request
    private var publishAndPRTabView: some View {
        Form {
            Section {
                if !githubAuth.isSignedIn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preferences.tr(
                            "Vui lòng kết nối Tài khoản GitHub trước khi tạo Repository hoặc Pull Request.",
                            "Connect your GitHub Account before publishing a workspace or creating a Pull Request."
                        ))
                        .font(.system(size: 12.5))
                        .foregroundColor(.orange)

                        Button(preferences.tr("Đi tới Đăng nhập GitHub", "Go to GitHub Sign In")) {
                            selectedTab = 0
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    HStack {
                        Text(preferences.tr("Workspace hiện tại", "Active Workspace"))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(workspace.workspaceDisplayName)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    TextField(
                        preferences.tr("Tên Repository mới (vd: my-app)", "New repository name"),
                        text: $publishRepoName
                    )
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                    TextField(
                        preferences.tr("Mô tả ngắn (tùy chọn)", "Short description (optional)"),
                        text: $publishDescription
                    )
                    .font(.system(size: 13))

                    Toggle(isOn: $publishIsPrivate) {
                        HStack(spacing: 6) {
                            Image(systemName: publishIsPrivate ? "lock.fill" : "globe")
                                .foregroundColor(publishIsPrivate ? .orange : .blue)
                            Text(preferences.tr("Private Repository (Chỉ mình bạn xem)", "Private Repository"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }

                    Button {
                        workspace.saveAllTabs()
                        let name = publishRepoName
                        let desc = publishDescription
                        let isPriv = publishIsPrivate
                        Task { @MainActor () -> Void in
                            let ok = await gitService.publishWorkspaceToNewRepo(
                                name: name,
                                description: desc,
                                isPrivate: isPriv,
                                workspaceRoot: workspace.rootURL
                            )
                            if ok {
                                workspace.resetDiffBaselineToCurrentDisk(with: gitService.commits.first?.snapshotFiles)
                                let rawURL = gitService.remoteOriginURL
                                publishedRepoURLString = rawURL.hasSuffix(".git") ? String(rawURL.dropLast(4)) : rawURL
                            }
                        }
                    } label: {
                        if gitService.isBusy {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text(preferences.tr("Đang tạo Repo & Push Code...", "Creating Repo & Pushing..."))
                            }
                        } else {
                            Label(
                                preferences.tr("Tạo Repo & Push Toàn Bộ Code", "Create Repo & Push Workspace"),
                                systemImage: "arrow.up.to.line"
                            )
                            .font(.system(size: 13.5, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gitService.isBusy || publishRepoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let repoLink = publishedRepoURLString, let url = URL(string: repoLink) {
                        Button {
                            safariTarget = GitHubSafariURLItem(url: url)
                        } label: {
                            Label(preferences.tr("Mở Repo vừa tạo trên GitHub", "Open Repository on GitHub"), systemImage: "safari")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(preferences.tr("Đưa Dự Án Lên GitHub (Publish)", "Publish Local Workspace to GitHub"))
            }

            if !gitService.remoteOriginURL.isEmpty {
                Section {
                    HStack {
                        Text("Remote")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(gitService.remoteOriginURL)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    TextField(preferences.tr("Tiêu đề Pull Request...", "Pull Request title..."), text: $prTitleInput)
                        .font(.system(size: 13))

                    TextField(preferences.tr("Nhánh đích (Base branch, vd: main)", "Base branch (e.g. main)"), text: $prBaseBranch)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    TextField(preferences.tr("Mô tả thay đổi...", "Description..."), text: $prBodyInput)
                        .font(.system(size: 12.5))

                    Button {
                        let title = prTitleInput
                        let body = prBodyInput
                        let base = prBaseBranch
                        Task { @MainActor () -> Void in
                            if let prURL = await gitService.createPullRequest(
                                title: title,
                                body: body,
                                head: gitService.currentBranch,
                                base: base
                            ) {
                                createdPRURLString = prURL
                                prTitleInput = ""
                                prBodyInput = ""
                            }
                        }
                    } label: {
                        Label(
                            preferences.tr("Tạo Pull Request (\(gitService.currentBranch) -> \(prBaseBranch))", "Create Pull Request"),
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gitService.isBusy || !githubAuth.isSignedIn || prTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let prLink = createdPRURLString, let url = URL(string: prLink) {
                        Button {
                            safariTarget = GitHubSafariURLItem(url: url)
                        } label: {
                            Label(preferences.tr("Xem Pull Request vừa tạo", "Open Created Pull Request"), systemImage: "safari")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text(preferences.tr("Tạo Pull Request Nhanh", "Quick Create Pull Request"))
                }
            }

            if !gitService.statusBanner.isEmpty {
                Section(preferences.tr("Trạng thái Git", "Git Status")) {
                    Text(gitService.statusBanner)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
