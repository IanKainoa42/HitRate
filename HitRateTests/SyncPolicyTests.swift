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

final class PendingPushQueueTests: XCTestCase {
    func testUndoDropsTheQueuedRepInsteadOfPushingIt() {
        // The shipped crash: a rep is logged (id 7 queued for push), undone
        // inside the debounce window, and the flush read `attempt.group` off
        // the now-dead row — EXC_BREAKPOINT inside SwiftData.
        let pending: Set<Int> = [7, 8]
        XCTAssertEqual(PendingPushQueue.prune(pending, deleted: [7]), [8])
    }

    func testACascadeDropsEveryRowItTookWithIt() {
        // Deleting a skill takes its whole rep history; each of those ids is
        // just as dead as the one the user asked to remove.
        let pending: Set<Int> = [1, 2, 3, 4]
        XCTAssertEqual(PendingPushQueue.prune(pending, deleted: [2, 3, 4, 99]), [1])
    }

    func testASaveWithNoDeletesLeavesTheQueueAlone() {
        let pending: Set<Int> = [1, 2]
        XCTAssertEqual(PendingPushQueue.prune(pending, deleted: []), pending)
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

/// Guards the App Review 2.1(a) rejection on 1.7 (34): Sign in with Apple
/// completed, then the app sat on the login screen. The cause was the collision
/// fallback re-sending an Apple identity token the failed link had already
/// spent — Apple's are single-use, and Firebase 10.28 attaches no updated
/// credential on the OAuth path.
final class CredentialCollisionPolicyTests: XCTestCase {
    func testAppleWithoutUpdatedCredentialAsksForAFreshOne() {
        XCTAssertEqual(
            CredentialCollisionPolicy.recovery(provider: .apple, hasUpdatedCredential: false),
            .refreshCredential,
            "Re-sending a spent Apple identity token is what dead-ended the login screen")
    }

    func testGoogleWithoutUpdatedCredentialReusesTheOriginal() {
        // Google id_tokens stay valid after a failed link, so there's no reason
        // to make the user go through the provider sheet twice.
        XCTAssertEqual(
            CredentialCollisionPolicy.recovery(provider: .google, hasUpdatedCredential: false),
            .signInWithOriginal)
    }

    func testAnUpdatedCredentialIsAlwaysPreferred() {
        for provider in [CredentialCollisionPolicy.Provider.apple, .google] {
            XCTAssertEqual(
                CredentialCollisionPolicy.recovery(provider: provider, hasUpdatedCredential: true),
                .signInWithUpdated)
        }
    }
}

/// Guards the device failure found while verifying the 2.1(a) fix:
/// "The nonce in ID Token … does not match the SHA256 hash of the raw nonce …".
/// The collision retry starts a SECOND Apple authorization, so the newest
/// pending nonce is not reliably the one the arriving token belongs to.
final class AppleIdentityTokenTests: XCTestCase {
    /// Minimal unsigned JWT — only the payload is ever parsed.
    private func token(nonceClaim: String) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["nonce": nonceClaim])
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).signature"
    }

    func testPicksTheNonceTheTokenWasMintedWithNotTheNewest() {
        let first = "nonce-from-the-original-tap"
        let second = "nonce-from-the-collision-retry"
        // Newest first, exactly how AuthViewModel stores them.
        let pending = [second, first]
        let arriving = token(nonceClaim: AppleIdentityToken.sha256(first))

        XCTAssertEqual(AppleIdentityToken.rawNonce(matching: arriving, from: pending), first,
                       "Pairing the token with the newest nonce is the on-device nonce mismatch")
    }

    func testMatchesTheNewestWhenItIsTheRightOne() {
        let first = "older"
        let second = "newest"
        let arriving = token(nonceClaim: AppleIdentityToken.sha256(second))
        XCTAssertEqual(AppleIdentityToken.rawNonce(matching: arriving, from: [second, first]), second)
    }

    func testUnreadableTokenFallsBackToNewest() {
        XCTAssertEqual(AppleIdentityToken.rawNonce(matching: "not-a-jwt", from: ["a", "b"]), "a")
    }

    func testNoMatchRatherThanAWrongPairing() {
        let arriving = token(nonceClaim: AppleIdentityToken.sha256("a-nonce-we-never-sent"))
        XCTAssertNil(AppleIdentityToken.rawNonce(matching: arriving, from: ["x", "y"]),
                     "A wrong pairing is what Firebase rejects — better to report no match")
    }
}

// MARK: - Account deletion screen

final class AccountDeletionPolicyTests: XCTestCase {
    /// The invariant the 2.1(a) rejection was about, stated once: a screen the
    /// user cannot act on is a dead end. Enumerated over `allCases` so adding a
    /// state without deciding what it offers fails here rather than in review.
    func testEveryStateLeavesSomethingToPress() {
        for step in AccountDeletionPolicy.Step.allCases {
            let actionable = AccountDeletionPolicy.showsDeleteButton(step)
                || AccountDeletionPolicy.showsEscape(step)
                || AccountDeletionPolicy.isTransient(step)
            XCTAssertTrue(actionable, "\(step) offers the user nothing")
        }
    }

    /// `working` is the sole exception, and only because it always terminates.
    func testOnlyWorkingIsAllowedToOfferNoControl() {
        for step in AccountDeletionPolicy.Step.allCases {
            let hasControl = AccountDeletionPolicy.showsDeleteButton(step)
                || AccountDeletionPolicy.showsEscape(step)
            XCTAssertEqual(hasControl, step != .working, "\(step)")
        }
    }

    func testReauthStepsOfferAnEscapeAndHideTheDeleteButton() {
        for step in [AccountDeletionPolicy.Step.needsRecentLogin, .reauthenticated] {
            XCTAssertTrue(AccountDeletionPolicy.showsEscape(step))
            XCTAssertFalse(AccountDeletionPolicy.showsDeleteButton(step),
                           "The reauth step replaces the danger zone")
        }
    }

    func testAFailedDeletionCanBeRetried() {
        XCTAssertTrue(AccountDeletionPolicy.showsDeleteButton(.failed))
        XCTAssertTrue(AccountDeletionPolicy.admitsRequest(current: .failed))
    }

    func testASecondRequestIsRefusedWhileAWalkIsLive() {
        XCTAssertFalse(AccountDeletionPolicy.admitsRequest(current: .working),
                       "The view re-enters deleteAccount on .reauthenticated")
        for step in AccountDeletionPolicy.Step.allCases where step != .working {
            XCTAssertTrue(AccountDeletionPolicy.admitsRequest(current: step), "\(step)")
        }
    }

    /// The erasure the view and the policy meet on.
    @MainActor
    func testDeletionStateMapsToItsStep() {
        XCTAssertEqual(AuthViewModel.AccountDeletion.idle.step, .idle)
        XCTAssertEqual(AuthViewModel.AccountDeletion.working.step, .working)
        XCTAssertEqual(AuthViewModel.AccountDeletion.needsRecentLogin.step, .needsRecentLogin)
        XCTAssertEqual(AuthViewModel.AccountDeletion.reauthenticated.step, .reauthenticated)
        XCTAssertEqual(AuthViewModel.AccountDeletion.failed("anything").step, .failed)
    }
}
