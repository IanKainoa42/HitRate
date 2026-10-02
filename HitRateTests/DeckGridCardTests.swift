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

    func testPrivateDeckHasNoAccessibilitySuffix() {
        XCTAssertEqual(
            DeckGridCardCopy.accessibilityLabel(
                name: "Solo",
                skillCount: 0,
                repCount: 0,
                sharingState: .privateDeck
            ),
            "Solo deck, 0 skills, 0 reps"
        )
    }

    func testSharingStatePrefersJoinedForNonOwners() {
        XCTAssertEqual(
            DeckSharingState.resolve(isOwner: false, isShared: true),
            .joined
        )
        XCTAssertEqual(
            DeckSharingState.resolve(isOwner: false, isShared: false),
            .joined
        )
    }

    func testOwnerSharingStateReflectsPublishedState() {
        XCTAssertEqual(
            DeckSharingState.resolve(isOwner: true, isShared: true),
            .shared
        )
        XCTAssertEqual(
            DeckSharingState.resolve(isOwner: true, isShared: false),
            .privateDeck
        )
    }
}
