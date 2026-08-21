import XCTest
import SwiftData
@testable import HitRate

/// The card ladder: stages are bought with reps and badges, never rate.
@MainActor
final class CardStageTests: XCTestCase {

    // MARK: Stage thresholds (pure CardStanding logic)

    func testZeroRepsIsMinted() {
        XCTAssertEqual(CardStanding(reps: 0, badges: []).stage, .minted)
    }

    func testFirstRepsAreInked() {
        let s = CardStanding(reps: 5, badges: [])
        XCTAssertEqual(s.stage, .inked)
        XCTAssertFalse(s.hasBandColor, "Band color waits for \(CardStanding.colorMinReps) reps")
        XCTAssertFalse(s.flavorUnlocked)
    }

    func testBandColorUnlocksAtTenReps() {
        XCTAssertTrue(CardStanding(reps: 10, badges: []).hasBandColor)
        XCTAssertFalse(CardStanding(reps: 9, badges: []).hasBandColor)
    }

    func testProvenAtFiftyReps() {
        let s = CardStanding(reps: 50, badges: [])
        XCTAssertEqual(s.stage, .proven)
        XCTAssertTrue(s.flavorUnlocked)
        XCTAssertEqual(CardStanding(reps: 49, badges: []).stage, .inked)
    }

    func testAnyBadgeDecorates() {
        let badge = CardBadge(id: "cup-1", icon: "trophy.fill", label: "Rate cup", tier: .rare)
        XCTAssertEqual(CardStanding(reps: 20, badges: [badge]).stage, .decorated)
    }

    func testFoilRequiresHoloOrLegendaryBadge() {
        let rare = CardBadge(id: "r", icon: "flame.fill", label: "10 straight", tier: .rare)
        let holo = CardBadge(id: "h", icon: "flame.fill", label: "25 straight", tier: .holo)
        let legendary = CardBadge(id: "l", icon: "crown.fill", label: "Mastered", tier: .legendary)
        XCTAssertEqual(CardStanding(reps: 200, badges: [rare]).stage, .decorated)
        XCTAssertEqual(CardStanding(reps: 200, badges: [rare, holo]).stage, .foil)
        XCTAssertEqual(CardStanding(reps: 200, badges: [legendary]).stage, .foil)
        XCTAssertEqual(CardStanding(reps: 200, badges: [rare, holo, legendary]).maxBadgeTier, .legendary)
    }

    func testHighRateAloneBuysNothing() {
        // 9-for-9 is a perfect rate and an INKED card — rate never decorates.
        let s = CardStanding(reps: 9, badges: [])
        XCTAssertEqual(s.stage, .inked)
        XCTAssertFalse(s.hasBandColor)
    }

    // MARK: Badge derivation (SwiftData fixtures)

    func testVolumeBadgeShowsHighestRungOnly() throws {
        let fx = try makeFixture(reps: 120, outcome: .hit)
        let badges = CardStandings.badges(for: fx.group, milestones: [], cups: [])
        let volume = badges.filter { $0.id.hasPrefix("vol") }
        XCTAssertEqual(volume.count, 1)
        XCTAssertEqual(volume.first?.id, "vol100")
        XCTAssertEqual(volume.first?.tier, .rare)
        _ = fx.container   // keep the in-memory store alive
    }

    func testHitRunBadgeBreaksOnMiss() throws {
        // 12 hits, a fall, then 4 hits — best run 12 → the 10-straight badge.
        let outcomes: [Outcome] = Array(repeating: .hit, count: 12) + [.majorFall]
            + Array(repeating: .hit, count: 4)
        let fx = try makeFixture(outcomes: outcomes)
        XCTAssertEqual(CardStandings.bestHitRun(fx.group.attempts), 12)
        let badges = CardStandings.badges(for: fx.group, milestones: [], cups: [])
        XCTAssertTrue(badges.contains { $0.id == "run10" })
        XCTAssertFalse(badges.contains { $0.id == "run25" })
        _ = fx.container
    }

    func testCupBadgeMatchesWinnerAndSkipsGhost() throws {
        let fx = try makeFixture(reps: 30, outcome: .hit)
        let week = DateInterval(start: .distantPast, duration: 604_800)
        let won = WeeklyCup(id: "1", week: week, game: .rate,
                            winnerName: fx.group.name, winnerNumber: fx.group.number,
                            winnerGroupID: fx.group.id, colorIndex: 0, score: 90)
        let ghost = WeeklyCup(id: "2", week: week, game: .grind,
                              winnerName: "THE SPIRIT", winnerNumber: 0,
                              winnerGroupID: nil, colorIndex: 0, score: 120, isGhost: true)
        let badges = CardStandings.badges(for: fx.group, milestones: [], cups: [won, ghost])
        XCTAssertEqual(badges.filter { $0.id.hasPrefix("cup-") }.count, 1)
        XCTAssertEqual(badges.first { $0.id.hasPrefix("cup-") }?.id, "cup-1")
        _ = fx.container
    }

    func testMasteryMilestoneBadgesItsOwnCard() throws {
        let fx = try makeFixture(reps: 60, outcome: .hit)
        let mine = Milestone(id: "mastery-\(fx.group.persistentModelID)-stunt", kind: .stunt,
                             variantIndex: 0, kicker: "MILESTONE", name: "Mastered: Full up",
                             icon: "crown.fill", tier: .legendary, flavor: "", earned: true,
                             progress: 1, detail: "", currentCount: nil)
        let other = Milestone(id: "mastery-someoneelse-stunt", kind: .stunt,
                              variantIndex: 0, kicker: "MILESTONE", name: "Mastered: Lib",
                              icon: "crown.fill", tier: .legendary, flavor: "", earned: true,
                              progress: 1, detail: "", currentCount: nil)
        let badges = CardStandings.badges(for: fx.group, milestones: [mine, other], cups: [])
        XCTAssertEqual(badges.filter { $0.label == "Mastered" }.count, 1)
        XCTAssertEqual(badges.first { $0.label == "Mastered" }?.tier, .legendary)
        _ = fx.container
    }

    func testTeamBadgesExcludeMasteryAndToughLove() {
        let volume = Milestone(id: "reps100-stunt", kind: .stunt, variantIndex: 0,
                               kicker: "MILESTONE", name: "Century Club", icon: "bolt.fill",
                               tier: .rare, flavor: "", earned: true, progress: 1,
                               detail: "", currentCount: nil)
        let mastery = Milestone(id: "mastery-x-stunt", kind: .stunt, variantIndex: 0,
                                kicker: "MILESTONE", name: "Mastered: Lib", icon: "crown.fill",
                                tier: .legendary, flavor: "", earned: true, progress: 1,
                                detail: "", currentCount: nil)
        let dubious = Milestone(id: "demolition-stunt", kind: .stunt, variantIndex: 0,
                                kicker: "TOUGH LOVE", name: "Demolition Day", icon: "hammer.fill",
                                tier: .holo, flavor: "", earned: true, progress: 1,
                                detail: "", currentCount: nil)
        let locked = Milestone(id: "reps500-stunt", kind: .stunt, variantIndex: nil,
                               kicker: "MILESTONE", name: "Half a Grand", icon: "bolt.fill",
                               tier: .holo, flavor: "", earned: false, progress: 0.4,
                               detail: "", currentCount: nil)
        let badges = CardStandings.teamBadges(milestones: [volume, mastery, dubious, locked])
        XCTAssertEqual(badges.map(\.id), ["reps100-stunt"],
                       "Mastery stays on its skill's card; TOUGH LOVE and locked never decorate")
    }

    // MARK: Fixtures (house pattern — keep the container alive)

    private func makeFixture(reps: Int, outcome: Outcome) throws
        -> (container: ModelContainer, group: StuntGroup) {
        try makeFixture(outcomes: Array(repeating: outcome, count: reps))
    }

    private func makeFixture(outcomes: [Outcome]) throws
        -> (container: ModelContainer, group: StuntGroup) {
        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Full up", number: 1, orderIndex: 0)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        session.endedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(group)
        context.insert(session)
        for (index, outcome) in outcomes.enumerated() {
            let attempt = Attempt(outcome: outcome, group: group, session: session,
                                  timestamp: Date(timeIntervalSince1970: 1_000 + Double(index)))
            context.insert(attempt)
        }
        try context.save()
        return (container, group)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Team.self, StuntGroup.self, PracticeSession.self, Attempt.self,
            PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self,
            CustomTally.self, Subject.self, OutcomeTemplate.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
