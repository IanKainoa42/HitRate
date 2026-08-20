import Foundation

/// Describes which Firestore collections stay live for each visible folder.
/// Rosters are lightweight and must remain available in the folder list, while
/// sessions and attempts can contain thousands of documents and are only needed
/// for the folder whose dashboard is currently open.
enum SyncListenerPlan {
    static let rosterCollections: Set<String> = ["subjects", "groups", "templates"]
    static let historyCollections: Set<String> = ["sessions", "attempts"]

    static func collections(forTeamID teamID: String, activeTeamID: String?) -> Set<String> {
        guard teamID == activeTeamID else { return rosterCollections }
        return rosterCollections.union(historyCollections)
    }

    /// Includes the two account-level owned/member team queries.
    static func listenerCount(visibleTeamCount: Int, hasActiveTeam: Bool) -> Int {
        2 + (visibleTeamCount * rosterCollections.count)
            + (hasActiveTeam ? historyCollections.count : 0)
    }
}

/// A cache snapshot is useful for immediately rendering offline data, but it is
/// not proof that Firestore has sent the complete server state. Reconciliation
/// can begin only after an acknowledged server snapshot.
enum SyncSnapshotPolicy {
    static func isReady(isFromCache: Bool, hasPendingWrites: Bool) -> Bool {
        !isFromCache && !hasPendingWrites
    }
}

/// Attempts belong to the Firebase account that originally logged them. A
/// legacy local attempt has no logger yet and may be claimed exactly once by the
/// current account; an imported attempt can only be uploaded by its logger.
enum SyncAttemptOwnershipPolicy {
    static func canUpload(storedLoggerID: String, currentUID: String) -> Bool {
        storedLoggerID.isEmpty || storedLoggerID == currentUID
    }

    static func resolvedLoggerID(storedLoggerID: String, currentUID: String) -> String {
        storedLoggerID.isEmpty ? currentUID : storedLoggerID
    }
}

/// New attempt documents carry their session id. Older Firestore documents do
/// not, so they are grouped into a deterministic per-team UTC-day session. That
/// fallback makes legacy shared reps visible to StatsEngine without inventing a
/// different session every time a snapshot arrives.
enum SyncSessionIdentity {
    static func resolve(remoteSessionID: String?, teamID: String, timestamp: Date) -> String {
        if let remoteSessionID, !remoteSessionID.isEmpty { return remoteSessionID }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = calendar.startOfDay(for: timestamp)
        return "legacy-\(teamID)-\(Int(dayStart.timeIntervalSince1970))"
    }
}

/// Publishing `joinCodes/{code}` makes the code a server-side fact the moment the
/// write lands, but the acknowledgement can outlive the client's timeout — a quota
/// rejection is retried inside the Firestore SDK rather than thrown, so the
/// completion handler simply never fires. Dropping the code in that window orphans
/// the directory entry that did land and mints a brand-new code on the next share.
enum SyncJoinCodePolicy {
    enum ShareWrite {
        case acknowledged
        /// Unacknowledged, not failed: the write stays in Firestore's local
        /// mutation queue and still commits once the connection recovers.
        case timedOut
        case failed
    }

    static func keepsCode(after write: ShareWrite) -> Bool {
        switch write {
        case .acknowledged, .timedOut: return true
        case .failed: return false
        }
    }

    /// The code to keep when a remote team document arrives. The owner is
    /// authoritative whenever it publishes a code, but nothing ever un-shares a
    /// folder, so a nil from the server only means our own push has not landed
    /// yet — it must never erase a code we already minted.
    static func merged(local: String?, remote: String?) -> String? {
        guard let remote, !remote.isEmpty else { return local }
        return remote
    }
}

/// A join-code document can outlive the folder it names. Firestore reports a
/// missing team as NOT_FOUND and a soft-deleted team as PERMISSION_DENIED (the
/// rules reject new membership). Both mean the code has no joinable target;
/// transport failures remain retryable errors instead of being mislabeled.
enum SyncJoinTargetPolicy {
    private static let firestoreErrorDomain = "FIRFirestoreErrorDomain"
    private static let notFoundCode = 5
    private static let permissionDeniedCode = 7

    static func isStaleTarget(errorDomain: String, errorCode: Int) -> Bool {
        errorDomain == firestoreErrorDomain
            && (errorCode == notFoundCode || errorCode == permissionDeniedCode)
    }
}

/// Membership changes affect access only. Logger-owned sessions/attempts are
/// deliberately outside this plan, so removing a member never selects or
/// deletes their history.
enum SyncRosterMembershipPolicy {
    enum QuerySource: Hashable {
        case owned
        case member
    }

    static func remainingMemberIDs(_ memberIDs: [String], removing memberID: String) -> [String] {
        memberIDs.filter { $0 != memberID }
    }

    static func isVisible(ownerUID: String, memberIDs: [String], currentUID: String) -> Bool {
        ownerUID == currentUID || memberIDs.contains(currentUID)
    }

    /// Once both acknowledged server queries have arrived, their union is the
    /// authority for joined-folder access. A local joined mirror can outlive
    /// Firestore's query cache without producing a `.removed` change on the
    /// next launch, so local `memberIds` must not override an empty union.
    static func shouldDetachLocalMirror(
        teamID: String,
        ownerUID: String?,
        currentUID: String,
        visibleTeamIDs: Set<String>
    ) -> Bool {
        ownerUID != nil
            && ownerUID != currentUID
            && !visibleTeamIDs.contains(teamID)
    }
}

/// A remote emergency brake: `config/ios`'s `minBuild` field can be bumped to
/// stop a specific bad TestFlight/App-Store build from hammering Firestore
/// (the July/August write-storm was exactly this — a build that rewrote every
/// synced doc on every save, discovered only after it burned the daily quota).
/// TestFlight builds can be expired remotely; App Store installs cannot — this
/// is the only lever for those. Fails OPEN: a missing doc, unset field, or
/// failed fetch must never lock users out, so `minBuild == nil` never blocks.
enum MinBuildPolicy {
    static func isBlocked(currentBuild: Int, minBuild: Int?) -> Bool {
        guard let minBuild else { return false }
        return currentBuild < minBuild
    }
}

/// The attempt-import id cache is only valid while every row it names still
/// exists. Deleting a folder cascades its whole rep history away, and resolving
/// one of those stranded identifiers traps inside SwiftData (EXC_BREAKPOINT in
/// applyAttempts) — so a local delete drops the cache, and an import already
/// walking the old copy has to notice and stop.
enum AttemptCacheInvalidation {
    /// A save that deleted rows invalidates the cache — UNLESS it's the import's
    /// own tombstone write, which maintains its map inline and would otherwise
    /// abort itself on every batch.
    static func shouldDrop(deletedCount: Int, isImporting: Bool) -> Bool {
        deletedCount > 0 && !isImporting
    }

    /// An in-flight import compares the generation it captured against the
    /// current one after each yield; a mismatch means rows went away underneath
    /// it and the remaining identifiers can no longer be trusted.
    static func isStale(captured: UInt, current: UInt) -> Bool {
        captured != current
    }
}

/// The debounced push queue holds identifiers between a save and the flush
/// 0.6s later — and every save RESTARTS that debounce, so a burst of logging
/// can hold ids for as long as the burst lasts.
///
/// A row deleted inside that window must be dropped from the queue, never
/// pushed: SwiftData hands `model(for:)` an invalidated instance for a deleted
/// row and TRAPS the moment a relationship is read off it. Undo is the
/// everyday path in — log reps quickly, undo the last one, and the flush reads
/// `attempt.group` on a dead row and kills the app (device crash 2026-08-19,
/// EXC_BREAKPOINT in `SyncEngine.pushLocalChanges` → `Attempt.group.getter`).
/// The tombstone survives regardless: it's a separate `PendingCloudDeletion`
/// row with its own identifier, queued before the delete.
enum PendingPushQueue {
    static func prune<ID: Hashable>(_ pending: Set<ID>, deleted: [ID]) -> Set<ID> {
        deleted.isEmpty ? pending : pending.subtracting(deleted)
    }
}

/// When to offer "save your account". Anonymous users are device-bound, so a
/// reinstall orphans their cloud folders — but the app works fully offline, and
/// App Review 5.1.1(i) doesn't allow gating that behind a login. So every
/// surface is an OFFER, never a wall, and each has to earn its interruption.
enum AccountPromptPolicy {
    /// Onboarding step 0. Front-loaded because signing in here is the only path
    /// that RESTORES a previous install's folders. Skipped for an intro replay
    /// (not a fresh install — the user still has their data) and for an already
    /// saved account. `restoring` pins it open so a sign-in that's still pulling
    /// the roster down can't flash past into the create-a-folder flow.
    static func showsOnboardingStep(dismissed: Bool, isUpgraded: Bool,
                                    replayingIntro: Bool, restoring: Bool) -> Bool {
        if restoring { return true }
        return !dismissed && !isUpgraded && !replayingIntro
    }

    /// After practice. Asked at most once per install, and only once there are
    /// reps to lose — an empty practice has nothing to protect, and a second
    /// unprompted ask reads as nagging.
    static func offersSaveAfterPractice(isUpgraded: Bool, alreadyAsked: Bool,
                                        repCount: Int) -> Bool {
        !isUpgraded && !alreadyAsked && repCount > 0
    }

    /// The always-on folder-list chip. Unlike the prompt this never expires —
    /// it's the standing door back in — but it stays hidden until there's a
    /// folder to lose so a first launch isn't nagged.
    static func showsFolderListChip(isUpgraded: Bool, folderCount: Int) -> Bool {
        !isUpgraded && folderCount > 0
    }
}

/// Value-only folder summaries keep SwiftUI from faulting every Attempt
/// relationship more than once while rendering the folder list.
enum FolderSummaryIndex {
    struct GroupRecord {
        let teamID: String
        let isDeleted: Bool
    }

    struct AttemptRecord {
        let teamID: String
        let isDeleted: Bool
    }

    struct Summary: Equatable {
        var skillCount = 0
        var repCount = 0
    }

    static func build(groups: [GroupRecord], attempts: [AttemptRecord]) -> [String: Summary] {
        var result: [String: Summary] = [:]
        for group in groups where !group.isDeleted {
            result[group.teamID, default: Summary()].skillCount += 1
        }
        for attempt in attempts where !attempt.isDeleted {
            result[attempt.teamID, default: Summary()].repCount += 1
        }
        return result
    }
}
