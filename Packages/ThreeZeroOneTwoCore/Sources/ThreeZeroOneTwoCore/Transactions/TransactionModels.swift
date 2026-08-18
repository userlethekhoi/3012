import Foundation

public enum TransactionStatus: String, Codable, Equatable, Sendable {
    case prepared
    case applying
    case completed
    case rollingBack
    case rolledBack
}

public enum TransactionEntryStatus: String, Codable, Equatable, Sendable {
    case pending
    case applying
    case applied
    case restored
}

public struct TransactionEntryReceipt: Codable, Equatable, Sendable {
    public let entryID: String
    public let bundleID: String
    public let relativePath: String
    public let operation: PackageOperation
    public let originalExisted: Bool
    public let backupRelativePath: String?
    public var createdDirectories: [String]
    public var status: TransactionEntryStatus
}

public struct TransactionJournal: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let transactionID: String
    public let packageID: String
    public let packageVersion: String
    public let createdAt: String
    public var status: TransactionStatus
    public var entries: [TransactionEntryReceipt]
}

public struct TransactionResult: Equatable, Sendable {
    public let transactionID: String
    public let journalURL: URL

    public init(transactionID: String, journalURL: URL) {
        self.transactionID = transactionID
        self.journalURL = journalURL
    }
}

public enum PackageTransactionError: Error, Equatable {
    case missingTargetRoot(String)
    case invalidTargetRoot(String)
    case symbolicLink(String)
    case replacementTargetMissing(String)
    case createTargetAlreadyExists(String)
    case invalidJournal
    case transactionNotRestorable
}
