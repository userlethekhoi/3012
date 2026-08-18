import Foundation

public struct AccessSupportMatrix: Equatable, Sendable {
    public static let mobileHouseArrestBundleID = "com.apple.mobile.MobileHouseArrest"
    public static let verifiedIOS27Builds: Set<String> = [
        "24A5355q",
        "24A5370h",
        "24A5380h",
        "24A5390f"
    ]

    public init() {}

    public func allows(_ providerID: AccessProviderID, context: DeviceAccessContext) -> Bool {
        switch providerID {
        case .standardFiles:
            return context.filesPickerAvailable
        case .mobileHouseArrest:
            guard context.bundleIdentifier == Self.mobileHouseArrestBundleID,
                  context.signingIdentifier == Self.mobileHouseArrestBundleID,
                  context.architecture == "arm64" || context.architecture == "arm64e" else {
                return false
            }
            if context.operatingSystemMajor == 26 {
                return context.operatingSystemMinor < 6
                    || (context.operatingSystemMinor == 6 && context.operatingSystemPatch <= 1)
            }
            return context.operatingSystemMajor == 27
                && context.operatingSystemMinor == 0
                && context.operatingSystemPatch == 0
                && Self.verifiedIOS27Builds.contains(context.systemBuild)
        case .darkSword:
            // No build is enabled until its exact hardware/build test matrix is
            // represented in this IPA. A server policy cannot turn this on.
            return false
        }
    }
}

public struct ProviderDisablePolicy: Equatable, Sendable {
    public let disabledProviders: Set<AccessProviderID>
    public let disabledBuilds: Set<String>

    public init(
        disabledProviders: Set<AccessProviderID> = [],
        disabledBuilds: Set<String> = []
    ) {
        self.disabledProviders = disabledProviders
        self.disabledBuilds = disabledBuilds
    }

    public func allows(_ providerID: AccessProviderID, build: String) -> Bool {
        !disabledProviders.contains(providerID) && !disabledBuilds.contains(build)
    }
}
