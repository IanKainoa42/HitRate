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
