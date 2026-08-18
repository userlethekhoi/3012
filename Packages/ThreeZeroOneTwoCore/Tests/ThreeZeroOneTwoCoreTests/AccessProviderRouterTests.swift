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
        machineIdentifier: String = "iPhone17,1",
        bundleID: String = AccessSupportMatrix.mobileHouseArrestBundleID,
        signingID: String = AccessSupportMatrix.mobileHouseArrestBundleID
    ) -> DeviceAccessContext {
        DeviceAccessContext(
            operatingSystemMajor: major,
            operatingSystemMinor: minor,
            operatingSystemPatch: patch,
            systemBuild: build,
            machineIdentifier: machineIdentifier,
            architecture: "arm64",
            bundleIdentifier: bundleID,
            signingIdentifier: signingID,
            filesPickerAvailable: true
        )
    }

    func testMismatchedSigningIdentifierDefersToRuntimeProbe() {
        XCTAssertTrue(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(signingID: "com.example.resigned")
        ))
    }

    func testMismatchedBundleIdentifierStillFailsClosed() {
        XCTAssertFalse(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(bundleID: "com.example.resigned")
        ))
    }

    func testIPhone13_2OnIOS26_0_1IsInsideVerifiedMatrix() {
        let device = context(
            major: 26,
            minor: 0,
            patch: 1,
            build: "23A355",
            machineIdentifier: "iPhone13,2"
        )
        XCTAssertTrue(AccessSupportMatrix().allows(.mobileHouseArrest, context: device))
    }

    func testIOS26BoundaryIsFailClosed() {
        XCTAssertTrue(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(major: 26, minor: 6, patch: 1)
        ))
        XCTAssertFalse(AccessSupportMatrix().allows(
            .mobileHouseArrest,
            context: context(major: 26, minor: 6, patch: 2)
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

    func testIOS16DoesNotClaimMobileHouseArrestSupport() {
        let ios16 = context(
            major: 16,
            minor: 7,
            patch: 14,
            build: "20H370",
            bundleID: AccessSupportMatrix.mobileHouseArrestBundleID,
            signingID: AccessSupportMatrix.mobileHouseArrestBundleID
        )
        XCTAssertFalse(AccessSupportMatrix().allows(.mobileHouseArrest, context: ios16))
        XCTAssertTrue(AccessSupportMatrix().allows(.standardFiles, context: ios16))
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
