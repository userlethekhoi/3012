import Foundation
import ZIPFoundation

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

    public var githubToken: String {
        get { KeychainVault.loadString(forKey: "git.github.pat") ?? "" }
        set { KeychainVault.saveString(newValue, forKey: "git.github.pat") }
    }

    public init() {}

    private func workspaceMetaDirectory(for workspaceRoot: URL) -> URL {
        WorkspaceManager.metaDirectory(for: workspaceRoot)
    }

    private func makeGitHubRequest(url: URL, method: String = "GET", pat: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("3012-Mobile-IDE/5.0", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if !pat.isEmpty {
            req.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func githubAPIURL(pathSegments: [String], queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        let cleaned = pathSegments.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }.filter { !$0.isEmpty }
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
                changedFiles = lines.map { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let code = String(trimmed.prefix(2)).trimmingCharacters(in: .whitespaces)
                    let path = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    let kind: WorkspaceFileDiffStatus
                    let badge: String
                    if code.contains("?") {
                        kind = .untrackedNew
                        badge = "U"
                    } else if code.contains("A") {
                        kind = .addedCode
                        badge = "A"
                    } else if code.contains("D") {
                        kind = .deleted
                        badge = "D"
                    } else {
                        kind = .modified
                        badge = "M"
                    }
                    return GitChangedFile(relativePath: path, statusBadge: badge, diffKind: kind)
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
            statusBanner = "Vui lòng nhập nội dung commit."
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
        let snapshot = collectWorkspaceTextFiles(at: workspaceRoot)
        let shortSHA = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(7))
        let record = GitCommitRecord(
            id: shortSHA,
            message: msg,
            author: "3012 Mobile Dev",
            timestamp: Date(),
            snapshotFiles: snapshot
        )
        commits.insert(record, at: 0)
        if commits.count > 30 {
            commits = Array(commits.prefix(30))
        }
        saveLocalRepoMeta(workspaceRoot: workspaceRoot)
        await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
        statusBanner = "Committed [\(shortSHA)]: \(msg)"
    }

    public func discardChanges(for filePath: String, workspaceRoot: URL) async {
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
        let deletedGhosts: [String: String] = {
            if let data = (try? Data(contentsOf: metaDir.appendingPathComponent("deleted.json")))
                ?? (try? Data(contentsOf: workspaceRoot.appendingPathComponent(".3012deleted.json"))),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                return decoded
            }
            return [:]
        }()
        let snapshot = commits.first?.snapshotFiles ?? fallbackBaseline
        let targetURL = workspaceRoot.appendingPathComponent(filePath)
        if let oldContent = snapshot[filePath] ?? deletedGhosts[filePath] {
            if let current = try? String(contentsOf: targetURL, encoding: .utf8) {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: current, label: "Before Discard")
            }
            try? FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? oldContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } else {
            if let current = try? String(contentsOf: targetURL, encoding: .utf8) {
                FileTimelineAndArchiveService.shared.recordSnapshot(for: targetURL, content: current, label: "Before Discard Untracked")
            }
            try? FileManager.default.removeItem(at: targetURL)
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

    // MARK: - Clone GitHub Repository Directly on iOS (No external git binary needed!)
    public func cloneGitHubRepository(repoInput: String, into parentDocumentsURL: URL) async -> URL? {
        guard let (owner, repo) = parseGitHubOwnerRepo(repoInput) else {
            statusBanner = "Nhập dạng owner/repo hoặc https://github.com/owner/repo"
            return nil
        }
        guard let metaURL = githubAPIURL(pathSegments: ["repos", owner, repo]) else {
            statusBanner = "Tên repository không hợp lệ."
            return nil
        }
        isBusy = true
        statusBanner = "Đang tải repository \(owner)/\(repo) từ GitHub..."
        defer { isBusy = false }

        do {
            let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let metaReq = makeGitHubRequest(url: metaURL, pat: pat)
            let (metaData, _) = try await URLSession.shared.data(for: metaReq)
            var defaultBranch = "main"
            if let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
               let br = json["default_branch"] as? String {
                defaultBranch = br
            }

            let branchSegments = defaultBranch.split(separator: "/").map(String.init)
            guard let zipEndpoint = githubAPIURL(pathSegments: ["repos", owner, repo, "zipball"] + branchSegments) else {
                statusBanner = "Nhánh mặc định không hợp lệ."
                return nil
            }
            let zipReq = makeGitHubRequest(url: zipEndpoint, pat: pat)
            let (tempZipURL, response) = try await URLSession.shared.download(for: zipReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                statusBanner = "Không tải được repo (kiểm tra tên repo hoặc GitHub Token nếu Private)."
                return nil
            }

            let fm = FileManager.default
            let extractTemp = fm.temporaryDirectory.appendingPathComponent("gh_clone_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: extractTemp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractTemp) }
            try fm.unzipItem(at: tempZipURL, to: extractTemp)

            let innerItems = (try? fm.contentsOfDirectory(at: extractTemp, includingPropertiesForKeys: nil)) ?? []
            let extractedRoot = innerItems.first ?? extractTemp

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

            self.currentBranch = defaultBranch
            self.remoteOriginURL = "https://github.com/\(owner)/\(repo).git"
            let initialFiles = collectWorkspaceTextFiles(at: destination)
            self.commits = [
                GitCommitRecord(
                    id: "initial",
                    message: "Cloned \(owner)/\(repo) (\(defaultBranch))",
                    author: owner,
                    timestamp: Date(),
                    snapshotFiles: initialFiles
                )
            ]
            saveLocalRepoMeta(workspaceRoot: destination)
            await refreshStatus(workspaceRoot: destination, sshService: nil)
            statusBanner = "Đã clone \(owner)/\(repo) thành công vào \(destination.lastPathComponent)."
            return destination
        } catch {
            statusBanner = "Lỗi clone GitHub: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Push Modified Files Directly to GitHub via REST API (Works Offline-First on iOS!)
    public func pushToGitHubREST(workspaceRoot: URL, commitMessage: String) async {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pat.isEmpty else {
            statusBanner = "Nhập GitHub Personal Access Token (PAT) để Push trực tiếp lên GitHub."
            return
        }
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            statusBanner = "Chưa có Remote GitHub URL (owner/repo)."
            return
        }

        isBusy = true
        statusBanner = "Đang đẩy các file thay đổi lên \(owner)/\(repo)..."
        defer { isBusy = false }

        let filesToUpsert = changedFiles.filter { $0.statusBadge != "D" }
        let filesToDelete = changedFiles.filter { $0.statusBadge == "D" }
        guard !filesToUpsert.isEmpty || !filesToDelete.isEmpty else {
            statusBanner = "Không có thay đổi nào cần Push."
            return
        }

        var pushedCount = 0
        var failedPaths: [String] = []
        let refQuery = [URLQueryItem(name: "ref", value: currentBranch)]

        for item in filesToUpsert {
            let fileURL = workspaceRoot.appendingPathComponent(item.relativePath)
            let relSegments = item.relativePath.split(separator: "/").map(String.init)
            guard let fileData = try? Data(contentsOf: fileURL),
                  let apiURL = githubAPIURL(pathSegments: ["repos", owner, repo, "contents"] + relSegments),
                  let getURL = githubAPIURL(pathSegments: ["repos", owner, repo, "contents"] + relSegments, queryItems: refQuery) else {
                failedPaths.append(item.relativePath)
                continue
            }

            var existingSHA: String?
            let getReq = makeGitHubRequest(url: getURL, pat: pat)
            if let (getData, getResp) = try? await URLSession.shared.data(for: getReq),
               let http = getResp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: getData) as? [String: Any] {
                existingSHA = json["sha"] as? String
            }

            var putBody: [String: Any] = [
                "message": commitMessage.isEmpty ? "Update \(item.relativePath) from 3012 Mobile IDE" : commitMessage,
                "content": fileData.base64EncodedString(),
                "branch": currentBranch
            ]
            if let existingSHA {
                putBody["sha"] = existingSHA
            }

            var putReq = makeGitHubRequest(url: apiURL, method: "PUT", pat: pat)
            putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            putReq.httpBody = try? JSONSerialization.data(withJSONObject: putBody)

            if let (_, putResp) = try? await URLSession.shared.data(for: putReq),
               let http = putResp as? HTTPURLResponse, (200...201).contains(http.statusCode) {
                pushedCount += 1
            } else {
                failedPaths.append(item.relativePath)
            }
        }

        var deletedCount = 0
        for item in filesToDelete {
            let relSegments = item.relativePath.split(separator: "/").map(String.init)
            guard let apiURL = githubAPIURL(pathSegments: ["repos", owner, repo, "contents"] + relSegments),
                  let getURL = githubAPIURL(pathSegments: ["repos", owner, repo, "contents"] + relSegments, queryItems: refQuery) else {
                failedPaths.append(item.relativePath)
                continue
            }
            let getReq = makeGitHubRequest(url: getURL, pat: pat)
            guard let (getData, getResp) = try? await URLSession.shared.data(for: getReq),
                  let http = getResp as? HTTPURLResponse else {
                failedPaths.append(item.relativePath)
                continue
            }
            if http.statusCode == 404 {
                deletedCount += 1
                continue
            }
            guard http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
                  let sha = json["sha"] as? String else {
                failedPaths.append(item.relativePath)
                continue
            }

            let delBody: [String: Any] = [
                "message": commitMessage.isEmpty ? "Delete \(item.relativePath) from 3012 Mobile IDE" : commitMessage,
                "sha": sha,
                "branch": currentBranch
            ]
            var delReq = makeGitHubRequest(url: apiURL, method: "DELETE", pat: pat)
            delReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            delReq.httpBody = try? JSONSerialization.data(withJSONObject: delBody)
            if let (_, delResp) = try? await URLSession.shared.data(for: delReq),
               let dHttp = delResp as? HTTPURLResponse, (200...204).contains(dHttp.statusCode) {
                deletedCount += 1
            } else {
                failedPaths.append(item.relativePath)
            }
        }

        guard failedPaths.isEmpty else {
            statusBanner = "Push chưa hoàn tất (\(failedPaths.count) file lỗi: \(failedPaths.prefix(3).joined(separator: ", "))) — chưa commit cục bộ."
            return
        }

        await commitAll(message: commitMessage.isEmpty ? "Sync to GitHub" : commitMessage, workspaceRoot: workspaceRoot, sshService: nil)
        let totalOps = filesToUpsert.count + filesToDelete.count
        statusBanner = "Đã Push +\(pushedCount) / -\(deletedCount) (tổng \(totalOps) thay đổi) lên GitHub (\(owner)/\(repo))."
    }

    public func fetchRemoteBranches() async -> [String] {
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else { return [currentBranch] }
        let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @discardableResult
    public func pullFromGitHub(into workspaceRoot: URL, branchOverride: String? = nil) async -> Bool {
        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            statusBanner = "Chưa có Remote GitHub URL (owner/repo)."
            return false
        }
        let targetBranch = (branchOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? branchOverride!
            : currentBranch

        isBusy = true
        statusBanner = "Đang kéo dữ liệu nhánh '\(targetBranch)' từ \(owner)/\(repo)..."
        defer { isBusy = false }

        do {
            let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let branchSegments = targetBranch.split(separator: "/").map(String.init)
            guard let zipEndpoint = githubAPIURL(pathSegments: ["repos", owner, repo, "zipball"] + branchSegments) else {
                statusBanner = "URL nhánh không hợp lệ."
                return false
            }
            let zipReq = makeGitHubRequest(url: zipEndpoint, pat: pat)
            let (tempZipURL, response) = try await URLSession.shared.download(for: zipReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                statusBanner = "Pull thất bại (mã lỗi HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."
                return false
            }

            let fm = FileManager.default
            let extractTemp = fm.temporaryDirectory.appendingPathComponent("gh_pull_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: extractTemp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractTemp) }
            try fm.unzipItem(at: tempZipURL, to: extractTemp)
            let innerItems = (try? fm.contentsOfDirectory(at: extractTemp, includingPropertiesForKeys: nil)) ?? []
            let extractedRoot = innerItems.first ?? extractTemp

            let updatedCount = try copyAllPulledFiles(from: extractedRoot, into: workspaceRoot)

            self.currentBranch = targetBranch
            let latestCommit = GitCommitRecord(
                id: String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(7)),
                message: "Pulled \(owner)/\(repo) (\(targetBranch))",
                author: owner,
                timestamp: Date(),
                snapshotFiles: collectWorkspaceTextFiles(at: workspaceRoot)
            )
            commits.insert(latestCommit, at: 0)
            if commits.count > 30 { commits = Array(commits.prefix(30)) }
            saveLocalRepoMeta(workspaceRoot: workspaceRoot)
            await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
            statusBanner = "Đã Pull nhánh '\(targetBranch)' (+/\(updatedCount) file cập nhật)."
            return true
        } catch {
            statusBanner = "Lỗi Git Pull: \(error.localizedDescription)"
            return false
        }
    }

    private func copyAllPulledFiles(from extractedRoot: URL, into workspaceRoot: URL) throws -> Int {
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
            return 0
        }
        var updatedCount = 0
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
        return updatedCount
    }

    private func parseGitHubOwnerRepo(_ raw: String) -> (String, String)? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        if let range = cleaned.range(of: "github.com/") {
            cleaned = String(cleaned[range.upperBound...])
        }
        let comps = cleaned.split(separator: "/").map(String.init)
        guard comps.count >= 2 else { return nil }
        return (comps[0], comps[1])
    }

    private func collectWorkspaceTextFiles(at root: URL) -> [String: String] {
        var map: [String: String] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return map }

        let rootPrefix = root.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text.utf8.count < 512_000 else { continue }
            var rel = fileURL.standardizedFileURL.path
            if rel.hasPrefix(rootPrefix) {
                rel = String(rel.dropFirst(rootPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if !rel.isEmpty {
                map[rel] = text
            }
        }
        return map
    }

    private func loadLocalRepoMeta(workspaceRoot: URL) {
        let metaURL = metaFileURL(for: workspaceRoot)
        let legacyURL = workspaceRoot.appendingPathComponent(".3012git.json")
        if let data = (try? Data(contentsOf: metaURL)) ?? (try? Data(contentsOf: legacyURL)),
           let decoded = try? JSONDecoder().decode(StoredRepoMeta.self, from: data) {
            self.currentBranch = decoded.branch
            self.remoteOriginURL = decoded.remoteURL
            self.commits = decoded.commits
        } else {
            self.currentBranch = "main"
            self.remoteOriginURL = ""
            self.commits = []
        }
    }

    private func saveLocalRepoMeta(workspaceRoot: URL) {
        let meta = StoredRepoMeta(branch: currentBranch, remoteURL: remoteOriginURL, commits: commits)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaFileURL(for: workspaceRoot), options: .atomic)
        }
    }
}
