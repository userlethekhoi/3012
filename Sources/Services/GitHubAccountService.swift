import Combine
import Foundation
import UIKit

public struct GitHubAccountProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var login: String
    public var name: String
    public var email: String
    public var avatarURL: String
    public var authKind: String
    public var hasPrivateRepoAccess: Bool
    public var scopesSummary: String
    public var addedAt: Date

    public init(
        id: String,
        login: String,
        name: String,
        email: String,
        avatarURL: String,
        authKind: String,
        hasPrivateRepoAccess: Bool,
        scopesSummary: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.login = login
        self.name = name
        self.email = email
        self.avatarURL = avatarURL
        self.authKind = authKind
        self.hasPrivateRepoAccess = hasPrivateRepoAccess
        self.scopesSummary = scopesSummary
        self.addedAt = addedAt
    }
}

public struct GitHubRepoItem: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let ownerLogin: String
    public let isPrivate: Bool
    public let isFork: Bool
    public let description: String
    public let language: String
    public let stargazersCount: Int
    public let updatedAt: Date
    public let defaultBranch: String
    public let cloneURL: String
    public let htmlURL: String
    public let isOrganizationRepo: Bool
    public var isStarred: Bool

    public init(
        id: Int,
        name: String,
        fullName: String,
        ownerLogin: String,
        isPrivate: Bool,
        isFork: Bool,
        description: String,
        language: String,
        stargazersCount: Int,
        updatedAt: Date,
        defaultBranch: String,
        cloneURL: String,
        htmlURL: String,
        isOrganizationRepo: Bool,
        isStarred: Bool
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.ownerLogin = ownerLogin
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.description = description
        self.language = language
        self.stargazersCount = stargazersCount
        self.updatedAt = updatedAt
        self.defaultBranch = defaultBranch
        self.cloneURL = cloneURL
        self.htmlURL = htmlURL
        self.isOrganizationRepo = isOrganizationRepo
        self.isStarred = isStarred
    }
}

public enum GitHubDeviceFlowState: Equatable, Sendable {
    case idle
    case requestingCode
    case awaitingUser(userCode: String, verificationURI: String, expiresIn: Int)
    case authorized(login: String)
    case failed(String)
}

@MainActor
public final class GitHubAccountService: ObservableObject {
    public static let shared = GitHubAccountService()

    @Published public private(set) var accounts: [GitHubAccountProfile] = []
    @Published public private(set) var activeAccountID: String? = nil
    @Published public private(set) var repositories: [GitHubRepoItem] = []
    @Published public private(set) var starredRepositories: [GitHubRepoItem] = []
    @Published public private(set) var isLoadingRepos: Bool = false
    @Published public private(set) var hasMoreRepoPages: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public var deviceFlowState: GitHubDeviceFlowState = .idle
    @Published public var statusMessage: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var customOAuthClientID: String {
        didSet {
            UserDefaults.standard.set(customOAuthClientID, forKey: customClientIDKey)
        }
    }

    private let defaultOAuthClientID = "178c6fc778ccc68e1d6a"
    private let accountsKey = "3012.github.accounts"
    private let activeAccountKey = "3012.github.activeAccountID"
    private let customClientIDKey = "3012.github.oauthClientID"
    private let legacyPATKey = "git.github.pat"
    private let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    private var currentRepoPage: Int = 1
    private var pollingTask: Task<Void, Never>? = nil

    public var effectiveOAuthClientID: String {
        let custom = customOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultOAuthClientID : custom
    }

    public var activeAccount: GitHubAccountProfile? {
        guard let activeAccountID else { return accounts.first }
        return accounts.first(where: { $0.id == activeAccountID }) ?? accounts.first
    }

    public var isSignedIn: Bool {
        activeAccount != nil || !activeToken.isEmpty
    }

    public var activeToken: String {
        if let acct = activeAccount,
           let token = KeychainVault.loadString(forKey: tokenKey(for: acct.id))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        return (KeychainVault.loadString(forKey: legacyPATKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init() {
        self.customOAuthClientID = UserDefaults.standard.string(forKey: customClientIDKey) ?? ""
        loadPersistedAccounts()

        if accounts.isEmpty {
            let legacy = (KeychainVault.loadString(forKey: legacyPATKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty {
                Task { @MainActor [weak self] () -> Void in
                    guard let self else { return }
                    _ = await self.signInWithToken(legacy, authKind: "pat", silentMigration: true)
                }
            }
        } else {
            syncActiveTokenToLegacyPAT()
        }
    }

    private func tokenKey(for accountID: String) -> String {
        "github.account.token.\(accountID)"
    }

    private func loadPersistedAccounts() {
        if let data = UserDefaults.standard.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([GitHubAccountProfile].self, from: data) {
            accounts = decoded
        }
        let storedActive = UserDefaults.standard.string(forKey: activeAccountKey)
        if let storedActive, accounts.contains(where: { $0.id == storedActive }) {
            activeAccountID = storedActive
        } else {
            activeAccountID = accounts.first?.id
        }
    }

    private func persistAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
        if let activeAccountID {
            UserDefaults.standard.set(activeAccountID, forKey: activeAccountKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeAccountKey)
        }
    }

    private func syncActiveTokenToLegacyPAT() {
        if let acct = activeAccount,
           let token = KeychainVault.loadString(forKey: tokenKey(for: acct.id))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            KeychainVault.saveString(token, forKey: legacyPATKey)
        }
    }

    private func makeGitHubAPIRequest(url: URL, method: String = "GET", token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("3012-Mobile-IDE/5.2", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanToken.isEmpty {
            req.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func githubAPIURL(pathSegments: [String], queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        let cleaned = pathSegments
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
        components.path = "/" + cleaned.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }

    private func formEncode(_ pairs: [(String, String)]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = pairs.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return encoded.data(using: .utf8)
    }

    // MARK: - 1-Tap GitHub OAuth Device Flow
    public func startDeviceFlow(scope: String = "repo read:org user:email workflow gist") {
        pollingTask?.cancel()
        pollingTask = nil
        errorMessage = nil
        deviceFlowState = .requestingCode
        statusMessage = L10n.tr("Đang xin mã đăng nhập từ GitHub...", "Requesting GitHub login code...")

        let clientID = effectiveOAuthClientID
        pollingTask = Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            guard let codeURL = URL(string: "https://github.com/login/device/code") else {
                self.deviceFlowState = .failed("URL GitHub Device Flow không hợp lệ.")
                return
            }
            var req = URLRequest(url: codeURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 30
            req.setValue("3012-Mobile-IDE/5.2", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = self.formEncode([
                ("client_id", clientID),
                ("scope", scope)
            ])

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if Task.isCancelled { return }
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let msg = L10n.tr("Không đọc được phản hồi từ GitHub (HTTP \(status)).", "Invalid GitHub response (HTTP \(status)).")
                    self.deviceFlowState = .failed(msg)
                    self.errorMessage = msg
                    return
                }
                if let errCode = json["error"] as? String {
                    let desc = (json["error_description"] as? String) ?? errCode
                    self.deviceFlowState = .failed(desc)
                    self.errorMessage = desc
                    return
                }
                guard (200...299).contains(status),
                      let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String else {
                    let msg = (json["error_description"] as? String)
                        ?? L10n.tr("GitHub từ chối tạo mã Device Flow (HTTP \(status)).", "GitHub refused Device Flow request (HTTP \(status)).")
                    self.deviceFlowState = .failed(msg)
                    self.errorMessage = msg
                    return
                }

                let verificationURI = (json["verification_uri"] as? String) ?? "https://github.com/login/device"
                let expiresIn = (json["expires_in"] as? Int) ?? 900
                var intervalSeconds = max(5, (json["interval"] as? Int) ?? 5)

                UIPasteboard.general.string = userCode
                self.deviceFlowState = .awaitingUser(
                    userCode: userCode,
                    verificationURI: verificationURI,
                    expiresIn: expiresIn
                )
                self.statusMessage = L10n.tr(
                    "Đã copy mã \(userCode). Hãy mở trình duyệt GitHub và dán mã để cấp quyền.",
                    "Copied code \(userCode). Open GitHub in browser and authorize access."
                )

                guard let tokenURL = URL(string: "https://github.com/login/oauth/access_token") else {
                    self.deviceFlowState = .failed("URL OAuth Token không hợp lệ.")
                    return
                }

                let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
                while !Task.isCancelled && Date() < deadline {
                    try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
                    if Task.isCancelled { return }

                    var pollReq = URLRequest(url: tokenURL)
                    pollReq.httpMethod = "POST"
                    pollReq.timeoutInterval = 30
                    pollReq.setValue("3012-Mobile-IDE/5.2", forHTTPHeaderField: "User-Agent")
                    pollReq.setValue("application/json", forHTTPHeaderField: "Accept")
                    pollReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    pollReq.httpBody = self.formEncode([
                        ("client_id", clientID),
                        ("device_code", deviceCode),
                        ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                    ])

                    guard let (pollData, _) = try? await URLSession.shared.data(for: pollReq),
                          let pollJSON = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] else {
                        continue
                    }

                    if let accessToken = pollJSON["access_token"] as? String, !accessToken.isEmpty {
                        let ok = await self.signInWithToken(accessToken, authKind: "oauth_device")
                        if ok, let login = self.activeAccount?.login {
                            self.deviceFlowState = .authorized(login: login)
                        } else if !ok {
                            let errText = self.errorMessage ?? L10n.tr("Không thể xác thực tài khoản GitHub.", "Failed to verify GitHub account.")
                            self.deviceFlowState = .failed(errText)
                        }
                        return
                    }

                    if let err = pollJSON["error"] as? String {
                        switch err {
                        case "authorization_pending":
                            continue
                        case "slow_down":
                            intervalSeconds += 5
                        case "expired_token":
                            let msg = L10n.tr("Mã xác nhận đã hết hạn. Vui lòng thử lại.", "Device code expired. Please try again.")
                            self.deviceFlowState = .failed(msg)
                            self.errorMessage = msg
                            return
                        case "access_denied":
                            let msg = L10n.tr("Bạn đã từ chối cấp quyền trên GitHub.", "Authorization was denied on GitHub.")
                            self.deviceFlowState = .failed(msg)
                            self.errorMessage = msg
                            return
                        default:
                            let desc = (pollJSON["error_description"] as? String) ?? err
                            self.deviceFlowState = .failed(desc)
                            self.errorMessage = desc
                            return
                        }
                    }
                }

                if !Task.isCancelled {
                    let msg = L10n.tr("Hết thời gian chờ xác nhận GitHub.", "Timed out waiting for GitHub authorization.")
                    self.deviceFlowState = .failed(msg)
                    self.errorMessage = msg
                }
            } catch {
                if !Task.isCancelled {
                    let msg = error.localizedDescription
                    self.deviceFlowState = .failed(msg)
                    self.errorMessage = msg
                }
            }
        }
    }

    public func cancelDeviceFlow() {
        pollingTask?.cancel()
        pollingTask = nil
        deviceFlowState = .idle
        statusMessage = L10n.tr("Đã hủy phiên đăng nhập GitHub.", "Cancelled GitHub login.")
    }

    // MARK: - Sign In With Token (PAT / OAuth Token) & Scope Inspection
    @discardableResult
    public func signInWithToken(_ rawToken: String, authKind: String = "pat", silentMigration: Bool = false) async -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            if !silentMigration {
                errorMessage = L10n.tr("Vui lòng nhập GitHub Token hợp lệ.", "Please enter a valid GitHub Token.")
            }
            return false
        }
        guard let userURL = githubAPIURL(pathSegments: ["user"]) else { return false }

        isAuthenticating = true
        if !silentMigration {
            errorMessage = nil
            statusMessage = L10n.tr("Đang kiểm tra tài khoản GitHub...", "Verifying GitHub account...")
        }
        defer { isAuthenticating = false }

        do {
            let userReq = makeGitHubAPIRequest(url: userURL, token: token)
            let (data, resp) = try await URLSession.shared.data(for: userReq)
            guard let http = resp as? HTTPURLResponse else {
                if !silentMigration {
                    errorMessage = L10n.tr("Không nhận được phản hồi HTTP từ GitHub.", "No HTTP response from GitHub.")
                }
                return false
            }

            guard (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let login = json["login"] as? String, !login.isEmpty else {
                if !silentMigration {
                    let apiMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                    if http.statusCode == 401 {
                        errorMessage = L10n.tr("Token không hợp lệ hoặc đã bị thu hồi (HTTP 401).", "Invalid or revoked GitHub token (HTTP 401).")
                    } else {
                        errorMessage = apiMsg ?? L10n.tr("Đăng nhập GitHub thất bại (HTTP \(http.statusCode)).", "GitHub sign-in failed (HTTP \(http.statusCode)).")
                    }
                }
                return false
            }

            let idString: String
            if let numID = json["id"] as? Int {
                idString = String(numID)
            } else {
                idString = login.lowercased()
            }
            let displayName = ((json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? login
            let avatarURL = (json["avatar_url"] as? String) ?? ""
            var resolvedEmail = ((json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if resolvedEmail.isEmpty {
                resolvedEmail = await fetchPrimaryEmail(token: token) ?? "\(idString)+\(login)@users.noreply.github.com"
            }

            // Classic PATs & OAuth tokens report X-OAuth-Scopes header; Fine-grained PATs (github_pat_...) omit it.
            let oauthScopesEntry = http.allHeaderFields.first { key, _ in
                "\(key)".lowercased() == "x-oauth-scopes"
            }
            var hasPrivateAccess = false
            var scopesSummary = ""
            if let headerValue = oauthScopesEntry?.value as? String {
                let rawScopesHeader = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopes = rawScopesHeader
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                hasPrivateAccess = scopes.contains("repo")
                scopesSummary = scopes.isEmpty
                    ? L10n.tr("Không có scope (Chỉ đọc Public)", "No scopes (Public read-only)")
                    : scopes.joined(separator: ", ")
            } else {
                let canReadPrivate = await probePrivateRepoAccess(token: token)
                hasPrivateAccess = canReadPrivate
                scopesSummary = canReadPrivate
                    ? L10n.tr("Fine-grained / App Token (Private OK)", "Fine-grained / App Token (Private OK)")
                    : L10n.tr("Public Only (chỉ đọc repo công khai)", "Public Only (limited scope)")
            }

            let profile = GitHubAccountProfile(
                id: idString,
                login: login,
                name: displayName,
                email: resolvedEmail,
                avatarURL: avatarURL,
                authKind: authKind,
                hasPrivateRepoAccess: hasPrivateAccess,
                scopesSummary: scopesSummary,
                addedAt: Date()
            )

            KeychainVault.saveString(token, forKey: tokenKey(for: idString))
            KeychainVault.saveString(token, forKey: legacyPATKey)

            if let existingIdx = accounts.firstIndex(where: { $0.id == idString }) {
                accounts[existingIdx] = profile
            } else {
                accounts.insert(profile, at: 0)
            }
            activeAccountID = idString
            persistAccounts()

            statusMessage = L10n.tr("Đã kết nối @\(login) (\(hasPrivateAccess ? "Private & Public" : "Public")).", "Connected @\(login) (\(hasPrivateAccess ? "Private & Public" : "Public")).")
            await refreshRepositories(reset: true)
            return true
        } catch {
            if !silentMigration {
                errorMessage = L10n.tr("Lỗi kết nối GitHub: \(error.localizedDescription)", "GitHub connection error: \(error.localizedDescription)")
            }
            return false
        }
    }

    private func fetchPrimaryEmail(token: String) async -> String? {
        guard let url = githubAPIURL(pathSegments: ["user", "emails"]) else { return nil }
        let req = makeGitHubAPIRequest(url: url, token: token)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        if let primary = items.first(where: { ($0["primary"] as? Bool) == true && ($0["verified"] as? Bool) == true }),
           let email = primary["email"] as? String {
            return email
        }
        return items.first(where: { ($0["verified"] as? Bool) == true })?["email"] as? String
    }

    private func probePrivateRepoAccess(token: String) async -> Bool {
        guard let url = githubAPIURL(
            pathSegments: ["user", "repos"],
            queryItems: [
                URLQueryItem(name: "visibility", value: "private"),
                URLQueryItem(name: "per_page", value: "1")
            ]
        ) else {
            return false
        }
        let req = makeGitHubAPIRequest(url: url, token: token)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return false
        }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Multi-Account Switching & Sign Out
    public func switchActiveAccount(to id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountID = id
        persistAccounts()
        syncActiveTokenToLegacyPAT()
        repositories = []
        starredRepositories = []
        errorMessage = nil
        if let login = activeAccount?.login {
            statusMessage = L10n.tr("Đã chuyển sang tài khoản @\(login).", "Switched to @\(login).")
        }
        Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            await self.refreshRepositories(reset: true)
        }
    }

    public func signOutAccount(id: String) {
        accounts.removeAll { $0.id == id }
        KeychainVault.delete(forKey: tokenKey(for: id))
        if activeAccountID == id || activeAccountID == nil {
            activeAccountID = accounts.first?.id
        }
        persistAccounts()
        if let next = accounts.first {
            syncActiveTokenToLegacyPAT()
            statusMessage = L10n.tr("Đã đăng xuất tài khoản cũ, đang dùng @\(next.login).", "Signed out account; active account is @\(next.login).")
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                await self.refreshRepositories(reset: true)
            }
        } else {
            KeychainVault.delete(forKey: legacyPATKey)
            repositories = []
            starredRepositories = []
            hasMoreRepoPages = false
            statusMessage = L10n.tr("Đã đăng xuất khỏi GitHub.", "Signed out from GitHub.")
        }
    }

    // MARK: - Deep Link (`3012sync://github-auth`)
    public func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "3012sync",
              url.host?.lowercased() == "github-auth" else {
            return false
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let rawTok = (items.first(where: { $0.name == "token" })?.value ?? items.first(where: { $0.name == "pat" })?.value)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawTok.isEmpty {
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                _ = await self.signInWithToken(rawTok, authKind: "pat")
            }
        }
        return true
    }

    // MARK: - Repositories, Branches & Creation
    public func refreshRepositories(reset: Bool = true) async {
        let token = activeToken
        guard !token.isEmpty else {
            repositories = []
            starredRepositories = []
            hasMoreRepoPages = false
            return
        }

        let targetPage = reset ? 1 : (currentRepoPage + 1)
        isLoadingRepos = true
        errorMessage = nil
        defer { isLoadingRepos = false }

        guard let reposURL = githubAPIURL(
            pathSegments: ["user", "repos"],
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc"),
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
                URLQueryItem(name: "visibility", value: "all"),
                URLQueryItem(name: "page", value: String(targetPage))
            ]
        ) else {
            return
        }

        do {
            let repoReq = makeGitHubAPIRequest(url: reposURL, token: token)
            async let repoResponse = URLSession.shared.data(for: repoReq)

            var fetchedStarred: [GitHubRepoItem]? = nil
            var starredIDs = Set(starredRepositories.map(\.id))

            if reset,
               let starURL = githubAPIURL(
                   pathSegments: ["user", "starred"],
                   queryItems: [URLQueryItem(name: "per_page", value: "100")]
               ) {
                let starReq = makeGitHubAPIRequest(url: starURL, token: token)
                if let (starData, starResp) = try? await URLSession.shared.data(for: starReq),
                   let starHTTP = starResp as? HTTPURLResponse,
                   (200...299).contains(starHTTP.statusCode),
                   let starArray = try? JSONSerialization.jsonObject(with: starData) as? [[String: Any]] {
                    let parsedStars = starArray.compactMap { parseRepoJSON($0, forcedStarred: true) }
                    fetchedStarred = parsedStars
                    starredIDs = Set(parsedStars.map(\.id))
                }
            }

            let (repoData, resp) = try await repoResponse
            guard let http = resp as? HTTPURLResponse else {
                errorMessage = L10n.tr("Lỗi phản hồi từ GitHub API.", "Invalid GitHub API response.")
                return
            }
            guard (200...299).contains(http.statusCode),
                  let rawArray = try? JSONSerialization.jsonObject(with: repoData) as? [[String: Any]] else {
                let msg = (try? JSONSerialization.jsonObject(with: repoData) as? [String: Any])?["message"] as? String
                errorMessage = msg ?? L10n.tr("Không thể tải danh sách repo (HTTP \(http.statusCode)).", "Failed to load repositories (HTTP \(http.statusCode)).")
                return
            }

            let parsedPage = rawArray.compactMap { dict -> GitHubRepoItem? in
                guard var item = parseRepoJSON(dict) else { return nil }
                if starredIDs.contains(item.id) {
                    item.isStarred = true
                }
                return item
            }

            if let fetchedStarred {
                starredRepositories = fetchedStarred
            }

            if reset {
                repositories = parsedPage
                currentRepoPage = 1
            } else {
                var existingIDs = Set(repositories.map(\.id))
                for item in parsedPage where !existingIDs.contains(item.id) {
                    existingIDs.insert(item.id)
                    repositories.append(item)
                }
                currentRepoPage = targetPage
            }
            hasMoreRepoPages = (parsedPage.count == 100)

            let privateCount = repositories.filter(\.isPrivate).count
            statusMessage = L10n.tr(
                "Đã tải \(repositories.count) repo (\(privateCount) Private).",
                "Loaded \(repositories.count) repositories (\(privateCount) Private)."
            )
        } catch {
            errorMessage = L10n.tr("Lỗi tải kho repo: \(error.localizedDescription)", "Error loading repositories: \(error.localizedDescription)")
        }
    }

    public func fetchBranches(owner: String, repo: String) async -> [String] {
        guard let url = githubAPIURL(
            pathSegments: ["repos", owner, repo, "branches"],
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        ) else {
            return []
        }
        let req = makeGitHubAPIRequest(url: url, token: activeToken)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { $0["name"] as? String }
    }

    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepoItem {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw NSError(domain: "GitHubAccountService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: L10n.tr("Tên repository không được để trống.", "Repository name cannot be empty.")
            ])
        }
        let token = activeToken
        guard !token.isEmpty else {
            throw NSError(domain: "GitHubAccountService", code: 401, userInfo: [
                NSLocalizedDescriptionKey: L10n.tr("Bạn chưa kết nối tài khoản GitHub.", "No GitHub account connected.")
            ])
        }
        guard let url = githubAPIURL(pathSegments: ["user", "repos"]) else {
            throw NSError(domain: "GitHubAccountService", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Invalid GitHub API URL"
            ])
        }

        let payload: [String: Any] = [
            "name": cleanName,
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "private": isPrivate,
            "auto_init": true
        ]
        var req = makeGitHubAPIRequest(url: url, method: "POST", token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "GitHubAccountService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: L10n.tr("Không nhận được phản hồi từ GitHub.", "No response from GitHub.")
            ])
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200...201).contains(http.statusCode),
              let dict = json,
              let createdItem = parseRepoJSON(dict) else {
            let apiMsg = (json?["message"] as? String) ?? L10n.tr("Tạo repository thất bại (HTTP \(http.statusCode)).", "Failed to create repository (HTTP \(http.statusCode)).")
            throw NSError(domain: "GitHubAccountService", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: apiMsg
            ])
        }

        repositories.removeAll { $0.id == createdItem.id }
        repositories.insert(createdItem, at: 0)
        return createdItem
    }

    private func parseRepoJSON(_ dict: [String: Any], forcedStarred: Bool = false) -> GitHubRepoItem? {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String,
              let fullName = dict["full_name"] as? String else {
            return nil
        }
        let ownerDict = dict["owner"] as? [String: Any]
        let ownerLogin = (ownerDict?["login"] as? String) ?? (fullName.split(separator: "/").first.map(String.init) ?? "")
        let ownerType = (ownerDict?["type"] as? String) ?? ""
        let activeLogin = activeAccount?.login.lowercased() ?? ""
        let isOrg = (ownerType == "Organization") || (!activeLogin.isEmpty && ownerLogin.lowercased() != activeLogin)
        let updatedStr = dict["updated_at"] as? String ?? dict["pushed_at"] as? String
        let updatedAt = updatedStr.flatMap { isoFormatter.date(from: $0) } ?? Date()

        return GitHubRepoItem(
            id: id,
            name: name,
            fullName: fullName,
            ownerLogin: ownerLogin,
            isPrivate: (dict["private"] as? Bool) ?? false,
            isFork: (dict["fork"] as? Bool) ?? false,
            description: (dict["description"] as? String) ?? "",
            language: (dict["language"] as? String) ?? "",
            stargazersCount: (dict["stargazers_count"] as? Int) ?? 0,
            updatedAt: updatedAt,
            defaultBranch: ((dict["default_branch"] as? String)?.isEmpty == false ? (dict["default_branch"] as? String) : nil) ?? "main",
            cloneURL: (dict["clone_url"] as? String) ?? "https://github.com/\(fullName).git",
            htmlURL: (dict["html_url"] as? String) ?? "https://github.com/\(fullName)",
            isOrganizationRepo: isOrg,
            isStarred: forcedStarred
        )
    }
}
