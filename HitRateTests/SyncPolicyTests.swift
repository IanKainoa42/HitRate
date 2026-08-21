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
    func testNewTimedOutCodeStaysPendingAndInvisible() {
        let state = SyncJoinCodePolicy.state(
            after: .timedOut,
            attemptedCode: "2D6A2N",
            current: .init(acknowledged: nil, pending: nil)
        )

        XCTAssertNil(state.acknowledged)
        XCTAssertEqual(state.pending, "2D6A2N")
    }

    func testAcknowledgementPromotesPendingCode() {
        let state = SyncJoinCodePolicy.state(
            after: .acknowledged,
            attemptedCode: "2D6A2N",
            current: .init(acknowledged: nil, pending: "2D6A2N")
        )

        XCTAssertEqual(state.acknowledged, "2D6A2N")
        XCTAssertNil(state.pending)
    }

    func testDefinitiveFailureClearsAttemptedPendingCode() {
        let state = SyncJoinCodePolicy.state(
            after: .failed,
            attemptedCode: "2D6A2N",
            current: .init(acknowledged: nil, pending: "2D6A2N")
        )

        XCTAssertNil(state.acknowledged)
        XCTAssertNil(state.pending)
    }

    func testTimeoutPreservesAnAlreadyAcknowledgedCode() {
        let state = SyncJoinCodePolicy.state(
            after: .timedOut,
            attemptedCode: "2D6A2N",
            current: .init(acknowledged: "2D6A2N", pending: nil)
        )

        XCTAssertEqual(state.acknowledged, "2D6A2N")
        XCTAssertNil(state.pending)
    }

    func testRepublishFailurePreservesAnAlreadyAcknowledgedCode() {
        let state = SyncJoinCodePolicy.state(
            after: .failed,
            attemptedCode: "2D6A2N",
            current: .init(acknowledged: "2D6A2N", pending: nil)
        )

        XCTAssertEqual(state.acknowledged, "2D6A2N")
        XCTAssertNil(state.pending)
    }

    func testLegacyUnverifiedCodeMovesToPendingBeforeItCanBeShown() {
        XCTAssertEqual(
            SyncJoinCodePolicy.normalizedForRetry(
                .init(acknowledged: "2D6A2N", pending: nil),
                isAcknowledged: false
            ),
            .init(acknowledged: nil, pending: "2D6A2N")
        )
    }

    func testVerifiedCodeStaysAcknowledged() {
        let current = SyncJoinCodePolicy.LocalState(
            acknowledged: "2D6A2N", pending: nil
        )
        XCTAssertEqual(
            SyncJoinCodePolicy.normalizedForRetry(current, isAcknowledged: true),
            current
        )
    }

    func testRemoteTeamSnapshotCannotPromotePendingCodeByItself() {
        let current = SyncJoinCodePolicy.LocalState(
            acknowledged: nil, pending: "2D6A2N"
        )
        let state = SyncJoinCodePolicy.mergingRemote(
            "2D6A2N",
            into: current,
            acknowledged: true
        )

        XCTAssertEqual(state, current)
    }

    func testPendingWriteSnapshotDoesNotPromotePendingCode() {
        let current = SyncJoinCodePolicy.LocalState(
            acknowledged: nil, pending: "2D6A2N"
        )

        XCTAssertEqual(
            SyncJoinCodePolicy.mergingRemote(
                "2D6A2N", into: current, acknowledged: false
            ),
            current
        )
    }

    func testAcknowledgedTeamSnapshotDoesNotVerifyMatchingPendingCode() {
        XCTAssertFalse(SyncJoinCodePolicy.remoteCodeIsVerified(
            "2D6A2N",
            prior: .init(acknowledged: nil, pending: "2D6A2N"),
            priorWasVerified: false,
            snapshotAcknowledged: true
        ))
    }

    func testTeamDocumentAloneDoesNotVerifyAnUnrelatedLegacyCode() {
        XCTAssertFalse(SyncJoinCodePolicy.remoteCodeIsVerified(
            "2D6A2N",
            prior: .init(acknowledged: nil, pending: nil),
            priorWasVerified: false,
            snapshotAcknowledged: true
        ))
    }

    func testAcknowledgedSnapshotPreservesProofForTheSameVerifiedCode() {
        XCTAssertTrue(SyncJoinCodePolicy.remoteCodeIsVerified(
            "2D6A2N",
            prior: .init(acknowledged: "2D6A2N", pending: nil),
            priorWasVerified: true,
            snapshotAcknowledged: true
        ))
    }

    func testRemoteNilNeverErasesAFreshlyMintedCode() {
        let current = SyncJoinCodePolicy.LocalState(
            acknowledged: "2D6A2N", pending: nil
        )
        XCTAssertEqual(
            SyncJoinCodePolicy.mergingRemote(nil, into: current, acknowledged: true),
            current
        )
        XCTAssertEqual(
            SyncJoinCodePolicy.mergingRemote("", into: current, acknowledged: true),
            current
        )
    }

    func testOwnerPublishedCodeWins() {
        XCTAssertEqual(
            SyncJoinCodePolicy.mergingRemote(
                "XQ2KUR",
                into: .init(acknowledged: "2D6A2N", pending: "2D6A2N"),
                acknowledged: true
            ),
            .init(acknowledged: "XQ2KUR", pending: nil)
        )
    }
}

final class SyncJoinTargetPolicyTests: XCTestCase {
    func testMissingFolderMakesAJoinCodeInvalid() {
        XCTAssertTrue(SyncJoinTargetPolicy.isStaleTarget(
            errorDomain: "FIRFirestoreErrorDomain", errorCode: 5
        ))
    }

    func testPermissionFailureDoesNotMasqueradeAsAnInvalidCode() {
        XCTAssertFalse(SyncJoinTargetPolicy.isStaleTarget(
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
