import SwiftData
import XCTest
@testable import HitRate

/// The fresh-join ordering rule for coach-set homework.
///
/// Assignments and groups arrive on SIBLING Firestore listeners with no delivery
/// order, and Firestore hands a document to a listener as `.added` exactly once.
/// These tests drive `AssignmentLinking` — the same code `SyncEngine.applyAssignment`
/// and `applyGroup` call — in BOTH orders, because the failure only appears in one
/// of them and a manual relaunch test can never catch it (by the second launch the
/// skill is already local, so the broken path looks fine).
@MainActor
final class AssignmentLinkingTests: XCTestCase {

    /// The dangerous order: homework lands before the skill it names.
    func testHomeworkArrivingBeforeItsSkillIsKeptAndAdoptedWhenTheSkillLands() throws {
        let f = try makeFixture()
        let skillID = UUID()

        // 1. The assignments listener fires first. Nothing names this skill yet.
        let applied = AssignmentLinking.apply(incoming(groupID: skillID.uuidString),
                                              team: f.team, in: f.context)
        try f.context.save()

        XCTAssertTrue(applied.changed)
        XCTAssertNil(applied.assignment.group, "Skill isn't in the store yet")
        XCTAssertFalse(applied.assignment.isLive, "An unlinked row must not render")
        XCTAssertTrue(HomeworkEngine.statuses(assignments: [applied.assignment],
                                              roster: [f.maya]).isEmpty)

        // 2. The groups listener fires. The waiting homework is adopted.
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0, id: skillID)
        skill.team = f.team
        f.context.insert(skill)
        let linked = AssignmentLinking.linkPending(to: skill, in: f.context)
        try f.context.save()

        XCTAssertTrue(linked)
        XCTAssertEqual(applied.assignment.group?.id, skillID)
        XCTAssertTrue(applied.assignment.isLive)
        let status = try XCTUnwrap(HomeworkEngine.statuses(assignments: [applied.assignment],
                                                           roster: [f.maya]).first)
        XCTAssertEqual(status.skillName, "Back tuck")
        XCTAssertEqual(status.target, 50)
    }

    /// The benign order, which must keep working unchanged.
    func testHomeworkArrivingAfterItsSkillLinksImmediately() throws {
        let f = try makeFixture()
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        skill.team = f.team
        f.context.insert(skill)
        XCTAssertFalse(AssignmentLinking.linkPending(to: skill, in: f.context),
                       "Nothing is waiting on this skill yet")

        let applied = AssignmentLinking.apply(incoming(groupID: skill.id.uuidString),
                                              team: f.team, in: f.context)
        try f.context.save()

        XCTAssertEqual(applied.assignment.group?.id, skill.id)
        XCTAssertTrue(applied.assignment.isLive)
    }

    /// A skill landing must not sweep up homework that named a DIFFERENT one.
    func testAdoptionOnlyClaimsHomeworkThatNamedThisSkill() throws {
        let f = try makeFixture()
        let wantedID = UUID()
        let applied = AssignmentLinking.apply(incoming(groupID: wantedID.uuidString),
                                              team: f.team, in: f.context)
        try f.context.save()

        let unrelated = StuntGroup(name: "Back handspring", number: 2, orderIndex: 1)
        unrelated.team = f.team
        f.context.insert(unrelated)
        let linked = AssignmentLinking.linkPending(to: unrelated, in: f.context)

        XCTAssertFalse(linked)
        XCTAssertNil(applied.assignment.group)
    }

    /// Backstop for the case where the skill's one `.added` delivery already
    /// happened: nothing will call `linkPending` again this session, so the
    /// launch sweep has to heal it.
    func testLaunchSweepAdoptsHomeworkWhoseSkillIsAlreadyInTheStore() throws {
        let f = try makeFixture()
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        skill.team = f.team
        f.context.insert(skill)
        try f.context.save()

        // Homework stored unlinked (its own listener delivered after the group's).
        let assignment = Assignment(group: nil, targetReps: 50)
        assignment.groupIDRaw = skill.id.uuidString
        assignment.team = f.team
        f.context.insert(assignment)
        try f.context.save()
        XCTAssertFalse(assignment.isLive)

        let healed = AssignmentLinking.linkOrphans(in: f.context)

        XCTAssertEqual(healed, 1)
        XCTAssertEqual(assignment.group?.id, skill.id)
        XCTAssertTrue(assignment.isLive)
    }

    /// A row still waiting on a skill nobody has (deleted upstream) stays put —
    /// invisible, not deleted, and not a crash.
    func testLaunchSweepLeavesHomeworkWhoseSkillIsMissing() throws {
        let f = try makeFixture()
        let assignment = Assignment(group: nil, targetReps: 50)
        assignment.groupIDRaw = UUID().uuidString
        assignment.team = f.team
        f.context.insert(assignment)
        try f.context.save()

        XCTAssertEqual(AssignmentLinking.linkOrphans(in: f.context), 0)
        XCTAssertNil(assignment.group)
        XCTAssertFalse(assignment.isLive)
    }

    /// Listeners re-deliver every doc as `.added` on each fresh listener, so the
    /// import has to be idempotent rather than duplicating the homework.
    func testRedeliveringTheSameDocumentUpdatesInsteadOfDuplicating() throws {
        let f = try makeFixture()
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        skill.team = f.team
        f.context.insert(skill)
        let docID = UUID()

        let first = AssignmentLinking.apply(incoming(id: docID, groupID: skill.id.uuidString),
                                            team: f.team, in: f.context)
        try f.context.save()
        // Same doc again, with the coach's edited target.
        let second = AssignmentLinking.apply(
            incoming(id: docID, groupID: skill.id.uuidString, targetReps: 100),
            team: f.team, in: f.context)
        try f.context.save()

        let all = try f.context.fetch(FetchDescriptor<Assignment>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(first.assignment.persistentModelID, second.assignment.persistentModelID)
        XCTAssertEqual(second.assignment.targetReps, 100)
    }

    /// An unchanged re-delivery must report `changed == false` — SyncEngine only
    /// saves on a change, and a false positive means a save on every snapshot.
    func testUnchangedRedeliveryReportsNoChange() throws {
        let f = try makeFixture()
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        skill.team = f.team
        f.context.insert(skill)
        let doc = incoming(groupID: skill.id.uuidString)

        _ = AssignmentLinking.apply(doc, team: f.team, in: f.context)
        try f.context.save()
        let again = AssignmentLinking.apply(doc, team: f.team, in: f.context)

        XCTAssertFalse(again.changed)
    }

    /// The coach archiving or trashing homework has to propagate to the athlete.
    func testArchiveAndDeleteTombstonesPropagate() throws {
        let f = try makeFixture()
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        skill.team = f.team
        f.context.insert(skill)
        let docID = UUID()
        _ = AssignmentLinking.apply(incoming(id: docID, groupID: skill.id.uuidString),
                                    team: f.team, in: f.context)

        let archived = AssignmentLinking.apply(
            incoming(id: docID, groupID: skill.id.uuidString, archivedAt: .now),
            team: f.team, in: f.context)
        try f.context.save()

        XCTAssertTrue(archived.changed)
        XCTAssertFalse(archived.assignment.isLive)
        XCTAssertTrue(HomeworkEngine.statuses(assignments: [archived.assignment],
                                              roster: [f.maya]).isEmpty)
    }

    // MARK: - Fixture

    private func incoming(id: UUID = UUID(), groupID: String, targetReps: Int = 50,
                          archivedAt: Date? = nil) -> AssignmentLinking.Incoming {
        AssignmentLinking.Incoming(
            id: id, groupID: groupID, targetReps: targetReps,
            note: "chest up out of the set", subjectIDsRaw: "",
            startedAt: Date(timeIntervalSince1970: 1_000),
            archivedAt: archivedAt, deletedAt: nil, createdBy: "coach-uid"
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let team: Team
        let maya: Subject
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([
            Team.self, StuntGroup.self, PracticeSession.self, Attempt.self,
            PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self,
            CustomTally.self, Subject.self, OutcomeTemplate.self, Assignment.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let team = Team(name: "Senior Coed", orderIndex: 0)
        let maya = Subject(name: "Maya", orderIndex: 0)
        maya.team = team
        context.insert(team)
        context.insert(maya)
        try context.save()
        return Fixture(container: container, context: context, team: team, maya: maya)
    }
}
