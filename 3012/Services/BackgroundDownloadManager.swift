import Combine
import Foundation
import ThreeZeroOneTwoCore

@MainActor
final class BackgroundDownloadManager: NSObject, ObservableObject {
    @Published private(set) var records: [DownloadRecord] = []

    private let fileManager = FileManager.default
    private let stateStore: DownloadStateStore
    private let stateDirectory: URL
    private let downloadsDirectory: URL
    private var session: URLSession!

    override init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let root = applicationSupport.appendingPathComponent("3012", isDirectory: true)
        stateDirectory = root.appendingPathComponent("DownloadState", isDirectory: true)
        downloadsDirectory = root.appendingPathComponent("Packages", isDirectory: true)
        stateStore = DownloadStateStore(fileURL: stateDirectory.appendingPathComponent("downloads.json"))
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.userlethekhoi.app3012.packages"
        )
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        Task { await restoreState() }
    }

    func enqueue(
        packageID: String,
        remoteURL: URL,
        expectedSize: Int64,
        expectedSHA256: String
    ) {
        guard remoteURL.scheme?.lowercased() == "https",
              expectedSize >= 0,
              expectedSHA256.count == 64,
              expectedSHA256.allSatisfy(\.isHexDigit) else { return }
        var record = DownloadRecord(
            packageID: packageID,
            remoteURL: remoteURL,
            expectedSHA256: expectedSHA256.lowercased(),
            expectedSize: expectedSize,
            status: .downloading
        )
        record.updatedAt = Date()
        records.append(record)
        persist()
        let task = session.downloadTask(with: remoteURL)
        task.taskDescription = record.id
        task.resume()
    }

    func pause(_ record: DownloadRecord) {
        session.getAllTasks { [weak self] tasks in
            guard let task = tasks.first(where: { $0.taskDescription == record.id }) as? URLSessionDownloadTask else {
                return
            }
            task.cancel(byProducingResumeData: { resumeData in
                Task { @MainActor [weak self] in
                    self?.storeResumeData(resumeData, recordID: record.id)
                }
            })
        }
    }

    func resume(_ record: DownloadRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        let task: URLSessionDownloadTask
        if let filename = records[index].resumeDataFilename {
            let url = stateDirectory.appendingPathComponent(filename)
            if let data = try? Data(contentsOf: url) {
                task = session.downloadTask(withResumeData: data)
                try? fileManager.removeItem(at: url)
            } else {
                task = session.downloadTask(with: records[index].remoteURL)
            }
        } else {
            task = session.downloadTask(with: records[index].remoteURL)
        }
        records[index].status = .downloading
        records[index].failureReason = nil
        records[index].resumeDataFilename = nil
        records[index].updatedAt = Date()
        persist()
        task.taskDescription = record.id
        task.resume()
    }

    func retry(_ record: DownloadRecord) {
        resume(record)
    }

    func remove(_ record: DownloadRecord) {
        guard record.status != .downloading && record.status != .verifying else { return }
        if let filename = record.resumeDataFilename {
            try? fileManager.removeItem(at: stateDirectory.appendingPathComponent(filename))
        }
        if let filename = record.localFilename {
            try? fileManager.removeItem(at: downloadsDirectory.appendingPathComponent(filename))
        }
        records.removeAll { $0.id == record.id }
        persist()
    }

    private func restoreState() async {
        do {
            records = try await stateStore.load()
            session.getAllTasks { [weak self] tasks in
                let activeIDs = Set(tasks.compactMap(\.taskDescription))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for index in self.records.indices where self.records[index].status == .downloading {
                        if !activeIDs.contains(self.records[index].id) {
                            self.records[index].status = .failed
                            self.records[index].failureReason = AppLocalization.text(
                                "error.backgroundTaskMissing",
                                fallback: "The background task no longer exists."
                            )
                        }
                    }
                    self.persist()
                }
            }
        } catch {
            records = []
        }
    }

    private func storeResumeData(_ data: Data?, recordID: String) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        if let data {
            try? fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            let filename = "\(recordID).resume"
            try? data.write(to: stateDirectory.appendingPathComponent(filename), options: .atomic)
            records[index].resumeDataFilename = filename
        }
        records[index].status = .paused
        records[index].updatedAt = Date()
        persist()
    }

    private func persist() {
        let snapshot = records
        Task { try? await stateStore.save(snapshot) }
    }

    private func updateProgress(recordID: String, bytesReceived: Int64) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].bytesReceived = bytesReceived
        records[index].status = .downloading
        records[index].updatedAt = Date()
        persist()
    }

    private func acceptDownloadedFile(recordID: String, temporaryURL: URL) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        do {
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            let filename = "\(recordID).3012pkg"
            let destination = downloadsDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporaryURL, to: destination)
            records[index].status = .verifying
            records[index].updatedAt = Date()
            persist()
            let expectedSize = records[index].expectedSize
            let expectedHash = records[index].expectedSHA256
            Task { [weak self] in
                let result = await Task.detached(priority: .utility) {
                    Result {
                        try StreamingSHA256.verify(
                            fileURL: destination,
                            expectedSize: expectedSize,
                            expectedSHA256: expectedHash
                        )
                    }
                }.value
                self?.finishVerification(recordID: recordID, filename: filename, result: result)
            }
        } catch {
            fail(recordID: recordID, reason: error.localizedDescription)
        }
    }

    private func finishVerification(
        recordID: String,
        filename: String,
        result: Result<Void, Error>
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        switch result {
        case .success:
            records[index].status = .completed
            records[index].localFilename = filename
            records[index].bytesReceived = records[index].expectedSize
            records[index].failureReason = nil
        case .failure(let error):
            try? fileManager.removeItem(at: downloadsDirectory.appendingPathComponent(filename))
            records[index].status = .failed
            records[index].failureReason = error.localizedDescription
        }
        records[index].updatedAt = Date()
        persist()
    }

    private func fail(recordID: String, reason: String) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].status = .failed
        records[index].failureReason = reason
        records[index].updatedAt = Date()
        persist()
    }
}

extension BackgroundDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let recordID = downloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.updateProgress(recordID: recordID, bytesReceived: totalBytesWritten)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let recordID = downloadTask.taskDescription else { return }
        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("3012-\(recordID).download")
        do {
            try? FileManager.default.removeItem(at: stagingURL)
            try FileManager.default.moveItem(at: location, to: stagingURL)
            Task { @MainActor [weak self] in
                self?.acceptDownloadedFile(recordID: recordID, temporaryURL: stagingURL)
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.fail(recordID: recordID, reason: error.localizedDescription)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let recordID = task.taskDescription else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor [weak self] in
            self?.fail(recordID: recordID, reason: error.localizedDescription)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            BackgroundSessionEvents.shared.finish()
        }
    }
}
