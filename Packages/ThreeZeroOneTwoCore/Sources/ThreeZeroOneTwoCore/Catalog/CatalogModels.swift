import Foundation

public struct CatalogDocument: Codable, Equatable, Sendable {
    public let signed: CatalogPayload
    public let signature: String

    public init(signed: CatalogPayload, signature: String) {
        self.signed = signed
        self.signature = signature
    }
}

public struct CatalogPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let channel: CatalogChannel
    public let generatedAt: String
    public let publisherKeyID: String
    public let patches: [CatalogPatch]

    public init(
        schemaVersion: Int = 1,
        revision: Int,
        channel: CatalogChannel,
        generatedAt: String,
        publisherKeyID: String,
        patches: [CatalogPatch]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.channel = channel
        self.generatedAt = generatedAt
        self.publisherKeyID = publisherKeyID
        self.patches = patches
    }
}

public enum CatalogChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta
}

public struct CatalogPatch: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let version: String
    public let category: String
    public let downloadURL: String
    public let fileSize: Int64
    public let sha256: String
    public let minAppVersion: String
    public let minIOS: String
    public let targetBundleIDs: [String]
    public let visible: Bool
    public let revoked: Bool
    public let updatedAt: String

    public init(
        id: String,
        name: String,
        summary: String,
        version: String,
        category: String,
        downloadURL: String,
        fileSize: Int64,
        sha256: String,
        minAppVersion: String,
        minIOS: String,
        targetBundleIDs: [String],
        visible: Bool = true,
        revoked: Bool = false,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.version = version
        self.category = category
        self.downloadURL = downloadURL
        self.fileSize = fileSize
        self.sha256 = sha256
        self.minAppVersion = minAppVersion
        self.minIOS = minIOS
        self.targetBundleIDs = targetBundleIDs
        self.visible = visible
        self.revoked = revoked
        self.updatedAt = updatedAt
    }
}

public struct VerifiedCatalog: Equatable, Sendable {
    public let payload: CatalogPayload
    public let canonicalData: Data

    public init(payload: CatalogPayload, canonicalData: Data) {
        self.payload = payload
        self.canonicalData = canonicalData
    }
}
