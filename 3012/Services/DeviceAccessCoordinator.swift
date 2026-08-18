import Foundation
import ThreeZeroOneTwoCore

struct AppContainerRecord: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let rootURL: URL

    var id: String { bundleIdentifier }
}

struct StandardFilesAccessProvider: DeviceAccessProvider {
    let id: AccessProviderID = .standardFiles
    let capabilities: AccessCapability = [.userSelectedFiles]

    func probe(context: DeviceAccessContext) async -> AccessProbe {
        AccessProbe(
            providerID: id,
            outcome: context.filesPickerAvailable ? .available : .unavailable,
            stage: .runtimeProbe,
            capabilities: context.filesPickerAvailable ? capabilities : [],
            detail: context.filesPickerAvailable ? "Files picker available" : "Files picker unavailable"
        )
    }
}

#if DEVICE_ACCESS_BUILD
struct MobileHouseArrestAccessProvider: DeviceAccessProvider {
    let id: AccessProviderID = .mobileHouseArrest
    let capabilities: AccessCapability = [.listAppContainers, .readAppContainers]

    func probe(context: DeviceAccessContext) async -> AccessProbe {
        guard MCMBridgeAvailable() else {
            return AccessProbe(
                providerID: id,
                outcome: .unavailable,
                stage: .preflight,
                detail: "ContainerManager symbols unavailable"
            )
        }
        var bridgeError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1, &bridgeError)
        let available = !identifiers.isEmpty
        return AccessProbe(
            providerID: id,
            outcome: available ? .available : .failed,
            stage: .runtimeProbe,
            capabilities: available ? capabilities : [],
            detail: available
                ? "Read-only class-2 enumeration available"
                : bridgeError.map { String($0) } ?? "No application containers returned"
        )
    }
}
#endif

@MainActor
final class DeviceAccessCoordinator: ObservableObject {
    @Published private(set) var selectedProvider = AccessProviderID.standardFiles
    @Published private(set) var capabilities: AccessCapability = [.userSelectedFiles]
    @Published private(set) var containers: [AppContainerRecord] = []
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    var directContainerAccessAvailable: Bool {
        capabilities.contains(.listAppContainers)
    }

    var deviceAccessBuild: Bool {
#if DEVICE_ACCESS_BUILD
        true
#else
        false
#endif
    }

    func refresh(profile: DeviceProfile, logger: SessionLogger) async {
        let context = Self.context(profile: profile)
        let providers: [any DeviceAccessProvider]
#if DEVICE_ACCESS_BUILD
        providers = [MobileHouseArrestAccessProvider(), StandardFilesAccessProvider()]
#else
        providers = [StandardFilesAccessProvider()]
#endif
        let route = await AccessProviderRouter(providers: providers).route(context: context)
        if let probe = route.selected {
            selectedProvider = probe.providerID
            capabilities = probe.capabilities
            logger.info("Access router selected \(probe.providerID.rawValue): \(probe.detail)")
        } else {
            selectedProvider = .standardFiles
            capabilities = []
            let detail = route.probes.last?.detail ?? "No compiled provider matched this build."
            errorMessage = detail
            logger.warning("Access router selected no provider: \(detail)")
        }
    }

    func scanContainers(logger: SessionLogger) {
        guard selectedProvider == .mobileHouseArrest,
              capabilities.contains(.listAppContainers),
              !isScanning else { return }
        isScanning = true
        errorMessage = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.discoverContainers()
            }.value
            isScanning = false
            switch result {
            case .success(let records):
                containers = records
                logger.info("Read-only container discovery resolved \(records.count) application identifiers.")
            case .failure(let error):
                errorMessage = AppLocalization.text(
                    "error.containerDiscoveryFailed",
                    fallback: "App containers could not be discovered. Check the build identity and session log."
                )
                logger.error("Container discovery failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func discoverContainers() -> Result<[AppContainerRecord], Error> {
#if DEVICE_ACCESS_BUILD
        var bridgeError: NSString?
        let identifiers = MCMEnumerateIdentifiersForClass(2, 1_024, &bridgeError)
        if identifiers.isEmpty, let bridgeError {
            return .failure(NSError(
                domain: "app.3012.access.mcm",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: bridgeError]
            ))
        }

        var records: [AppContainerRecord] = []
        for identifier in identifiers.prefix(1_024) {
            autoreleasepool {
                var activationError: NSString?
                guard let path = MCMActivateContainerPath(2, identifier, false, &activationError),
                      path.hasPrefix("/private/var/mobile/Containers/Data/Application/") else {
                    return
                }
                records.append(AppContainerRecord(
                    bundleIdentifier: identifier,
                    rootURL: URL(fileURLWithPath: path, isDirectory: true)
                ))
            }
        }
        records.sort {
            $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending
        }
        return .success(records)
#else
        return .failure(NSError(
            domain: "app.3012.access.standard",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Direct container access is not compiled into this build."]
        ))
#endif
    }

    private static func context(profile: DeviceProfile) -> DeviceAccessContext {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceAccessContext(
            operatingSystemMajor: version.majorVersion,
            operatingSystemMinor: version.minorVersion,
            operatingSystemPatch: version.patchVersion,
            systemBuild: profile.buildNumber,
            machineIdentifier: profile.machineIdentifier,
            architecture: profile.architecture,
            bundleIdentifier: profile.bundleIdentifier,
            signingIdentifier: profile.bundleIdentifier,
            filesPickerAvailable: true
        )
    }
}
