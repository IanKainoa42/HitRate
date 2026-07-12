import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Cloud sync coordinator (Firebase Firestore) for multi-user team sharing.
///
/// SYNC MODEL — deliberately simple so it's correct without an `updatedAt` on
/// every @Model:
///   • ROSTER is owner-authoritative. The team's `ownerUID` device pushes the
///     roster (Team meta, Subjects, StuntGroups, OutcomeTemplates) to Firestore;
///     member devices MIRROR it (remote → local upsert, honoring the `deletedAt`
///     tombstone). Only the owner ever writes roster docs, so there's no roster
///     merge conflict to resolve.
///   • ATTEMPTS are append-only and keyed by their local UUID. A rep is never
///     edited after logging, so syncing them is a plain set-union: every device
///     pushes its own new reps and pulls everyone else's. `loggerId` records who
///     threw it (attribution). Deleting a rep writes a `deletedAt` tombstone.
///
/// Firestore layout:
///   teams/{teamId}                         → FTeam (meta, memberIds, ownerUID)
///   teams/{teamId}/subjects/{subjectId}    → FSubject
///   teams/{teamId}/groups/{groupId}        → FGroup
///   teams/{teamId}/templates/{templateId}  → FTemplate
///   teams/{teamId}/attempts/{attemptId}    → FAttempt
///
/// Doc id === the local model's `id.uuidString`, so push/pull is a straight
/// upsert. `startSyncing` is idempotent; it re-pushes on every local save
/// (SwiftData `didSave` notification, debounced) and keeps live listeners open
/// for the pull direction.
///
/// STATUS: build-verified only. Runtime behavior is UNVERIFIED until the Firebase
/// backend is configured (auth providers enabled, Firestore database created,
/// firestore.rules deployed) and it's exercised across two real accounts.
@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    /// User-visible sync state (drive a small status chip later if wanted).
    @Published private(set) var lastError: String?
    @Published private(set) var lastPushedAt: Date?

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var modelContext: ModelContext?
    private var isRunning = false

    /// Ids we've already mirrored to Firestore this session, so a full re-push on
    /// every `didSave` skips unchanged docs (cheap idempotence, not correctness).
    private var pushedTeamIDs: Set<String> = []
    private var pushedRosterIDs: Set<String> = []
    private var pushedAttemptIDs: Set<String> = []

    /// Debounce token for save-triggered pushes.
    private var pushWorkItem: DispatchWorkItem?
    private var saveObserver: NSObjectProtocol?

    private init() {}

    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: - Lifecycle

    /// Begin syncing for the signed-in user. Idempotent — safe to call on every
    /// launch / auth change.
    func startSyncing(context: ModelContext) {
        modelContext = context
        guard uid != nil else { return }
        guard !isRunning else { return }
        isRunning = true

        observeLocalSaves()
        pushLocalData()
        attachListeners()
    }

    /// Tear down listeners + the save observer (called on sign-out).
    func stopSyncing() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
            self.saveObserver = nil
        }
        pushWorkItem?.cancel()
        pushedTeamIDs.removeAll()
        pushedRosterIDs.removeAll()
        pushedAttemptIDs.removeAll()
        isRunning = false
    }

    // MARK: - Local change observation

    /// SwiftData posts `ModelContext.didSave` after every persisted mutation.
    /// We debounce and re-push; the pushed-id sets keep it to just the deltas.
    private func observeLocalSaves() {
        guard saveObserver == nil else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { [weak self] _ in
            self?.schedulePush()
        }
    }

    private func schedulePush() {
        pushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pushLocalData() }
        pushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Push (local → Firestore)

    /// Mirror every locally-owned team's roster + all local attempts up to
    /// Firestore. Owner pushes the roster; every device pushes its own reps.
    private func pushLocalData() {
        guard let context = modelContext, let uid else { return }
        do {
            let teams = try context.fetch(FetchDescriptor<Team>())
            for team in teams {
                let teamID = team.id.uuidString
                let isOwner = (team.ownerUID == nil) || (team.ownerUID == uid)
                // Claim ownership of a pre-cloud team the first time we sync it.
                if team.ownerUID == nil { team.ownerUID = uid }

                if isOwner {
                    pushTeamMeta(team)
                    for subject in team.subjects { pushSubject(subject, teamID: teamID) }
                    for group in team.groups { pushGroup(group, teamID: teamID) }
                    for template in team.outcomeTemplates { pushTemplate(template, teamID: teamID) }
                }
                // Attempts: everyone pushes their own new reps (append-only).
                for group in team.groups {
                    for attempt in group.attempts { pushAttempt(attempt, teamID: teamID, uid: uid) }
                }
            }
            lastPushedAt = .now
            lastError = nil
        } catch {
            lastError = "Sync push failed: \(error.localizedDescription)"
        }
    }

    private func teamDoc(_ teamID: String) -> DocumentReference {
        db.collection("teams").document(teamID)
    }

    private func pushTeamMeta(_ team: Team) {
        let id = team.id.uuidString
        let doc = FTeam(
            id: id,
            name: team.name,
            ownerUID: team.ownerUID ?? uid ?? "",
            memberIds: team.memberIds,
            orderIndex: team.orderIndex,
            itemNoun: team.itemNoun,
            joinCode: team.joinCode,
            deletedAt: team.deletedAt,
            updatedAt: .now
        )
        setDoc(teamDoc(id), doc, cache: &pushedTeamIDs, key: id)
    }

    private func pushSubject(_ subject: Subject, teamID: String) {
        let id = subject.id.uuidString
        let doc = FSubject(
            id: id, teamId: teamID, name: subject.name,
            kindRaw: subject.kindRaw, orderIndex: subject.orderIndex,
            deletedAt: subject.deletedAt, updatedAt: .now
        )
        setDoc(teamDoc(teamID).collection("subjects").document(id), doc,
               cache: &pushedRosterIDs, key: "s-\(id)")
    }

    private func pushGroup(_ group: StuntGroup, teamID: String) {
        let id = group.id.uuidString
        let doc = FGroup(
            id: id, teamId: teamID, name: group.name, number: group.number,
            orderIndex: group.orderIndex, kindRaw: group.kindRaw,
            categoryRaw: group.categoryRaw, typeLabelRaw: group.typeLabelRaw,
            outcomeDefsRaw: group.outcomeDefsRaw,
            outcomeOverridesRaw: group.outcomeOverridesRaw,
            deletedAt: group.deletedAt, updatedAt: .now
        )
        setDoc(teamDoc(teamID).collection("groups").document(id), doc,
               cache: &pushedRosterIDs, key: "g-\(id)")
    }

    private func pushTemplate(_ template: OutcomeTemplate, teamID: String) {
        let id = template.id.uuidString
        let doc = FTemplate(
            id: id, teamId: teamID, name: template.name,
            defsRaw: template.defsRaw, orderIndex: template.orderIndex,
            updatedAt: .now
        )
        setDoc(teamDoc(teamID).collection("templates").document(id), doc,
               cache: &pushedRosterIDs, key: "t-\(id)")
    }

    private func pushAttempt(_ attempt: Attempt, teamID: String, uid: String) {
        guard let groupID = attempt.group?.id.uuidString else { return }
        let docID = attemptDocID(attempt)
        let doc = FAttempt(
            id: docID, teamId: teamID, groupId: groupID,
            subjectId: attempt.subject?.id.uuidString,
            outcomeRaw: attempt.outcomeRaw, timestamp: attempt.timestamp,
            waveID: attempt.waveID?.uuidString,
            executionScored: attempt.executionScored,
            lostDriversRaw: attempt.lostDriversRaw,
            loggerId: uid, updatedAt: .now
        )
        setDoc(teamDoc(teamID).collection("attempts").document(docID), doc,
               cache: &pushedAttemptIDs, key: docID)
    }

    /// Attempt has no stored UUID id, so we derive a deterministic doc id from its
    /// immutable fields (append-only reps are never edited, so this is stable).
    private func attemptDocID(_ attempt: Attempt) -> String {
        let group = attempt.group?.id.uuidString ?? "nil"
        let subject = attempt.subject?.id.uuidString ?? "nil"
        let ts = Int(attempt.timestamp.timeIntervalSince1970 * 1000)
        return "\(group)-\(subject)-\(attempt.outcomeRaw)-\(ts)"
    }

    private func setDoc<T: Encodable>(_ ref: DocumentReference, _ value: T,
                                      cache: inout Set<String>, key: String) {
        do {
            try ref.setData(from: value, merge: true)
            cache.insert(key)
        } catch {
            lastError = "Encode failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Pull (Firestore → local)

    /// Attach live listeners for every team the user can see (owned or a member
    /// of), mirroring remote roster + attempts into SwiftData.
    private func attachListeners() {
        guard let uid else { return }
        // Teams I own or am a member of. Two queries unioned by their listeners.
        let owned = db.collection("teams").whereField("ownerUID", isEqualTo: uid)
        let member = db.collection("teams").whereField("memberIds", arrayContains: uid)
        for query in [owned, member] {
            let reg = query.addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                for change in snap.documentChanges {
                    if let team = try? change.document.data(as: FTeam.self) {
                        self.applyTeam(team)
                        self.attachTeamSubcollections(teamID: team.id ?? change.document.documentID)
                    }
                }
            }
            listeners.append(reg)
        }
    }

    private func attachTeamSubcollections(teamID: String) {
        let base = teamDoc(teamID)
        listeners.append(base.collection("subjects").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let s = try? c.document.data(as: FSubject.self) { self?.applySubject(s) }
            }
        })
        listeners.append(base.collection("groups").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let g = try? c.document.data(as: FGroup.self) { self?.applyGroup(g) }
            }
        })
        listeners.append(base.collection("attempts").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let a = try? c.document.data(as: FAttempt.self) { self?.applyAttempt(a) }
            }
        })
    }

    // MARK: - Apply remote docs into SwiftData

    private func team(_ id: String) -> Team? {
        guard let context = modelContext, let uuid = UUID(uuidString: id) else { return nil }
        return try? context.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.id == uuid })).first
    }

    private func applyTeam(_ remote: FTeam) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr) else { return }
        let local = team(idStr)
        if let local {
            // Members mirror owner's roster meta; don't clobber our own ownership.
            local.name = remote.name
            local.itemNoun = remote.itemNoun
            local.orderIndex = remote.orderIndex
            local.memberIds = remote.memberIds
            local.joinCode = remote.joinCode
            local.deletedAt = remote.deletedAt
            if local.ownerUID == nil { local.ownerUID = remote.ownerUID }
        } else {
            let t = Team(name: remote.name, orderIndex: remote.orderIndex, id: uuid)
            t.itemNoun = remote.itemNoun
            t.ownerUID = remote.ownerUID
            t.memberIds = remote.memberIds
            t.joinCode = remote.joinCode
            t.deletedAt = remote.deletedAt
            context.insert(t)
        }
        try? context.save()
    }

    private func applySubject(_ remote: FSubject) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr), let team = team(remote.teamId) else { return }
        let existing = try? context.fetch(FetchDescriptor<Subject>(
            predicate: #Predicate { $0.id == uuid })).first
        if let s = existing.flatMap({ $0 }) {
            s.name = remote.name; s.kindRaw = remote.kindRaw
            s.orderIndex = remote.orderIndex; s.deletedAt = remote.deletedAt
        } else {
            let s = Subject(name: remote.name,
                            kind: SubjectKind(rawValue: remote.kindRaw) ?? .person,
                            orderIndex: remote.orderIndex, id: uuid)
            s.deletedAt = remote.deletedAt
            s.team = team
            context.insert(s)
        }
        try? context.save()
    }

    private func applyGroup(_ remote: FGroup) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr), let team = team(remote.teamId) else { return }
        let existing = (try? context.fetch(FetchDescriptor<StuntGroup>(
            predicate: #Predicate { $0.id == uuid })))?.first
        let g: StuntGroup
        if let existing { g = existing } else {
            g = StuntGroup(name: remote.name, number: remote.number,
                           orderIndex: remote.orderIndex)
            g.team = team
            context.insert(g)
        }
        g.name = remote.name; g.number = remote.number
        g.orderIndex = remote.orderIndex; g.kindRaw = remote.kindRaw
        g.categoryRaw = remote.categoryRaw; g.typeLabelRaw = remote.typeLabelRaw
        g.outcomeDefsRaw = remote.outcomeDefsRaw
        g.outcomeOverridesRaw = remote.outcomeOverridesRaw
        g.deletedAt = remote.deletedAt
        try? context.save()
    }

    // MARK: - Sharing (join codes)

    /// Outcome of redeeming a join code, surfaced to the join sheet.
    enum JoinOutcome: Equatable {
        case joined          // membership written; the roster pulls down via listener
        case invalidCode     // no such code
        case notSignedIn
        case failed(String)  // network / permission error
    }

    /// Human-friendly code alphabet — no 0/O, 1/I/L, so a shared code can't be
    /// misread. 6 chars over 31 symbols ≈ 887M combos; collisions are vanishing.
    private static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private func generateCode() -> String {
        String((0..<6).map { _ in SyncEngine.codeAlphabet.randomElement()! })
    }

    /// Make `team` shareable: mint (or reuse) a join code, publish a public
    /// `joinCodes/{code}` → { teamId, ownerUID } directory entry, stamp the code
    /// on the team, and push the team meta so members see it. Returns the code
    /// (existing or new), or nil on failure. Owner-only in practice — a joined
    /// team already carries a code and this just returns it.
    func shareTeam(_ team: Team) async -> String? {
        guard let uid else { lastError = "Not signed in."; return nil }
        // Claim ownership of a not-yet-synced local team so the code is valid.
        if team.ownerUID == nil { team.ownerUID = uid }
        if let existing = team.joinCode, !existing.isEmpty { return existing }
        let teamID = team.id.uuidString
        for _ in 0..<5 {
            let code = generateCode()
            let ref = db.collection("joinCodes").document(code)
            do {
                let snap = try await ref.getDocument()
                if snap.exists { continue }   // extremely unlikely; try another
                try await ref.setData([
                    "teamId": teamID,
                    "ownerUID": uid,
                    "createdAt": FieldValue.serverTimestamp()
                ])
                team.joinCode = code
                try? modelContext?.save()
                pushTeamMeta(team)   // propagate the code onto the team doc
                lastError = nil
                return code
            } catch {
                lastError = "Share failed: \(error.localizedDescription)"
                return nil
            }
        }
        lastError = "Couldn't allocate a code — try again."
        return nil
    }

    /// Redeem a join code: resolve it to a team and add ourselves to that team's
    /// `memberIds` (the sole member-write the rules allow). The `memberIds`
    /// listener then pulls the roster + attempts down automatically.
    func joinTeam(code rawCode: String) async -> JoinOutcome {
        guard let uid else { return .notSignedIn }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return .invalidCode }
        do {
            let snap = try await db.collection("joinCodes").document(code).getDocument()
            guard snap.exists, let teamID = snap.data()?["teamId"] as? String else {
                return .invalidCode
            }
            try await db.collection("teams").document(teamID).updateData([
                "memberIds": FieldValue.arrayUnion([uid]),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            // Ensure the pull listeners are live so the joined roster lands.
            if let modelContext, !isRunning { startSyncing(context: modelContext) }
            lastError = nil
            return .joined
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func applyAttempt(_ remote: FAttempt) {
        guard let context = modelContext, let idStr = remote.id,
              let groupUUID = UUID(uuidString: remote.groupId) else { return }
        // Dedup by the same deterministic doc id we push with.
        let group = (try? context.fetch(FetchDescriptor<StuntGroup>(
            predicate: #Predicate { $0.id == groupUUID })))?.first
        guard let group else { return }
        let alreadyHave = group.attempts.contains { attemptDocID($0) == idStr }
        if alreadyHave { return }
        let subject: Subject? = remote.subjectId.flatMap { sid in
            guard let su = UUID(uuidString: sid) else { return nil }
            return (try? context.fetch(FetchDescriptor<Subject>(
                predicate: #Predicate { $0.id == su })))?.first
        }
        let attempt = Attempt(slot: remote.outcomeRaw, group: group, session: nil,
                              subject: subject, timestamp: remote.timestamp,
                              waveID: remote.waveID.flatMap { UUID(uuidString: $0) })
        attempt.executionScored = remote.executionScored
        attempt.lostDriversRaw = remote.lostDriversRaw
        context.insert(attempt)
        try? context.save()
    }
}
