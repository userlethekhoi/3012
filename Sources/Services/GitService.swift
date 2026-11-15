import Combine
import CryptoKit
import Foundation
import ZIPFoundation

private final class GitHubRedirectSanitizerDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var sanitized = request
        if sanitized.url?.host?.lowercased() != "api.github.com" {
            sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(sanitized)
    }
}

public struct GitChangedFile: Identifiable, Equatable {
    public var id: String { relativePath }
    public let relativePath: String
    public let statusBadge: String // "U", "A", "M", "D"
    public let diffKind: WorkspaceFileDiffStatus
    public let addedLines: Int
    public let removedLines: Int

    public init(
        relativePath: String,
        statusBadge: String,
        diffKind: WorkspaceFileDiffStatus = .modified,
        addedLines: Int = 0,
        removedLines: Int = 0
    ) {
        self.relativePath = relativePath
        self.statusBadge = statusBadge
        self.diffKind = diffKind
        self.addedLines = addedLines
        self.removedLines = removedLines
    }
}

public struct GitCommitRecord: Codable, Identifiable, Equatable {
    public let id: String
    public let message: String
    public let author: String
    public let timestamp: Date
    public let snapshotFiles: [String: String]
}

public struct UnifiedDiffLine: Identifiable, Equatable {
    public enum Kind: Equatable {
        case context
        case added
        case removed
    }
    public let id: Int
    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let text: String
}

@MainActor
public final class GitService: ObservableObject {
    @Published public var changedFiles: [GitChangedFile] = []
    @Published public var commits: [GitCommitRecord] = []
    @Published public var currentBranch: String = "main"
    @Published public var remoteOriginURL: String = ""
    @Published public var statusBanner: String = ""
    @Published public private(set) var isBusy: Bool = false
    @Published public var aheadCount: Int = 0
    @Published public var behindCount: Int = 0
    @Published public var lastPushRejectedNonFastForward: Bool = false
    @Published public var lastSyncedRemoteCommitSHA: String = ""

    private var pendingPushDeletePaths: [String] = []
    private var lastLoadedMetaWorkspacePath: String = ""

    private lazy var archiveDownloadSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg, delegate: GitHubRedirectSanitizerDelegate(), delegateQueue: nil)
    }()

    public var githubToken: String {
        get { KeychainVault.loadString(forKey: "git.github.pat") ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                KeychainVault.delete(forKey: "git.github.pat")
            } else {
                KeychainVault.saveString(trimmed, forKey: "git.github.pat")
            }
        }
    }

    public var resolvedGitHubToken: String {
        let acctToken = GitHubAccountService.shared.activeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !acctToken.isEmpty {
            return acctToken
        }
        return githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init() {}

    private func workspaceMetaDirectory(for workspaceRoot: URL) -> URL {
        WorkspaceManager.metaDirectory(for: workspaceRoot)
    }

    private func makeGitHubRequest(url: URL, method: String = "GET", pat: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("3012-Mobile-IDE/5.2", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let cleanPAT = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPAT.isEmpty {
            req.setValue("Bearer \(cleanPAT)", forHTTPHeaderField: "Authorization")
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

    private func metaFileURL(for workspaceRoot: URL) -> URL {
        workspaceMetaDirectory(for: workspaceRoot).appendingPathComponent("git.json")
    }

    private struct StoredRepoMeta: Codable {
        var branch: String
        var remoteURL: String
        var commits: [GitCommitRecord]
        var lastSyncedRemoteCommitSHA: String?
        var localAheadCount: Int?
        var pendingPushDeletePaths: [String]?
    }

    private func gitBlobSHA1(for data: Data) -> String {
        var payload = Data("blob \(data.count)\0".utf8)
        payload.append(data)
        let digest = Insecure.SHA1.hash(data: payload)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func githubErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = json["message"] as? String, !msg.isEmpty {
            return "\(msg) (HTTP \(statusCode))"
        }
        return "HTTP \(statusCode)"
    }

    public func refreshStatus(workspaceRoot: URL, sshService: SSHWorkspaceService?) async {
        if let ssh = sshService, ssh.isConnected {
            let safeDir = ssh.currentRemoteDirectory.replacingOccurrences(of: "'", with: "'\\''")
            let raw = await ssh.executeCommandOnVPS("cd '\(safeDir)' && git rev-parse --abbrev-ref HEAD 2>/dev/null && echo '---SPLIT---' && git status --porcelain 2>/dev/null")
            if raw.contains("---SPLIT---") {
                let parts = raw.components(separatedBy: "---SPLIT---")
                let branch = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !branch.isEmpty { currentBranch = branch }
                let lines = parts[1].components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                changedFiles = lines.compactMap { line in
                    let rawLine = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                    guard rawLine.count >= 3 else { return nil }
                    let xy = String(rawLine.prefix(2))
                    let code = xy.trimmingCharacters(in: .whitespaces)
                    var rawPath = String(rawLine.dropFirst(2))
                    if rawPath.hasPrefix(" ") {
                        rawPath.removeFirst()
                    }
                    rawPath = rawPath.trimmingCharacters(in: .whitespaces)
                    if (xy.contains("R") || xy.contains("C")),
                       let arrowRange = rawPath.range(of: " -> ", options: .backwards) {
                        rawPath = String(rawPath[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    }
                    if rawPath.hasPrefix("\""), rawPath.hasSuffix("\""), rawPath.count >= 2 {
                        rawPath = String(rawPath.dropFirst().dropLast())
                            .replacingOccurrences(of: "\\\"", with: "\"")
                            .replacingOccurrences(of: "\\\\", with: "\\")
                    }
                    guard !rawPath.isEmpty else { return nil }
                    let kind: WorkspaceFileDiffStatus
                    let badge: String
                    if code.contains("?") {
                        kind = .untrackedNew
                        badge = "U"
                    } else if code.contains("D") {
                        kind = .deleted
                        badge = "D"
                    } else if code.contains("A") {
                        kind = .addedCode
                        badge = "A"
                    } else {
                        kind = .modified
                        badge = "M"
                    }
                    return GitChangedFile(relativePath: rawPath, statusBadge: badge, diffKind: kind)
                }
                return
            }
        }

        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let currentDisk = collectWorkspaceTextFiles(at: workspaceRoot)
        let metaDir = workspaceMetaDirectory(for: workspaceRoot)
        let fallbackBaseline: [String: String] = {
            if let data = (try? Data(contentsOf: metaDir.appendingPathComponent("baseline.json")))
                ?? (try? Data(contentsOf: workspaceRoot.appendingPathComponent(".3012baseline.json"))),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let deletedGhosts: [String: String] = {
            if let data = (try? Data(contentsOf: metaDir.appendingPathComponent("deleted.json")))
                ?? (try? Data(contentsOf: workspaceRoot.appendingPathComponent(".3012deleted.json"))),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let baseline = commits.first?.snapshotFiles ?? fallbackBaseline

        var diffs: [GitChangedFile] = []
        for (path, content) in currentDisk {
            let status = WorkspaceFileDiffStatus.classify(baselineContent: baseline[path], currentContent: content)
            if status != .unchanged, let badge = status.badgeText {
                let delta = WorkspaceFileDiffStatus.lineDelta(baselineContent: baseline[path], currentContent: content)
                diffs.append(GitChangedFile(
                    relativePath: path,
                    statusBadge: badge,
                    diffKind: status,
                    addedLines: delta.added,
                    removedLines: delta.removed
                ))
            }
        }
        let allDeleted = Set(baseline.keys).union(deletedGhosts.keys).filter { currentDisk[$0] == nil }
        for oldPath in allDeleted {
            let oldText = baseline[oldPath] ?? deletedGhosts[oldPath]
            let delta = WorkspaceFileDiffStatus.lineDelta(baselineContent: oldText, currentContent: nil)
            diffs.append(GitChangedFile(
                relativePath: oldPath,
                statusBadge: "D",
                diffKind: .deleted,
                addedLines: 0,
                removedLines: delta.removed
            ))
        }
        diffs.sort { $0.relativePath < $1.relativePath }
        changedFiles = diffs
    }

    public func commitAll(message: String, workspaceRoot: URL, sshService: SSHWorkspaceService?) async {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else {
            statusBanner = L10n.tr("Vui lòng nhập nội dung commit.", "Please enter a commit message.")
            return
        }
        isBusy = true
        defer { isBusy = false }

        if let ssh = sshService, ssh.isConnected {
            let safeMsg = msg.replacingOccurrences(of: "'", with: "'\\''")
            let safeDir = ssh.currentRemoteDirectory.replacingOccurrences(of: "'", with: "'\\''")
            let out = await ssh.executeCommandOnVPS("cd '\(safeDir)' && git add -A && git commit -m '\(safeMsg)' 2>&1")
            statusBanner = out.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshStatus(workspaceRoot: workspaceRoot, sshService: sshService)
            return
        }

        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let currentPendingDeletes = Set(changedFiles.filter { $0.statusBadge == "D" }.map(\.relativePath))
        var mergedDeletes = Set(pendingPushDeletePaths)
        mergedDeletes.formUnion(currentPendingDeletes)
        let snapshot = collectWorkspaceTextFiles(at: workspaceRoot)
        mergedDeletes.subtract(snapshot.keys)
        pendingPushDeletePaths = Array(mergedDeletes).sorted()

        let shortSHA = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(7))
        let authorName = GitHubAccountService.shared.activeAccount?.login ?? "3012 Mobile Dev"
        let record = GitCommitRecord(
            id: shortSHA,
            message: msg,
            author: authorName,
            timestamp: Date(),
            snapshotFiles: snapshot
        )
        commits.insert(record, at: 0)
        if commits.count > 30 {
            commits = Array(commits.prefix(30))
        }
        if !remoteOriginURL.isEmpty {
            aheadCount += 1
        }
        saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
        statusBanner = "Committed [\(shortSHA)]: \(msg)"
    }

    public func discardChanges(for filePath: String, workspaceRoot: URL) async {
        guard WorkspaceManager.isSafeRelativeSyncPath(filePath) else { return }
        let rootCanon = WorkspaceManager.canonicalPath(workspaceRoot)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"
        let targetURL = workspaceRoot.appendingPathComponent(filePath)
        guard WorkspaceManager.canonicalPath(targetURL).hasPrefix(rootPrefix) else { return }

        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let metaDir = workspaceMetaDirectory(for: workspaceRoot)
        let fallbackBaseline: [String: String] = {
            if let data = (try? Data(contentsOf: metaDir.appendingPathComponent("baseline.json")))
                ?? (try? Data(contentsOf: workspaceRoot.appendingPathComponent(".3012baseline.json"))),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let deletedMetaURL = metaDir.appendingPathComponent("deleted.json")
        let legacyDeletedURL = workspaceRoot.appendingPathComponent(".3012deleted.json")
        var deletedGhosts: [String: String] = {
            if let data = (try? Data(contentsOf: deletedMetaURL))
                ?? (try? Data(contentsOf: legacyDeletedURL)),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let snapshot = commits.first?.snapshotFiles ?? fallbackBaseline
        if let oldContent = snapshot[filePath] ?? deletedGhosts[filePath] {
            if let current = try? String(contentsOf: targetURL, encoding: .utf8) {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: current, label: "Before Discard")
            }
            try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? oldContent.write(to: targetURL, atomically: true, encoding: .utf8)
            if deletedGhosts.removeValue(forKey: filePath) != nil {
                try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
                if let encoded = try? JSONEncoder().encode(deletedGhosts) {
                    try? encoded.write(to: deletedMetaURL, options: .atomic)
                }
                if FileManager.default.fileExists(atPath: legacyDeletedURL.path),
                   let encoded = try? JSONEncoder().encode(deletedGhosts) {
                    try? encoded.write(to: legacyDeletedURL, options: .atomic)
                }
            }
        } else {
            if let current = try? String(contentsOf: targetURL, encoding: .utf8) {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: current, label: "Before Discard Untracked")
            }
            try? FileManager.default.removeItem(at: targetURL)
        }
        if pendingPushDeletePaths.contains(filePath) {
            pendingPushDeletePaths.removeAll { $0 == filePath }
            saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        }
        await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
    }

    public func diffLines(for filePath: String, workspaceRoot: URL) -> [UnifiedDiffLine] {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let metaDir = workspaceMetaDirectory(for: workspaceRoot)
        let fallbackBaseline: [String: String] = {
            if let data = (try? Data(contentsOf: metaDir.appendingPathComponent("baseline.json")))
                ?? (try? Data(contentsOf: workspaceRoot.appendingPathComponent(".3012baseline.json"))),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let oldText = commits.first?.snapshotFiles[filePath] ?? fallbackBaseline[filePath] ?? ""
        let targetURL = workspaceRoot.appendingPathComponent(filePath)
        let newText = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        return computeOrderedUnifiedDiff(oldText: oldText, newText: newText)
    }

    public func diffPreview(for filePath: String, workspaceRoot: URL) -> String {
        let items = diffLines(for: filePath, workspaceRoot: workspaceRoot)
        var out: [String] = []
        out.append("--- a/\(filePath)")
        out.append("+++ b/\(filePath)")
        for item in items.prefix(350) {
            switch item.kind {
            case .removed: out.append("- \(item.text)")
            case .added: out.append("+ \(item.text)")
            case .context: out.append("  \(item.text)")
            }
        }
        if out.count == 2 {
            out.append("  (No changes)")
        }
        return out.joined(separator: "\n")
    }

    private func computeOrderedUnifiedDiff(oldText: String, newText: String) -> [UnifiedDiffLine] {
        let oldLines = oldText.isEmpty ? [] : oldText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let newLines = newText.isEmpty ? [] : newText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        if oldLines.count * newLines.count > 1_200_000 {
            var fast: [UnifiedDiffLine] = []
            var seq = 0
            for (idx, line) in oldLines.prefix(250).enumerated() {
                fast.append(UnifiedDiffLine(id: seq, kind: .removed, oldLineNumber: idx + 1, newLineNumber: nil, text: line))
                seq += 1
            }
            for (idx, line) in newLines.prefix(250).enumerated() {
                fast.append(UnifiedDiffLine(id: seq, kind: .added, oldLineNumber: nil, newLineNumber: idx + 1, text: line))
                seq += 1
            }
            return fast
        }

        let m = oldLines.count
        let n = newLines.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if oldLines[i] == newLines[j] {
                        dp[i][j] = dp[i + 1][j + 1] + 1
                    } else {
                        dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
        }

        var result: [UnifiedDiffLine] = []
        var i = 0
        var j = 0
        var seq = 0
        while i < m && j < n {
            if oldLines[i] == newLines[j] {
                result.append(UnifiedDiffLine(id: seq, kind: .context, oldLineNumber: i + 1, newLineNumber: j + 1, text: newLines[j]))
                i += 1
                j += 1
                seq += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                result.append(UnifiedDiffLine(id: seq, kind: .removed, oldLineNumber: i + 1, newLineNumber: nil, text: oldLines[i]))
                i += 1
                seq += 1
            } else {
                result.append(UnifiedDiffLine(id: seq, kind: .added, oldLineNumber: nil, newLineNumber: j + 1, text: newLines[j]))
                j += 1
                seq += 1
            }
        }
        while i < m {
            result.append(UnifiedDiffLine(id: seq, kind: .removed, oldLineNumber: i + 1, newLineNumber: nil, text: oldLines[i]))
            i += 1
            seq += 1
        }
        while j < n {
            result.append(UnifiedDiffLine(id: seq, kind: .added, oldLineNumber: nil, newLineNumber: j + 1, text: newLines[j]))
            j += 1
            seq += 1
        }
        return result
    }

    // MARK: - Clone GitHub Repository Directly on iOS (Supports Private & Public Repos via Redirect Sanitizer)
    public func cloneGitHubRepository(
        repoInput: String,
        into parentDocumentsURL: URL,
        branchOverride: String? = nil
    ) async -> URL? {
        guard let (owner, repo) = parseGitHubOwnerRepo(repoInput) else {
            statusBanner = L10n.tr("Nhập dạng owner/repo hoặc https://github.com/owner/repo", "Enter owner/repo or https://github.com/owner/repo")
            return nil
        }
        guard let metaURL = githubAPIURL(pathSegments: ["repos", owner, repo]) else {
            statusBanner = L10n.tr("Tên repository không hợp lệ.", "Invalid repository name.")
            return nil
        }

        isBusy = true
        statusBanner = L10n.tr("Đang tải repository \(owner)/\(repo) từ GitHub...", "Cloning \(owner)/\(repo) from GitHub...")
        defer { isBusy = false }

        do {
            let pat = resolvedGitHubToken
            let metaReq = makeGitHubRequest(url: metaURL, pat: pat)
            let (metaData, metaResp) = try await URLSession.shared.data(for: metaReq)
            let metaStatus = (metaResp as? HTTPURLResponse)?.statusCode ?? 0
            switch metaStatus {
            case 200...299:
                break
            case 401:
                statusBanner = L10n.tr("Token GitHub không hợp lệ hoặc đã hết hạn. Hãy đăng nhập lại trong GitHub Account.", "GitHub token expired or invalid (HTTP 401).")
                return nil
            case 403:
                statusBanner = L10n.tr("Token không đủ quyền truy cập \(owner)/\(repo) (cần scope repo hoặc Contents: Read).", "Insufficient GitHub permissions for \(owner)/\(repo) (HTTP 403).")
                return nil
            case 404:
                statusBanner = pat.isEmpty
                    ? L10n.tr("Không tìm thấy \(owner)/\(repo). Nếu là Private Repo, hãy kết nối Tài khoản GitHub trước.", "Repository \(owner)/\(repo) not found (connect GitHub Account if Private).")
                    : L10n.tr("Không tìm thấy \(owner)/\(repo) hoặc tài khoản chưa được cấp quyền truy cập.", "Repository \(owner)/\(repo) not found or unauthorized.")
                return nil
            default:
                statusBanner = L10n.tr("Lỗi đọc thông tin repo: \(githubErrorMessage(from: metaData, statusCode: metaStatus))", "Repo lookup failed: \(githubErrorMessage(from: metaData, statusCode: metaStatus))")
                return nil
            }

            var defaultBranch = "main"
            if let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
               let br = json["default_branch"] as? String, !br.isEmpty {
                defaultBranch = br
            }

            let cleanOverride = branchOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetBranch = (cleanOverride?.isEmpty == false) ? cleanOverride! : defaultBranch
            let branchSegments = targetBranch.split(separator: "/").map(String.init)
            guard let zipEndpoint = githubAPIURL(pathSegments: ["repos", owner, repo, "zipball"] + branchSegments) else {
                statusBanner = L10n.tr("Nhánh không hợp lệ.", "Invalid branch name.")
                return nil
            }

            let zipReq = makeGitHubRequest(url: zipEndpoint, pat: pat)
            let (tempZipURL, response) = try await archiveDownloadSession.download(for: zipReq)
            defer { try? FileManager.default.removeItem(at: tempZipURL) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 404 {
                    statusBanner = L10n.tr("Repo \(owner)/\(repo) đang trống (chưa có commit trên nhánh '\(targetBranch)').", "Repository branch '\(targetBranch)' is empty or missing (HTTP 404).")
                } else {
                    statusBanner = L10n.tr("Tải archive thất bại (HTTP \(code)).", "Failed to download archive (HTTP \(code)).")
                }
                return nil
            }

            let remoteHeadSHA = await fetchRemoteBranchHeadSHA(owner: owner, repo: repo, branch: targetBranch, pat: pat) ?? ""

            let fm = FileManager.default
            let extractTemp = fm.temporaryDirectory.appendingPathComponent("gh_clone_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: extractTemp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractTemp) }
            try fm.unzipItem(at: tempZipURL, to: extractTemp)

            let innerItems = (try? fm.contentsOfDirectory(at: extractTemp, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let extractedRoot = innerItems.first(where: { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir && item.lastPathComponent != "__MACOSX"
            }) ?? innerItems.first ?? extractTemp

            var destination = parentDocumentsURL.appendingPathComponent(repo, isDirectory: true)
            if fm.fileExists(atPath: destination.path) {
                let existing = (try? fm.contentsOfDirectory(atPath: destination.path)) ?? []
                if existing.isEmpty {
                    try? fm.removeItem(at: destination)
                } else {
                    var suffix = 2
                    while fm.fileExists(atPath: parentDocumentsURL.appendingPathComponent("\(repo)-\(suffix)", isDirectory: true).path) {
                        suffix += 1
                    }
                    destination = parentDocumentsURL.appendingPathComponent("\(repo)-\(suffix)", isDirectory: true)
                }
            }
            try fm.moveItem(at: extractedRoot, to: destination)

            self.currentBranch = targetBranch
            self.remoteOriginURL = "https://github.com/\(owner)/\(repo).git"
            self.lastSyncedRemoteCommitSHA = remoteHeadSHA
            self.aheadCount = 0
            self.behindCount = 0
            self.pendingPushDeletePaths = []
            self.lastPushRejectedNonFastForward = false
            self.lastLoadedMetaWorkspacePath = WorkspaceManager.canonicalPath(destination)

            let initialFiles = collectWorkspaceTextFiles(at: destination)
            self.commits = [
                GitCommitRecord(
                    id: remoteHeadSHA.isEmpty ? "initial" : String(remoteHeadSHA.prefix(7)),
                    message: "Cloned \(owner)/\(repo) (\(targetBranch))",
                    author: owner,
                    timestamp: Date(),
                    snapshotFiles: initialFiles
                )
            ]
            saveLocalRepoMeta(workspaceRoot: destination)
            await refreshStatus(workspaceRoot: destination, sshService: nil)
            statusBanner = L10n.tr(
                "Đã clone \(owner)/\(repo) (\(targetBranch)) vào \(destination.lastPathComponent).",
                "Cloned \(owner)/\(repo) (\(targetBranch)) to \(destination.lastPathComponent)."
            )
            return destination
        } catch {
            statusBanner = L10n.tr("Lỗi clone GitHub: \(error.localizedDescription)", "GitHub clone error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Atomic Single-Commit Push via GitHub Git Data Tree API
    @discardableResult
    public func pushToGitHubREST(
        workspaceRoot: URL,
        commitMessage: String,
        force: Bool = false,
        pushAllWorkspaceFiles: Bool = false
    ) async -> Bool {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        lastPushRejectedNonFastForward = false

        let pat = resolvedGitHubToken
        guard !pat.isEmpty else {
            statusBanner = L10n.tr("Hãy kết nối Tài khoản GitHub hoặc nhập Token (PAT) để Push.", "Connect your GitHub Account or enter a Token to push.")
            return false
        }
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            statusBanner = L10n.tr("Chưa có Remote GitHub URL (owner/repo).", "No GitHub remote URL configured.")
            return false
        }

        isBusy = true
        statusBanner = L10n.tr("Đang đồng bộ nguyên tử lên \(owner)/\(repo) (\(currentBranch))...", "Pushing atomic commit to \(owner)/\(repo) (\(currentBranch))...")
        defer { isBusy = false }

        if !pushAllWorkspaceFiles {
            await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
        }

        var upsertPaths: [String]
        var deletePaths: [String]
        if pushAllWorkspaceFiles {
            upsertPaths = collectWorkspacePushableRelativePaths(at: workspaceRoot)
            deletePaths = []
        } else {
            var upsertSet = Set(changedFiles.filter { $0.statusBadge != "D" }.map(\.relativePath))
            var deleteSet = Set(changedFiles.filter { $0.statusBadge == "D" }.map(\.relativePath))
            deleteSet.formUnion(pendingPushDeletePaths)

            if aheadCount > 0 {
                // User tapped "Commit All" before "Push": include committed workspace files alongside any new working-tree edits
                upsertSet.formUnion(collectWorkspacePushableRelativePaths(at: workspaceRoot))
            }
            deleteSet.subtract(upsertSet)
            upsertPaths = Array(upsertSet).sorted()
            deletePaths = Array(deleteSet).sorted()
        }

        guard !upsertPaths.isEmpty || !deletePaths.isEmpty else {
            statusBanner = L10n.tr("Không có thay đổi nào cần Push.", "Working tree is clean — nothing to push.")
            return false
        }

        do {
            guard let (initialCommitSHA, bootstrappedFirstPath) = try await ensureRemoteBranchRefExists(
                owner: owner,
                repo: repo,
                branch: currentBranch,
                firstBootstrapFile: upsertPaths.first,
                workspaceRoot: workspaceRoot,
                commitMessage: commitMessage,
                pat: pat
            ) else {
                return false
            }

            if let bootstrappedFirstPath, upsertPaths.count == 1 && deletePaths.isEmpty && upsertPaths[0] == bootstrappedFirstPath {
                return finalizeSuccessfulPush(
                    commitSHA: initialCommitSHA,
                    commitMessage: commitMessage,
                    workspaceRoot: workspaceRoot,
                    owner: owner,
                    repo: repo,
                    uploadedCount: 1,
                    deletedCount: 0
                )
            }

            // 1. Read commit object -> base tree SHA
            guard let commitURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "commits", initialCommitSHA]) else {
                statusBanner = "Invalid GitHub commit URL."
                return false
            }
            let (commitData, commitResp) = try await URLSession.shared.data(for: makeGitHubRequest(url: commitURL, pat: pat))
            let commitHTTP = (commitResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(commitHTTP),
                  let commitJSON = try? JSONSerialization.jsonObject(with: commitData) as? [String: Any],
                  let treeObj = commitJSON["tree"] as? [String: Any],
                  let baseTreeSHA = treeObj["sha"] as? String else {
                statusBanner = L10n.tr("Không đọc được commit trên GitHub: \(githubErrorMessage(from: commitData, statusCode: commitHTTP))", "Failed to read remote commit: \(githubErrorMessage(from: commitData, statusCode: commitHTTP))")
                return false
            }

            // 2. Fetch existing remote tree paths & blob SHAs so we never send sha: null for untracked ghosts or re-upload identical blobs
            guard let remoteTreeURL = githubAPIURL(
                pathSegments: ["repos", owner, repo, "git", "trees", baseTreeSHA],
                queryItems: [URLQueryItem(name: "recursive", value: "1")]
            ) else {
                statusBanner = "Invalid GitHub tree URL."
                return false
            }
            let (remoteTreeData, remoteTreeResp) = try await URLSession.shared.data(for: makeGitHubRequest(url: remoteTreeURL, pat: pat))
            let remoteTreeHTTP = (remoteTreeResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(remoteTreeHTTP),
                  let remoteTreeJSON = try? JSONSerialization.jsonObject(with: remoteTreeData) as? [String: Any],
                  let remoteNodes = remoteTreeJSON["tree"] as? [[String: Any]] else {
                statusBanner = L10n.tr("Không đọc được cây file trên GitHub: \(githubErrorMessage(from: remoteTreeData, statusCode: remoteTreeHTTP))", "Failed to inspect remote tree: \(githubErrorMessage(from: remoteTreeData, statusCode: remoteTreeHTTP))")
                return false
            }

            var remotePaths = Set<String>()
            var remoteBlobSHAs: [String: String] = [:]
            for node in remoteNodes {
                guard (node["type"] as? String) == "blob",
                      let path = node["path"] as? String else { continue }
                remotePaths.insert(path)
                if let sha = node["sha"] as? String {
                    remoteBlobSHAs[path] = sha
                }
            }

            // 3. Create Git blobs for new/changed files
            guard let blobsURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "blobs"]) else { return false }
            var treeEntries: [[String: Any]] = []
            var uploadedCount = 0
            var skippedLargeCount = 0

            for relPath in upsertPaths {
                let fileURL = workspaceRoot.appendingPathComponent(relPath)
                guard let fileData = try? Data(contentsOf: fileURL) else { continue }
                if fileData.count > 2_000_000 {
                    skippedLargeCount += 1
                    continue
                }
                let localSHA1 = gitBlobSHA1(for: fileData)
                if remoteBlobSHAs[relPath] == localSHA1 {
                    continue
                }

                let blobPayload: [String: Any] = [
                    "content": fileData.base64EncodedString(),
                    "encoding": "base64"
                ]
                var blobReq = makeGitHubRequest(url: blobsURL, method: "POST", pat: pat)
                blobReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                blobReq.httpBody = try JSONSerialization.data(withJSONObject: blobPayload)

                let (blobData, blobResp) = try await URLSession.shared.data(for: blobReq)
                let blobHTTP = (blobResp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(blobHTTP),
                      let blobJSON = try? JSONSerialization.jsonObject(with: blobData) as? [String: Any],
                      let blobSHA = blobJSON["sha"] as? String else {
                    statusBanner = L10n.tr(
                        "Lỗi upload blob '\(relPath)': \(githubErrorMessage(from: blobData, statusCode: blobHTTP))",
                        "Failed uploading blob '\(relPath)': \(githubErrorMessage(from: blobData, statusCode: blobHTTP))"
                    )
                    return false
                }
                treeEntries.append([
                    "path": relPath,
                    "mode": "100644",
                    "type": "blob",
                    "sha": blobSHA
                ])
                uploadedCount += 1
            }

            var deletedCount = 0
            for delPath in deletePaths where remotePaths.contains(delPath) {
                treeEntries.append([
                    "path": delPath,
                    "mode": "100644",
                    "type": "blob",
                    "sha": NSNull()
                ])
                deletedCount += 1
            }

            if treeEntries.isEmpty {
                if bootstrappedFirstPath != nil {
                    let ok = finalizeSuccessfulPush(
                        commitSHA: initialCommitSHA,
                        commitMessage: commitMessage,
                        workspaceRoot: workspaceRoot,
                        owner: owner,
                        repo: repo,
                        uploadedCount: 1,
                        deletedCount: 0,
                        skippedLargeCount: skippedLargeCount
                    )
                    await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
                    return ok
                }
                aheadCount = 0
                pendingPushDeletePaths = []
                lastSyncedRemoteCommitSHA = initialCommitSHA
                saveLocalRepoMeta(workspaceRoot: workspaceRoot)
                await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
                statusBanner = L10n.tr(
                    "Code trên máy đã trùng khớp hoàn toàn với GitHub (\(owner)/\(repo)).",
                    "Remote \(owner)/\(repo) is already up to date."
                )
                return true
            }

            // 4. Create new tree
            guard let createTreeURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "trees"]) else { return false }
            let treeBody: [String: Any] = [
                "base_tree": baseTreeSHA,
                "tree": treeEntries
            ]
            var treeReq = makeGitHubRequest(url: createTreeURL, method: "POST", pat: pat)
            treeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            treeReq.httpBody = try JSONSerialization.data(withJSONObject: treeBody)

            let (newTreeData, newTreeResp) = try await URLSession.shared.data(for: treeReq)
            let newTreeHTTP = (newTreeResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(newTreeHTTP),
                  let newTreeJSON = try? JSONSerialization.jsonObject(with: newTreeData) as? [String: Any],
                  let newTreeSHA = newTreeJSON["sha"] as? String else {
                statusBanner = L10n.tr("Tạo Git Tree thất bại: \(githubErrorMessage(from: newTreeData, statusCode: newTreeHTTP))", "Failed creating Git tree: \(githubErrorMessage(from: newTreeData, statusCode: newTreeHTTP))")
                return false
            }

            // 5. Create atomic commit
            guard let createCommitURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "commits"]) else { return false }
            let finalMessage = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Sync from 3012 Mobile IDE"
                : commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            var commitBody: [String: Any] = [
                "message": finalMessage,
                "tree": newTreeSHA,
                "parents": [initialCommitSHA]
            ]
            if let acct = GitHubAccountService.shared.activeAccount, !acct.email.isEmpty {
                commitBody["author"] = [
                    "name": acct.name.isEmpty ? acct.login : acct.name,
                    "email": acct.email
                ]
            }

            var newCommitReq = makeGitHubRequest(url: createCommitURL, method: "POST", pat: pat)
            newCommitReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            newCommitReq.httpBody = try JSONSerialization.data(withJSONObject: commitBody)

            let (newCommitData, newCommitResp) = try await URLSession.shared.data(for: newCommitReq)
            let newCommitHTTP = (newCommitResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(newCommitHTTP),
                  let newCommitJSON = try? JSONSerialization.jsonObject(with: newCommitData) as? [String: Any],
                  let newCommitSHA = newCommitJSON["sha"] as? String else {
                statusBanner = L10n.tr("Tạo Commit thất bại: \(githubErrorMessage(from: newCommitData, statusCode: newCommitHTTP))", "Failed creating commit: \(githubErrorMessage(from: newCommitData, statusCode: newCommitHTTP))")
                return false
            }

            // 6. Fast-forward (or force) branch ref
            let branchSegments = currentBranch.split(separator: "/").map(String.init)
            guard let patchRefURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "refs", "heads"] + branchSegments) else { return false }
            let patchBody: [String: Any] = [
                "sha": newCommitSHA,
                "force": force
            ]
            var patchReq = makeGitHubRequest(url: patchRefURL, method: "PATCH", pat: pat)
            patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            patchReq.httpBody = try JSONSerialization.data(withJSONObject: patchBody)

            let (patchData, patchResp) = try await URLSession.shared.data(for: patchReq)
            let patchHTTP = (patchResp as? HTTPURLResponse)?.statusCode ?? 0
            if patchHTTP == 422 && !force {
                lastPushRejectedNonFastForward = true
                statusBanner = L10n.tr(
                    "Push bị từ chối (Non-fast-forward): Remote có commit mới hơn. Hãy Pull trước hoặc bấm Force Push.",
                    "Push rejected (non-fast-forward): remote has newer commits. Pull first or Force Push."
                )
                return false
            }
            guard (200...299).contains(patchHTTP) else {
                statusBanner = L10n.tr("Cập nhật nhánh thất bại: \(githubErrorMessage(from: patchData, statusCode: patchHTTP))", "Failed updating branch ref: \(githubErrorMessage(from: patchData, statusCode: patchHTTP))")
                return false
            }

            let ok = finalizeSuccessfulPush(
                commitSHA: newCommitSHA,
                commitMessage: finalMessage,
                workspaceRoot: workspaceRoot,
                owner: owner,
                repo: repo,
                uploadedCount: uploadedCount,
                deletedCount: deletedCount,
                skippedLargeCount: skippedLargeCount
            )
            await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
            return ok
        } catch {
            statusBanner = L10n.tr("Lỗi Git Push: \(error.localizedDescription)", "Git Push error: \(error.localizedDescription)")
            return false
        }
    }

    private func finalizeSuccessfulPush(
        commitSHA: String,
        commitMessage: String,
        workspaceRoot: URL,
        owner: String,
        repo: String,
        uploadedCount: Int,
        deletedCount: Int,
        skippedLargeCount: Int = 0
    ) -> Bool {
        let finalMsg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Sync from 3012 Mobile IDE"
            : commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorName = GitHubAccountService.shared.activeAccount?.login ?? "3012 Mobile Dev"
        let record = GitCommitRecord(
            id: String(commitSHA.prefix(7)),
            message: finalMsg,
            author: authorName,
            timestamp: Date(),
            snapshotFiles: collectWorkspaceTextFiles(at: workspaceRoot)
        )
        commits.insert(record, at: 0)
        if commits.count > 30 {
            commits = Array(commits.prefix(30))
        }
        lastSyncedRemoteCommitSHA = commitSHA
        aheadCount = 0
        behindCount = 0
        pendingPushDeletePaths = []
        lastPushRejectedNonFastForward = false
        saveLocalRepoMeta(workspaceRoot: workspaceRoot)

        var summary = L10n.tr(
            "Đã Push 1 commit [\(String(commitSHA.prefix(7)))] (+\(uploadedCount) / -\(deletedCount) file) lên \(owner)/\(repo).",
            "Pushed atomic commit [\(String(commitSHA.prefix(7)))] (+\(uploadedCount) / -\(deletedCount)) to \(owner)/\(repo)."
        )
        if skippedLargeCount > 0 {
            summary += L10n.tr(" (Bỏ qua \(skippedLargeCount) file >2MB)", " (Skipped \(skippedLargeCount) files >2MB)")
        }
        statusBanner = summary
        return true
    }

    private func ensureRemoteBranchRefExists(
        owner: String,
        repo: String,
        branch: String,
        firstBootstrapFile: String?,
        workspaceRoot: URL,
        commitMessage: String,
        pat: String
    ) async throws -> (commitSHA: String, bootstrappedPath: String?)? {
        let branchSegments = branch.split(separator: "/").map(String.init)
        guard let refURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "ref", "heads"] + branchSegments) else {
            return nil
        }
        let (refData, refResp) = try await URLSession.shared.data(for: makeGitHubRequest(url: refURL, pat: pat))
        let refHTTP = (refResp as? HTTPURLResponse)?.statusCode ?? 0
        if (200...299).contains(refHTTP),
           let json = try? JSONSerialization.jsonObject(with: refData) as? [String: Any],
           let obj = json["object"] as? [String: Any],
           let sha = obj["sha"] as? String {
            return (sha, nil)
        }

        // Check if repo has a default branch we can branch from, OR is completely empty
        if let repoURL = githubAPIURL(pathSegments: ["repos", owner, repo]),
           let (repoData, repoResp) = try? await URLSession.shared.data(for: makeGitHubRequest(url: repoURL, pat: pat)),
           let repoHTTP = (repoResp as? HTTPURLResponse)?.statusCode,
           (200...299).contains(repoHTTP),
           let repoJSON = try? JSONSerialization.jsonObject(with: repoData) as? [String: Any],
           let defaultBranch = repoJSON["default_branch"] as? String,
           defaultBranch != branch {
            let defSegs = defaultBranch.split(separator: "/").map(String.init)
            if let defRefURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "ref", "heads"] + defSegs),
               let (defData, defResp) = try? await URLSession.shared.data(for: makeGitHubRequest(url: defRefURL, pat: pat)),
               let defHTTP = (defResp as? HTTPURLResponse)?.statusCode,
               (200...299).contains(defHTTP),
               let defJSON = try? JSONSerialization.jsonObject(with: defData) as? [String: Any],
               let defObj = defJSON["object"] as? [String: Any],
               let baseSHA = defObj["sha"] as? String,
               let createRefsURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "refs"]) {
                var createReq = makeGitHubRequest(url: createRefsURL, method: "POST", pat: pat)
                createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                createReq.httpBody = try JSONSerialization.data(withJSONObject: [
                    "ref": "refs/heads/\(branch)",
                    "sha": baseSHA
                ])
                let (_, cResp) = try await URLSession.shared.data(for: createReq)
                if let cHTTP = (cResp as? HTTPURLResponse)?.statusCode, (200...201).contains(cHTTP) {
                    return (baseSHA, nil)
                }
            }
        }

        // Completely empty repository (HTTP 404/409): bootstrap first file via Contents API so Git Data API unlocks
        if refHTTP == 404 || refHTTP == 409,
           let firstPath = firstBootstrapFile,
           let firstData = try? Data(contentsOf: workspaceRoot.appendingPathComponent(firstPath)),
           let contentsURL = githubAPIURL(pathSegments: ["repos", owner, repo, "contents"] + firstPath.split(separator: "/").map(String.init)) {
            let putBody: [String: Any] = [
                "message": commitMessage.isEmpty ? "Initial commit from 3012 Mobile IDE" : commitMessage,
                "content": firstData.base64EncodedString(),
                "branch": branch
            ]
            var putReq = makeGitHubRequest(url: contentsURL, method: "PUT", pat: pat)
            putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            putReq.httpBody = try JSONSerialization.data(withJSONObject: putBody)
            let (putData, putResp) = try await URLSession.shared.data(for: putReq)
            let putHTTP = (putResp as? HTTPURLResponse)?.statusCode ?? 0
            if (200...201).contains(putHTTP),
               let putJSON = try? JSONSerialization.jsonObject(with: putData) as? [String: Any],
               let commitObj = putJSON["commit"] as? [String: Any],
               let sha = commitObj["sha"] as? String {
                return (sha, firstPath)
            }
            statusBanner = L10n.tr("Không khởi tạo được repo trống: \(githubErrorMessage(from: putData, statusCode: putHTTP))", "Failed bootstrapping empty repo: \(githubErrorMessage(from: putData, statusCode: putHTTP))")
            return nil
        }

        statusBanner = L10n.tr("Không đọc được nhánh '\(branch)': \(githubErrorMessage(from: refData, statusCode: refHTTP))", "Failed reading branch '\(branch)': \(githubErrorMessage(from: refData, statusCode: refHTTP))")
        return nil
    }

    public func fetchRemoteBranches() async -> [String] {
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else { return [currentBranch] }
        let pat = resolvedGitHubToken
        guard let url = githubAPIURL(pathSegments: ["repos", owner, repo, "branches"], queryItems: [URLQueryItem(name: "per_page", value: "50")]) else { return [currentBranch] }
        let req = makeGitHubRequest(url: url, pat: pat)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [currentBranch]
        }
        let names = arr.compactMap { $0["name"] as? String }
        return names.isEmpty ? [currentBranch] : names
    }

    private func fetchRemoteBranchHeadSHA(owner: String, repo: String, branch: String, pat: String) async -> String? {
        let branchSegs = branch.split(separator: "/").map(String.init)
        guard let url = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "ref", "heads"] + branchSegs) else {
            return nil
        }
        let req = makeGitHubRequest(url: url, pat: pat)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = json["object"] as? [String: Any],
              let sha = obj["sha"] as? String else {
            return nil
        }
        return sha
    }

    @discardableResult
    public func pullFromGitHub(into workspaceRoot: URL, branchOverride: String? = nil) async -> Bool {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            statusBanner = L10n.tr("Chưa có Remote GitHub URL (owner/repo).", "No GitHub remote URL configured.")
            return false
        }
        let cleanOverride = branchOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetBranch = (cleanOverride?.isEmpty == false) ? cleanOverride! : currentBranch

        isBusy = true
        statusBanner = L10n.tr("Đang Pull nhánh '\(targetBranch)' từ \(owner)/\(repo)...", "Pulling branch '\(targetBranch)' from \(owner)/\(repo)...")
        defer { isBusy = false }

        do {
            let pat = resolvedGitHubToken
            let branchSegments = targetBranch.split(separator: "/").map(String.init)
            guard let zipEndpoint = githubAPIURL(pathSegments: ["repos", owner, repo, "zipball"] + branchSegments) else {
                statusBanner = L10n.tr("URL nhánh không hợp lệ.", "Invalid branch URL.")
                return false
            }
            let zipReq = makeGitHubRequest(url: zipEndpoint, pat: pat)
            let (tempZipURL, response) = try await archiveDownloadSession.download(for: zipReq)
            defer { try? FileManager.default.removeItem(at: tempZipURL) }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 401 || code == 403 || code == 404 {
                    statusBanner = L10n.tr(
                        "Pull thất bại (HTTP \(code)): kiểm tra Tài khoản GitHub hoặc quyền truy cập nhánh '\(targetBranch)'.",
                        "Pull failed (HTTP \(code)): check GitHub Account or branch '\(targetBranch)' access."
                    )
                } else {
                    statusBanner = L10n.tr("Pull thất bại (HTTP \(code)).", "Pull failed (HTTP \(code)).")
                }
                return false
            }

            let remoteHeadSHA = await fetchRemoteBranchHeadSHA(owner: owner, repo: repo, branch: targetBranch, pat: pat) ?? ""

            let fm = FileManager.default
            let extractTemp = fm.temporaryDirectory.appendingPathComponent("gh_pull_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: extractTemp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractTemp) }
            try fm.unzipItem(at: tempZipURL, to: extractTemp)
            let innerItems = (try? fm.contentsOfDirectory(at: extractTemp, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let extractedRoot = innerItems.first(where: { item in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir && item.lastPathComponent != "__MACOSX"
            }) ?? innerItems.first ?? extractTemp

            let previousBaseline = commits.first?.snapshotFiles ?? [:]
            let (updatedCount, archiveRelPaths) = try copyAllPulledFiles(from: extractedRoot, into: workspaceRoot)

            // Remove tracked files that were deleted upstream ONLY when they have no local uncommitted edits
            var removedCount = 0
            for (trackedRel, oldText) in previousBaseline where !archiveRelPaths.contains(trackedRel) {
                guard WorkspaceManager.isSafeRelativeSyncPath(trackedRel) else { continue }
                let localURL = workspaceRoot.appendingPathComponent(trackedRel)
                guard fm.fileExists(atPath: localURL.path) else { continue }
                if let currentLocalText = try? String(contentsOf: localURL, encoding: .utf8), currentLocalText == oldText {
                    FileTimelineAndArchiveService.shared.recordSnapshot(for: localURL, content: currentLocalText, label: "Before Git Pull Remove")
                    try? fm.removeItem(at: localURL)
                    removedCount += 1
                }
            }

            self.currentBranch = targetBranch
            if !remoteHeadSHA.isEmpty {
                self.lastSyncedRemoteCommitSHA = remoteHeadSHA
            }
            self.aheadCount = 0
            self.behindCount = 0
            self.pendingPushDeletePaths = []
            self.lastPushRejectedNonFastForward = false

            let latestCommit = GitCommitRecord(
                id: remoteHeadSHA.isEmpty ? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(7)) : String(remoteHeadSHA.prefix(7)),
                message: "Pulled \(owner)/\(repo) (\(targetBranch))",
                author: owner,
                timestamp: Date(),
                snapshotFiles: collectWorkspaceTextFiles(at: workspaceRoot)
            )
            commits.insert(latestCommit, at: 0)
            if commits.count > 30 { commits = Array(commits.prefix(30)) }
            saveLocalRepoMeta(workspaceRoot: workspaceRoot)
            await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
            statusBanner = L10n.tr(
                "Đã Pull nhánh '\(targetBranch)' (+\(updatedCount) cập nhật, -\(removedCount) file xóa từ remote).",
                "Pulled '\(targetBranch)' (\(updatedCount) updated, \(removedCount) deleted upstream)."
            )
            return true
        } catch {
            statusBanner = L10n.tr("Lỗi Git Pull: \(error.localizedDescription)", "Git Pull error: \(error.localizedDescription)")
            return false
        }
    }

    public func refreshRemoteDivergence(workspaceRoot: URL) async {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        guard !lastSyncedRemoteCommitSHA.isEmpty,
              let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            return
        }
        let pat = resolvedGitHubToken
        let rangeExpr = "\(lastSyncedRemoteCommitSHA)...\(currentBranch)"
        guard let url = githubAPIURL(pathSegments: ["repos", owner, repo, "compare", rangeExpr]) else { return }
        let req = makeGitHubRequest(url: url, pat: pat)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        behindCount = (json["ahead_by"] as? Int) ?? 0
    }

    @discardableResult
    public func createAndCheckoutBranch(name: String, workspaceRoot: URL) async -> Bool {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !clean.contains(" "),
              !clean.contains(".."),
              !clean.hasPrefix("/"),
              !clean.hasSuffix("/") else {
            statusBanner = L10n.tr("Tên branch không hợp lệ (không chứa khoảng trắng hoặc '..').", "Invalid branch name.")
            return false
        }

        if let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL), !resolvedGitHubToken.isEmpty {
            let pat = resolvedGitHubToken
            if let baseSHA = await fetchRemoteBranchHeadSHA(owner: owner, repo: repo, branch: currentBranch, pat: pat),
               let createRefsURL = githubAPIURL(pathSegments: ["repos", owner, repo, "git", "refs"]) {
                var req = makeGitHubRequest(url: createRefsURL, method: "POST", pat: pat)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: [
                    "ref": "refs/heads/\(clean)",
                    "sha": baseSHA
                ])
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse {
                    if !(200...201).contains(http.statusCode) && http.statusCode != 422 {
                        statusBanner = L10n.tr("Tạo branch trên GitHub thất bại: \(githubErrorMessage(from: data, statusCode: http.statusCode))", "Failed creating remote branch: \(githubErrorMessage(from: data, statusCode: http.statusCode))")
                        return false
                    }
                    lastSyncedRemoteCommitSHA = baseSHA
                }
            }
        }

        currentBranch = clean
        saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        statusBanner = L10n.tr("Đã chuyển sang nhánh '\(clean)'.", "Switched to branch '\(clean)'.")
        return true
    }

    public func createPullRequest(title: String, body: String, head: String? = nil, base: String = "main") async -> String? {
        let pat = resolvedGitHubToken
        guard !pat.isEmpty else {
            statusBanner = L10n.tr("Cần kết nối Tài khoản GitHub để tạo Pull Request.", "Connect your GitHub Account to create a Pull Request.")
            return nil
        }
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL),
              let url = githubAPIURL(pathSegments: ["repos", owner, repo, "pulls"]) else {
            statusBanner = L10n.tr("Workspace hiện chưa có Remote GitHub.", "No GitHub remote configured for this workspace.")
            return nil
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            statusBanner = L10n.tr("Nhập tiêu đề Pull Request.", "Enter a Pull Request title.")
            return nil
        }
        let sourceHead = (head?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? currentBranch
        let targetBase = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : base.trimmingCharacters(in: .whitespacesAndNewlines)

        isBusy = true
        defer { isBusy = false }

        do {
            var req = makeGitHubRequest(url: url, method: "POST", pat: pat)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "title": cleanTitle,
                "body": body,
                "head": sourceHead,
                "base": targetBase
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...201).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let htmlURL = json["html_url"] as? String else {
                statusBanner = L10n.tr("Tạo PR thất bại: \(githubErrorMessage(from: data, statusCode: code))", "PR creation failed: \(githubErrorMessage(from: data, statusCode: code))")
                return nil
            }
            statusBanner = L10n.tr("Đã tạo Pull Request thành công!", "Created Pull Request successfully!")
            return htmlURL
        } catch {
            statusBanner = L10n.tr("Lỗi tạo PR: \(error.localizedDescription)", "PR error: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    public func publishWorkspaceToNewRepo(
        name: String,
        description: String,
        isPrivate: Bool,
        workspaceRoot: URL
    ) async -> Bool {
        isBusy = true
        statusBanner = L10n.tr("Đang tạo Repository '\(name)' trên GitHub...", "Creating repository '\(name)' on GitHub...")
        do {
            let created = try await GitHubAccountService.shared.createRepository(
                name: name,
                description: description,
                isPrivate: isPrivate
            )
            remoteOriginURL = created.cloneURL
            currentBranch = created.defaultBranch
            lastSyncedRemoteCommitSHA = ""
            aheadCount = 0
            behindCount = 0
            pendingPushDeletePaths = []
            lastLoadedMetaWorkspacePath = WorkspaceManager.canonicalPath(workspaceRoot)
            saveLocalRepoMeta(workspaceRoot: workspaceRoot)
            isBusy = false

            let pushed = await pushToGitHubREST(
                workspaceRoot: workspaceRoot,
                commitMessage: "Initial commit from 3012 Mobile IDE",
                force: false,
                pushAllWorkspaceFiles: true
            )
            return pushed
        } catch {
            isBusy = false
            statusBanner = L10n.tr("Publish thất bại: \(error.localizedDescription)", "Publish failed: \(error.localizedDescription)")
            return false
        }
    }

    private func copyAllPulledFiles(from extractedRoot: URL, into workspaceRoot: URL) throws -> (updatedCount: Int, archiveRelativePaths: Set<String>) {
        let fm = FileManager.default
        let rootPath = WorkspaceManager.canonicalPath(extractedRoot)
        let rootPrefix = rootPath == "/" ? "/" : rootPath + "/"
        let destCanon = WorkspaceManager.canonicalPath(workspaceRoot)
        let destPrefix = destCanon == "/" ? "/" : destCanon + "/"
        guard let enumerator = fm.enumerator(
            at: extractedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return (0, [])
        }
        var updatedCount = 0
        var archivePaths = Set<String>()
        for case let srcURL as URL in enumerator {
            let values = try? srcURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            let name = srcURL.lastPathComponent
            if name == ".git" || name == ".3012" || name == "__MACOSX" || name == ".DS_Store" {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true { continue }

            let srcCanon = WorkspaceManager.canonicalPath(srcURL)
            guard srcCanon.hasPrefix(rootPrefix) else { continue }
            let rel = String(srcCanon.dropFirst(rootPrefix.count))
            guard WorkspaceManager.isSafeRelativeSyncPath(rel) else { continue }
            archivePaths.insert(rel)

            let candidateDst = workspaceRoot.appendingPathComponent(rel)
            let dstCanon = WorkspaceManager.canonicalPath(candidateDst)
            guard dstCanon.hasPrefix(destPrefix) else { continue }
            let dstURL = URL(fileURLWithPath: dstCanon)

            let newData = try Data(contentsOf: srcURL)
            if let existingData = try? Data(contentsOf: dstURL) {
                if existingData == newData { continue }
                if let existingText = String(data: existingData, encoding: .utf8) {
                    FileTimelineAndArchiveService.shared.recordSnapshot(for: dstURL, content: existingText, label: "Before Git Pull")
                }
            }
            try fm.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try newData.write(to: dstURL, options: .atomic)
            updatedCount += 1
        }
        return (updatedCount, archivePaths)
    }

    private func parseGitHubOwnerRepo(_ raw: String) -> (String, String)? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        if let range = cleaned.range(of: "github.com/") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let colonRange = cleaned.range(of: "github.com:") {
            cleaned = String(cleaned[colonRange.upperBound...])
        }
        let comps = cleaned.split(separator: "/").map(String.init)
        guard comps.count >= 2 else { return nil }
        return (comps[0], comps[1])
    }

    private static let ignoredWorkspaceEntries: Set<String> = [
        ".git", ".3012", ".3012meta", ".ExternalMirror",
        ".3012git.json", ".3012baseline.json", ".3012deleted.json",
        ".DS_Store", "__MACOSX", "node_modules", ".build", "DerivedData", "packages"
    ]

    private func collectWorkspaceTextFiles(at root: URL) -> [String: String] {
        var map: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return map }

        let rootCanon = WorkspaceManager.canonicalPath(root)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"
        for case let fileURL as URL in enumerator {
            let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = vals?.isDirectory ?? false
            let name = fileURL.lastPathComponent
            if Self.ignoredWorkspaceEntries.contains(name) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if vals?.isSymbolicLink == true || isDir { continue }

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text.utf8.count < 512_000 else { continue }
            let fileCanon = WorkspaceManager.canonicalPath(fileURL)
            guard fileCanon.hasPrefix(rootPrefix) else { continue }
            let rel = String(fileCanon.dropFirst(rootPrefix.count))
            if WorkspaceManager.isSafeRelativeSyncPath(rel) {
                map[rel] = text
            }
        }
        return map
    }

    private func collectWorkspacePushableRelativePaths(at root: URL) -> [String] {
        var list: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return list }

        let rootCanon = WorkspaceManager.canonicalPath(root)
        let rootPrefix = rootCanon == "/" ? "/" : rootCanon + "/"
        for case let fileURL as URL in enumerator {
            let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = vals?.isDirectory ?? false
            let name = fileURL.lastPathComponent
            if Self.ignoredWorkspaceEntries.contains(name) {
                if isDir { enumerator.skipDescendants() }
                continue
            }
            if vals?.isSymbolicLink == true || isDir { continue }

            let fileCanon = WorkspaceManager.canonicalPath(fileURL)
            guard fileCanon.hasPrefix(rootPrefix) else { continue }
            let rel = String(fileCanon.dropFirst(rootPrefix.count))
            if WorkspaceManager.isSafeRelativeSyncPath(rel) {
                list.append(rel)
            }
        }
        return list.sorted()
    }

    public func selectBranch(_ branch: String, workspaceRoot: URL) {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if lastLoadedMetaWorkspacePath != WorkspaceManager.canonicalPath(workspaceRoot) {
            loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        }
        guard self.currentBranch != trimmed else { return }
        self.currentBranch = trimmed
        self.lastSyncedRemoteCommitSHA = ""
        self.aheadCount = 0
        self.behindCount = 0
        self.lastPushRejectedNonFastForward = false
        self.saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        Task { @MainActor [weak self] () -> Void in
            guard let self else { return }
            await self.refreshRemoteDivergence(workspaceRoot: workspaceRoot)
        }
    }

    public func setRemoteOriginURL(_ rawURL: String, workspaceRoot: URL) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastLoadedMetaWorkspacePath != WorkspaceManager.canonicalPath(workspaceRoot) {
            loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        }
        guard self.remoteOriginURL != trimmed else { return }
        self.remoteOriginURL = trimmed
        self.lastSyncedRemoteCommitSHA = ""
        self.aheadCount = 0
        self.behindCount = 0
        self.lastPushRejectedNonFastForward = false
        self.saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        if !trimmed.isEmpty {
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                await self.refreshRemoteDivergence(workspaceRoot: workspaceRoot)
            }
        }
    }

    private func loadLocalRepoMeta(workspaceRoot: URL) {
        let canonRoot = WorkspaceManager.canonicalPath(workspaceRoot)
        let isWorkspaceSwitch = (lastLoadedMetaWorkspacePath != canonRoot)
        lastLoadedMetaWorkspacePath = canonRoot

        let metaURL = metaFileURL(for: workspaceRoot)
        let legacyURL = workspaceRoot.appendingPathComponent(".3012git.json")
        if let data = (try? Data(contentsOf: metaURL)) ?? (try? Data(contentsOf: legacyURL)),
           let decoded = try? JSONDecoder().decode(StoredRepoMeta.self, from: data) {
            self.currentBranch = decoded.branch
            self.remoteOriginURL = decoded.remoteURL
            self.commits = decoded.commits
            self.lastSyncedRemoteCommitSHA = decoded.lastSyncedRemoteCommitSHA ?? ""
            self.aheadCount = decoded.localAheadCount ?? 0
            self.pendingPushDeletePaths = decoded.pendingPushDeletePaths ?? []
            if isWorkspaceSwitch {
                self.behindCount = 0
                self.lastPushRejectedNonFastForward = false
            }
        } else {
            self.currentBranch = "main"
            self.remoteOriginURL = ""
            self.commits = []
            self.lastSyncedRemoteCommitSHA = ""
            self.aheadCount = 0
            self.pendingPushDeletePaths = []
            if isWorkspaceSwitch {
                self.behindCount = 0
                self.lastPushRejectedNonFastForward = false
            }
        }
    }

    private func saveLocalRepoMeta(workspaceRoot: URL) {
        let meta = StoredRepoMeta(
            branch: currentBranch,
            remoteURL: remoteOriginURL,
            commits: commits,
            lastSyncedRemoteCommitSHA: lastSyncedRemoteCommitSHA,
            localAheadCount: aheadCount,
            pendingPushDeletePaths: pendingPushDeletePaths
        )
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaFileURL(for: workspaceRoot), options: .atomic)
        }
    }
}
