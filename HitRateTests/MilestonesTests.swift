import SwiftData
import XCTest
@testable import HitRate

@MainActor
final class MilestonesTests: XCTestCase {
    func testFiveHundredLifetimeRepsUnlocksVolumeMilestone() throws {
        let fixture = try makeFixture(outcomes: Array(repeating: .hit, count: 500))

        let halfAGrand = try XCTUnwrap(milestone("reps500-stunt", in: fixture))

        XCTAssertTrue(halfAGrand.earned)
        XCTAssertEqual(halfAGrand.progress, 1)
        XCTAssertEqual(halfAGrand.currentCount, 500)
    }

    func testVolumeMilestoneRemainsLockedBelowFiveHundredReps() throws {
        let fixture = try makeFixture(outcomes: Array(repeating: .hit, count: 499))

        let halfAGrand = try XCTUnwrap(milestone("reps500-stunt", in: fixture))

        XCTAssertFalse(halfAGrand.earned)
        XCTAssertEqual(halfAGrand.currentCount, 499)
        XCTAssertEqual(halfAGrand.progress, 0.998, accuracy: 0.000_001)
    }

    func testTenCleanHitsUnlocksHitStreakMilestone() throws {
        let fixture = try makeFixture(outcomes: Array(repeating: .hit, count: 10))

        let hotHand = try XCTUnwrap(milestone("streak10-stunt", in: fixture))

        XCTAssertTrue(hotHand.earned)
        XCTAssertEqual(hotHand.currentCount, 10)
    }

    func testFiveConsecutiveMajorFallsUnlocksDubiousColdStreak() throws {
        let fixture = try makeFixture(outcomes: Array(repeating: .majorFall, count: 5))

        let coldStreak = try XCTUnwrap(milestone("coldstreak-stunt", in: fixture))

        XCTAssertTrue(coldStreak.earned)
        XCTAssertEqual(coldStreak.currentCount, 5)
        XCTAssertEqual(coldStreak.progress, 1)
    }

    private func milestone(
        _ id: String,
        in fixture: (container: ModelContainer, group: StuntGroup, session: PracticeSession)
    ) -> Milestone? {
        Milestones.evaluate(
            sessions: [fixture.session],
            groups: [fixture.group],
            mode: .coach
        ).first { $0.id == id }
    }

    private func makeFixture(
        outcomes: [Outcome]
    ) throws -> (container: ModelContainer, group: StuntGroup, session: PracticeSession) {
        let container = try makeContainer()
        let context = container.mainContext
        let group = StuntGroup(name: "Full up", number: 1, orderIndex: 0)
        let session = PracticeSession(startedAt: Date(timeIntervalSince1970: 1_000))
        session.endedAt = Date(timeIntervalSince1970: 2_000)

        context.insert(group)
        context.insert(session)
        for (index, outcome) in outcomes.enumerated() {
            context.insert(Attempt(
                outcome: outcome,
                group: group,
                session: session,
                timestamp: Date(timeIntervalSince1970: 1_000 + Double(index))
            ))
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
