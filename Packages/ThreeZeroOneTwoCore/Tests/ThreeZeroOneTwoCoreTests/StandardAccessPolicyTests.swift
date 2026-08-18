import XCTest
@testable import ThreeZeroOneTwoCore

final class StandardAccessPolicyTests: XCTestCase {
    func testFilesPickerSelectsStandardProviderOnAnyReportedBuild() {
        let decision = StandardAccessPolicy.evaluate(StandardAccessInput(
            filesPickerAvailable: true,
            machineIdentifier: "iPhone17,1",
            systemBuild: "23A000"
        ))

        XCTAssertEqual(decision.status, .supported)
        XCTAssertEqual(decision.providerID, "StandardFilesProvider")
    }

    func testMissingFilesPickerFailsClosed() {
        let decision = StandardAccessPolicy.evaluate(StandardAccessInput(
            filesPickerAvailable: false,
            machineIdentifier: "unknown",
            systemBuild: "unknown"
        ))

        XCTAssertEqual(decision.status, .unavailable)
        XCTAssertNil(decision.providerID)
    }
}
