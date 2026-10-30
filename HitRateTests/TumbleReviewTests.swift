import Foundation
import XCTest
@testable import HitRate

final class TumbleReviewTests: XCTestCase {
    func testExcludedBlockAndItsPoseFramesLeaveReviewedArchive() throws {
        let json = """
        {
          "version": 1,
          "recordingID": "C934B11A-6290-4F1E-8EF5-C86DF630F145",
          "recordingTitle": "Roundoff back handspring",
          "framesPerSecond": 30,
          "blocks": [
            {"tagID":"A0000000-0000-0000-0000-000000000001","trackID":7,"skill":"unclassified","firstFrame":10,"lastFrame":20,"takeoffRatings":[],"takeoffSpeeds":[]},
            {"tagID":"A0000000-0000-0000-0000-000000000002","trackID":7,"skill":"unclassified","firstFrame":30,"lastFrame":40,"takeoffRatings":[],"takeoffSpeeds":[]}
          ],
          "poses": [
            {"frameIndex":15,"trackID":7,"skeleton":{"keypoints":[]}},
            {"frameIndex":35,"trackID":7,"skeleton":{"keypoints":[]}}
          ]
        }
        """
        let raw = try TumbleArchive.decode(Data(json.utf8))
        var review = TumbleReview()
        review.excludedBlockKeys.insert(raw.blocks[0].reviewKey)
        review.skillOverrides[raw.blocks[1].reviewKey] = "Back handspring"

        let reviewed = raw.applying(review)
        XCTAssertEqual(reviewed.blocks.count, 1)
        XCTAssertEqual(reviewed.blocks.first?.skill, "Back handspring")
        XCTAssertEqual(reviewed.poses.map(\.frameIndex), [35])
        XCTAssertEqual(raw.blocks.count, 2, "Review must leave the raw StuntScope data intact")

        review.hiddenRecording = true
        XCTAssertTrue(raw.applying(review).blocks.isEmpty)
        XCTAssertTrue(raw.applying(review).poses.isEmpty)
    }
}
