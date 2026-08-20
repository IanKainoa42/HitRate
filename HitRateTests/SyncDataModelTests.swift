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

    func testCurrentTeamNeverSubstitutesADifferentFolder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let maya = Team(name: "Maya", orderIndex: 0)
        let lucy = Team(name: "Lucy", orderIndex: 1)
        context.insert(maya)
        context.insert(lucy)
        try context.save()

        let teams = [maya, lucy]

        // A valid id resolves to the matching team, not just "the first one".
        XCTAssertEqual(teams.current(id: lucy.id.uuidString)?.name, "Lucy")

        // Regression for "tap Maya's folder, see Lucy's data": a stale/
        // dangling id (e.g. dedupeSyncIDs reassigned the selected team's id
        // and currentTeamID still names the old one) must return nil, never
        // silently substitute a different folder's full data.
        XCTAssertNil(teams.current(id: UUID().uuidString))

        // Empty id (nothing ever selected — fresh install) is the one
        // legitimate case that defaults to the first active team.
        XCTAssertEqual(teams.current(id: "")?.name, "Maya")
    }

    func testNewAttemptsReceiveStableUniqueCloudIDs() {
        let first = Attempt(outcome: .hit, group: nil, session: nil)
        let second = Attempt(outcome: .hit, group: nil, session: nil)

        XCTAssertFalse(first.cloudID.isEmpty)
        XCTAssertNotEqual(first.cloudID, second.cloudID)
        XCTAssertEqual(first.syncState, .pending)
    }

    /// The precondition behind the applyAttempts crash: deleting a folder takes
    /// its whole rep history with it, so any identifier the import cache had
    /// recorded for those reps is left naming a row that no longer exists.
    func testDeletingATeamCascadesItsAttemptsAway() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let team = Team(name: "Doomed", orderIndex: 0)
        let group = StuntGroup(name: "Full up", number: 1, orderIndex: 0)
        group.team = team
        let session = PracticeSession(startedAt: .now)
        let attempt = Attempt(outcome: .hit, group: group, session: session)
        context.insert(team)
        context.insert(group)
        context.insert(session)
        context.insert(attempt)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Attempt>()).count, 1)

        context.delete(team)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<StuntGroup>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Attempt>()).isEmpty,
                      "Reps must not outlive their folder — the cache that named them is now stale")
    }

    /// Deleted-but-not-yet-saved: the registered instance reports itself, which
    /// is the only case `pushLocalChanges`'s `isDeleted` guard can catch. (Once
    /// the delete is SAVED it stops reporting — see the test below, which is
    /// why the queue has to be pruned at the notification instead.)
    func testARepDeletedButNotYetSavedReportsItselfDeleted() throws {
        let (container, attempt) = try loggedRep()
        let context = container.mainContext
        let id = attempt.persistentModelID
        context.delete(attempt)

        XCTAssertTrue(context.model(for: id).isDeleted)
    }

    /// Why the push queue must be pruned at the save notification rather than
    /// guarded at the flush: once a delete is SAVED, the identifier still
    /// resolves to a live-looking instance that no longer admits it is deleted.
    /// Reading a relationship off that instance is what killed the app on
    /// device (2026-08-19, EXC_BREAKPOINT in `SyncEngine.pushLocalChanges` →
    /// `Attempt.group.getter`). If this ever starts reporting `isDeleted`, the
    /// flush guard would cover it — until then `PendingPushQueue.prune` is the
    /// only thing standing between undo and a crash.
    func testASavedDeleteNoLongerAdmitsItIsDeleted() throws {
        let (container, attempt) = try loggedRep()
        let context = container.mainContext
        let id = attempt.persistentModelID
        context.delete(attempt)
        try context.save()

        XCTAssertFalse(context.model(for: id).isDeleted,
                       "the flush guard cannot see this — the queue prune is not optional")
    }

    /// One logged rep in a live folder, saved. Hands the CONTAINER back, not
    /// just the context: let it go out of scope and the store is torn down
    /// under the models, which traps rather than failing an assertion.
    private func loggedRep() throws -> (ModelContainer, Attempt) {
        let container = try makeContainer()
        let context = container.mainContext
        let team = Team(name: "Deck", orderIndex: 0)
        let group = StuntGroup(name: "Toe touch", number: 1, orderIndex: 0)
        group.team = team
        let session = PracticeSession()
        let attempt = Attempt(outcome: .hit, group: group, session: session)
        context.insert(team)
        context.insert(group)
        context.insert(session)
        context.insert(attempt)
        try context.save()
        return (container, attempt)
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
