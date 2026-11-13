import Foundation
import ZIPFoundation

public struct GitChangedFile: Identifiable, Equatable {
    public var id: String { relativePath }
    public let relativePath: String
    public let statusBadge: String // "M", "A", "D"
}

public struct GitCommitRecord: Codable, Identifiable, Equatable {
    public let id: String
    public let message: String
    public let author: String
    public let timestamp: Date
    public let snapshotFiles: [String: String]
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

    private func metaFileURL(for workspaceRoot: URL) -> URL {
        workspaceRoot.appendingPathComponent(".3012git.json")
    }

    private struct StoredRepoMeta: Codable {
        var branch: String
        var remoteURL: String
        var commits: [GitCommitRecord]
    }

    public func refreshStatus(workspaceRoot: URL, sshService: SSHWorkspaceService?) async {
        if let ssh = sshService, ssh.isConnected {
            let dir = ssh.currentRemoteDirectory
            let raw = await ssh.executeCommandOnVPS("cd '\(dir)' && git rev-parse --abbrev-ref HEAD 2>/dev/null && echo '---SPLIT---' && git status --porcelain 2>/dev/null")
            if raw.contains("---SPLIT---") {
                let parts = raw.components(separatedBy: "---SPLIT---")
                let branch = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !branch.isEmpty { currentBranch = branch }
                let lines = parts[1].components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                changedFiles = lines.map { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let code = String(trimmed.prefix(2)).trimmingCharacters(in: .whitespaces)
                    let path = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    return GitChangedFile(relativePath: path, statusBadge: code.isEmpty ? "M" : code)
                }
                return
            }
        }

        loadLocalRepoMeta(workspaceRoot: workspaceRoot)
        let currentDisk = collectWorkspaceTextFiles(at: workspaceRoot)
        let baseline = commits.first?.snapshotFiles ?? [:]

        var diffs: [GitChangedFile] = []
        for (path, content) in currentDisk {
            if let old = baseline[path] {
                if old != content {
                    diffs.append(GitChangedFile(relativePath: path, statusBadge: "M"))
                }
            } else {
                diffs.append(GitChangedFile(relativePath: path, statusBadge: "A"))
            }
        }
        for (oldPath, _) in baseline where currentDisk[oldPath] == nil {
            diffs.append(GitChangedFile(relativePath: oldPath, statusBadge: "D"))
        }
        diffs.sort { $0.relativePath < $1.relativePath }
        changedFiles = diffs
    }

    public func commitAll(message: String, workspaceRoot: URL, sshService: SSHWorkspaceService?) async {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else {
            statusBanner = "⚠️ Vui lòng nhập nội dung commit."
            return
        }
        isBusy = true
        defer { isBusy = false }

        if let ssh = sshService, ssh.isConnected {
            let safeMsg = msg.replacingOccurrences(of: "'", with: "'\\''")
            let dir = ssh.currentRemoteDirectory
            let out = await ssh.executeCommandOnVPS("cd '\(dir)' && git add -A && git commit -m '\(safeMsg)' 2>&1")
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
        statusBanner = "✓ Committed [\(shortSHA)]: \(msg)"
    }

    public func discardChanges(for filePath: String, workspaceRoot: URL) async {
        guard let latest = commits.first else { return }
        let targetURL = workspaceRoot.appendingPathComponent(filePath)
        if let oldContent = latest.snapshotFiles[filePath] {
            try? oldContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: targetURL)
        }
        await refreshStatus(workspaceRoot: workspaceRoot, sshService: nil)
    }

    public func diffPreview(for filePath: String, workspaceRoot: URL) -> String {
        let targetURL = workspaceRoot.appendingPathComponent(filePath)
        let newText = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        let oldText = commits.first?.snapshotFiles[filePath] ?? ""
        let oldSet = Set(oldText.components(separatedBy: "\n"))
        let newSet = Set(newText.components(separatedBy: "\n"))
        var lines: [String] = []
        for l in oldText.components(separatedBy: "\n") where !oldText.isEmpty && !newSet.contains(l) {
            lines.append("- " + l)
        }
        for l in newText.components(separatedBy: "\n") where !newText.isEmpty && !oldSet.contains(l) {
            lines.append("+ " + l)
        }
        return lines.isEmpty ? "(No line changes)" : lines.prefix(80).joined(separator: "\n")
    }

    // MARK: - Clone GitHub Repository Directly on iOS (No external git binary needed!)
    public func cloneGitHubRepository(repoInput: String, into parentDocumentsURL: URL) async -> URL? {
        guard let (owner, repo) = parseGitHubOwnerRepo(repoInput) else {
            statusBanner = "⚠️ Nhập dạng owner/repo hoặc https://github.com/owner/repo"
            return nil
        }
        isBusy = true
        statusBanner = "Đang tải repository \(owner)/\(repo) từ GitHub..."
        defer { isBusy = false }

        do {
            var metaReq = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!)
            let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pat.isEmpty {
                metaReq.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
            }
            let (metaData, _) = try await URLSession.shared.data(for: metaReq)
            var defaultBranch = "main"
            if let json = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
               let br = json["default_branch"] as? String {
                defaultBranch = br
            }

            let zipEndpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/zipball/\(defaultBranch)")!
            var zipReq = URLRequest(url: zipEndpoint)
            if !pat.isEmpty {
                zipReq.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
            }
            let (tempZipURL, response) = try await URLSession.shared.download(for: zipReq)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                statusBanner = "❌ Không tải được repo (kiểm tra tên repo hoặc GitHub Token nếu Private)."
                return nil
            }

            let fm = FileManager.default
            let extractTemp = fm.temporaryDirectory.appendingPathComponent("gh_clone_\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: extractTemp, withIntermediateDirectories: true)
            try fm.unzipItem(at: tempZipURL, to: extractTemp)

            let innerItems = (try? fm.contentsOfDirectory(at: extractTemp, includingPropertiesForKeys: nil)) ?? []
            let extractedRoot = innerItems.first ?? extractTemp

            let destination = parentDocumentsURL.appendingPathComponent(repo, isDirectory: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: extractedRoot, to: destination)
            try? fm.removeItem(at: extractTemp)

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
            statusBanner = "✅ Đã clone \(owner)/\(repo) thành công!"
            return destination
        } catch {
            statusBanner = "❌ Lỗi clone GitHub: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Push Modified Files Directly to GitHub via REST API (Works Offline-First on iOS!)
    public func pushToGitHubREST(workspaceRoot: URL, commitMessage: String) async {
        let pat = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pat.isEmpty else {
            statusBanner = "⚠️ Nhập GitHub Personal Access Token (PAT) để Push trực tiếp lên GitHub."
            return
        }
        guard let (owner, repo) = parseGitHubOwnerRepo(remoteOriginURL) else {
            statusBanner = "⚠️ Chưa có Remote GitHub URL (owner/repo)."
            return
        }

        isBusy = true
        statusBanner = "Đang đẩy các file thay đổi lên \(owner)/\(repo)..."
        defer { isBusy = false }

        let filesToPush = changedFiles.filter { $0.statusBadge != "D" }
        guard !filesToPush.isEmpty else {
            statusBanner = "ℹ️ Không có file mới/sửa nào cần Push."
            return
        }

        var pushedCount = 0
        for item in filesToPush {
            let fileURL = workspaceRoot.appendingPathComponent(item.relativePath)
            guard let fileData = try? Data(contentsOf: fileURL) else { continue }
            let encodedPath = item.relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.relativePath
            guard let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(encodedPath)") else { continue }

            // Fetch existing blob SHA if file already exists on remote
            var existingSHA: String?
            var getReq = URLRequest(url: URL(string: "\(apiURL.absoluteString)?ref=\(currentBranch)")!)
            getReq.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
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

            var putReq = URLRequest(url: apiURL)
            putReq.httpMethod = "PUT"
            putReq.setValue("Bearer \(pat)", forHTTPHeaderField: "Authorization")
            putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            putReq.httpBody = try? JSONSerialization.data(withJSONObject: putBody)

            if let (_, putResp) = try? await URLSession.shared.data(for: putReq),
               let http = putResp as? HTTPURLResponse, (200...201).contains(http.statusCode) {
                pushedCount += 1
            }
        }

        await commitAll(message: commitMessage.isEmpty ? "Sync to GitHub" : commitMessage, workspaceRoot: workspaceRoot, sshService: nil)
        statusBanner = "🚀 Đã Push \(pushedCount)/\(filesToPush.count) file lên GitHub (\(owner)/\(repo))!"
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
        if let data = try? Data(contentsOf: metaURL),
           let decoded = try? JSONDecoder().decode(StoredRepoMeta.self, from: data) {
            self.currentBranch = decoded.branch
            self.remoteOriginURL = decoded.remoteURL
            self.commits = decoded.commits
        }
    }

    private func saveLocalRepoMeta(workspaceRoot: URL) {
        let meta = StoredRepoMeta(branch: currentBranch, remoteURL: remoteOriginURL, commits: commits)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: metaFileURL(for: workspaceRoot), options: .atomic)
        }
    }
}
