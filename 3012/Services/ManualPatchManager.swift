import Combine
import CryptoKit
import Foundation
import ThreeZeroOneTwoCore

struct ManualPatchItem: Identifiable, Sendable {
    let id: String
    let sourceURL: URL
    let bookmark: Data
    let byteCount: Int64
    var relativePath: String
    var operation: PackageOperation
}

struct InstalledManualPatch: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let installedAt: Date
    let journalURL: URL
    let targetBookmark: Data
    let fileCount: Int
    let payloadBytes: Int64
}

enum ManualPatchError: LocalizedError {
    case targetNotSelected
    case noFiles
    case bookmarkUnavailable
    case staleBookmark
    case invalidRelativePath(String)
    case insufficientStorage(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .targetNotSelected: return "Bạn chưa chọn thư mục đích."
        case .noFiles: return "Bạn chưa chọn file thay thế."
        case .bookmarkUnavailable: return "Không thể lưu quyền truy cập file hoặc thư mục."
        case .staleBookmark: return "Quyền truy cập đã hết hạn. Hãy chọn lại file hoặc thư mục."
        case .invalidRelativePath(let path): return "Đường dẫn không hợp lệ: \(path)"
        case .insufficientStorage(let required, let available):
            return "Không đủ dung lượng trống. Cần khoảng \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), hiện có \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))."
        }
    }
}

@MainActor
final class ManualPatchManager: ObservableObject {
    nonisolated static let manualBundleID = "manual.selected-folder"

    @Published var patchName = "Patch thủ công"
    @Published var targetURL: URL?
    @Published var targetBookmark: Data?
    @Published var items: [ManualPatchItem] = []
    @Published private(set) var installed: [InstalledManualPatch] = []
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published var lastOperationSucceeded = false

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let packagesDirectory: URL
    private let transactionsDirectory: URL
    private let receiptsURL: URL

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        rootDirectory = applicationSupport.appendingPathComponent("3012/ManualPatches", isDirectory: true)
        packagesDirectory = rootDirectory.appendingPathComponent("Packages", isDirectory: true)
        transactionsDirectory = rootDirectory.appendingPathComponent("Transactions", isDirectory: true)
        receiptsURL = rootDirectory.appendingPathComponent("receipts.json")
        try? fileManager.createDirectory(at: packagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: transactionsDirectory, withIntermediateDirectories: true)
        loadReceipts()
    }

    func selectTarget(_ url: URL) {
        do {
            targetBookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            targetURL = url
            message = nil
        } catch {
            message = ManualPatchError.bookmarkUnavailable.localizedDescription
        }
    }

    func addFiles(_ urls: [URL]) {
        for url in urls {
            do {
                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: [.fileSizeKey],
                    relativeTo: nil
                )
                let byteCount = Int64(
                    (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                )
                let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                items.append(ManualPatchItem(
                    id: id,
                    sourceURL: url,
                    bookmark: bookmark,
                    byteCount: byteCount,
                    relativePath: url.lastPathComponent,
                    operation: .replaceFile
                ))
            } catch {
                message = ManualPatchError.bookmarkUnavailable.localizedDescription
            }
        }
    }

    func updatePath(id: String, path: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].relativePath = path
    }

    func updateOperation(id: String, operation: PackageOperation) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].operation = operation
    }

    func removeItem(id: String) {
        items.removeAll { $0.id == id }
    }

    func apply() {
        guard !isWorking else { return }
        guard let targetBookmark else {
            message = ManualPatchError.targetNotSelected.localizedDescription
            return
        }
        guard !items.isEmpty else {
            message = ManualPatchError.noFiles.localizedDescription
            return
        }
        for item in items {
            do { try PackagePathValidator.validate(item.relativePath) }
            catch {
                message = ManualPatchError.invalidRelativePath(item.relativePath).localizedDescription
                return
            }
        }
        let snapshot = items
        let name = patchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Patch thủ công"
            : patchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let packageURL = packagesDirectory.appendingPathComponent("\(UUID().uuidString).3012pkg")
        let transactionsDirectory = transactionsDirectory
        isWorking = true
        lastOperationSucceeded = false
        message = "Đang xác minh và tạo backup…"

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try Self.performApply(
                        name: name,
                        items: snapshot,
                        targetBookmark: targetBookmark,
                        packageURL: packageURL,
                        transactionsDirectory: transactionsDirectory
                    )
                }
            }.value
            isWorking = false
            switch result {
            case .success(let receipt):
                installed.insert(receipt, at: 0)
                saveReceipts()
                items.removeAll()
                lastOperationSucceeded = true
                message = "Patch hoàn tất. Backup đã được lưu để khôi phục."
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    func restore(_ receipt: InstalledManualPatch) {
        guard !isWorking else { return }
        isWorking = true
        message = "Đang kiểm tra và khôi phục backup…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    var stale = false
                    let target = try URL(
                        resolvingBookmarkData: receipt.targetBookmark,
                        options: [.withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    )
                    guard !stale else { throw ManualPatchError.staleBookmark }
                    let granted = target.startAccessingSecurityScopedResource()
                    defer { if granted { target.stopAccessingSecurityScopedResource() } }
                    let reader = PackageReader(trustedPublicKeys: [:])
                    try PackageTransactionEngine(packageReader: reader).restore(
                        journalURL: receipt.journalURL,
                        targetRoots: [Self.manualBundleID: target]
                    )
                }
            }.value
            isWorking = false
            switch result {
            case .success:
                installed.removeAll { $0.id == receipt.id }
                saveReceipts()
                lastOperationSucceeded = true
                message = "Đã khôi phục các file gốc."
            case .failure(let error):
                message = error.localizedDescription
            }
        }
    }

    nonisolated private static func performApply(
        name: String,
        items: [ManualPatchItem],
        targetBookmark: Data,
        packageURL: URL,
        transactionsDirectory: URL
    ) throws -> InstalledManualPatch {
        var targetStale = false
        let target = try URL(
            resolvingBookmarkData: targetBookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &targetStale
        )
        guard !targetStale else { throw ManualPatchError.staleBookmark }
        let targetGranted = target.startAccessingSecurityScopedResource()
        defer { if targetGranted { target.stopAccessingSecurityScopedResource() } }

        var sourceURLs: [URL] = []
        var grantedSources: [URL] = []
        for item in items {
            var stale = false
            let source = try URL(
                resolvingBookmarkData: item.bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { throw ManualPatchError.staleBookmark }
            if source.startAccessingSecurityScopedResource() { grantedSources.append(source) }
            sourceURLs.append(source)
        }
        defer { grantedSources.forEach { $0.stopAccessingSecurityScopedResource() } }
        try preflightStorage(
            storageRoot: packageURL.deletingLastPathComponent(),
            target: target,
            items: items
        )

        let privateKey = Curve25519.Signing.PrivateKey()
        let sources = zip(items, sourceURLs).map { item, url in
            LocalPackageSource(
                id: item.id,
                sourceURL: url,
                bundleID: manualBundleID,
                relativePath: item.relativePath,
                operation: item.operation
            )
        }
        let publicKey = try LocalPackageBuilder.build(
            name: name,
            publisherKeyID: "local-manual",
            privateKeyData: privateKey.rawRepresentation,
            sources: sources,
            outputURL: packageURL
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let reader = PackageReader(trustedPublicKeys: ["local-manual": publicKey])
        let package = try reader.inspect(fileURL: packageURL)
        let result = try PackageTransactionEngine(packageReader: reader).apply(
            package: package,
            targetRoots: [manualBundleID: target],
            backupRoot: transactionsDirectory
        )
        return InstalledManualPatch(
            id: result.transactionID,
            name: name,
            installedAt: Date(),
            journalURL: result.journalURL,
            targetBookmark: targetBookmark,
            fileCount: items.count,
            payloadBytes: items.reduce(0) { $0 + $1.byteCount }
        )
    }

    nonisolated private static func preflightStorage(
        storageRoot: URL,
        target: URL,
        items: [ManualPatchItem]
    ) throws {
        let values = try storageRoot.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64.max
        let payload = items.reduce(Int64(0)) { partial, item in
            partial > Int64.max - item.byteCount ? Int64.max : partial + item.byteCount
        }
        var backups: Int64 = 0
        for item in items where item.operation == .replaceFile {
            let destination = try PackagePathValidator.destination(
                root: target,
                relativePath: item.relativePath
            )
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            backups = backups > Int64.max - size ? Int64.max : backups + size
        }
        let reserve: Int64 = 32 * 1_024 * 1_024
        let packageAndBackup = payload > Int64.max - backups ? Int64.max : payload + backups
        let required = packageAndBackup > Int64.max - reserve
            ? Int64.max
            : packageAndBackup + reserve
        guard available >= required else {
            throw ManualPatchError.insufficientStorage(required: required, available: available)
        }
    }

    private func loadReceipts() {
        guard let data = try? Data(contentsOf: receiptsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        installed = (try? decoder.decode([InstalledManualPatch].self, from: data)) ?? []
    }

    private func saveReceipts() {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(installed).write(to: receiptsURL, options: .atomic)
        } catch {
            message = "Patch đã chạy nhưng không thể lưu lịch sử: \(error.localizedDescription)"
        }
    }
}
