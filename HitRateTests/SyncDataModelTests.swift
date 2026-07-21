import XCTest
import SwiftData
@testable import HitRate

@MainActor
final class SyncDataModelTests: XCTestCase {
    func testImportedAttemptAttachedToSessionContributesToDashboardStats() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let team = Team(name: "Shared", orderIndex: 0)
        let group = StuntGroup(name: "Full up", number: 1, orderIndex: 0)
        group.team = team
        let session = PracticeSession(startedAt: .now.addingTimeInterval(-60))
        session.cloudID = "remote-session"
        session.cloudTeamID = team.id.uuidString
        session.loggerID = "member-b"
        session.syncStateRaw = CloudSyncState.synced.rawValue
        session.endedAt = .now
        let attempt = Attempt(outcome: .hit, group: group, session: session)
        attempt.cloudID = "remote-attempt"
        attempt.cloudTeamID = team.id.uuidString
        attempt.loggerID = "member-b"
        attempt.syncState = .synced

        context.insert(team)
        context.insert(group)
        context.insert(session)
        context.insert(attempt)
        try context.save()

        let stats = StatsEngine.compute(
            sessions: [session],
            groups: [group],
            timeframe: .all
        )

        XCTAssertEqual(stats.total, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.rate, 100)
    }

    func testNewAttemptsReceiveStableUniqueCloudIDs() {
        let first = Attempt(outcome: .hit, group: nil, session: nil)
        let second = Attempt(outcome: .hit, group: nil, session: nil)

        XCTAssertFalse(first.cloudID.isEmpty)
        XCTAssertNotEqual(first.cloudID, second.cloudID)
        XCTAssertEqual(first.syncState, .pending)
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
