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
