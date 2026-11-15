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
        reps[0].flightSeconds = [1.25]
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
        XCTAssertEqual(stability.groups[0].avgHoldSeconds, 2.75)
        XCTAssertEqual(stability.groups[0].maxFlightSeconds, 1.25)
        XCTAssertEqual(stability.groups[0].rockSolidCount, 1)
        XCTAssertEqual(stability.avgHoldSeconds, 2.75)
        XCTAssertEqual(stability.maxHoldSeconds, 3.5)
        XCTAssertEqual(stability.totalWobbles, 2)
        XCTAssertEqual(stability.wobblesPerRep, 1.0)
        XCTAssertEqual(stability.maxFlightSeconds, 1.25)
        XCTAssertEqual(stability.rockSolidCount, 1)
        XCTAssertEqual(stability.rockSolidRate, 50)
        XCTAssertEqual(stability.recentAttempts.count, 2)
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

    func testLegacyStuntScopeAttemptDoesNotChangeHitRate() throws {
        let fixture = try makeFixture(outcomes: [.hit, .majorFall])
        let legacy = fixture.session.sortedAttempts.first { $0.outcome == .majorFall }!
        legacy.sourceRaw = "stuntscope"
        legacy.onBasePercent = 50
        try fixture.container.mainContext.save()

        let stats = StatsEngine.compute(sessions: [fixture.session], groups: [fixture.group], timeframe: .all)
        XCTAssertEqual(stats.total, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.rate, 100)
        XCTAssertNil(stats.stability)
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

    // MARK: Appended outcomes (balk / out of range / coach-made extras)

    /// The reported bug: a coach added a 0%-credit "Missed skill" outcome,
    /// logged 14 of them and zero major falls, and the all-groups summary said
    /// "Major fall 14". The reps must keep crediting as misses (rate) while
    /// being NAMED as what they are (legend, falls, top miss).
    func testAppendedZeroCreditOutcomeIsNotReportedAsMajorFalls() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Stretch to arabesque", number: 1, orderIndex: 0)
        group.setOutcomeDefs([
            .init("Hit", .green, .hit), .init("Bobble", .yellow, .decent),
            .init("Building fall", .orange, .rough), .init("Major fall", .red, .miss),
            .init("Missed skill", .gray, .miss)
        ])
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(group)
        context.insert(session)
        let slots = Array(repeating: 0, count: 6) + Array(repeating: 4, count: 14)
        for (index, slot) in slots.enumerated() {
            context.insert(Attempt(slot: slot, group: group, session: session,
                                   timestamp: Date(timeIntervalSince1970: 1_000 + Double(index))))
        }
        try context.save()

        let stats = StatsEngine.compute(sessions: [session], groups: [group], timeframe: .all)

        XCTAssertEqual(stats.total, 20)
        XCTAssertEqual(stats.overall, [6, 0, 0, 14], "tier counts still carry the misses — the rate depends on it")
        XCTAssertEqual(stats.rate, 30, "6 hits of 20 at full credit, 14 at zero")
        XCTAssertEqual(stats.coreCounts, [6, 0, 0, 0], "no major fall was logged, so none is shown")
        XCTAssertEqual(stats.extras.map(\.def.label), ["Missed skill"])
        XCTAssertEqual(stats.extras.map(\.count), [14])
        XCTAssertEqual(stats.falls, 0)
        XCTAssertEqual(stats.groups.first?.falls, 0)
        XCTAssertEqual(stats.topMissRow?.label, "Missed skill")
        XCTAssertEqual(stats.topMissRow?.count, 14)
        XCTAssertEqual(stats.coreCounts.reduce(0, +) + stats.extras.reduce(0) { $0 + $1.count }, stats.total)
    }

    /// The stunt preset's two appended deductions credit like the fall they
    /// default to, without being counted AS falls.
    func testStuntPresetBalkAndOutOfRangeCreditLikeFallsButAreNotFalls() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Rewinds", number: 1, orderIndex: 0)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(group)
        context.insert(session)

        let defs = group.outcomeDefs
        XCTAssertEqual(defs.map(\.label),
                       ["Hit", "Bobble", "Building fall", "Major fall", "Balk / Missed", "Out of range"])
        XCTAssertEqual(defs.map(\.credit), [100, 67, 33, 0, 33, 0],
                       "slots 0-3 must stay put — every existing rep indexes them")

        // 2 hits, 1 major fall, 1 balk (33), 3 out of range (0).
        for (index, slot) in [0, 0, 3, 4, 5, 5, 5].enumerated() {
            context.insert(Attempt(slot: slot, group: group, session: session,
                                   timestamp: Date(timeIntervalSince1970: 1_000 + Double(index))))
        }
        try context.save()

        let stats = StatsEngine.compute(sessions: [session], groups: [group], timeframe: .all)

        XCTAssertEqual(stats.overall, [2, 0, 1, 4])
        XCTAssertEqual(stats.rate, 33, "(200 + 33) / 7")
        XCTAssertEqual(stats.coreCounts, [2, 0, 0, 1])
        XCTAssertEqual(stats.extras.map(\.def.label), ["Balk / Missed", "Out of range"])
        XCTAssertEqual(stats.extras.map(\.count), [1, 3])
        XCTAssertEqual(stats.falls, 1, "only the major fall is a fall")
        XCTAssertEqual(stats.topMissRow?.label, "Out of range")

        let attempts = session.sortedAttempts
        XCTAssertEqual(attempts.map(\.isFallRep), [false, false, true, false, false, false, false])
        XCTAssertEqual(attempts.map(\.isExtraOutcomeRep), [false, false, false, true, true, true, true])
        XCTAssertFalse(attempts[3].isLandingRep, "a balk breaks a streak like any sub-50% rep")
    }

    /// A store with no appended outcomes reads exactly as it did before.
    func testFourSlotStoreHasNoExtrasAndUnchangedCoreCounts() throws {
        let fixture = try makeFixture(outcomes: [.hit, .bobble, .buildingFall, .majorFall, .majorFall])

        let stats = StatsEngine.compute(sessions: [fixture.session], groups: [fixture.group], timeframe: .all)

        XCTAssertTrue(stats.extras.isEmpty)
        XCTAssertEqual(stats.coreCounts, stats.overall)
        XCTAssertEqual(stats.falls, 3)
        XCTAssertEqual(stats.topMissRow?.label, "Major fall")
        XCTAssertEqual(stats.topMissRow?.count, 2)
    }

    /// Same-named extras on two skills roll up into one floor row.
    func testSameNamedExtrasMergeAcrossSkills() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = StuntGroup(name: "A", number: 1, orderIndex: 0)
        let b = StuntGroup(name: "B", number: 2, orderIndex: 1)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(a); context.insert(b); context.insert(session)
        var t = 1_000.0
        for (group, slot) in [(a, 5), (a, 5), (b, 5), (b, 0)] {
            context.insert(Attempt(slot: slot, group: group, session: session,
                                   timestamp: Date(timeIntervalSince1970: t)))
            t += 1
        }
        try context.save()

        let stats = StatsEngine.compute(sessions: [session], groups: [a, b], timeframe: .all)

        XCTAssertEqual(stats.extras.count, 1)
        XCTAssertEqual(stats.extras.first?.def.label, "Out of range")
        XCTAssertEqual(stats.extras.first?.count, 3)
        XCTAssertEqual(stats.coreCounts, [1, 0, 0, 0])
    }

    /// `Attempt.outcome` only knows four slots and falls back to .hit, so the
    /// CSV used to export every appended outcome as "Hit".
    func testCSVExportsAppendedOutcomeByItsOwnName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Rewinds", number: 1, orderIndex: 0)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        context.insert(group)
        context.insert(session)
        for (index, slot) in [0, 3, 4, 5].enumerated() {
            context.insert(Attempt(slot: slot, group: group, session: session,
                                   timestamp: Date(timeIntervalSince1970: 1_000 + Double(index))))
        }
        try context.save()

        let csv = CSVExportItem(sessions: [session])

        XCTAssertEqual(csv.rows.map(\.outcome), ["Hit", "Major fall", "Balk / Missed", "Out of range"])
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
