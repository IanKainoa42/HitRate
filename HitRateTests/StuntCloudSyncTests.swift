import FirebaseFirestore
import XCTest
@testable import HitRate

final class StuntCloudSyncTests: XCTestCase {
    func testStuntScopeManifestAndFramesDecodeWithoutOutcome() throws {
        let id = "A934B11A-6290-4F1E-8EF5-C86DF630F145"
        let team = "TEAM"
        let fields: [String: Any] = [
            "ready": true, "recordingTitle": "Full up hold", "skillId": "SKILL",
            "onBasePercent": 82, "holdSeconds": 3.4, "wobbleCount": 1,
            "athleteIds": ["ATHLETE"], "rolesRaw": "flyer=ATHLETE",
            "framesPath": "teams/TEAM/stuntAnalyses/\(id)/frames.json",
            "updatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_000))
        ]
        let analysis = try XCTUnwrap(StuntCloudSync.decode(documentID: id, fields: fields, teamID: team))
        XCTAssertEqual(analysis.title, "Full up hold")
        XCTAssertEqual(analysis.onBasePercent, 82)
        XCTAssertEqual(analysis.athleteIDs, ["ATHLETE"])
        XCTAssertNil(StuntCloudSync.decode(documentID: id,
            fields: fields.merging(["ready": false]) { _, new in new }, teamID: team))
        XCTAssertNil(StuntCloudSync.decode(documentID: id,
            fields: fields.merging(["framesPath": "teams/OTHER/frames.json"]) { _, new in new }, teamID: team))

        let data = Data(#"{"version":1,"fps":30,"frameWidth":1920,"frameHeight":1080,"frames":[{"i":7,"t":0.233,"s":"edge","m":0.123,"com":[100.3,200.7],"drop":[101.1,300],"span":[[90,300],[130,300]]}]}"#.utf8)
        let archive = try JSONDecoder().decode(StuntCloudSync.FrameArchive.self, from: data)
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.frames.count, 1)
        XCTAssertEqual(archive.frames[0].com, [100.3, 200.7])
    }
}
