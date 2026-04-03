import XCTest
@testable import Fort_Abode_Utility_Central

final class VersionComparisonTests: XCTestCase {

    func testNewerPatchVersion() {
        XCTAssertTrue(SemverComparison.isNewer("1.2.1", than: "1.2.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(SemverComparison.isNewer("1.3.0", than: "1.2.0"))
    }

    func testNewerMajorVersion() {
        XCTAssertTrue(SemverComparison.isNewer("2.0.0", than: "1.9.9"))
    }

    func testSameVersion() {
        XCTAssertFalse(SemverComparison.isNewer("1.2.0", than: "1.2.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(SemverComparison.isNewer("1.1.0", than: "1.2.0"))
    }

    func testVPrefixStripping() {
        XCTAssertTrue(SemverComparison.isNewer("v1.3.0", than: "1.2.0"))
        XCTAssertTrue(SemverComparison.isNewer("1.3.0", than: "v1.2.0"))
        XCTAssertTrue(SemverComparison.isNewer("v1.3.0", than: "v1.2.0"))
    }

    func testMissingPatchComponent() {
        // "1.2" should be treated as "1.2.0"
        XCTAssertFalse(SemverComparison.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(SemverComparison.isNewer("1.3", than: "1.2.0"))
    }

    func testParsing() {
        XCTAssertEqual(SemverComparison.parse("1.2.3"), [1, 2, 3])
        XCTAssertEqual(SemverComparison.parse("v1.2.3"), [1, 2, 3])
        XCTAssertEqual(SemverComparison.parse("10.20.30"), [10, 20, 30])
        XCTAssertEqual(SemverComparison.parse("1.0"), [1, 0])
    }
}
