import XCTest
import SwiftData
@testable import HitRate

final class WatchSyncTests: XCTestCase {
    private struct LegacyWatchRosterSnapshot: Encodable {
        var modeRaw: String
        var teamName: String
        var noun: String
        var nounPlural: String
        var groups: [WatchGroupSnapshot]
        var selectedGroupID: UUID?
        var activeSessionReps: Int
        var generatedAt: Date
    }

    func testWatchRosterSnapshotCodecRoundTrip() throws {
        let groupID = UUID()
        let outcomes = [
            WatchOutcomeSnapshot(rawValue: 0, label: "Hit", shortLabel: "HIT"),
            WatchOutcomeSnapshot(rawValue: 1, label: "Bobble", shortLabel: "BOB"),
            WatchOutcomeSnapshot(rawValue: 2, label: "Building fall", shortLabel: "BF"),
            WatchOutcomeSnapshot(rawValue: 3, label: "Major fall", shortLabel: "MF"),
        ]
        let group = WatchGroupSnapshot(
            id: groupID,
            name: "Full Up",
            number: 1,
            kindRaw: "stunt",
            counts: [10, 2, 1, 0],
            outcomes: outcomes
        )
        let snapshot = WatchRosterSnapshot(
            modeRaw: "coach",
            teamName: "Varsity",
            noun: "skill",
            nounPlural: "skills",
            groups: [group],
            selectedGroupID: groupID,
            activeSessionReps: 13,
            isPracticeLive: true,
            generatedAt: Date()
        )

        let message = WatchPayloadCodec.message(type: WatchPayloadCodec.snapshot, payload: snapshot)
        XCTAssertEqual(message[WatchPayloadCodec.typeKey] as? String, WatchPayloadCodec.snapshot)

        let decoded = WatchPayloadCodec.decode(WatchRosterSnapshot.self, from: message)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.teamName, "Varsity")
        XCTAssertEqual(decoded?.modeRaw, "coach")
        XCTAssertEqual(decoded?.groups.count, 1)
        XCTAssertEqual(decoded?.groups.first?.name, "Full Up")
        XCTAssertEqual(decoded?.groups.first?.counts, [10, 2, 1, 0])
        XCTAssertEqual(decoded?.activeSessionReps, 13)
        XCTAssertEqual(decoded?.isPracticeLive, true)
    }

    func testWatchLogRequestCodecRoundTrip() throws {
        let groupID = UUID()
        let request = WatchLogRequest(
            id: UUID(),
            groupID: groupID,
            outcomeRaw: 0,
            timestamp: Date()
        )

        let message = WatchPayloadCodec.message(type: WatchPayloadCodec.logAttempt, payload: request)
        XCTAssertEqual(message[WatchPayloadCodec.typeKey] as? String, WatchPayloadCodec.logAttempt)

        let decoded = WatchPayloadCodec.decode(WatchLogRequest.self, from: message)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.groupID, groupID)
        XCTAssertEqual(decoded?.outcomeRaw, 0)
    }

    func testLegacyRosterWithoutPracticeFlagDefaultsToNotLive() throws {
        let legacy = LegacyWatchRosterSnapshot(
            modeRaw: "athlete",
            teamName: "My Skills",
            noun: "skill",
            nounPlural: "skills",
            groups: [],
            selectedGroupID: nil,
            activeSessionReps: 0,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message: [String: Any] = [
            WatchPayloadCodec.typeKey: WatchPayloadCodec.snapshot,
            WatchPayloadCodec.dataKey: try JSONEncoder().encode(legacy),
        ]

        let decoded = WatchPayloadCodec.decode(WatchRosterSnapshot.self, from: message)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.isPracticeLive, false)
    }

    @MainActor
    func testRedeliveredWatchRequestOnlyWritesOneAttempt() throws {
        let schema = Schema([
            Team.self, StuntGroup.self, PracticeSession.self, Attempt.self,
            PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self,
            CustomTally.self, Subject.self, OutcomeTemplate.self, Assignment.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let team = Team(name: "Varsity", orderIndex: 0)
        let group = StuntGroup(name: "Full Up", number: 1, orderIndex: 0)
        group.team = team
        context.insert(team)
        context.insert(group)
        try context.save()

        let request = WatchLogRequest(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            groupID: group.id,
            outcomeRaw: Outcome.hit.rawValue,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let writer = WatchLogWriter(context: context)

        XCTAssertTrue(writer.log(request, groups: [group], subject: nil, loggerID: "coach"))
        XCTAssertTrue(writer.log(request, groups: [group], subject: nil, loggerID: "coach"))

        let attempts = try context.fetch(FetchDescriptor<Attempt>())
        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(attempts.first?.cloudID, "watch-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(attempts.first?.loggerID, "coach")
    }

    func testScreenshotDemoSnapshot() {
        let demo = WatchRosterSnapshot.screenshotDemo
        XCTAssertFalse(demo.groups.isEmpty)
        XCTAssertEqual(demo.teamName, "My Skills")
        XCTAssertEqual(demo.activeSessionReps, 17)
        XCTAssertEqual(demo.groups.first?.total, 17)
    }

    func testWatchConnectionStatusTitles() {
        XCTAssertEqual(WatchConnectionStatus.ready.title, "Watch ready")
        XCTAssertEqual(WatchConnectionStatus.installed.title, "Watch installed")
        XCTAssertEqual(WatchConnectionStatus.unsupported.title, "Watch unavailable")
    }
}
