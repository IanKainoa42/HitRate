import SwiftData
import XCTest
@testable import HitRate

@MainActor
final class HomeworkEngineTests: XCTestCase {

    /// Volume is the target: a fall is still a rep the athlete threw.
    func testEveryOutcomeCountsTowardTheRepTarget() throws {
        let f = try makeFixture()
        log(f, subject: f.maya, outcomes: [.hit, .majorFall, .bobble, .buildingFall])

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.reps, 4)
        XCTAssertEqual(row.hits, 1)
        XCTAssertEqual(row.rate, 25)
    }

    func testTargetIsMetAtTheAssignedRepCount() throws {
        let f = try makeFixture(target: 10)
        log(f, subject: f.maya, outcomes: Array(repeating: .hit, count: 10))

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertTrue(row.isComplete)
        XCTAssertEqual(row.remaining, 0)
        XCTAssertEqual(row.fraction, 1)
    }

    func testOvershootingTheTargetDoesNotOverfillTheBar() throws {
        let f = try makeFixture(target: 10)
        log(f, subject: f.maya, outcomes: Array(repeating: .hit, count: 25))

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.reps, 25)
        XCTAssertEqual(row.fraction, 1)
    }

    /// The receipt that carries the whole verification story.
    func testDayCountsRecordWhenTheWorkActuallyHappened() throws {
        let f = try makeFixture(target: 6)
        let cal = Calendar.current
        let weekStart = try XCTUnwrap(cal.dateInterval(of: .weekOfYear, for: .now)).start
        // Two reps on the week's first day, one on its third — never both on one.
        log(f, subject: f.maya, outcomes: [.hit, .hit],
            at: weekStart.addingTimeInterval(3600))
        log(f, subject: f.maya, outcomes: [.hit],
            at: cal.date(byAdding: .day, value: 2, to: weekStart)!.addingTimeInterval(3600))

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.dayCounts[0], 2)
        XCTAssertEqual(row.dayCounts[2], 1)
        XCTAssertEqual(row.daysPracticed, 2)
        XCTAssertFalse(row.isSingleDayDump)
    }

    /// The night-before dump — target met, but every rep in one sitting.
    func testMeetingTheTargetInOneSittingIsFlagged() throws {
        let f = try makeFixture(target: 3)
        let cal = Calendar.current
        let weekStart = try XCTUnwrap(cal.dateInterval(of: .weekOfYear, for: .now)).start
        log(f, subject: f.maya, outcomes: [.hit, .hit, .hit],
            at: weekStart.addingTimeInterval(3600))

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertTrue(row.isComplete)
        XCTAssertTrue(row.isSingleDayDump)
    }

    func testRepsFromLastWeekDoNotCountTowardThisWeek() throws {
        let f = try makeFixture(target: 5)
        let lastWeek = Date.now.addingTimeInterval(-8 * 24 * 3600)
        log(f, subject: f.maya, outcomes: Array(repeating: .hit, count: 5), at: lastWeek)

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.reps, 0)
        XCTAssertFalse(row.isComplete)
    }

    /// One athlete's homework can never be advanced by somebody else's reps.
    func testAnotherAthletesRepsStayOnTheirOwnRow() throws {
        let f = try makeFixture(target: 5)
        log(f, subject: f.lucy, outcomes: Array(repeating: .hit, count: 5))

        let s = try XCTUnwrap(status(f))
        let maya = try XCTUnwrap(s.rows.first { $0.subjectID == f.maya.id })
        let lucy = try XCTUnwrap(s.rows.first { $0.subjectID == f.lucy.id })

        XCTAssertEqual(maya.reps, 0)
        XCTAssertEqual(lucy.reps, 5)
        XCTAssertEqual(s.completedCount, 1)
        XCTAssertEqual(s.assignedCount, 2)
    }

    /// Reps on a DIFFERENT skill are somebody's work, but not this homework.
    func testRepsOnAnotherSkillDoNotCount() throws {
        let f = try makeFixture(target: 5)
        let other = StuntGroup(name: "Back handspring", number: 2, orderIndex: 1)
        other.team = f.team
        f.context.insert(other)
        for _ in 0..<5 {
            f.context.insert(Attempt(outcome: .hit, group: other, session: f.session,
                                     subject: f.maya))
        }
        try f.context.save()

        let row = try XCTUnwrap(status(f)?.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.reps, 0)
    }

    /// The failure mode that reads as "I did the work and nothing moved".
    func testUntaggedRepsAreReportedRatherThanSilentlyDropped() throws {
        let f = try makeFixture(target: 5)
        log(f, subject: nil, outcomes: Array(repeating: .hit, count: 4))

        let s = try XCTUnwrap(status(f))

        XCTAssertEqual(s.unattributedReps, 4)
        XCTAssertEqual(s.teamReps, 0)
        XCTAssertFalse(s.isUntouched)
    }

    /// Empty id list = the whole roster, so an athlete added later inherits
    /// standing homework instead of quietly escaping it.
    func testEmptyAssigneeListCoversTheWholeRoster() throws {
        let f = try makeFixture(target: 5)
        let newcomer = Subject(name: "Priya", orderIndex: 2)
        newcomer.team = f.team
        f.context.insert(newcomer)
        try f.context.save()

        let s = try XCTUnwrap(HomeworkEngine.statuses(
            assignments: [f.assignment], roster: [f.maya, f.lucy, newcomer]).first)

        XCTAssertEqual(s.assignedCount, 3)
    }

    func testNamedAssigneesExcludeEveryoneElse() throws {
        let f = try makeFixture(target: 5)
        f.assignment.subjectIDs = [f.maya.id]
        try f.context.save()

        let s = try XCTUnwrap(status(f))

        XCTAssertEqual(s.assignedCount, 1)
        XCTAssertEqual(s.rows.first?.subjectID, f.maya.id)
    }

    /// A trashed athlete's id lingers in the raw string; it must not render.
    func testTrashedAthleteDropsOffTheAssignment() throws {
        let f = try makeFixture(target: 5)
        f.assignment.subjectIDs = [f.maya.id, f.lucy.id]
        f.lucy.deletedAt = .now
        try f.context.save()

        let s = try XCTUnwrap(HomeworkEngine.statuses(
            assignments: [f.assignment], roster: [f.maya, f.lucy].active).first)

        XCTAssertEqual(s.assignedCount, 1)
        XCTAssertEqual(s.rows.first?.subjectID, f.maya.id)
    }

    func testArchivedHomeworkLeavesTheCard() throws {
        let f = try makeFixture(target: 5)
        f.assignment.archivedAt = .now
        try f.context.save()

        XCTAssertTrue(HomeworkEngine.statuses(assignments: [f.assignment],
                                              roster: [f.maya, f.lucy]).isEmpty)
    }

    /// Attribution: a coach logging a private lesson is not the athlete grinding
    /// at open gym, and the split is what makes the honor system checkable.
    func testCoachLoggedRepsAreSplitOutFromSelfLoggedOnes() throws {
        let f = try makeFixture(target: 5)
        log(f, subject: f.maya, outcomes: [.hit, .hit], loggerID: "coach-uid")
        log(f, subject: f.maya, outcomes: [.hit], loggerID: "maya-uid")

        let s = try XCTUnwrap(HomeworkEngine.statuses(
            assignments: [f.assignment], roster: [f.maya, f.lucy],
            teamOwnerUID: "coach-uid", currentUID: "maya-uid").first)
        let row = try XCTUnwrap(s.rows.first { $0.subjectID == f.maya.id })

        XCTAssertEqual(row.coachLoggedReps, 2)
        XCTAssertEqual(row.selfLoggedReps, 1)
    }

    /// History never reaches back before the homework existed — weeks that
    /// predate the assignment aren't misses.
    func testHistoryStopsAtTheWeekTheHomeworkWasSet() throws {
        let f = try makeFixture(target: 5)
        f.assignment.startedAt = .now
        try f.context.save()

        let weeks = HomeworkEngine.history(for: f.assignment, subject: f.maya,
                                           roster: [f.maya, f.lucy], weeks: 6)

        XCTAssertEqual(weeks.count, 1)
    }

    /// A fresh join can deliver the homework doc BEFORE its skill (sibling
    /// listeners, no delivery order, `.added` fires once). The assignment must
    /// survive unlinked and heal when the skill lands — never render a ghost,
    /// never disappear for good.
    func testHomeworkThatArrivesBeforeItsSkillHealsInsteadOfVanishing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let team = Team(name: "Senior Coed", orderIndex: 0)
        let maya = Subject(name: "Maya", orderIndex: 0)
        maya.team = team
        // Homework lands first: it knows its skill's id but not the skill.
        let skillID = UUID()
        let assignment = Assignment(group: nil, targetReps: 50)
        assignment.groupIDRaw = skillID.uuidString
        assignment.team = team
        context.insert(team)
        context.insert(maya)
        context.insert(assignment)
        try context.save()

        XCTAssertFalse(assignment.isLive, "Unlinked homework must not render")
        XCTAssertTrue(HomeworkEngine.statuses(assignments: [assignment], roster: [maya]).isEmpty)

        // The skill arrives on a later snapshot and adopts it.
        let skill = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0, id: skillID)
        skill.team = team
        context.insert(skill)
        assignment.link(skill)
        try context.save()

        XCTAssertTrue(assignment.isLive)
        let s = try XCTUnwrap(HomeworkEngine.statuses(assignments: [assignment],
                                                      roster: [maya]).first)
        XCTAssertEqual(s.skillName, "Back tuck")
        XCTAssertEqual(s.target, 50)
    }

    func testLinkingASkillKeepsTheStoredIDInStep() throws {
        let f = try makeFixture()
        let other = StuntGroup(name: "Back handspring", number: 2, orderIndex: 1)
        f.context.insert(other)

        f.assignment.link(other)

        XCTAssertEqual(f.assignment.groupIDRaw, other.id.uuidString)
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let team: Team
        let group: StuntGroup
        let session: PracticeSession
        let maya: Subject
        let lucy: Subject
        let assignment: Assignment
    }

    private func status(_ f: Fixture) -> HomeworkEngine.Status? {
        HomeworkEngine.statuses(assignments: [f.assignment], roster: [f.maya, f.lucy]).first
    }

    private func log(_ f: Fixture, subject: Subject?, outcomes: [Outcome],
                     at timestamp: Date = .now, loggerID: String = "") {
        for (i, outcome) in outcomes.enumerated() {
            let attempt = Attempt(outcome: outcome, group: f.group, session: f.session,
                                  subject: subject,
                                  timestamp: timestamp.addingTimeInterval(Double(i)))
            attempt.loggerID = loggerID
            f.context.insert(attempt)
        }
        try? f.context.save()
    }

    private func makeFixture(target: Int = 50) throws -> Fixture {
        let container = try makeContainer()
        let context = container.mainContext
        let team = Team(name: "Senior Coed", orderIndex: 0)
        let group = StuntGroup(name: "Back tuck", number: 1, orderIndex: 0)
        group.team = team
        let maya = Subject(name: "Maya", orderIndex: 0)
        let lucy = Subject(name: "Lucy", orderIndex: 1)
        maya.team = team
        lucy.team = team
        let session = PracticeSession(startedAt: .now)
        let assignment = Assignment(group: group, targetReps: target)
        assignment.team = team

        for model in [team as any PersistentModel, group, maya, lucy, session, assignment] {
            context.insert(model)
        }
        try context.save()
        return Fixture(container: container, context: context, team: team, group: group,
                       session: session, maya: maya, lucy: lucy, assignment: assignment)
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
