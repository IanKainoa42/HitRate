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
///   • ATTEMPTS are append-only and keyed by a stable cloud id. A rep is never
///     edited after logging, so syncing them is a plain set-union: every device
///     pushes its own new reps and pulls everyone else's. `loggerId` records who
///     threw it (attribution). Deleting a rep writes a `deletedAt` tombstone.
///
/// Firestore layout:
///   teams/{teamId}                         → FTeam (meta, memberIds, ownerUID)
///   teams/{teamId}/subjects/{subjectId}    → FSubject
///   teams/{teamId}/groups/{groupId}        → FGroup
///   teams/{teamId}/templates/{templateId}  → FTemplate
///   teams/{teamId}/sessions/{sessionId}    → FSession
///   teams/{teamId}/attempts/{attemptId}    → FAttempt
///
/// `startSyncing` is idempotent; local saves enqueue only their changed records,
/// while live listeners keep the pull direction current.
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
    /// A team is reconciled only after every listener has delivered an
    /// acknowledged server snapshot. Cache snapshots still populate the UI and
    /// fingerprints, but can be stale or incomplete.
    private var teamsReadyForAttemptPush: Set<String> = []
    private var serverReadyCollections: [String: Set<String>] = [:]
    private let requiredServerCollections: Set<String> = [
        "team", "subjects", "groups", "templates", "sessions", "attempts"
    ]
    private var attemptImportTasks: [String: Task<Void, Never>] = [:]

    /// Last payload sent/received for each document this session. A plain id set
    /// cannot distinguish "already uploaded" from "edited since upload"; it also
    /// caused 1.2 to rewrite every document after every SwiftData save because the
    /// old set was populated but never consulted. Fingerprints make the debounce
    /// genuinely incremental while still allowing later edits to sync.
    private var syncedFingerprints: [String: String] = [:]
    private var inFlightFingerprints: [String: String] = [:]
    private var knownAttemptIDsByTeam: [String: [String: PersistentIdentifier]] = [:]

    /// Debounce token for save-triggered pushes.
    private var pushWorkItem: DispatchWorkItem?
    private var saveObserver: NSObjectProtocol?
    private var pendingPushIDs: Set<PersistentIdentifier> = []
    private var needsFullPush = false

    /// A rejected attempt/session push (e.g. a quota rejection) flips
    /// `syncState` to `.failed` via its own completion handler, which saves
    /// the model — and that save re-triggers `didSave`, queuing another push
    /// attempt of the very same record moments later. Without a cooldown this
    /// is an unbounded retry loop bound only by the debounce interval, and it
    /// replays every failed record again on every relaunch too. 5 minutes is
    /// long enough to stop hammering a systemic outage, short enough that a
    /// transient blip recovers within a session.
    private static let retryCooldown: TimeInterval = 300

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
        pushLocalBootstrap()
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
        inFlightFingerprints.removeAll()
        knownAttemptIDsByTeam.removeAll()
        teamsReadyForAttemptPush.removeAll()
        serverReadyCollections.removeAll()
        attemptImportTasks.values.forEach { $0.cancel() }
        attemptImportTasks.removeAll()
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
        for key in changedKeys {
            guard let ids = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] else {
                continue
            }
            pendingPushIDs.formUnion(ids)
        }
        // Deleted models cannot be resolved after didSave. Attempt deletions are
        // represented by PendingCloudDeletion insertions, so a delete-only save
        // needs no fallback rescan.
        guard !pendingPushIDs.isEmpty else { return }
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

    /// Publish only never-synced local folders at launch. Existing cloud teams
    /// wait for their server snapshots so a second launch performs zero
    /// redundant writes.
    private func pushLocalBootstrap() {
        guard let context = modelContext, let uid else { return }
        do {
            let teams = try context.fetch(FetchDescriptor<Team>())
            for team in teams where team.ownerUID == nil && !team.isDemo {
                team.ownerUID = uid
                let teamID = team.id.uuidString
                _ = pushTeamMeta(team)
                for subject in team.subjects { _ = pushSubject(subject, teamID: teamID) }
                for group in team.groups { _ = pushGroup(group, teamID: teamID) }
                for template in team.outcomeTemplates { _ = pushTemplate(template, teamID: teamID) }
            }
            if context.hasChanges { try context.save() }
        } catch {
            lastError = "Sync bootstrap failed: \(error.localizedDescription)"
        }
    }

    /// Mirror every locally-owned team's roster + all local attempts up to
    /// Firestore. Owner pushes the roster; every device pushes its own reps.
    private func pushLocalData() {
        guard let context = modelContext, let uid else { return }
        do {
            let teams = try context.fetch(FetchDescriptor<Team>())
            var wroteDocument = false
            for team in teams {
                guard !team.isDemo else { continue }
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
            }

            // Attempt.syncStateRaw is the durable outbox. A normal launch does
            // not fault the complete history; only unsent/failed rows are read.
            let pendingAttempts = try context.fetch(FetchDescriptor<Attempt>(
                predicate: #Predicate { $0.syncStateRaw != "synced" }
            ))
            for attempt in pendingAttempts {
                guard let team = attempt.group?.team else { continue }
                let teamID = team.id.uuidString
                guard teamsReadyForAttemptPush.contains(teamID) else { continue }
                wroteDocument = pushAttempt(attempt, teamID: teamID, uid: uid) || wroteDocument
            }

            let pendingSessions = try context.fetch(FetchDescriptor<PracticeSession>(
                predicate: #Predicate { $0.syncStateRaw != "synced" }
            ))
            for session in pendingSessions {
                guard let teamID = sessionTeamID(session),
                      teamsReadyForAttemptPush.contains(teamID) else { continue }
                wroteDocument = pushSession(session, teamID: teamID, uid: uid) || wroteDocument
            }

            let deletions = try context.fetch(FetchDescriptor<PendingCloudDeletion>())
            for deletion in deletions where teamsReadyForAttemptPush.contains(deletion.teamID) {
                wroteDocument = pushDeletion(deletion, uid: uid) || wroteDocument
            }
            if !wroteDocument { lastError = nil }
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
                guard !team.isDemo else { continue }
                let isOwner = team.ownerUID == nil || team.ownerUID == uid
                if team.ownerUID == nil { team.ownerUID = uid }
                if isOwner {
                    wroteDocument = pushTeamMeta(team) || wroteDocument
                }

            case let subject as Subject:
                guard let team = subject.team, !team.isDemo,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushSubject(subject, teamID: team.id.uuidString) || wroteDocument

            case let group as StuntGroup:
                guard let team = group.team, !team.isDemo,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushGroup(group, teamID: team.id.uuidString) || wroteDocument

            case let template as OutcomeTemplate:
                guard let team = template.team, !team.isDemo,
                      team.ownerUID == nil || team.ownerUID == uid else { continue }
                wroteDocument = pushTemplate(template, teamID: team.id.uuidString) || wroteDocument

            case let attempt as Attempt:
                guard let team = attempt.group?.team else { continue }
                let teamID = team.id.uuidString
                guard teamsReadyForAttemptPush.contains(teamID) else { continue }
                wroteDocument = pushAttempt(attempt, teamID: teamID, uid: uid) || wroteDocument

            case let session as PracticeSession:
                guard let teamID = sessionTeamID(session),
                      teamsReadyForAttemptPush.contains(teamID) else { continue }
                wroteDocument = pushSession(session, teamID: teamID, uid: uid) || wroteDocument

            case let deletion as PendingCloudDeletion:
                guard teamsReadyForAttemptPush.contains(deletion.teamID) else { continue }
                wroteDocument = pushDeletion(deletion, uid: uid) || wroteDocument

            default:
                continue
            }
        }

        if !wroteDocument { lastError = nil }
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
    private func pushSession(_ session: PracticeSession, teamID: String, uid: String) -> Bool {
        guard SyncAttemptOwnershipPolicy.canUpload(
            storedLoggerID: session.loggerID,
            currentUID: uid
        ) else { return false }
        if session.syncStateRaw == CloudSyncState.failed.rawValue,
           let last = session.lastSyncAttemptAt,
           Date.now.timeIntervalSince(last) < SyncEngine.retryCooldown {
            return false
        }

        let loggerID = SyncAttemptOwnershipPolicy.resolvedLoggerID(
            storedLoggerID: session.loggerID,
            currentUID: uid
        )
        if session.cloudID.isEmpty {
            session.cloudID = "session-\(UUID().uuidString)"
        }
        if session.cloudTeamID != teamID { session.cloudTeamID = teamID }
        if session.loggerID != loggerID { session.loggerID = loggerID }

        let documentID = session.cloudID
        let key = sessionKey(teamID, documentID)
        let fingerprint = sessionFingerprint(session, teamID: teamID, loggerID: loggerID)
        if syncedFingerprints[key] != fingerprint,
           inFlightFingerprints[key] != fingerprint,
           session.syncStateRaw != CloudSyncState.uploading.rawValue {
            session.syncStateRaw = CloudSyncState.uploading.rawValue
            session.lastSyncAttemptAt = .now
        }
        if modelContext?.hasChanges == true { try? modelContext?.save() }

        let doc = FSession(
            id: documentID,
            teamId: teamID,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            loggerId: loggerID,
            updatedAt: .now
        )
        return setDoc(
            teamDoc(teamID).collection("sessions").document(documentID),
            doc,
            key: key,
            fingerprint: fingerprint
        ) { [weak self, weak session] result in
            guard let self, let session else { return }
            let state = result ? CloudSyncState.synced.rawValue : CloudSyncState.failed.rawValue
            guard session.syncStateRaw != state else { return }
            session.syncStateRaw = state
            try? self.modelContext?.save()
        }
    }

    @discardableResult
    private func pushAttempt(_ attempt: Attempt, teamID: String, uid: String) -> Bool {
        guard let groupID = attempt.group?.id.uuidString else { return false }
        guard SyncAttemptOwnershipPolicy.canUpload(
            storedLoggerID: attempt.loggerID,
            currentUID: uid
        ) else { return false }
        if attempt.syncState == .failed,
           let last = attempt.lastSyncAttemptAt,
           Date.now.timeIntervalSince(last) < SyncEngine.retryCooldown {
            return false
        }

        let loggerID = SyncAttemptOwnershipPolicy.resolvedLoggerID(
            storedLoggerID: attempt.loggerID,
            currentUID: uid
        )
        if attempt.cloudID.isEmpty { attempt.cloudID = legacyAttemptDocID(attempt) }
        if let session = attempt.session {
            _ = pushSession(session, teamID: teamID, uid: uid)
        }

        if attempt.cloudTeamID != teamID { attempt.cloudTeamID = teamID }
        if attempt.loggerID != loggerID { attempt.loggerID = loggerID }

        let docID = attempt.cloudID
        let key = attemptKey(teamID, docID)
        let fingerprint = attemptFingerprint(attempt, teamID: teamID, loggerID: loggerID)
        if syncedFingerprints[key] != fingerprint,
           inFlightFingerprints[key] != fingerprint,
           attempt.syncState != .uploading {
            attempt.syncState = .uploading
            attempt.lastSyncAttemptAt = .now
        }
        if modelContext?.hasChanges == true { try? modelContext?.save() }

        let doc = FAttempt(
            id: docID, teamId: teamID, groupId: groupID,
            subjectId: attempt.subject?.id.uuidString,
            outcomeRaw: attempt.outcomeRaw, timestamp: attempt.timestamp,
            waveID: attempt.waveID?.uuidString,
            sessionId: attempt.session.flatMap { $0.cloudID.isEmpty ? nil : $0.cloudID },
            executionScored: attempt.executionScored,
            lostDriversRaw: attempt.lostDriversRaw,
            loggerId: loggerID,
            deletedAt: nil,
            updatedAt: .now
        )
        return setDoc(teamDoc(teamID).collection("attempts").document(docID), doc,
                      key: key,
                      fingerprint: fingerprint) {
            [weak self, weak attempt] result in
            guard let self, let attempt else { return }
            let state: CloudSyncState = result ? .synced : .failed
            guard attempt.syncState != state else { return }
            attempt.syncState = state
            try? self.modelContext?.save()
        }
    }

    /// Pre-1.4 attempts had no cloud id. Preserve their deployed deterministic
    /// document ids so migration never duplicates existing Firestore history.
    private func legacyAttemptDocID(_ attempt: Attempt) -> String {
        let group = attempt.group?.id.uuidString ?? "nil"
        let subject = attempt.subject?.id.uuidString ?? "nil"
        let ts = Int(attempt.timestamp.timeIntervalSince1970 * 1000)
        return "\(group)-\(subject)-\(attempt.outcomeRaw)-\(ts)"
    }

    private func sessionTeamID(_ session: PracticeSession) -> String? {
        if !session.cloudTeamID.isEmpty { return session.cloudTeamID }
        return session.attempts.compactMap { $0.group?.team?.id.uuidString }.first
    }

    /// Insert the durable tombstone in the same local save as the deletion.
    /// Callers may then remove the Attempt without losing the remote operation.
    func queueDeletion(of attempt: Attempt, in context: ModelContext) {
        // A never-attempted local upload has no remote document to tombstone.
        // `uploading` is included because Firestore preserves write ordering:
        // its create is already queued ahead of this tombstone while offline.
        guard attempt.syncState == .synced || attempt.syncState == .uploading else { return }
        guard let currentUID = uid,
              SyncAttemptOwnershipPolicy.canUpload(
                storedLoggerID: attempt.loggerID,
                currentUID: currentUID
              ) else { return }
        guard let teamID = attempt.group?.team?.id.uuidString else { return }
        let documentID = attempt.cloudID.isEmpty ? legacyAttemptDocID(attempt) : attempt.cloudID
        let loggerID = SyncAttemptOwnershipPolicy.resolvedLoggerID(
            storedLoggerID: attempt.loggerID,
            currentUID: currentUID
        )
        context.insert(PendingCloudDeletion(
            teamID: teamID,
            documentID: documentID,
            loggerID: loggerID
        ))
    }

    @discardableResult
    private func pushDeletion(_ deletion: PendingCloudDeletion, uid: String) -> Bool {
        guard deletion.loggerID.isEmpty || deletion.loggerID == uid else { return false }
        let key = attemptKey(deletion.teamID, deletion.documentID)
        let fingerprint = "deleted:\(deletion.documentID)"
        if syncedFingerprints[key] == fingerprint {
            modelContext?.delete(deletion)
            try? modelContext?.save()
            return false
        }
        guard inFlightFingerprints[key] != fingerprint else { return false }
        inFlightFingerprints[key] = fingerprint

        let ref = teamDoc(deletion.teamID).collection("attempts").document(deletion.documentID)
        let deletionIdentifier = deletion.persistentModelID
        ref.setData(["deletedAt": Timestamp(date: deletion.createdAt)], merge: true) {
            [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.inFlightFingerprints.removeValue(forKey: key)
                if let error {
                    self.lastError = "Sync delete failed: \(error.localizedDescription)"
                } else {
                    self.syncedFingerprints[key] = fingerprint
                    self.lastPushedAt = .now
                    if let deletion = self.modelContext?.model(for: deletionIdentifier)
                        as? PendingCloudDeletion {
                        self.modelContext?.delete(deletion)
                    }
                    try? self.modelContext?.save()
                }
            }
        }
        return true
    }

    @discardableResult
    private func setDoc<T: Encodable>(_ ref: DocumentReference, _ value: T,
                                      key: String, fingerprint: String,
                                      completion: ((Bool) -> Void)? = nil) -> Bool {
        if syncedFingerprints[key] == fingerprint {
            completion?(true)
            return false
        }
        guard inFlightFingerprints[key] != fingerprint else { return false }
        do {
            inFlightFingerprints[key] = fingerprint
            try ref.setData(from: value, merge: true) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.inFlightFingerprints.removeValue(forKey: key)
                    if let error {
                        self.lastError = "Sync write failed: \(error.localizedDescription)"
                        completion?(false)
                    } else {
                        self.syncedFingerprints[key] = fingerprint
                        self.lastError = nil
                        self.lastPushedAt = .now
                        completion?(true)
                    }
                }
            }
            return true
        } catch {
            inFlightFingerprints.removeValue(forKey: key)
            lastError = "Encode failed: \(error.localizedDescription)"
            completion?(false)
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
            let reg = query.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    self.lastError = "Team sync failed: \(error.localizedDescription)"
                    return
                }
                guard let snap else { return }
                for change in snap.documentChanges {
                    if let team = try? change.document.data(as: FTeam.self) {
                        let teamID = team.id ?? change.document.documentID
                        self.applyTeam(
                            team,
                            acknowledged: !change.document.metadata.hasPendingWrites
                        )
                        self.attachTeamSubcollections(teamID: teamID)
                        self.markServerReady(teamID: teamID, collection: "team",
                                             metadata: snap.metadata)
                    }
                }
                // Metadata-only snapshots have no document changes. Mark every
                // visible team represented by the snapshot in that case.
                for document in snap.documents {
                    self.markServerReady(teamID: document.documentID, collection: "team",
                                         metadata: snap.metadata)
                }
            }
            listeners.append(reg)
        }
    }

    private func attachTeamSubcollections(teamID: String) {
        guard teamListeners[teamID] == nil else { return }
        let base = teamDoc(teamID)
        var registrations: [ListenerRegistration] = []
        registrations.append(base.collection("subjects").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { self.lastError = "Subject sync failed: \(error.localizedDescription)"; return }
            snap?.documentChanges.forEach { c in
                if let s = try? c.document.data(as: FSubject.self) {
                    self.applySubject(s, acknowledged: !c.document.metadata.hasPendingWrites)
                }
            }
            if let snap { self.markServerReady(teamID: teamID, collection: "subjects", metadata: snap.metadata) }
        })
        registrations.append(base.collection("groups").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { self.lastError = "Skill sync failed: \(error.localizedDescription)"; return }
            snap?.documentChanges.forEach { c in
                if let g = try? c.document.data(as: FGroup.self) {
                    self.applyGroup(g, acknowledged: !c.document.metadata.hasPendingWrites)
                }
            }
            if let snap { self.markServerReady(teamID: teamID, collection: "groups", metadata: snap.metadata) }
        })
        registrations.append(base.collection("templates").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { self.lastError = "Template sync failed: \(error.localizedDescription)"; return }
            snap?.documentChanges.forEach { c in
                if let t = try? c.document.data(as: FTemplate.self) {
                    self.applyTemplate(t, acknowledged: !c.document.metadata.hasPendingWrites)
                }
            }
            if let snap { self.markServerReady(teamID: teamID, collection: "templates", metadata: snap.metadata) }
        })
        registrations.append(base.collection("sessions").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { self.lastError = "Session sync failed: \(error.localizedDescription)"; return }
            snap?.documentChanges.forEach { change in
                guard !change.document.metadata.hasPendingWrites else { return }
                if let session = try? change.document.data(as: FSession.self) {
                    self.applySession(session)
                }
            }
            if let snap { self.markServerReady(teamID: teamID, collection: "sessions", metadata: snap.metadata) }
        })
        registrations.append(base.collection("attempts").addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self else { return }
            if let error { self.lastError = "Attempt sync failed: \(error.localizedDescription)"; return }
            guard let snap else { return }
            // A pending-write document is our own local Firestore echo, not a
            // backend acknowledgement. The write completion owns its outbox
            // transition; the listener imports only cache/server records.
            let attempts = snap.documentChanges.compactMap { change -> FAttempt? in
                guard !change.document.metadata.hasPendingWrites else { return nil }
                return try? change.document.data(as: FAttempt.self)
            }
            self.enqueueAttemptImport(attempts, teamID: teamID, metadata: snap.metadata)
        })
        teamListeners[teamID] = registrations
    }

    private func markServerReady(teamID: String, collection: String,
                                 metadata: SnapshotMetadata) {
        guard SyncSnapshotPolicy.isReady(
            isFromCache: metadata.isFromCache,
            hasPendingWrites: metadata.hasPendingWrites
        ) else { return }
        serverReadyCollections[teamID, default: []].insert(collection)
        guard serverReadyCollections[teamID]?.isSuperset(of: requiredServerCollections) == true,
              teamsReadyForAttemptPush.insert(teamID).inserted else { return }
        scheduleFullPush()
    }

    /// Serialize imports per team. The importer builds its relationship indexes
    /// once, then saves/yields every 250 records so a 10k-rep hydration cannot
    /// monopolize the main actor long enough to block opening a folder.
    private func enqueueAttemptImport(_ remotes: [FAttempt], teamID: String,
                                      metadata: SnapshotMetadata) {
        let previous = attemptImportTasks[teamID]
        attemptImportTasks[teamID] = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.applyAttempts(remotes, teamID: teamID)
            self.markServerReady(teamID: teamID, collection: "attempts", metadata: metadata)
        }
    }

    // MARK: - Apply remote docs into SwiftData

    private func team(_ id: String) -> Team? {
        guard let context = modelContext, let uuid = UUID(uuidString: id) else { return nil }
        return try? context.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.id == uuid })).first
    }

    private func applyTeam(_ remote: FTeam, acknowledged: Bool) {
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
        if acknowledged, let local = team(idStr) {
            syncedFingerprints[teamKey(idStr)] = teamFingerprint(local)
        }
        if changed { try? context.save() }
    }

    private func applySubject(_ remote: FSubject, acknowledged: Bool) {
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
        if acknowledged {
            syncedFingerprints[subjectKey(remote.teamId, idStr)] = subjectFingerprint(subject, teamID: remote.teamId)
        }
        if changed { try? context.save() }
    }

    private func applyGroup(_ remote: FGroup, acknowledged: Bool) {
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
        if acknowledged {
            syncedFingerprints[groupKey(remote.teamId, idStr)] = groupFingerprint(g, teamID: remote.teamId)
        }
        if changed { try? context.save() }
    }

    private func applyTemplate(_ remote: FTemplate, acknowledged: Bool) {
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
        if acknowledged {
            syncedFingerprints[templateKey(remote.teamId, idStr)] = templateFingerprint(template, teamID: remote.teamId)
        }
        if changed { try? context.save() }
    }

    private func applySession(_ remote: FSession) {
        guard let context = modelContext, let id = remote.id else { return }
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.cloudID == id }
        )
        let existing = (try? context.fetch(descriptor))?.first
        let session = existing ?? PracticeSession(startedAt: remote.startedAt)
        var changed = existing == nil
        if existing == nil { context.insert(session) }
        if session.cloudID != id { session.cloudID = id; changed = true }
        if session.cloudTeamID != remote.teamId { session.cloudTeamID = remote.teamId; changed = true }
        if session.loggerID != remote.loggerId { session.loggerID = remote.loggerId; changed = true }
        if session.startedAt != remote.startedAt { session.startedAt = remote.startedAt; changed = true }
        if session.endedAt != remote.endedAt { session.endedAt = remote.endedAt; changed = true }
        if session.syncStateRaw != CloudSyncState.synced.rawValue {
            session.syncStateRaw = CloudSyncState.synced.rawValue
            changed = true
        }
        syncedFingerprints[sessionKey(remote.teamId, id)] = remoteSessionFingerprint(remote)
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

    private struct TimedOutError: LocalizedError {
        var errorDescription: String? { "Timed out — check your connection and try again." }
    }

    /// Resumes a continuation at most once. A `withThrowingTaskGroup` race
    /// doesn't work here: the group can't return until every child finishes,
    /// even a cancelled one, and a Firestore continuation that's silently
    /// dropped (e.g. a quota rejection the SDK retries instead of throwing)
    /// never finishes — so the "timeout" would hang right alongside it. An
    /// unstructured `Task` per side lets the loser keep running detached
    /// while this function returns as soon as either side resumes.
    private actor ResumeOnce {
        private var done = false
        func claim() -> Bool {
            guard !done else { return false }
            done = true
            return true
        }
    }

    /// Bounds a single Firestore await so a stuck request fails the UI
    /// instead of spinning forever. Share/join are user-initiated, one-shot
    /// calls — a hung continuation here has no other way to surface.
    private func withTimeout<T: Sendable>(
        seconds: TimeInterval = 12,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let guardian = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let value = try await operation()
                    if await guardian.claim() { continuation.resume(returning: value) }
                } catch {
                    if await guardian.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if await guardian.claim() { continuation.resume(throwing: TimedOutError()) }
            }
        }
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
                // Both round trips share ONE timeout window — two stacked 12s
                // waits (lookup, then write) made a single attempt take up to
                // 24s before the user saw anything, which read as "spins
                // forever" even though it eventually failed.
                let claimed = try await withTimeout(seconds: 10) { () async throws -> Bool in
                    let snap = try await ref.getDocument()
                    if snap.exists { return false }   // extremely unlikely; try another
                    try await ref.setData([
                        "teamId": teamID,
                        "ownerUID": uid,
                        "createdAt": FieldValue.serverTimestamp()
                    ])
                    return true
                }
                guard claimed else { continue }
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
            let firestore = db
            let ref = firestore.collection("joinCodes").document(code)
            // One timeout window for both round trips (code lookup, then the
            // membership write) — see shareTeam for why stacking two 12s
            // waits made a single join attempt feel like it hung.
            let outcome = try await withTimeout(seconds: 10) { () async throws -> Bool in
                let snap = try await ref.getDocument()
                guard snap.exists, let teamID = snap.data()?["teamId"] as? String else {
                    return false
                }
                let teamRef = firestore.collection("teams").document(teamID)
                try await teamRef.updateData([
                    "memberIds": FieldValue.arrayUnion([uid]),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                return true
            }
            guard outcome else { return .invalidCode }
            // Ensure the pull listeners are live so the joined roster lands.
            if let modelContext, !isRunning { startSyncing(context: modelContext) }
            lastError = nil
            return .joined
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func applyAttempts(_ remotes: [FAttempt], teamID: String) async {
        guard let context = modelContext, !remotes.isEmpty else { return }

        do {
            let groups = try context.fetch(FetchDescriptor<StuntGroup>())
            let subjects = try context.fetch(FetchDescriptor<Subject>())
            let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
            let groupsByID = groups.reduce(into: [UUID: StuntGroup]()) { result, group in
                result[group.id] = result[group.id] ?? group
            }
            let subjectsByID = subjects.reduce(into: [UUID: Subject]()) { result, subject in
                result[subject.id] = result[subject.id] ?? subject
            }
            var sessionsByCloudID = sessions.reduce(into: [String: PracticeSession]()) { result, session in
                guard !session.cloudID.isEmpty else { return }
                result[session.cloudID] = result[session.cloudID] ?? session
            }

            if knownAttemptIDsByTeam[teamID] == nil {
                let allAttempts = try context.fetch(FetchDescriptor<Attempt>())
                knownAttemptIDsByTeam[teamID] = allAttempts.reduce(into: [:]) { result, attempt in
                    let localTeamID = attempt.cloudTeamID.isEmpty
                        ? attempt.group?.team?.id.uuidString
                        : attempt.cloudTeamID
                    guard localTeamID == teamID else { return }
                    let documentID = attempt.cloudID.isEmpty
                        ? legacyAttemptDocID(attempt)
                        : attempt.cloudID
                    result[documentID] = attempt.persistentModelID
                }
            }
            var known = knownAttemptIDsByTeam[teamID, default: [:]]
            var changed = false

            for (index, remote) in remotes.enumerated() {
                guard remote.teamId == teamID else { continue }
                guard let idStr = remote.id,
                      let groupUUID = UUID(uuidString: remote.groupId),
                      let group = groupsByID[groupUUID] else { continue }

                syncedFingerprints[attemptKey(remote.teamId, idStr)] = remoteAttemptFingerprint(remote)

                let existing = known[idStr].flatMap { context.model(for: $0) as? Attempt }
                if remote.deletedAt != nil {
                    if let existing {
                        context.delete(existing)
                        known.removeValue(forKey: idStr)
                        changed = true
                    }
                    continue
                }

                let subject = remote.subjectId
                    .flatMap(UUID.init(uuidString:))
                    .flatMap { subjectsByID[$0] }
                let sessionID = SyncSessionIdentity.resolve(
                    remoteSessionID: remote.sessionId,
                    teamID: remote.teamId,
                    timestamp: remote.timestamp
                )
                let session: PracticeSession
                if let existingSession = sessionsByCloudID[sessionID] {
                    session = existingSession
                    if remote.sessionId == nil {
                        session.startedAt = min(session.startedAt, remote.timestamp)
                        session.endedAt = max(session.endedAt ?? remote.timestamp, remote.timestamp)
                    }
                } else {
                    session = PracticeSession(startedAt: remote.timestamp)
                    session.cloudID = sessionID
                    session.cloudTeamID = remote.teamId
                    session.loggerID = remote.loggerId
                    session.syncStateRaw = CloudSyncState.synced.rawValue
                    session.endedAt = remote.timestamp
                    context.insert(session)
                    sessionsByCloudID[sessionID] = session
                    changed = true
                }

                let attempt: Attempt
                if let existing {
                    attempt = existing
                } else {
                    attempt = Attempt(slot: remote.outcomeRaw, group: group, session: session,
                                      subject: subject, timestamp: remote.timestamp,
                                      waveID: remote.waveID.flatMap(UUID.init(uuidString:)))
                    context.insert(attempt)
                    known[idStr] = attempt.persistentModelID
                    changed = true
                }

                if attempt.cloudID != idStr { attempt.cloudID = idStr; changed = true }
                if attempt.cloudTeamID != remote.teamId { attempt.cloudTeamID = remote.teamId; changed = true }
                if attempt.loggerID != remote.loggerId { attempt.loggerID = remote.loggerId; changed = true }
                if attempt.syncState != .synced { attempt.syncState = .synced; changed = true }
                if attempt.group !== group { attempt.group = group; changed = true }
                if attempt.session !== session { attempt.session = session; changed = true }
                if attempt.subject !== subject { attempt.subject = subject; changed = true }
                if attempt.outcomeRaw != remote.outcomeRaw { attempt.outcomeRaw = remote.outcomeRaw; changed = true }
                if attempt.timestamp != remote.timestamp { attempt.timestamp = remote.timestamp; changed = true }
                let waveID = remote.waveID.flatMap(UUID.init(uuidString:))
                if attempt.waveID != waveID { attempt.waveID = waveID; changed = true }
                if attempt.executionScored != remote.executionScored {
                    attempt.executionScored = remote.executionScored
                    changed = true
                }
                if attempt.lostDriversRaw != remote.lostDriversRaw {
                    attempt.lostDriversRaw = remote.lostDriversRaw
                    changed = true
                }

                if (index + 1).isMultiple(of: 250) {
                    knownAttemptIDsByTeam[teamID] = known
                    if changed { try context.save(); changed = false }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                }
            }

            knownAttemptIDsByTeam[teamID] = known
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
    private func sessionKey(_ teamID: String, _ id: String) -> String { "\(teamID):session:\(id)" }
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

    private func sessionFingerprint(_ session: PracticeSession, teamID: String,
                                    loggerID: String) -> String {
        stamp(teamID, session.startedAt, session.endedAt, loggerID)
    }

    private func remoteSessionFingerprint(_ session: FSession) -> String {
        stamp(session.teamId, session.startedAt, session.endedAt, session.loggerId)
    }

    private func attemptFingerprint(_ attempt: Attempt, teamID: String, loggerID: String) -> String {
        stamp(teamID, attempt.group?.id.uuidString, attempt.subject?.id.uuidString,
              attempt.outcomeRaw, attempt.timestamp, attempt.waveID?.uuidString,
              attempt.session?.cloudID,
              attempt.executionScored, attempt.lostDriversRaw, loggerID,
              Optional<Date>.none)
    }

    private func remoteAttemptFingerprint(_ attempt: FAttempt) -> String {
        stamp(attempt.teamId, attempt.groupId, attempt.subjectId, attempt.outcomeRaw,
              attempt.timestamp, attempt.waveID, attempt.sessionId,
              attempt.executionScored, attempt.lostDriversRaw, attempt.loggerId,
              attempt.deletedAt)
    }
}
