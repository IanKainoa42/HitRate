import Foundation
import SwiftData

/// How a cloud homework document lands in the local store — split out of
/// `SyncEngine` so the ORDERING RULE below is testable without Firestore.
///
/// THE RULE: an assignment names its skill by id, and that skill may not exist
/// locally yet. Assignments and groups are SIBLING Firestore listeners with no
/// delivery order between them, and Firestore hands a document to a listener as
/// `.added` exactly ONCE per listener lifetime. So on a fresh join — the very
/// case coach-set homework exists for — the assignment can arrive first, and
/// dropping it for having no resolvable group would lose that homework for good
/// on that install.
///
/// Instead an unresolved assignment is stored UNLINKED (`groupIDRaw` set,
/// `group` nil). `Assignment.isLive` already hides those, so it stays invisible
/// rather than rendering as a ghost row, and it is adopted the moment its skill
/// appears — via `linkPending(to:)` when the group lands, or `linkOrphans(in:)`
/// on the next launch if that delivery never came.
///
/// This is deliberately hard to verify by hand: a device test that force-quits
/// and reopens the app always passes, because by then the group is local.
enum AssignmentLinking {

    /// A homework document's contents, in wire shape but free of any Firebase
    /// type, so the import path can be exercised in tests.
    struct Incoming {
        let id: UUID
        let groupID: String
        let targetReps: Int
        let note: String
        let subjectIDsRaw: String
        let startedAt: Date
        let archivedAt: Date?
        let deletedAt: Date?
        let createdBy: String
    }

    /// Upsert one homework document, linking its skill if that skill is already
    /// in the store. Returns the row and whether anything actually changed
    /// (callers save only on a change, like every other `apply*` in SyncEngine).
    @discardableResult
    static func apply(_ incoming: Incoming, team: Team,
                      in context: ModelContext) -> (assignment: Assignment, changed: Bool) {
        let uuid = incoming.id
        let group = skill(withID: incoming.groupID, in: context)
        let existing = (try? context.fetch(FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.id == uuid })))?.first

        let assignment = existing ?? Assignment(group: group,
                                                targetReps: incoming.targetReps,
                                                id: uuid, startedAt: incoming.startedAt)
        var changed = existing == nil
        if existing == nil {
            assignment.team = team
            context.insert(assignment)
        }
        if assignment.targetReps != incoming.targetReps {
            assignment.targetReps = incoming.targetReps; changed = true
        }
        if assignment.note != incoming.note { assignment.note = incoming.note; changed = true }
        if assignment.subjectIDsRaw != incoming.subjectIDsRaw {
            assignment.subjectIDsRaw = incoming.subjectIDsRaw; changed = true
        }
        if assignment.startedAt != incoming.startedAt {
            assignment.startedAt = incoming.startedAt; changed = true
        }
        if assignment.archivedAt != incoming.archivedAt {
            assignment.archivedAt = incoming.archivedAt; changed = true
        }
        if assignment.deletedAt != incoming.deletedAt {
            assignment.deletedAt = incoming.deletedAt; changed = true
        }
        if assignment.createdByUID != incoming.createdBy {
            assignment.createdByUID = incoming.createdBy; changed = true
        }
        // Always keep the raw id, even when the skill is still missing — it is
        // what lets the row heal later.
        if assignment.groupIDRaw != incoming.groupID {
            assignment.groupIDRaw = incoming.groupID; changed = true
        }
        if let group, assignment.group?.id != group.id {
            assignment.link(group); changed = true
        }
        if assignment.team?.id != team.id { assignment.team = team; changed = true }
        return (assignment, changed)
    }

    /// Adopt every assignment that named this skill before it existed locally.
    /// Called as each group lands. Returns true when anything was linked.
    @discardableResult
    static func linkPending(to group: StuntGroup, in context: ModelContext) -> Bool {
        let raw = group.id.uuidString
        let waiting = (try? context.fetch(FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.groupIDRaw == raw }))) ?? []
        var linked = false
        for assignment in waiting where assignment.group == nil {
            assignment.link(group)
            linked = true
        }
        return linked
    }

    /// Launch sweep: adopt any assignment still waiting on a skill that IS in
    /// the store. Backstop for the case where the group's `.added` delivery
    /// happened before the assignment landed and never repeated — without it,
    /// healing would depend on Firestore re-delivering, which it only does for a
    /// fresh listener. Returns how many rows healed.
    @discardableResult
    static func linkOrphans(in context: ModelContext) -> Int {
        let orphans = (try? context.fetch(FetchDescriptor<Assignment>(
            predicate: #Predicate { $0.group == nil && $0.groupIDRaw != "" }))) ?? []
        guard !orphans.isEmpty else { return 0 }
        var healed = 0
        for assignment in orphans {
            guard let group = skill(withID: assignment.groupIDRaw, in: context) else { continue }
            assignment.link(group)
            healed += 1
        }
        if healed > 0 { try? context.save() }
        return healed
    }

    private static func skill(withID raw: String, in context: ModelContext) -> StuntGroup? {
        guard let uuid = UUID(uuidString: raw) else { return nil }
        return (try? context.fetch(FetchDescriptor<StuntGroup>(
            predicate: #Predicate { $0.id == uuid })))?.first
    }
}
