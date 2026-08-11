import XCTest
@testable import HitRate

final class WatchSyncTests: XCTestCase {
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
