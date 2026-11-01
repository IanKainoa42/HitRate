import CryptoKit
import Foundation
import XCTest
@testable import HitRate

/// Decodes StuntScope's real tumble export. `Fixtures/TumbleTransfer/v1-golden.json` is recorded by
/// FlightFilter's `TumbleExchangeTests` from `TumbleExchange` and mirrored byte-for-byte here
/// (see `Fixtures/TumbleTransfer/README.md`). If the hash test fails, the copies drifted: update
/// the fixture and `goldenSHA256` in FlightFilter AND HitRate together. (IAN-612)
final class TumbleArchiveTests: XCTestCase {
    static let goldenSHA256 = "f18af990901ecd9016cbd639412d413dbe7b65c691b1f7389b4f7343a27c29b4"

    static var goldenURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/TumbleTransfer/v1-golden.json")
    }

    private func golden() throws -> Data { try Data(contentsOf: Self.goldenURL) }

    /// The fixture as a mutable JSON object, for the rejection cases.
    private func goldenObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: golden()) as? [String: Any])
    }

    func testGoldenFixtureHashIsPinned() throws {
        let hex = SHA256.hash(data: try golden()).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, Self.goldenSHA256,
                       "v1-golden.json drifted from FlightFilter's copy: update both repos together.")
    }

    func testDecodesStuntScopeExportWithExactValues() throws {
        let archive = try TumbleArchive.decode(golden())
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.recordingID, UUID(uuidString: "5A1E0000-0000-4000-8000-000000000001"))
        XCTAssertEqual(archive.recordingTitle, "RO BHS full")
        XCTAssertEqual(archive.framesPerSecond, 30)

        XCTAssertEqual(archive.blocks.count, 1)
        let block = try XCTUnwrap(archive.blocks.first)
        XCTAssertEqual(block.tagID, UUID(uuidString: "5A1E0000-0000-4000-8000-000000000002"))
        XCTAssertEqual(block.trackID, 1)
        XCTAssertEqual(block.skill, "backHandspring")
        XCTAssertEqual(block.firstFrame, 2)
        XCTAssertEqual(block.lastFrame, 5)
        XCTAssertEqual(block.reviewKey, "t1_2_5")
        XCTAssertEqual(block.launchDegrees, 62.5)

        let marks = try XCTUnwrap(block.phases?.marks)
        XCTAssertEqual(marks.count, 2)
        XCTAssertEqual(marks[0].boundary, "set")
        XCTAssertEqual(marks[0].frameIndex, 3)
        XCTAssertEqual(marks[0].status, "detected")
        XCTAssertEqual(marks[0].note, "feet left the floor")
        XCTAssertEqual(marks[1].boundary, "firstHandDown")
        XCTAssertNil(marks[1].frameIndex, "a missing boundary has no frame")
        XCTAssertEqual(marks[1].status, "missing")

        let rating = try XCTUnwrap(block.takeoffRatings.first)
        XCTAssertEqual(block.takeoffRatings.count, 1)
        XCTAssertEqual(rating.takeoffFrame, 3)
        XCTAssertEqual(rating.flip, "strong")
        XCTAssertEqual(rating.twist, "weak")
        XCTAssertEqual(rating.flipRPS, 1.5)
        XCTAssertEqual(rating.twistRPS, 0.25)

        let speed = try XCTUnwrap(block.takeoffSpeeds.first)
        XCTAssertEqual(block.takeoffSpeeds.count, 1)
        XCTAssertEqual(speed.frameIndex, 3)
        XCTAssertEqual(speed.flip, 1.5)
        XCTAssertEqual(speed.twist, 0.25)
        XCTAssertEqual(speed.flagged, false)
        XCTAssertEqual(speed.flipSamples, 6)
        XCTAssertEqual(speed.twistSamples, 4)
        XCTAssertEqual(speed.flipIsKeyed, true)
        XCTAssertEqual(speed.twistIsMarked, false)
        XCTAssertEqual(speed.airtimeSeconds, 0.0625)

        let stroke = try XCTUnwrap(block.inOutStroke)
        XCTAssertEqual(stroke.inDegrees, -24.5)
        XCTAssertEqual(stroke.outDegrees, 15.25)
        XCTAssertEqual(stroke.paintedFrames, 3)

        XCTAssertEqual(archive.poses.map(\.frameIndex), [2, 3, 4, 5])
        XCTAssertTrue(archive.poses.allSatisfy { $0.trackID == 1 })
        let pose = try XCTUnwrap(archive.poses.first)
        XCTAssertEqual(pose.skeleton.keypoints.count, 17)
        XCTAssertEqual(pose.skeleton.keypoints[0].x, 100.5)
        XCTAssertEqual(pose.skeleton.keypoints[0].y, 202)
        XCTAssertEqual(pose.skeleton.keypoints[0].confidence, 0.75)
        XCTAssertEqual(try XCTUnwrap(pose.bodyAngleDegrees), -63.434948822922, accuracy: 1e-9)
    }

    func testRejectsUnknownVersion() throws {
        var object = try goldenObject()
        object["version"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try TumbleArchive.decode(data)) { error in
            guard case TumbleArchive.ImportError.unsupported = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
        }
    }

    func testRejectsExportWithNoBlocks() throws {
        var object = try goldenObject()
        object["blocks"] = []
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try TumbleArchive.decode(data))
    }

    /// StuntScope may add fields; a v1 reader must ignore what it doesn't know.
    func testIgnoresFieldsItDoesNotRead() throws {
        var object = try goldenObject()
        object["exportedBy"] = "StuntScope 9.9"
        var blocks = try XCTUnwrap(object["blocks"] as? [[String: Any]])
        blocks[0]["futureField"] = ["a": 1]
        object["blocks"] = blocks
        let archive = try TumbleArchive.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(archive.blocks.first?.reviewKey, "t1_2_5")
    }

    /// Round trip through the coach review: an empty review keeps every value, and the review key
    /// survives a re-sync of the same video (StuntScope re-mints untagged block UUIDs).
    func testEmptyReviewRoundTripsEveryValue() throws {
        let archive = try TumbleArchive.decode(golden())
        let reviewed = archive.applying(TumbleReview())
        XCTAssertEqual(reviewed.version, archive.version)
        XCTAssertEqual(reviewed.recordingID, archive.recordingID)
        XCTAssertEqual(reviewed.blocks.map(\.reviewKey), archive.blocks.map(\.reviewKey))
        XCTAssertEqual(reviewed.blocks.first?.skill, "backHandspring")
        XCTAssertEqual(reviewed.blocks.first?.inOutStroke?.outDegrees, 15.25)
        XCTAssertEqual(reviewed.poses.map(\.frameIndex), archive.poses.map(\.frameIndex))

        var hidden = TumbleReview()
        hidden.excludedBlockKeys = ["t1_2_5"]
        let excluded = archive.applying(hidden)
        XCTAssertTrue(excluded.blocks.isEmpty)
        XCTAssertTrue(excluded.poses.isEmpty, "poses outside every visible block are dropped")
    }
}
