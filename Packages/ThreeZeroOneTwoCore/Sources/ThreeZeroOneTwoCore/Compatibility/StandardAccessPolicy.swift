import Foundation

public struct StandardAccessInput: Equatable, Sendable {
    public let filesPickerAvailable: Bool
    public let machineIdentifier: String
    public let systemBuild: String

    public init(filesPickerAvailable: Bool, machineIdentifier: String, systemBuild: String) {
        self.filesPickerAvailable = filesPickerAvailable
        self.machineIdentifier = machineIdentifier
        self.systemBuild = systemBuild
    }
}

public struct StandardAccessDecision: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case supported
        case unavailable
    }

    public let status: Status
    public let providerID: String?

    public init(status: Status, providerID: String?) {
        self.status = status
        self.providerID = providerID
    }
}

public enum StandardAccessPolicy {
    public static func evaluate(_ input: StandardAccessInput) -> StandardAccessDecision {
        guard input.filesPickerAvailable else {
            return StandardAccessDecision(status: .unavailable, providerID: nil)
        }
        return StandardAccessDecision(status: .supported, providerID: "StandardFilesProvider")
    }
}
