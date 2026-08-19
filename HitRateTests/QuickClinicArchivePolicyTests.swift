import XCTest
@testable import HitRate

final class QuickClinicArchivePolicyTests: XCTestCase {
    func testUnavailablePurchasesArchiveTheClinicDirectly() {
        let destination = QuickClinicArchivePolicy.destination(purchasesAvailable: false)

        XCTAssertEqual(destination, .archive)
    }
}
