import XCTest
@testable import HitRate

final class DeckGridCardTests: XCTestCase {
    func testSummaryPluralizesZeroAndManyCounts() {
        XCTAssertEqual(
            DeckGridCardCopy.summary(skillCount: 0, repCount: 12),
            "0 skills · 12 reps"
        )
    }

    func testSummaryUsesSingularWords() {
        XCTAssertEqual(
            DeckGridCardCopy.summary(skillCount: 1, repCount: 1),
            "1 skill · 1 rep"
        )
    }

    func testJoinedDeckAccessibilityIncludesOwnershipState() {
        XCTAssertEqual(
            DeckGridCardCopy.accessibilityLabel(
                name: "Ravens Black",
                skillCount: 7,
                repCount: 171,
                sharingState: .joined
            ),
            "Ravens Black deck, 7 skills, 171 reps, joined deck"
        )
    }

    func testOwnedSharedDeckAccessibilityIncludesSharingState() {
        XCTAssertEqual(
            DeckGridCardCopy.accessibilityLabel(
                name: "Kainoa",
                skillCount: 1,
                repCount: 1,
                sharingState: .shared
            ),
            "Kainoa deck, 1 skill, 1 rep, shared deck"
        )
    }

    func testOnlySharedDecksExposeABadgeLabel() {
        XCTAssertNil(DeckSharingState.privateDeck.badgeLabel)
        XCTAssertEqual(DeckSharingState.shared.badgeLabel, "SHARED")
        XCTAssertEqual(DeckSharingState.joined.badgeLabel, "JOINED")
    }
}
