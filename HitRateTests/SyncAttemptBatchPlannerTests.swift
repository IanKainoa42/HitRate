import XCTest
@testable import HitRate

final class SyncAttemptBatchPlannerTests: XCTestCase {
    func testMissingDocumentIDsAreIndexedAndDeduplicated() {
        let existing = (0..<5_000).map { "attempt-\($0)" }
        let remote = Array(existing.reversed()) + ["new-a", "new-b", "new-a"]

        let missing = SyncAttemptBatchPlanner.missingDocumentIDs(
            remote: remote,
            existing: existing
        )

        XCTAssertEqual(missing, ["new-a", "new-b"])
    }
}
