import Foundation

public struct PackageDocument: Codable, Equatable, Sendable {
    public let signed: PackageManifest
    public let signature: String

    public init(signed: PackageManifest, signature: String) {
        self.signed = signed
        self.signature = signature
    }
}

public struct PackageManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let packageID: String
    public let name: String
    public let version: String
    public let publisherKeyID: String
    public let createdAt: String
    public let minAppVersion: String
    public let entries: [PackageEntry]

    public init(
        schemaVersion: Int = 1,
        packageID: String,
        name: String,
        version: String,
        publisherKeyID: String,
        createdAt: String,
        minAppVersion: String,
        entries: [PackageEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.name = name
        self.version = version
        self.publisherKeyID = publisherKeyID
        self.createdAt = createdAt
        self.minAppVersion = minAppVersion
        self.entries = entries
    }
}

public struct PackageEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let bundleID: String
    public let relativePath: String
    public let operation: PackageOperation
    public let length: Int64
    public let sha256: String

    public init(
        id: String,
        bundleID: String,
        relativePath: String,
        operation: PackageOperation,
        length: Int64,
        sha256: String
    ) {
        self.id = id
        self.bundleID = bundleID
        self.relativePath = relativePath
        self.operation = operation
        self.length = length
        self.sha256 = sha256
    }
}

public enum PackageOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case replaceFile
    case createFile
}

public struct VerifiedPackageEntry: Equatable, Sendable {
    public let entry: PackageEntry
    public let payloadOffset: UInt64

    public init(entry: PackageEntry, payloadOffset: UInt64) {
        self.entry = entry
        self.payloadOffset = payloadOffset
    }
}

public struct VerifiedPackage: Equatable, Sendable {
    public let fileURL: URL
    public let manifest: PackageManifest
    public let entries: [VerifiedPackageEntry]

    public init(fileURL: URL, manifest: PackageManifest, entries: [VerifiedPackageEntry]) {
        self.fileURL = fileURL
        self.manifest = manifest
        self.entries = entries
    }
}
