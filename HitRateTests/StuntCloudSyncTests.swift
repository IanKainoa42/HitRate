import CryptoKit
import FirebaseFirestore
import XCTest
@testable import HitRate

/// Decodes StuntScope's stats-only stunt export from `Fixtures/StuntAnalysis` (IAN-618).
/// The same doc is pushed through the Firestore rules emulator in `firestore.rules.test.mjs`.
final class StuntCloudSyncTests: XCTestCase {
    static let docSHA256 = "56f21f247a86ff342a0473beba21e1c9375bc51afeb37204f9f29658919f5b89"
    static let framesSHA256 = "62699d997a83adb7c16c53ed6afee0ae854c89dac1d2925e3b11525f5da5503a"
    static let id = "A934B11A-6290-4F1E-8EF5-C86DF630F145"
    static let team = "3DDA7E8A-091D-4B62-A0AA-56DB2521E300"

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/StuntAnalysis/\(name)"))
    }

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The doc as Firestore hands it back: `updatedAt` becomes a `Timestamp`.
    private func goldenFields() throws -> [String: Any] {
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(
            with: fixture("v1-golden-doc.json")) as? [String: Any])
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: fields["updatedAt"] as? String ?? ""))
        fields["updatedAt"] = Timestamp(date: date)
        return fields
    }

    func testGoldenFixtureHashesArePinned() throws {
        XCTAssertEqual(sha(try fixture("v1-golden-doc.json")), Self.docSHA256)
        XCTAssertEqual(sha(try fixture("v1-golden-frames.json")), Self.framesSHA256)
    }

    func testDecodesGoldenManifestWithExactValues() throws {
        let a = try XCTUnwrap(StuntCloudSync.decode(documentID: Self.id,
                                                    fields: try goldenFields(), teamID: Self.team))
        XCTAssertEqual(a.id, UUID(uuidString: Self.id))
        XCTAssertEqual(a.title, "Full up hold")
        XCTAssertEqual(a.skillID, "0B0F2A56-9F4D-4B23-9B5B-2D30F0E7A111")
        XCTAssertEqual(a.stuntGroupID, "6E2F4C10-2222-4B33-8D44-ABCDEF012345")
        XCTAssertEqual(a.athleteIDs.count, 2)
        XCTAssertEqual(a.rolesRaw.split(separator: "\n").count, 2)
        XCTAssertEqual(a.onBasePercent, 82)
        XCTAssertEqual(a.holdSeconds, 3.4)
        XCTAssertEqual(a.wobbleCount, 1)
        XCTAssertEqual(a.worstWobbleSecond, 1.2)
        XCTAssertEqual(a.flightSeconds, [0.4])
        XCTAssertEqual(a.updatedAt, Date(timeIntervalSince1970: 1_793_664_000))
    }

    func testManifestRejections() throws {
        let fields = try goldenFields()
        func decode(_ f: [String: Any], team: String = Self.team) -> StuntCloudSync.Analysis? {
            StuntCloudSync.decode(documentID: Self.id, fields: f, teamID: team)
        }
        XCTAssertNil(decode(fields.merging(["ready": false]) { $1 }))
        XCTAssertNil(decode(fields, team: "OTHER"))
        XCTAssertNil(decode(fields.merging(["framesPath": "teams/OTHER/frames.json"]) { $1 }))
        // A writer type change (Int -> Double) must fail loudly here, not silently drop the card.
        XCTAssertNil(decode(fields.merging(["onBasePercent": 82.5]) { $1 }))
        for key in ["onBasePercent", "holdSeconds", "wobbleCount", "skillId", "recordingTitle"] {
            var missing = fields
            missing[key] = nil
            XCTAssertNil(decode(missing), "missing \(key)")
        }
    }

    func testDecodesGoldenFramesIncludingWobblesAndFlights() throws {
        let archive = try StuntCloudSync.FrameArchive.decode(fixture("v1-golden-frames.json"))
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.fps, 30)
        XCTAssertEqual(archive.frameWidth, 1920)
        XCTAssertEqual(archive.frameHeight, 1080)
        XCTAssertEqual(archive.frames.count, 2)
        XCTAssertEqual(archive.frames[0].i, 7)
        XCTAssertEqual(archive.frames[0].s, "edge")
        XCTAssertEqual(archive.frames[0].com, [100.3, 200.7])
        XCTAssertEqual(archive.frames[0].span, [[90, 300], [130, 300]])
        let wobble = try XCTUnwrap(archive.wobbles?.first)
        XCTAssertEqual([wobble.start, wobble.end], [7, 9])
        XCTAssertEqual(wobble.peakMargin, 0.05)
        let flight = try XCTUnwrap(archive.flights?.first)
        XCTAssertEqual(flight.release, 7)
        XCTAssertEqual(flight.catchFrame, 19)
    }

    func testUnsupportedFramesVersionIsRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: fixture("v1-golden-frames.json")) as? [String: Any])
        object["version"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try StuntCloudSync.FrameArchive.decode(data))
    }
}
