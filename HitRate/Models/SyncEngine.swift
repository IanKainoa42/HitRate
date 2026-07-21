import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

/// Builds the import plan once per Firestore snapshot. The old implementation
/// called `contains` on a group's complete SwiftData history for every remote
/// document, turning a large folder refresh into quadratic main-thread work.
enum SyncAttemptBatchPlanner {
    static func missingDocumentIDs<S: Sequence>(remote: [String], existing: S) -> [String]
    where S.Element == String {
        var known = Set(existing)
        return remote.filter { known.insert($0).inserted }
    }
}

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
    private var teamListeners: [String: [ListenerRegistration]] = [:]
    private var modelContext: ModelContext?
    private var isRunning = false
    /// A team's remote attempts must be indexed before local history is pushed.
    /// Otherwise every launch blindly rewrites the folder's entire rep history.
    private var teamsReadyForAttemptPush: Set<String> = []

    /// Last payload sent/received for each document this session. A plain id set
    /// cannot distinguish "already uploaded" from "edited since upload"; it also
    /// caused 1.2 to rewrite every document after every SwiftData save because the
    /// old set was populated but never consulted. Fingerprints make the debounce
    /// genuinely incremental while still allowing later edits to sync.
    private var syncedFingerprints: [String: String] = [:]

    /// Debounce token for save-triggered pushes.
    private var pushWorkItem: DispatchWorkItem?
    private var saveObserver: NSObjectProtocol?
    private var pendingPushIDs: Set<PersistentIdentifier> = []
    private var needsFullPush = false

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
        attachListeners()
        pushLocalData()
    }

    /// Tear down listeners + the save observer (called on sign-out).
    func stopSyncing() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        teamListeners.values.flatMap { $0 }.forEach { $0.remove() }
        teamListeners.removeAll()
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
            self.saveObserver = nil
        }
        pushWorkItem?.cancel()
        syncedFingerprints.removeAll()
        teamsReadyForAttemptPush.removeAll()
        pendingPushIDs.removeAll()
        needsFullPush = false
        isRunning = false
    }

    // MARK: - Local change observation

    /// SwiftData posts `ModelContext.didSave` after every persisted mutation.
    /// We debounce and re-push; the pushed-id sets keep it to just the deltas.
    private func observeLocalSaves() {
        guard saveObserver == nil, let modelContext else { return }
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: modelContext, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.schedulePush(for: notification)
            }
        }
    }

    private func schedulePush(for notification: Notification) {
        let changedKeys: [ModelContext.NotificationKey] = [
            .insertedIdentifiers, .updatedIdentifiers
        ]
        var foundIdentifiers = false
        for key in changedKeys {
            guard let ids = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] else {
                continue
            }
            pendingPushIDs.formUnion(ids)
            foundIdentifiers = foundIdentifiers || !ids.isEmpty
        }
        // Older/alternate SwiftData stores may omit the identifier payload.
        // Preserve sync correctness with a full pass in that rare case.
        if !foundIdentifiers { needsFullPush = true }
        enqueuePush()
    }

    private func scheduleFullPush() {
        needsFullPush = true
        enqueuePush()
    }

    private func enqueuePush() {
        pushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushScheduledPush() }
        pushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func flushScheduledPush() {
        let fullPush = needsFullPush
        let changedIDs = pendingPushIDs
        needsFullPush = false
        pendingPushIDs.removeAll()
        if fullPush {
            pushLocalData()
        } else if !changedIDs.isEmpty {
            pushLocalChanges(changedIDs)
        }
    }

    // MARK: - Push (local → Firestore)

    /// Mirror every locally-owned team's roster + all local attempts up to
    /// Firestore. Owner pushes the roster; every device pushes its own reps.
    private func pushLocalData() {
        guard let context = modelContext, let uid else { return }
        do {
            let teams = try context.fetch(FetchDescriptor<Team>())
            var wroteDocument = false
            for team in teams {
                let teamID = team.id.uuidString
                let isOwner = (team.ownerUID == nil) || (team.ownerUID == uid)
                // Claim ownership of a pre-cloud team the first time we sync it.
                if team.ownerUID == nil { team.ownerUID = uid }

                if isOwner {
                    wroteDocument = pushTeamMeta(team) || wroteDocument
                    for subject in team.subjects {
                        wroteDocument = pushSubject(subject, teamID: teamID) || wroteDocument
                    }
                    for group in team.groups {
                        wroteDocument = pushGroup(group, teamID: teamID) || wroteDocument
                    }
                    for template in team.outcomeTemplates {
                        wroteDocument = pushTemplate(template, teamID: teamID) || wroteDocument
                    }
                }
                // Seed fingerprints from the remote snapshot before touching
                // history. This prevents a full rewrite on every app launch.
                if teamsReadyForAttemptPush.contains(teamID) {
                    for group in team.groups {
                        for attempt in group.attempts {
                            wroteDocument = pushAttempt(attempt, teamID: teamID, uid: uid) || wroteDocument
                        }
                    }
                }
            }
            if wroteDocument { lastPushedAt = .now }
            lastError = nil
        } catch {
            lastError = "Sync push failed: \(error.localizedDescription)"
        }
    }

    /// Push only the models reported by SwiftData's save notification. Logging
    /// one rep must not re-walk every rep in every folder.
    private func pushLocalChanges(_ identifiers: Set<PersistentIdentifier>) {
        guard let context = modelContext, let uid else { return }
        var wroteDocument = false

        for identifier in identifiers {
            let model = context.model(for: identifier)
            switch model {
            case let team as Team:
                let isOwner = team.ownerUID == nil || team.ownerUID == uid
                if team.ownerUID == nil { team.ownerUID = uid }
                if isOwner {
                    wroteDocument = pushTeamMeta(team) || wroteDocument
                }

            case let subject as Subject:
                guard let team = subject.team,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushSubject(subject, teamID: team.id.uuidString) || wroteDocument

            case let group as StuntGroup:
                guard let team = group.team,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushGroup(group, teamID: team.id.uuidString) || wroteDocument

            case let template as OutcomeTemplate:
                guard let team = template.team,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushTemplate(template, teamID: team.id.uuidString) || wroteDocument

            case let attempt as Attempt:
                guard let team = attempt.group?.team else { continue }
                let teamID = team.id.uuidString
                guard teamsReadyForAttemptPush.contains(teamID) else { continue }
                wroteDocument = pushAttempt(attempt, teamID: teamID, uid: uid) || wroteDocument

            default:
                continue
            }
        }

        if wroteDocument { lastPushedAt = .now }
        lastError = nil
    }

    private func teamDoc(_ teamID: String) -> DocumentReference {
        db.collection("teams").document(teamID)
    }

    @discardableResult
    private func pushTeamMeta(_ team: Team) -> Bool {
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
        return setDoc(teamDoc(id), doc, key: teamKey(id), fingerprint: teamFingerprint(team))
    }

    @discardableResult
    private func pushSubject(_ subject: Subject, teamID: String) -> Bool {
        let id = subject.id.uuidString
        let doc = FSubject(
            id: id, teamId: teamID, name: subject.name,
            kindRaw: subject.kindRaw, orderIndex: subject.orderIndex,
            deletedAt: subject.deletedAt, updatedAt: .now
        )
        return setDoc(teamDoc(teamID).collection("subjects").document(id), doc,
                      key: subjectKey(teamID, id), fingerprint: subjectFingerprint(subject, teamID: teamID))
    }

    @discardableResult
    private func pushGroup(_ group: StuntGroup, teamID: String) -> Bool {
        let id = group.id.uuidString
        let doc = FGroup(
            id: id, teamId: teamID, name: group.name, number: group.number,
            orderIndex: group.orderIndex, kindRaw: group.kindRaw,
            categoryRaw: group.categoryRaw, typeLabelRaw: group.typeLabelRaw,
            outcomeDefsRaw: group.outcomeDefsRaw,
            outcomeOverridesRaw: group.outcomeOverridesRaw,
            deletedAt: group.deletedAt, updatedAt: .now
        )
        return setDoc(teamDoc(teamID).collection("groups").document(id), doc,
                      key: groupKey(teamID, id), fingerprint: groupFingerprint(group, teamID: teamID))
    }

    @discardableResult
    private func pushTemplate(_ template: OutcomeTemplate, teamID: String) -> Bool {
        let id = template.id.uuidString
        let doc = FTemplate(
            id: id, teamId: teamID, name: template.name,
            defsRaw: template.defsRaw, orderIndex: template.orderIndex,
            updatedAt: .now
        )
        return setDoc(teamDoc(teamID).collection("templates").document(id), doc,
                      key: templateKey(teamID, id), fingerprint: templateFingerprint(template, teamID: teamID))
    }

    @discardableResult
    private func pushAttempt(_ attempt: Attempt, teamID: String, uid: String) -> Bool {
        guard let groupID = attempt.group?.id.uuidString else { return false }
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
        return setDoc(teamDoc(teamID).collection("attempts").document(docID), doc,
                      key: attemptKey(teamID, docID),
                      fingerprint: attemptFingerprint(attempt, teamID: teamID, loggerID: uid))
    }

    /// Attempt has no stored UUID id, so we derive a deterministic doc id from its
    /// immutable fields (append-only reps are never edited, so this is stable).
    private func attemptDocID(_ attempt: Attempt) -> String {
        let group = attempt.group?.id.uuidString ?? "nil"
        let subject = attempt.subject?.id.uuidString ?? "nil"
        let ts = Int(attempt.timestamp.timeIntervalSince1970 * 1000)
        return "\(group)-\(subject)-\(attempt.outcomeRaw)-\(ts)"
    }

    @discardableResult
    private func setDoc<T: Encodable>(_ ref: DocumentReference, _ value: T,
                                      key: String, fingerprint: String) -> Bool {
        guard syncedFingerprints[key] != fingerprint else { return false }
        do {
            try ref.setData(from: value, merge: true)
            syncedFingerprints[key] = fingerprint
            return true
        } catch {
            lastError = "Encode failed: \(error.localizedDescription)"
            return false
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
        guard teamListeners[teamID] == nil else { return }
        let base = teamDoc(teamID)
        var registrations: [ListenerRegistration] = []
        registrations.append(base.collection("subjects").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let s = try? c.document.data(as: FSubject.self) { self?.applySubject(s) }
            }
        })
        registrations.append(base.collection("groups").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let g = try? c.document.data(as: FGroup.self) { self?.applyGroup(g) }
            }
        })
        registrations.append(base.collection("templates").addSnapshotListener { [weak self] snap, _ in
            snap?.documentChanges.forEach { c in
                if let t = try? c.document.data(as: FTemplate.self) { self?.applyTemplate(t) }
            }
        })
        registrations.append(base.collection("attempts").addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            let attempts = snap.documentChanges.compactMap {
                try? $0.document.data(as: FAttempt.self)
            }
            self.applyAttempts(attempts)
            if self.teamsReadyForAttemptPush.insert(teamID).inserted {
                // One linear reconciliation uploads local-only history after
                // the remote snapshot has populated the fingerprint cache.
                self.scheduleFullPush()
            }
        })
        teamListeners[teamID] = registrations
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
        var changed = false
        if let local {
            // Members mirror owner's roster meta; don't clobber our own ownership.
            if local.name != remote.name { local.name = remote.name; changed = true }
            if local.itemNoun != remote.itemNoun { local.itemNoun = remote.itemNoun; changed = true }
            if local.orderIndex != remote.orderIndex { local.orderIndex = remote.orderIndex; changed = true }
            if local.memberIds != remote.memberIds { local.memberIds = remote.memberIds; changed = true }
            if local.joinCode != remote.joinCode { local.joinCode = remote.joinCode; changed = true }
            if local.deletedAt != remote.deletedAt { local.deletedAt = remote.deletedAt; changed = true }
            if local.ownerUID == nil { local.ownerUID = remote.ownerUID; changed = true }
        } else {
            let t = Team(name: remote.name, orderIndex: remote.orderIndex, id: uuid)
            t.itemNoun = remote.itemNoun
            t.ownerUID = remote.ownerUID
            t.memberIds = remote.memberIds
            t.joinCode = remote.joinCode
            t.deletedAt = remote.deletedAt
            context.insert(t)
            changed = true
        }
        if let local = team(idStr) {
            syncedFingerprints[teamKey(idStr)] = teamFingerprint(local)
        }
        if changed { try? context.save() }
    }

    private func applySubject(_ remote: FSubject) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr), let team = team(remote.teamId) else { return }
        let existing = try? context.fetch(FetchDescriptor<Subject>(
            predicate: #Predicate { $0.id == uuid })).first
        var changed = false
        let subject: Subject
        if let s = existing.flatMap({ $0 }) {
            subject = s
            if s.name != remote.name { s.name = remote.name; changed = true }
            if s.kindRaw != remote.kindRaw { s.kindRaw = remote.kindRaw; changed = true }
            if s.orderIndex != remote.orderIndex { s.orderIndex = remote.orderIndex; changed = true }
            if s.deletedAt != remote.deletedAt { s.deletedAt = remote.deletedAt; changed = true }
            if s.team?.id != team.id { s.team = team; changed = true }
        } else {
            let s = Subject(name: remote.name,
                            kind: SubjectKind(rawValue: remote.kindRaw) ?? .person,
                            orderIndex: remote.orderIndex, id: uuid)
            s.deletedAt = remote.deletedAt
            s.team = team
            context.insert(s)
            subject = s
            changed = true
        }
        syncedFingerprints[subjectKey(remote.teamId, idStr)] = subjectFingerprint(subject, teamID: remote.teamId)
        if changed { try? context.save() }
    }

    private func applyGroup(_ remote: FGroup) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr), let team = team(remote.teamId) else { return }
        let existing = (try? context.fetch(FetchDescriptor<StuntGroup>(
            predicate: #Predicate { $0.id == uuid })))?.first
        let g: StuntGroup
        if let existing { g = existing } else {
            g = StuntGroup(name: remote.name, number: remote.number,
                           orderIndex: remote.orderIndex, id: uuid)
            g.team = team
            context.insert(g)
        }
        var changed = existing == nil
        if g.name != remote.name { g.name = remote.name; changed = true }
        if g.number != remote.number { g.number = remote.number; changed = true }
        if g.orderIndex != remote.orderIndex { g.orderIndex = remote.orderIndex; changed = true }
        if g.kindRaw != remote.kindRaw { g.kindRaw = remote.kindRaw; changed = true }
        if g.categoryRaw != remote.categoryRaw { g.categoryRaw = remote.categoryRaw; changed = true }
        if g.typeLabelRaw != remote.typeLabelRaw { g.typeLabelRaw = remote.typeLabelRaw; changed = true }
        if g.outcomeDefsRaw != remote.outcomeDefsRaw { g.outcomeDefsRaw = remote.outcomeDefsRaw; changed = true }
        if g.outcomeOverridesRaw != remote.outcomeOverridesRaw { g.outcomeOverridesRaw = remote.outcomeOverridesRaw; changed = true }
        if g.deletedAt != remote.deletedAt { g.deletedAt = remote.deletedAt; changed = true }
        if g.team?.id != team.id { g.team = team; changed = true }
        syncedFingerprints[groupKey(remote.teamId, idStr)] = groupFingerprint(g, teamID: remote.teamId)
        if changed { try? context.save() }
    }

    private func applyTemplate(_ remote: FTemplate) {
        guard let context = modelContext, let idStr = remote.id,
              let uuid = UUID(uuidString: idStr), let team = team(remote.teamId) else { return }
        let existing = (try? context.fetch(FetchDescriptor<OutcomeTemplate>(
            predicate: #Predicate { $0.id == uuid })))?.first
        let template = existing ?? OutcomeTemplate(name: remote.name, orderIndex: remote.orderIndex, id: uuid)
        if existing == nil { template.team = team; context.insert(template) }
        var changed = existing == nil
        if template.name != remote.name { template.name = remote.name; changed = true }
        if template.defsRaw != remote.defsRaw { template.defsRaw = remote.defsRaw; changed = true }
        if template.orderIndex != remote.orderIndex { template.orderIndex = remote.orderIndex; changed = true }
        if template.team?.id != team.id { template.team = team; changed = true }
        syncedFingerprints[templateKey(remote.teamId, idStr)] = templateFingerprint(template, teamID: remote.teamId)
        if changed { try? context.save() }
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

    private func applyAttempts(_ remotes: [FAttempt]) {
        guard let context = modelContext, !remotes.isEmpty else { return }

        do {
            let groups = try context.fetch(FetchDescriptor<StuntGroup>())
            let subjects = try context.fetch(FetchDescriptor<Subject>())
            let groupsByID = groups.reduce(into: [UUID: StuntGroup]()) { result, group in
                result[group.id] = result[group.id] ?? group
            }
            let subjectsByID = subjects.reduce(into: [UUID: Subject]()) { result, subject in
                result[subject.id] = result[subject.id] ?? subject
            }
            let existingDocumentIDs = groups.lazy.flatMap(\.attempts).map(attemptDocID)
            let remoteDocumentIDs = remotes.compactMap(\.id)
            var missingDocumentIDs = Set(SyncAttemptBatchPlanner.missingDocumentIDs(
                remote: remoteDocumentIDs,
                existing: existingDocumentIDs
            ))
            var changed = false

            for remote in remotes {
                guard let idStr = remote.id,
                      let groupUUID = UUID(uuidString: remote.groupId),
                      let group = groupsByID[groupUUID] else { continue }

                syncedFingerprints[attemptKey(remote.teamId, idStr)] = remoteAttemptFingerprint(remote)
                guard missingDocumentIDs.remove(idStr) != nil else { continue }

                let subject = remote.subjectId
                    .flatMap(UUID.init(uuidString:))
                    .flatMap { subjectsByID[$0] }
                let attempt = Attempt(slot: remote.outcomeRaw, group: group, session: nil,
                                      subject: subject, timestamp: remote.timestamp,
                                      waveID: remote.waveID.flatMap(UUID.init(uuidString:)))
                attempt.executionScored = remote.executionScored
                attempt.lostDriversRaw = remote.lostDriversRaw
                context.insert(attempt)
                changed = true
            }

            if changed { try context.save() }
        } catch {
            lastError = "Sync pull failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync fingerprints

    private func stamp(_ values: Any?...) -> String {
        values.map { value in
            switch value {
            case let date as Date: return String(date.timeIntervalSinceReferenceDate)
            case let strings as [String]: return strings.joined(separator: "\u{1E}")
            case .none: return "∅"
            default: return String(describing: value!)
            }
        }.joined(separator: "\u{1F}")
    }

    private func teamKey(_ id: String) -> String { "team:\(id)" }
    private func subjectKey(_ teamID: String, _ id: String) -> String { "\(teamID):subject:\(id)" }
    private func groupKey(_ teamID: String, _ id: String) -> String { "\(teamID):group:\(id)" }
    private func templateKey(_ teamID: String, _ id: String) -> String { "\(teamID):template:\(id)" }
    private func attemptKey(_ teamID: String, _ id: String) -> String { "\(teamID):attempt:\(id)" }

    private func teamFingerprint(_ team: Team) -> String {
        stamp(team.name, team.ownerUID, team.memberIds, team.orderIndex, team.itemNoun,
              team.joinCode, team.deletedAt)
    }

    private func subjectFingerprint(_ subject: Subject, teamID: String) -> String {
        stamp(teamID, subject.name, subject.kindRaw, subject.orderIndex, subject.deletedAt)
    }

    private func groupFingerprint(_ group: StuntGroup, teamID: String) -> String {
        stamp(teamID, group.name, group.number, group.orderIndex, group.kindRaw,
              group.categoryRaw, group.typeLabelRaw, group.outcomeDefsRaw,
              group.outcomeOverridesRaw, group.deletedAt)
    }

    private func templateFingerprint(_ template: OutcomeTemplate, teamID: String) -> String {
        stamp(teamID, template.name, template.defsRaw, template.orderIndex)
    }

    private func attemptFingerprint(_ attempt: Attempt, teamID: String, loggerID: String) -> String {
        stamp(teamID, attempt.group?.id.uuidString, attempt.subject?.id.uuidString,
              attempt.outcomeRaw, attempt.timestamp, attempt.waveID?.uuidString,
              attempt.executionScored, attempt.lostDriversRaw, loggerID)
    }

    private func remoteAttemptFingerprint(_ attempt: FAttempt) -> String {
        stamp(attempt.teamId, attempt.groupId, attempt.subjectId, attempt.outcomeRaw,
              attempt.timestamp, attempt.waveID, attempt.executionScored,
              attempt.lostDriversRaw, attempt.loggerId)
    }
}
