import Foundation
import ThreeZeroOneTwoCore

struct AppContainerRecord: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let rootURL: URL
    let discoverySources: [String]

    var id: String { rootURL.path }
}

enum ContainerAccessState: Equatable {
    case checking
    case available
    case unsupportedSystem
    case notCompiled
    case signingMismatch
    case hostOnly
    case accessDenied
    case runtimeUnavailable
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

private struct ContainerDiscoveryResult: Sendable {
    let records: [AppContainerRecord]
    let retainedHandles: [Int64]
    let diagnostics: String
}

private enum ContainerDiscoveryError: LocalizedError {
    case noCandidates(String)
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .noCandidates(let detail):
            return "No application-container candidates were discovered. \(detail)"
        case .accessDenied(let detail):
            return "Application containers were found but could not be opened. \(detail)"
        }
    }
}

#if DEVICE_ACCESS_BUILD
private let applicationDataRoots = [
    "/private/var/mobile/Containers/Data/Application",
    "/var/mobile/Containers/Data/Application"
]

private func canonicalContainerPath(_ path: String) -> String {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    return standardized.hasPrefix("/private/var/")
        ? String(standardized.dropFirst("/private".count))
        : standardized
}

private func isValidApplicationContainerPath(_ path: String?) -> Bool {
    guard let path else { return false }
    let canonical = canonicalContainerPath(path)
    let root = "/var/mobile/Containers/Data/Application/"
    guard canonical.hasPrefix(root) else { return false }
    return UUID(uuidString: URL(fileURLWithPath: canonical).lastPathComponent) != nil
}

private func applicationRootForReading() -> String {
    FileManager.default.fileExists(atPath: applicationDataRoots[0])
        ? applicationDataRoots[0]
        : applicationDataRoots[1]
}

private struct NativeAccessSnapshot: Sendable {
    let mcmIdentifiers: [String]
    let installedInfo: [String: [String: String]]
    let rootNames: [String]
    let rootHandle: Int64
    let mcmError: String?
    let pathError: String?

    var foreignMCMIdentifiers: [String] {
        let host = Bundle.main.bundleIdentifier
        return mcmIdentifiers.filter { $0 != host }
    }
}

private func nativeAccessSnapshot(identifierLimit: Int, rootLimit: Int) -> NativeAccessSnapshot {
    var mcmError: NSString?
    let identifiers = MCMEnumerateIdentifiersForClass(2, UInt(identifierLimit), &mcmError)
    let rawInfo = PA3012InstalledAppInfo()
    var installedInfo: [String: [String: String]] = [:]
    for (key, value) in rawInfo { installedInfo[key] = value }
    var rootError: NSString?
    var rootHandle: Int64 = -1
    let rootNames = PA3012DirectoryNames(
        applicationRootForReading(), UInt(rootLimit), &rootHandle, &rootError
    )
    return NativeAccessSnapshot(
        mcmIdentifiers: identifiers,
        installedInfo: installedInfo,
        rootNames: rootNames,
        rootHandle: rootHandle,
        mcmError: mcmError.map(String.init),
        pathError: rootError.map(String.init)
    )
}

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
        let snapshot = nativeAccessSnapshot(identifierLimit: 128, rootLimit: 4_096)
        defer { PA3012ReleaseGrant(snapshot.rootHandle) }
        let uuidRoots = snapshot.rootNames.filter { UUID(uuidString: $0) != nil }
        var activationWorked = false
        var activationError: NSString?
        for identifier in snapshot.foreignMCMIdentifiers.prefix(32) {
            if isValidApplicationContainerPath(
                MCMActivateContainerPath(2, identifier, false, &activationError)
            ) {
                activationWorked = true
                break
            }
        }
        let traversalWorked = snapshot.rootHandle >= 0 && !uuidRoots.isEmpty
        let available = activationWorked || traversalWorked
        let detail = [
            "MCM=\(snapshot.mcmIdentifiers.count)",
            "foreign=\(snapshot.foreignMCMIdentifiers.count)",
            "installedAPI=\(snapshot.installedInfo.count)",
            "filesystem=\(uuidRoots.count)",
            "MCMError=\(activationError.map(String.init) ?? snapshot.mcmError ?? "none")",
            "pathError=\(snapshot.pathError ?? "none")"
        ].joined(separator: "; ")
        return AccessProbe(
            providerID: id,
            outcome: available ? .available : .failed,
            stage: .privilegedAttempt,
            capabilities: available ? capabilities : [],
            detail: detail
        )
    }
}

#endif

@MainActor
final class DeviceAccessCoordinator: ObservableObject {
    @Published private(set) var selectedProvider = AccessProviderID.standardFiles
    @Published private(set) var capabilities: AccessCapability = [.userSelectedFiles]
    @Published private(set) var containers: [AppContainerRecord] = []
    @Published private(set) var containerAccessState: ContainerAccessState = .checking
    @Published private(set) var statusDetail = "Checking direct app-container access."
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

#if DEVICE_ACCESS_BUILD
    private var retainedPathHandles: [Int64] = []
#endif

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

    deinit {
#if DEVICE_ACCESS_BUILD
        retainedPathHandles.forEach(PA3012ReleaseGrant)
#endif
    }

    func refresh(profile: DeviceProfile, logger: SessionLogger) async {
        let context = Self.context(profile: profile)
        containerAccessState = .checking
        statusDetail = "Checking direct app-container access."
        errorMessage = nil
        logger.info(
            "Access preflight build=\(deviceAccessBuild ? "DeviceAccess" : "Standard") " +
            "bundle=\(profile.bundleIdentifier) signing=\(profile.signingIdentifier) " +
            "applicationIdentifier=\(profile.applicationIdentifier) team=\(profile.teamIdentifier)"
        )

#if DEVICE_ACCESS_BUILD
        let expectedID = AccessSupportMatrix.mobileHouseArrestBundleID
        guard profile.bundleIdentifier == expectedID else {
            selectedProvider = .standardFiles
            capabilities = [.userSelectedFiles]
            containerAccessState = .signingMismatch
            statusDetail = AppLocalization.text(
                "The Device Access IPA has an incompatible Bundle ID.",
                fallback: "The Device Access IPA has an incompatible Bundle ID."
            )
            logger.error(
                "Device Access Bundle ID mismatch; actual=\(profile.bundleIdentifier), expected=\(expectedID)."
            )
            return
        }
        if profile.signingIdentifier != expectedID {
            logger.warning(
                "CodeDirectory identity differs from Bundle ID; continuing with runtime probes. " +
                "signing=\(profile.signingIdentifier), bundle=\(profile.bundleIdentifier)."
            )
        }
#endif

        let providers: [any DeviceAccessProvider]
#if DEVICE_ACCESS_BUILD
        providers = [MobileHouseArrestAccessProvider(), StandardFilesAccessProvider()]
#else
        providers = [StandardFilesAccessProvider()]
#endif
        let route = await AccessProviderRouter(providers: providers).route(context: context)
        for probe in route.probes {
            logger.info(
                "Access probe \(probe.providerID.rawValue) stage=\(probe.stage) " +
                "outcome=\(probe.outcome): \(probe.detail)"
            )
        }
        let probeDetail: String
        if let probe = route.selected {
            selectedProvider = probe.providerID
            capabilities = probe.capabilities
            probeDetail = probe.detail
        } else {
            selectedProvider = .standardFiles
            capabilities = []
            probeDetail = route.probes.last?.detail ?? "No compiled provider matched this build."
        }

#if DEVICE_ACCESS_BUILD
        let matrixAllows = AccessSupportMatrix().allows(.mobileHouseArrest, context: context)
        if selectedProvider == .mobileHouseArrest && capabilities.contains(.listAppContainers) {
            containerAccessState = .available
            statusDetail = AppLocalization.text(
                "Read-only app-container access is available.",
                fallback: "Read-only app-container access is available."
            )
        } else if !matrixAllows {
            containerAccessState = .unsupportedSystem
            statusDetail = AppLocalization.text(
                "Direct app-container access is not supported on this iOS build. Manual patching through Files is still available.",
                fallback: "Direct app-container access is not supported on this iOS build. Manual patching through Files is still available."
            )
        } else if probeDetail.contains("foreign=0") && probeDetail.contains("filesystem=0") {
            containerAccessState = .hostOnly
            statusDetail = AppLocalization.text(
                "Only the 3012 host container is visible; device-wide access is not active.",
                fallback: "Only the 3012 host container is visible; device-wide access is not active."
            )
        } else if probeDetail.contains("path grant failed") || probeDetail.contains("denied") {
            containerAccessState = .accessDenied
            statusDetail = AppLocalization.text(
                "The system denied access to application containers. Check signing and session logs.",
                fallback: "The system denied access to application containers. Check signing and session logs."
            )
        } else {
            containerAccessState = .runtimeUnavailable
            statusDetail = AppLocalization.text(
                "Compatibility checks passed, but the container provider could not be activated. Check the signing identity and session log.",
                fallback: "Compatibility checks passed, but the container provider could not be activated. Check the signing identity and session log."
            )
        }
#else
        containerAccessState = .notCompiled
        statusDetail = AppLocalization.text(
            "This build does not include direct app-container access. Use the Device Access IPA.",
            fallback: "This build does not include direct app-container access. Use the Device Access IPA."
        )
#endif

        if !directContainerAccessAvailable { containers = [] }
        logger.info(
            "Container access state: \(String(describing: containerAccessState)); detail=\(statusDetail)"
        )
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
            case .success(let discovery):
#if DEVICE_ACCESS_BUILD
                retainedPathHandles.forEach(PA3012ReleaseGrant)
                retainedPathHandles = discovery.retainedHandles
#endif
                containers = discovery.records
                containerAccessState = .available
                statusDetail = AppLocalization.format(
                    "Found %lld readable app containers.",
                    fallback: "Found %lld readable app containers.",
                    Int64(discovery.records.count)
                )
                logger.info("Container discovery completed: \(discovery.diagnostics)")
            case .failure(let error):
                containerAccessState = .accessDenied
                statusDetail = AppLocalization.text(
                    "error.containerDiscoveryFailed",
                    fallback: "App containers could not be discovered. Check the build identity and session log."
                )
                errorMessage = error.localizedDescription
                logger.error("Container discovery failed: \(error.localizedDescription)")
            }
        }
    }

#if DEVICE_ACCESS_BUILD
    nonisolated private static func discoverContainers() -> Result<ContainerDiscoveryResult, Error> {
        let snapshot = nativeAccessSnapshot(identifierLimit: 4_096, rootLimit: 16_384)
        var retainedHandles: [Int64] = []
        if snapshot.rootHandle >= 0 { retainedHandles.append(snapshot.rootHandle) }
        let root = applicationRootForReading()
        var sourcesByPath: [String: Set<String>] = [:]
        var identityByPath: [String: (bundleID: String, name: String)] = [:]

        func accept(path rawPath: String, bundleID: String, name: String, source: String) {
            guard isValidApplicationContainerPath(rawPath) else { return }
            let path = canonicalContainerPath(rawPath)
            sourcesByPath[path, default: []].insert(source)
            let current = identityByPath[path]
            let preferredID = bundleID.isEmpty
                ? current?.bundleID ?? URL(fileURLWithPath: path).lastPathComponent
                : bundleID
            let preferredName = name.isEmpty ? current?.name ?? preferredID : name
            identityByPath[path] = (preferredID, preferredName)
        }

        for (bundleID, info) in snapshot.installedInfo {
            if let path = info["container"] {
                accept(
                    path: path,
                    bundleID: bundleID,
                    name: info["name"] ?? bundleID,
                    source: "InstalledAppAPI"
                )
            }
        }
        for identifier in Set(snapshot.mcmIdentifiers).union(snapshot.installedInfo.keys) {
            autoreleasepool {
                var error: NSString?
                if let path = MCMActivateContainerPath(2, identifier, false, &error) {
                    accept(
                        path: path,
                        bundleID: identifier,
                        name: snapshot.installedInfo[identifier]?["name"] ?? identifier,
                        source: "MCM"
                    )
                }
            }
        }
        for uuid in snapshot.rootNames where UUID(uuidString: uuid) != nil {
            let rawPath = (root as NSString).appendingPathComponent(uuid)
            var bundleID = uuid
            var name = "Container \(uuid.prefix(8))"
            let metadataPath = (rawPath as NSString).appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist"
            )
            let metadataHandle = PA3012GrantPath(metadataPath)
            if metadataHandle >= 0 {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: metadataPath)),
                   let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                   ) as? [String: Any] {
                    bundleID = plist["MCMMetadataIdentifier"] as? String ?? bundleID
                    if let info = plist["MCMMetadataInfo"] as? [String: Any] {
                        name = info["CFBundleDisplayName"] as? String
                            ?? info["CFBundleName"] as? String ?? bundleID
                    } else {
                        name = snapshot.installedInfo[bundleID]?["name"] ?? bundleID
                    }
                }
                PA3012ReleaseGrant(metadataHandle)
            }
            accept(path: rawPath, bundleID: bundleID, name: name, source: "Filesystem")
        }

        guard !sourcesByPath.isEmpty else {
            PA3012ReleaseGrant(snapshot.rootHandle)
            let detail = "MCM=\(snapshot.mcmIdentifiers.count); API=\(snapshot.installedInfo.count); " +
                "filesystem=\(snapshot.rootNames.count); " +
                "\(snapshot.pathError ?? snapshot.mcmError ?? "no detail")"
            return .failure(ContainerDiscoveryError.noCandidates(detail))
        }

        var records: [AppContainerRecord] = []
        for path in sourcesByPath.keys.sorted() {
            let handle = PA3012GrantPath(path)
            guard handle >= 0 else { continue }
            guard FileManager.default.isReadableFile(atPath: path) else {
                PA3012ReleaseGrant(handle)
                continue
            }
            retainedHandles.append(handle)
            let identity = identityByPath[path]!
            records.append(AppContainerRecord(
                bundleIdentifier: identity.bundleID,
                displayName: identity.name,
                rootURL: URL(fileURLWithPath: path, isDirectory: true),
                discoverySources: Array(sourcesByPath[path]!).sorted()
            ))
        }
        guard !records.isEmpty else {
            retainedHandles.forEach(PA3012ReleaseGrant)
            return .failure(ContainerDiscoveryError.accessDenied(
                "\(sourcesByPath.count) candidates were identified but every path grant or read check failed."
            ))
        }
        records.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let filesystemCount = snapshot.rootNames.filter { UUID(uuidString: $0) != nil }.count
        let diagnostics = "resolved=\(records.count); MCM=\(snapshot.mcmIdentifiers.count); " +
            "API=\(snapshot.installedInfo.count); filesystem=\(filesystemCount)"
        return .success(ContainerDiscoveryResult(
            records: records,
            retainedHandles: retainedHandles,
            diagnostics: diagnostics
        ))
    }
#else
    nonisolated private static func discoverContainers() -> Result<ContainerDiscoveryResult, Error> {
        .failure(NSError(
            domain: "app.3012.access.standard",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Direct container access is not compiled into this build."]
        ))
    }
#endif

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
            signingIdentifier: profile.signingIdentifier,
            filesPickerAvailable: true
        )
    }
}
