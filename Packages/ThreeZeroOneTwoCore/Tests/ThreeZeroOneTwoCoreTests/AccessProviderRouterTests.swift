import XCTest
@testable import ThreeZeroOneTwoCore

private struct ProbeProvider: DeviceAccessProvider {
    let id: AccessProviderID
    let capabilities: AccessCapability
    let result: AccessProbe

    func probe(context: DeviceAccessContext) async -> AccessProbe { result }
}

final class AccessProviderRouterTests: XCTestCase {
    private func context(
        major: Int = 26,
        minor: Int = 1,
        patch: Int = 0,
        build: String = "23B1",
        bundleID: String = AccessSupportMatrix.mobileHouseArrestBundleID,
        signingID: String = AccessSupportMatrix.mobileHouseArrestBundleID
    ) -> DeviceAccessContext {
        DeviceAccessContext(
            operatingSystemMajor: major,
            operatingSystemMinor: minor,
            operatingSystemPatch: patch,
            systemBuild: build,
            machineIdentifier: "iPhone17,1",
            architecture: "arm64",
            bundleIdentifier: bundleID,
            signingIdentifier: signingID,
            filesPickerAvailable: true
        )
    }

    func testMismatchedSigningIdentifierFailsClosed() {
        XCTAssertFalse(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(signingID: "com.example.resigned")
        ))
    }

    func testOnlyVerifiedIOS27BuildsAreAllowed() {
        XCTAssertTrue(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(major: 27, minor: 0, patch: 0, build: "24A5390f")
        ))
        XCTAssertFalse(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(major: 27, minor: 0, patch: 0, build: "24A9999z")
        ))
    }

    func testPrivilegedFailureRequiresFreshSessionAndStopsFallback() async {
        let privileged = ProbeProvider(
            id: .mobileHouseArrest,
            capabilities: [.listAppContainers],
            result: AccessProbe(
                providerID: .mobileHouseArrest,
                outcome: .failed,
                stage: .privilegedAttempt,
                detail: "probe failed"
            )
        )
        let standard = ProbeProvider(
            id: .standardFiles,
            capabilities: [.userSelectedFiles],
            result: AccessProbe(
                providerID: .standardFiles,
                outcome: .available,
                stage: .runtimeProbe,
                capabilities: [.userSelectedFiles],
                detail: "available"
            )
        )

        let route = await AccessProviderRouter(providers: [privileged, standard])
            .route(context: context())
        XCTAssertNil(route.selected)
        XCTAssertTrue(route.requiresFreshSession)
        XCTAssertEqual(route.probes.count, 1)
    }

    func testRemotePolicyCanDisableButCannotEnableDarkSword() async {
        let darkSword = ProbeProvider(
            id: .darkSword,
            capabilities: [.listAppContainers],
            result: AccessProbe(
                providerID: .darkSword,
                outcome: .available,
                stage: .runtimeProbe,
                capabilities: [.listAppContainers],
                detail: "unexpected"
            )
        )
        let route = await AccessProviderRouter(providers: [darkSword]).route(context: context())
        XCTAssertNil(route.selected)
        XCTAssertTrue(route.probes.isEmpty)
    }
}
