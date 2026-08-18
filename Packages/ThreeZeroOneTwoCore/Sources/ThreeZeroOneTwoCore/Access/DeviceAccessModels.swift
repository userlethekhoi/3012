import Foundation

public enum AccessProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case standardFiles = "StandardFilesProvider"
    case mobileHouseArrest = "MobileHouseArrestProvider"
    case darkSword = "DarkSwordProvider"
}

public struct AccessCapability: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let userSelectedFiles = AccessCapability(rawValue: 1 << 0)
    public static let listAppContainers = AccessCapability(rawValue: 1 << 1)
    public static let readAppContainers = AccessCapability(rawValue: 1 << 2)
    public static let writeAppContainers = AccessCapability(rawValue: 1 << 3)
}

public enum AccessFailureStage: Int, Codable, Comparable, Sendable {
    case preflight = 0
    case runtimeProbe = 1
    case privilegedAttempt = 2
    case mutation = 3

    public static func < (lhs: AccessFailureStage, rhs: AccessFailureStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct DeviceAccessContext: Equatable, Sendable {
    public let operatingSystemMajor: Int
    public let operatingSystemMinor: Int
    public let operatingSystemPatch: Int
    public let systemBuild: String
    public let machineIdentifier: String
    public let architecture: String
    public let bundleIdentifier: String
    public let signingIdentifier: String
    public let filesPickerAvailable: Bool

    public init(
        operatingSystemMajor: Int,
        operatingSystemMinor: Int,
        operatingSystemPatch: Int,
        systemBuild: String,
        machineIdentifier: String,
        architecture: String,
        bundleIdentifier: String,
        signingIdentifier: String,
        filesPickerAvailable: Bool
    ) {
        self.operatingSystemMajor = operatingSystemMajor
        self.operatingSystemMinor = operatingSystemMinor
        self.operatingSystemPatch = operatingSystemPatch
        self.systemBuild = systemBuild
        self.machineIdentifier = machineIdentifier
        self.architecture = architecture
        self.bundleIdentifier = bundleIdentifier
        self.signingIdentifier = signingIdentifier
        self.filesPickerAvailable = filesPickerAvailable
    }
}

public struct AccessProbe: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case available
        case unavailable
        case failed
    }

    public let providerID: AccessProviderID
    public let outcome: Outcome
    public let stage: AccessFailureStage
    public let capabilities: AccessCapability
    public let detail: String

    public init(
        providerID: AccessProviderID,
        outcome: Outcome,
        stage: AccessFailureStage,
        capabilities: AccessCapability = [],
        detail: String
    ) {
        self.providerID = providerID
        self.outcome = outcome
        self.stage = stage
        self.capabilities = capabilities
        self.detail = detail
    }
}

public struct AccessLease: Equatable, Sendable {
    public let providerID: AccessProviderID
    public let capabilities: AccessCapability
    public let rootsByIdentifier: [String: URL]

    public init(
        providerID: AccessProviderID,
        capabilities: AccessCapability,
        rootsByIdentifier: [String: URL]
    ) {
        self.providerID = providerID
        self.capabilities = capabilities
        self.rootsByIdentifier = rootsByIdentifier
    }
}

public protocol DeviceAccessProvider: Sendable {
    var id: AccessProviderID { get }
    var capabilities: AccessCapability { get }
    func probe(context: DeviceAccessContext) async -> AccessProbe
}
