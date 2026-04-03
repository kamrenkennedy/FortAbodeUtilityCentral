import XCTest
@testable import Fort_Abode_Utility_Central

final class VersionDetectionTests: XCTestCase {

    func testUpdateStatusProperties() {
        let upToDate = UpdateStatus.upToDate(version: "1.2.0")
        XCTAssertEqual(upToDate.installedVersion, "1.2.0")
        XCTAssertFalse(upToDate.isUpdateAvailable)

        let updateAvail = UpdateStatus.updateAvailable(installed: "1.2.0", latest: "1.3.0")
        XCTAssertEqual(updateAvail.installedVersion, "1.2.0")
        XCTAssertTrue(updateAvail.isUpdateAvailable)

        let notInstalled = UpdateStatus.notInstalled
        XCTAssertNil(notInstalled.installedVersion)
        XCTAssertFalse(notInstalled.isUpdateAvailable)

        let unknown = UpdateStatus.unknown
        XCTAssertNil(unknown.installedVersion)
        XCTAssertFalse(unknown.isUpdateAvailable)
    }

    func testStatusTextFormatting() {
        let upToDate = UpdateStatus.upToDate(version: "1.2.0")
        XCTAssertEqual(upToDate.statusText, "Up to date (1.2.0)")

        let updateAvail = UpdateStatus.updateAvailable(installed: "1.2.0", latest: "1.3.0")
        XCTAssertEqual(updateAvail.statusText, "1.3.0 available (you have 1.2.0)")

        let error = UpdateStatus.error(message: "Network timeout")
        XCTAssertEqual(error.statusText, "Error: Network timeout")
    }

    func testSFSymbolNames() {
        XCTAssertEqual(UpdateStatus.upToDate(version: "1.0").sfSymbolName, "checkmark.circle.fill")
        XCTAssertEqual(UpdateStatus.updateAvailable(installed: "1.0", latest: "2.0").sfSymbolName, "arrow.up.circle.fill")
        XCTAssertEqual(UpdateStatus.error(message: "fail").sfSymbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(UpdateStatus.checking.sfSymbolName, "arrow.triangle.2.circlepath")
    }
}
