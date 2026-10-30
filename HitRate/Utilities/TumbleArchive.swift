import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// StuntScope's versioned, per-recording tumble analysis. It normally arrives through the
/// shared HitRate account; the file importer remains for older exports.
struct TumbleArchive: Decodable {
    struct Block: Decodable {
        struct Phases: Decodable {
            struct Mark: Decodable {
                let boundary: String
                let frameIndex: Int?
                let status: String
            }
            let marks: [Mark]?
        }
        struct Rating: Decodable {
            let takeoffFrame: Int
            let flipRPS: Double?
            let twistRPS: Double?
            let flip: String?
            let twist: String?
        }
        struct Speed: Decodable {
            let frameIndex: Int
            let flip: Double?
            let twist: Double?
        }
        struct Stroke: Decodable {
            let inDegrees: Double
            let outDegrees: Double
            let paintedFrames: Int
        }
        let tagID: UUID
        let trackID: Int
        let skill: String
        let firstFrame: Int
        let lastFrame: Int
        let phases: Phases?
        let takeoffRatings: [Rating]
        let takeoffSpeeds: [Speed]
        let inOutStroke: Stroke?
        let launchDegrees: Double?
    }
    let version: Int
    let recordingID: UUID
    let recordingTitle: String
    let framesPerSecond: Double
    let blocks: [Block]
    struct PoseFrame: Decodable {
        struct Skeleton: Decodable {
            struct Joint: Decodable { let x: Double; let y: Double; let confidence: Double }
            let keypoints: [Joint]
        }
        let frameIndex: Int
        let trackID: Int
        let skeleton: Skeleton
        let bodyAngleDegrees: Double?
    }
    let poses: [PoseFrame]

    static func importFile(_ source: URL) throws -> TumbleArchive {
        let data = try Data(contentsOf: source)
        let archive = try decode(data)
        let directory = storeDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(archive.recordingID.uuidString + ".json"), options: .atomic)
        return archive
    }

    static func decode(_ data: Data) throws -> TumbleArchive {
        let archive = try JSONDecoder().decode(TumbleArchive.self, from: data)
        guard archive.version == 1, !archive.blocks.isEmpty else { throw ImportError.unsupported }
        return archive
    }

    static func all() -> [TumbleArchive] {
        let files = (try? FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(TumbleArchive.self, from: data)
        }
    }

    private static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TumbleArchives", isDirectory: true)
    }
    enum ImportError: LocalizedError {
        case unsupported
        var errorDescription: String? { "This tumble file is empty or uses an unsupported format." }
    }
}

struct TumbleSpreadsheet: Transferable {
    let archives: [TumbleArchive]
    let athleteIDs: [String: String]
    let athleteNamesByID: [String: String]
    var hasData: Bool { archives.contains { !$0.blocks.isEmpty } }

    private func write() throws -> URL {
        let header = ["video", "athlete", "skill", "start_second", "end_second", "in_deg", "out_deg", "contact_frames", "launch_deg", "phase_marks", "flip_rps", "twist_rps", "flip_rating", "twist_rating"]
        var lines = [header.map(Self.field).joined(separator: ",")]
        for archive in archives.sorted(by: { $0.recordingTitle < $1.recordingTitle }) {
            for block in archive.blocks.sorted(by: { $0.firstFrame < $1.firstFrame }) {
                let fps = archive.framesPerSecond
                let ratings = block.takeoffRatings.sorted { $0.takeoffFrame < $1.takeoffFrame }
                let marks = (block.phases?.marks ?? []).map { "\($0.boundary):\($0.frameIndex.map(String.init) ?? "?")(\($0.status))" }.joined(separator: " | ")
                let first = ratings.first
                let speed = block.takeoffSpeeds.sorted { $0.frameIndex < $1.frameIndex }.first
                let key = "\(archive.recordingID.uuidString):\(block.trackID)"
                let athlete = athleteIDs[key].flatMap { athleteNamesByID[$0] } ?? "Track \(block.trackID)"
                let start = fps > 0 ? String(format: "%.3f", Double(block.firstFrame) / fps) : ""
                let end = fps > 0 ? String(format: "%.3f", Double(block.lastFrame) / fps) : ""
                let inAngle = block.inOutStroke.map { String($0.inDegrees) } ?? ""
                let outAngle = block.inOutStroke.map { String($0.outDegrees) } ?? ""
                let contact = block.inOutStroke.map { String($0.paintedFrames) } ?? ""
                let launch = block.launchDegrees.map { String($0) } ?? ""
                let flipRate = (speed?.flip ?? first?.flipRPS).map { String($0) } ?? ""
                let twistRate = (speed?.twist ?? first?.twistRPS).map { String($0) } ?? ""
                let row: [String] = [archive.recordingTitle, athlete, block.skill, start, end,
                                     inAngle, outAngle, contact, launch, marks, flipRate, twistRate,
                                     first?.flip ?? "", first?.twist ?? ""]
                lines.append(row.map(Self.field).joined(separator: ","))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HitRate-Tumbling-Blocks.csv")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func field(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(where: { ",\"\n\r".contains($0) }) ? "\"\(escaped)\"" : escaped
    }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { SentTransferredFile(try $0.write()) }
    }
}

/// Detailed frame table for spreadsheet analysis. Joint indices follow StuntScope's 21-point
/// schema; each row retains the clip and athlete mapping instead of flattening bodies together.
struct TumblePoseSpreadsheet: Transferable {
    let archives: [TumbleArchive]
    let athleteIDs: [String: String]
    let athleteNamesByID: [String: String]
    var hasData: Bool { archives.contains { !$0.poses.isEmpty } }

    private func write() throws -> URL {
        var lines = ["video,athlete,track_in_video,second,frame,joint_index,x_px,y_px,confidence,body_angle_deg"]
        for archive in archives {
            for pose in archive.poses {
                let key = "\(archive.recordingID.uuidString):\(pose.trackID)"
                let athlete = athleteIDs[key].flatMap { athleteNamesByID[$0] } ?? "Track \(pose.trackID)"
                let second = archive.framesPerSecond > 0 ? String(Double(pose.frameIndex) / archive.framesPerSecond) : ""
                for (jointIndex, joint) in pose.skeleton.keypoints.enumerated() {
                    let values = [archive.recordingTitle, athlete, String(pose.trackID), second,
                                  String(pose.frameIndex), String(jointIndex), String(joint.x),
                                  String(joint.y), String(joint.confidence),
                                  pose.bodyAngleDegrees.map { String($0) } ?? ""]
                    lines.append(values.map(Self.field).joined(separator: ","))
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HitRate-Tumbling-Pose-Frames.csv")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private static func field(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(where: { ",\"\n\r".contains($0) }) ? "\"\(escaped)\"" : escaped
    }
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { SentTransferredFile(try $0.write()) }
    }
}
