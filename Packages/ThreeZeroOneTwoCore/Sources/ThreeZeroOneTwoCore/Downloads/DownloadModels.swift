import Foundation

public enum DownloadStatus: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case paused
    case verifying
    case completed
    case failed
}

public struct DownloadRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let packageID: String
    public let remoteURL: URL
    public let expectedSHA256: String
    public let expectedSize: Int64
    public var status: DownloadStatus
    public var bytesReceived: Int64
    public var resumeDataFilename: String?
    public var localFilename: String?
    public var failureReason: String?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        packageID: String,
        remoteURL: URL,
        expectedSHA256: String,
        expectedSize: Int64,
        status: DownloadStatus = .queued,
        bytesReceived: Int64 = 0,
        resumeDataFilename: String? = nil,
        localFilename: String? = nil,
        failureReason: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.packageID = packageID
        self.remoteURL = remoteURL
        self.expectedSHA256 = expectedSHA256
        self.expectedSize = expectedSize
        self.status = status
        self.bytesReceived = bytesReceived
        self.resumeDataFilename = resumeDataFilename
        self.localFilename = localFilename
        self.failureReason = failureReason
        self.updatedAt = updatedAt
    }
}
