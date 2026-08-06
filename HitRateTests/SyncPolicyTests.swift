import XCTest
@testable import HitRate

final class SyncSnapshotPolicyTests: XCTestCase {
    func testOnlyAcknowledgedServerSnapshotUnlocksReconciliation() {
        XCTAssertFalse(SyncSnapshotPolicy.isReady(isFromCache: true, hasPendingWrites: false))
        XCTAssertFalse(SyncSnapshotPolicy.isReady(isFromCache: false, hasPendingWrites: true))
        XCTAssertFalse(SyncSnapshotPolicy.isReady(isFromCache: true, hasPendingWrites: true))
        XCTAssertTrue(SyncSnapshotPolicy.isReady(isFromCache: false, hasPendingWrites: false))
    }
}

final class SyncListenerPlanTests: XCTestCase {
    func testOnlyActiveFolderReceivesHistoryListeners() {
        XCTAssertEqual(
            SyncListenerPlan.collections(forTeamID: "team-a", activeTeamID: nil),
            Set(["subjects", "groups", "templates"])
        )
        XCTAssertEqual(
            SyncListenerPlan.collections(forTeamID: "team-a", activeTeamID: "team-b"),
            Set(["subjects", "groups", "templates"])
        )
        XCTAssertEqual(
            SyncListenerPlan.collections(forTeamID: "team-a", activeTeamID: "team-a"),
            Set(["subjects", "groups", "templates", "sessions", "attempts"])
        )
    }

    func testPerConnectionListenerCountWithFiveFolders() {
        XCTAssertEqual(
            SyncListenerPlan.listenerCount(visibleTeamCount: 5, hasActiveTeam: true),
            19
        )
        XCTAssertEqual(
            SyncListenerPlan.listenerCount(visibleTeamCount: 5, hasActiveTeam: false),
            17
        )
    }
}

final class SyncAttemptOwnershipPolicyTests: XCTestCase {
    func testImportedAttemptIsNeverReattributedToCurrentUser() {
        XCTAssertFalse(SyncAttemptOwnershipPolicy.canUpload(
            storedLoggerID: "member-b",
            currentUID: "owner-a"
        ))
        XCTAssertEqual(SyncAttemptOwnershipPolicy.resolvedLoggerID(
            storedLoggerID: "member-b",
            currentUID: "owner-a"
        ), "member-b")
    }

    func testLegacyLocalAttemptClaimsCurrentLoggerOnce() {
        XCTAssertTrue(SyncAttemptOwnershipPolicy.canUpload(
            storedLoggerID: "",
            currentUID: "member-b"
        ))
        XCTAssertEqual(SyncAttemptOwnershipPolicy.resolvedLoggerID(
            storedLoggerID: "",
            currentUID: "member-b"
        ), "member-b")
    }
}

final class SyncSessionIdentityTests: XCTestCase {
    func testExplicitRemoteSessionIDIsPreserved() {
        XCTAssertEqual(SyncSessionIdentity.resolve(
            remoteSessionID: "session-123",
            teamID: "team-a",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        ), "session-123")
    }

    func testLegacyAttemptsOnSameUTCDayShareSyntheticSession() {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(60 * 60)

        XCTAssertEqual(
            SyncSessionIdentity.resolve(remoteSessionID: nil, teamID: "team-a", timestamp: first),
            SyncSessionIdentity.resolve(remoteSessionID: nil, teamID: "team-a", timestamp: second)
        )
    }

    func testLegacySessionIdentityIsScopedByTeam() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNotEqual(
            SyncSessionIdentity.resolve(remoteSessionID: nil, teamID: "team-a", timestamp: timestamp),
            SyncSessionIdentity.resolve(remoteSessionID: nil, teamID: "team-b", timestamp: timestamp)
        )
    }
}

final class FolderSummaryIndexTests: XCTestCase {
    func testBuildsFolderCountsInOnePass() {
        let groups = [
            FolderSummaryIndex.GroupRecord(teamID: "a", isDeleted: false),
            FolderSummaryIndex.GroupRecord(teamID: "a", isDeleted: false),
            FolderSummaryIndex.GroupRecord(teamID: "b", isDeleted: false),
            FolderSummaryIndex.GroupRecord(teamID: "b", isDeleted: true)
        ]
        let attempts = (0..<10_000).map { index in
            FolderSummaryIndex.AttemptRecord(teamID: index.isMultiple(of: 2) ? "a" : "b",
                                             isDeleted: index < 10)
        }

        let summaries = FolderSummaryIndex.build(groups: groups, attempts: attempts)

        XCTAssertEqual(summaries["a"], .init(skillCount: 2, repCount: 4_995))
        XCTAssertEqual(summaries["b"], .init(skillCount: 1, repCount: 4_995))
    }
}
