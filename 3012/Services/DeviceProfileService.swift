import Darwin
import Foundation
import SwiftUI
import UIKit

struct DeviceProfile: Equatable {
    let deviceName: String
    let machineIdentifier: String
    let architecture: String
    let systemVersion: String
    let buildNumber: String
    let appVersion: String
    let bundleIdentifier: String
}

enum SupportLevel {
    case supported
    case limited
    case unavailable

    var title: LocalizedStringKey {
        switch self {
        case .supported: return "Supported"
        case .limited: return "Limited Access"
        case .unavailable: return "Unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .supported: return "checkmark.circle.fill"
        case .limited: return "exclamationmark.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .supported: return AppTheme.success
        case .limited: return AppTheme.warning
        case .unavailable: return AppTheme.failure
        }
    }
}

struct CompatibilitySnapshot {
    let level: SupportLevel
    let providerName: String
    let detail: LocalizedStringKey

    static let standardFiles = CompatibilitySnapshot(
        level: .supported,
        providerName: "StandardFilesProvider",
        detail: "Manual patching through Files is available. Direct app-container access is not enabled in this build."
    )
}

@MainActor
final class DeviceProfileService: ObservableObject {
    @Published private(set) var profile: DeviceProfile
    @Published private(set) var compatibility: CompatibilitySnapshot = .standardFiles

    init() {
        profile = Self.readProfile()
    }

    func refresh(logger: SessionLogger? = nil) {
        profile = Self.readProfile()
        compatibility = .standardFiles
        logger?.info("Compatibility probe selected StandardFilesProvider for \(profile.machineIdentifier), iOS \(profile.systemVersion) (\(profile.buildNumber)).")
    }

    private static func readProfile() -> DeviceProfile {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return DeviceProfile(
            deviceName: UIDevice.current.name,
            machineIdentifier: sysctlString("hw.machine"),
            architecture: architectureName,
            systemVersion: UIDevice.current.systemVersion,
            buildNumber: sysctlString("kern.osversion"),
            appVersion: version,
            bundleIdentifier: bundle.bundleIdentifier ?? "—"
        )
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "—" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "—" }
        return String(cString: value)
    }

    private static var architectureName: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }
}
