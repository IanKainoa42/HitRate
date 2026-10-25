import XCTest
@testable import HitRate

final class CoachGrandfatherPolicyTests: XCTestCase {
    func testPaidEraBuildsQualifyIncludingCoachSubscriptionShip() {
        for build in [1, 35, 36, 37, 38, 39, 40] {
            XCTAssertTrue(
                CoachGrandfatherPolicy.qualifies(originalAppVersion: String(build)),
                "build \(build) should grandfather"
            )
        }
    }

    func testFirstFreeBuildAndLaterDoNotQualify() {
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: "41"))
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: "50"))
    }

    func testSandboxAndReviewVersionNeverQualifies() {
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: "1.0"))
    }

    func testNonNumericOriginalVersionNeverQualifies() {
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: ""))
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: "1.8"))
        XCTAssertFalse(CoachGrandfatherPolicy.qualifies(originalAppVersion: "abc"))
    }
}
