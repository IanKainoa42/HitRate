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

final class SyncJoinCodePolicyTests: XCTestCase {
    func testTimedOutShareKeepsTheCodeItAlreadyPublished() {
        XCTAssertTrue(SyncJoinCodePolicy.keepsCode(after: .acknowledged))
        XCTAssertTrue(SyncJoinCodePolicy.keepsCode(after: .timedOut))
        XCTAssertFalse(SyncJoinCodePolicy.keepsCode(after: .failed))
    }

    func testRemoteNilNeverErasesAFreshlyMintedCode() {
        XCTAssertEqual(SyncJoinCodePolicy.merged(local: "2D6A2N", remote: nil), "2D6A2N")
        XCTAssertEqual(SyncJoinCodePolicy.merged(local: "2D6A2N", remote: ""), "2D6A2N")
    }

    func testOwnerPublishedCodeWins() {
        XCTAssertEqual(SyncJoinCodePolicy.merged(local: nil, remote: "XQ2KUR"), "XQ2KUR")
        XCTAssertEqual(SyncJoinCodePolicy.merged(local: "2D6A2N", remote: "XQ2KUR"), "XQ2KUR")
        XCTAssertNil(SyncJoinCodePolicy.merged(local: nil, remote: nil))
    }
}

final class SyncJoinTargetPolicyTests: XCTestCase {
    func testMissingOrInaccessibleFolderMakesAJoinCodeInvalid() {
        XCTAssertTrue(SyncJoinTargetPolicy.isStaleTarget(
            errorDomain: "FIRFirestoreErrorDomain", errorCode: 5
        ))
        XCTAssertTrue(SyncJoinTargetPolicy.isStaleTarget(
            errorDomain: "FIRFirestoreErrorDomain", errorCode: 7
        ))
    }

    func testNetworkFailureDoesNotMasqueradeAsAnInvalidCode() {
        XCTAssertFalse(SyncJoinTargetPolicy.isStaleTarget(
            errorDomain: "NSURLErrorDomain", errorCode: -1009
        ))
        XCTAssertFalse(SyncJoinTargetPolicy.isStaleTarget(
            errorDomain: "FIRFirestoreErrorDomain", errorCode: 14
        ))
    }
}

final class SyncRosterMembershipPolicyTests: XCTestCase {
    func testOwnerRemovalDropsOnlyTheSelectedMember() {
        XCTAssertEqual(
            SyncRosterMembershipPolicy.remainingMemberIDs(
                ["member-a", "member-b", "member-c"], removing: "member-b"
            ),
            ["member-a", "member-c"]
        )
    }

    func testRemovedJoinerNoLongerKeepsFolderListeners() {
        XCTAssertTrue(SyncRosterMembershipPolicy.isVisible(
            ownerUID: "owner", memberIDs: [], currentUID: "owner"
        ))
        XCTAssertFalse(SyncRosterMembershipPolicy.isVisible(
            ownerUID: "owner", memberIDs: ["member-a"], currentUID: "member-b"
        ))
    }

    func testAcknowledgedEmptyQueryUnionDetachesStaleJoinedMirror() {
        let visibleTeamIDs: Set<String> = []

        XCTAssertTrue(SyncRosterMembershipPolicy.shouldDetachLocalMirror(
            teamID: "team-a",
            ownerUID: "owner",
            currentUID: "member-a",
            visibleTeamIDs: visibleTeamIDs
        ))
    }

    func testAcknowledgedQueryUnionKeepsOwnedAndVisibleJoinedFolders() {
        XCTAssertFalse(SyncRosterMembershipPolicy.shouldDetachLocalMirror(
            teamID: "owned-team",
            ownerUID: "owner",
            currentUID: "owner",
            visibleTeamIDs: []
        ))
        XCTAssertFalse(SyncRosterMembershipPolicy.shouldDetachLocalMirror(
            teamID: "joined-team",
            ownerUID: "owner",
            currentUID: "member-a",
            visibleTeamIDs: ["joined-team"]
        ))
    }
}

final class MinBuildPolicyTests: XCTestCase {
    func testBuildBelowThresholdIsBlocked() {
        XCTAssertTrue(MinBuildPolicy.isBlocked(currentBuild: 21, minBuild: 22))
    }

    func testThresholdBuildAndNewerRun() {
        XCTAssertFalse(MinBuildPolicy.isBlocked(currentBuild: 22, minBuild: 22))
        XCTAssertFalse(MinBuildPolicy.isBlocked(currentBuild: 27, minBuild: 22))
    }

    func testMissingRemoteConfigNeverLocksAnyoneOut() {
        XCTAssertFalse(MinBuildPolicy.isBlocked(currentBuild: 1, minBuild: nil))
        XCTAssertFalse(MinBuildPolicy.isBlocked(currentBuild: 0, minBuild: nil))
    }

    func testUnreadableBuildNumberIsNotBlockedByADefaultThreshold() {
        // CFBundleVersion parses to 0 when absent; a live minBuild would block
        // it, which is correct — but only when a threshold is actually set.
        XCTAssertFalse(MinBuildPolicy.isBlocked(currentBuild: 0, minBuild: nil))
        XCTAssertTrue(MinBuildPolicy.isBlocked(currentBuild: 0, minBuild: 22))
    }
}

final class AttemptCacheInvalidationTests: XCTestCase {
    func testExternalDeleteDropsTheCache() {
        // The shipped crash: deleting a folder cascaded its reps away while the
        // import cache still named them, and resolving one trapped in SwiftData.
        XCTAssertTrue(AttemptCacheInvalidation.shouldDrop(deletedCount: 40, isImporting: false))
    }

    func testSaveWithoutDeletesKeepsTheCache() {
        XCTAssertFalse(AttemptCacheInvalidation.shouldDrop(deletedCount: 0, isImporting: false))
    }

    func testImportsOwnTombstonesDoNotAbortIt() {
        // applyAttempts deletes tombstoned reps and maintains `known` inline; if
        // its own save invalidated the cache it would abort on every batch.
        XCTAssertFalse(AttemptCacheInvalidation.shouldDrop(deletedCount: 12, isImporting: true))
    }

    func testGenerationMismatchMarksAnInFlightImportStale() {
        XCTAssertFalse(AttemptCacheInvalidation.isStale(captured: 7, current: 7))
        XCTAssertTrue(AttemptCacheInvalidation.isStale(captured: 7, current: 8))
    }
}

final class AccountPromptPolicyTests: XCTestCase {
    func testOnboardingStepLeadsAFreshInstall() {
        XCTAssertTrue(AccountPromptPolicy.showsOnboardingStep(
            dismissed: false, isUpgraded: false, replayingIntro: false, restoring: false))
    }

    func testOnboardingStepIsSkippedOnceSavedOrOnAnIntroReplay() {
        // Already saved — nothing to offer.
        XCTAssertFalse(AccountPromptPolicy.showsOnboardingStep(
            dismissed: false, isUpgraded: true, replayingIntro: false, restoring: false))
        // Replay is not a fresh install; the user still has their data.
        XCTAssertFalse(AccountPromptPolicy.showsOnboardingStep(
            dismissed: false, isUpgraded: false, replayingIntro: true, restoring: false))
        // "Not now" is honored for the rest of the flow.
        XCTAssertFalse(AccountPromptPolicy.showsOnboardingStep(
            dismissed: true, isUpgraded: false, replayingIntro: false, restoring: false))
    }

    func testRestoringHoldsTheStepEvenAfterSignInFlipsUpgraded() {
        // The regression this guards: sign-in flips isUpgraded immediately, so
        // without the restoring pin the step vanishes mid-restore and the user
        // gets walked through building a duplicate folder.
        XCTAssertTrue(AccountPromptPolicy.showsOnboardingStep(
            dismissed: false, isUpgraded: true, replayingIntro: false, restoring: true))
        XCTAssertTrue(AccountPromptPolicy.showsOnboardingStep(
            dismissed: true, isUpgraded: true, replayingIntro: true, restoring: true))
    }

    func testAfterPracticePromptNeedsRepsAndAsksOnlyOnce() {
        XCTAssertTrue(AccountPromptPolicy.offersSaveAfterPractice(
            isUpgraded: false, alreadyAsked: false, repCount: 12))
        // An empty practice has nothing to protect.
        XCTAssertFalse(AccountPromptPolicy.offersSaveAfterPractice(
            isUpgraded: false, alreadyAsked: false, repCount: 0))
        // Never twice, and never once saved.
        XCTAssertFalse(AccountPromptPolicy.offersSaveAfterPractice(
            isUpgraded: false, alreadyAsked: true, repCount: 12))
        XCTAssertFalse(AccountPromptPolicy.offersSaveAfterPractice(
            isUpgraded: true, alreadyAsked: false, repCount: 12))
    }

    func testFolderChipPersistsButOnlyWithAFolderToLose() {
        XCTAssertTrue(AccountPromptPolicy.showsFolderListChip(isUpgraded: false, folderCount: 1))
        XCTAssertFalse(AccountPromptPolicy.showsFolderListChip(isUpgraded: false, folderCount: 0))
        XCTAssertFalse(AccountPromptPolicy.showsFolderListChip(isUpgraded: true, folderCount: 3))
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
