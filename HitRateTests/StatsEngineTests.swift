import SwiftData
import XCTest
@testable import HitRate

@MainActor
final class StatsEngineTests: XCTestCase {
    func testWeightedHitRateUsesEveryOutcomeCredit() throws {
        let fixture = try makeFixture(outcomes: [.hit, .bobble, .buildingFall, .majorFall])

        let stats = StatsEngine.compute(
            sessions: [fixture.session],
            groups: [fixture.group],
            timeframe: .all
        )

        XCTAssertEqual(stats.overall, [1, 1, 1, 1])
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.rate, 50, "(100 + 67 + 33 + 0) / 4 should round to 50%")
    }

    func testLoggerFilterSeparatesCoachLoggedAndSelfLoggedAttempts() throws {
        let fixture = try makeFixture(
            outcomes: [.hit, .majorFall, .hit, .bobble, .buildingFall],
            loggerIDs: ["coach", "coach", "athlete", "athlete", "athlete"]
        )

        let coachStats = StatsEngine.compute(
            sessions: [fixture.session],
            groups: [fixture.group],
            timeframe: .all,
            logger: LoggerFilter(scope: .coach, ownerUID: "coach", currentUID: "athlete")
        )
        let selfStats = StatsEngine.compute(
            sessions: [fixture.session],
            groups: [fixture.group],
            timeframe: .all,
            logger: LoggerFilter(scope: .selfLogged, ownerUID: "coach", currentUID: "athlete")
        )

        XCTAssertEqual(coachStats.total, 2)
        XCTAssertEqual(coachStats.overall, [1, 0, 0, 1])
        XCTAssertEqual(coachStats.rate, 50)
        XCTAssertEqual(selfStats.total, 3)
        XCTAssertEqual(selfStats.overall, [1, 1, 1, 0])
        XCTAssertEqual(selfStats.rate, 67)
    }

    func testLoggerFilterWithoutFolderOwnerDoesNotHideAttempts() throws {
        let fixture = try makeFixture(
            outcomes: [.hit, .majorFall],
            loggerIDs: ["coach", "athlete"]
        )

        let stats = StatsEngine.compute(
            sessions: [fixture.session],
            groups: [fixture.group],
            timeframe: .all,
            logger: LoggerFilter(scope: .coach, ownerUID: nil, currentUID: "athlete")
        )

        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.rate, 50)
    }

    func testCreditAtOrAboveFiftyKeepsCurrentStreakActive() throws {
        let fixture = try makeFixture(outcomes: [.hit, .bobble, .hit])

        let streak = StatsEngine.currentLandingStreak(in: fixture.session.sortedAttempts)

        XCTAssertEqual(streak, 3)
    }

    func testCreditBelowFiftyResetsCurrentStreakToZero() throws {
        let fixture = try makeFixture(outcomes: [.hit, .bobble, .buildingFall])

        let streak = StatsEngine.currentLandingStreak(in: fixture.session.sortedAttempts)

        XCTAssertEqual(streak, 0)
    }

    func testStabilityBreakdownCountsOnlyVideoScoredReps() throws {
        let fixture = try makeFixture(outcomes: [.hit, .bobble, .hit, .majorFall])
        let reps = fixture.session.sortedAttempts
        // Two reps filmed by StuntScope, two logged by hand.
        reps[0].onBasePercent = 90
        reps[0].wobbleCount = 0
        reps[0].holdSeconds = 2.0
        reps[1].onBasePercent = 70
        reps[1].wobbleCount = 2
        reps[1].holdSeconds = 3.5
        try fixture.container.mainContext.save()

        let stats = StatsEngine.compute(
            sessions: [fixture.session], groups: [fixture.group], timeframe: .all)

        let stability = try XCTUnwrap(stats.stability)
        XCTAssertEqual(stability.reps, 2)
        XCTAssertEqual(stability.onBase, 80)
        XCTAssertEqual(stability.groups.count, 1)
        XCTAssertEqual(stability.groups[0].hits, 1)
        XCTAssertEqual(stability.groups[0].hitRate, 50)
        XCTAssertEqual(stability.groups[0].wobbles, 2)
        XCTAssertEqual(stability.groups[0].longestHoldSeconds, 3.5)
        XCTAssertEqual(stability.trend, [80], "one session → one point, video reps only")
        XCTAssertEqual(stability.hitTrend, [84], "(100 + 67) / 2 over the same two reps")
        // The headline rate is untouched by the layer: all four reps, as before.
        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.rate, 67)
    }

    func testHandLoggedPracticeHasNoStabilityBreakdown() throws {
        let fixture = try makeFixture(outcomes: [.hit, .hit])

        let stats = StatsEngine.compute(
            sessions: [fixture.session], groups: [fixture.group], timeframe: .all)

        XCTAssertNil(stats.stability)
        XCTAssertFalse(stats.hasStability)
    }

    func testAthleteTaggedInAStuntGroupRepSeesItUnderTheirOwnFilter() throws {
        let fixture = try makeFixture(outcomes: [.hit, .majorFall, .hit])
        let context = fixture.container.mainContext
        let flyer = Subject(name: "Maya", orderIndex: 0)
        let stuntGroup = Subject(name: "Group 3", kind: .group, orderIndex: 1)
        context.insert(flyer)
        context.insert(stuntGroup)
        let reps = fixture.session.sortedAttempts
        // Rep 0: StuntScope logged it against the group and tagged the flyer.
        reps[0].subject = stuntGroup
        reps[0].athleteIDs = [flyer.id]
        reps[0].onBasePercent = 88
        // Rep 1: the coach logged it against Maya by hand.
        reps[1].subject = flyer
        // Rep 2: somebody else's rep.
        reps[2].subject = stuntGroup
        try context.save()

        let stats = StatsEngine.compute(
            sessions: [fixture.session], groups: [fixture.group], timeframe: .all, subject: flyer)

        XCTAssertEqual(stats.total, 2, "the group rep she was tagged on plus her own hand-logged rep")
        XCTAssertEqual(stats.overall, [1, 0, 0, 1])
        XCTAssertEqual(stats.stability?.reps, 1)
    }

    func testStabilitySplitsByThePositionTheAthleteHeld() throws {
        let fixture = try makeFixture(outcomes: [.hit, .hit, .bobble])
        let context = fixture.container.mainContext
        let maya = Subject(name: "Maya", orderIndex: 0)
        let jo = Subject(name: "Jo", orderIndex: 1)
        context.insert(maya)
        context.insert(jo)
        let reps = fixture.session.sortedAttempts
        // Rep 0: Maya flew over Jo — 90% on base.
        reps[0].athleteIDs = [maya.id, jo.id]
        reps[0].rolesRaw = "flyer=\(maya.id.uuidString)\nmainBase=\(jo.id.uuidString)"
        reps[0].onBasePercent = 90
        // Rep 1: they swapped — Maya based under Jo — 60% on base.
        reps[1].athleteIDs = [maya.id, jo.id]
        reps[1].rolesRaw = "flyer=\(jo.id.uuidString)\nmainBase=\(maya.id.uuidString)"
        reps[1].onBasePercent = 60
        // Rep 2: video-scored, but Maya wasn't in the group.
        reps[2].athleteIDs = [jo.id]
        reps[2].rolesRaw = "flyer=\(jo.id.uuidString)"
        reps[2].onBasePercent = 20
        try context.save()

        let stats = StatsEngine.compute(
            sessions: [fixture.session], groups: [fixture.group], timeframe: .all, subject: maya)

        let stability = try XCTUnwrap(stats.stability)
        XCTAssertEqual(stability.reps, 2)
        XCTAssertEqual(stability.onBase, 75, "the headline still averages both of her reps")
        XCTAssertEqual(stability.byRole, [
            StabilityRoleStat(role: .flyer, reps: 1, onBase: 90),
            StabilityRoleStat(role: .mainBase, reps: 1, onBase: 60),
        ], "flying and basing must not average into one number")
        // The layer never touches the hit rate.
        XCTAssertEqual(stats.total, 2)
        XCTAssertEqual(stats.rate, 100)

        // A whole-floor compute has nobody to split by.
        let floor = StatsEngine.compute(
            sessions: [fixture.session], groups: [fixture.group], timeframe: .all)
        XCTAssertEqual(floor.stability?.reps, 3)
        XCTAssertEqual(floor.stability?.byRole.isEmpty, true)
    }

    func testStuntRoleMapRoundTripsThroughRolesRaw() throws {
        let fixture = try makeFixture(outcomes: [.hit])
        let rep = fixture.session.sortedAttempts[0]
        let flyer = UUID(), base = UUID()
        rep.rolesRaw = "flyer=\(flyer.uuidString)\nmainBase=\(base.uuidString)\nbogus=nope"

        XCTAssertEqual(rep.roles, [.flyer: flyer, .mainBase: base])
        XCTAssertFalse(rep.hasStability)
    }

    private func makeFixture(
        outcomes: [Outcome],
        loggerIDs: [String]? = nil
    ) throws -> (container: ModelContainer, group: StuntGroup, session: PracticeSession) {
        if let loggerIDs {
            XCTAssertEqual(loggerIDs.count, outcomes.count, "Fixture logger count must match outcome count")
        }

        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Full up", number: 1, orderIndex: 0)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        session.endedAt = Date(timeIntervalSince1970: 2_000)

        context.insert(group)
        context.insert(session)
        for (index, outcome) in outcomes.enumerated() {
            let attempt = Attempt(
                outcome: outcome,
                group: group,
                session: session,
                timestamp: Date(timeIntervalSince1970: 1_000 + Double(index))
            )
            attempt.loggerID = loggerIDs?[index] ?? ""
            context.insert(attempt)
        }
        try context.save()
        return (container, group, session)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Team.self, StuntGroup.self, PracticeSession.self, Attempt.self,
            PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self,
            CustomTally.self, Subject.self, OutcomeTemplate.self, Assignment.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
