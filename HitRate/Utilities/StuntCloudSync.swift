import FirebaseFirestore
import FirebaseStorage
import Foundation

/// StuntScope stability data is kept outside `attempts`, so it cannot change hit rates.
enum StuntCloudSync {
    struct Analysis: Identifiable {
        let id: UUID
        let title: String
        let skillID: String
        let stuntGroupID: String?
        let athleteIDs: [String]
        let rolesRaw: String
        let onBasePercent: Int
        let holdSeconds: Double
        let wobbleCount: Int
        let worstWobbleSecond: Double?
        let flightSeconds: [Double]
        let framesPath: String
        let updatedAt: Date
    }

    struct FrameArchive: Decodable {
        struct Frame: Decodable {
            let i: Int
            let t: Double
            let s: String
            let m: Double
            let com: [Double]
            let drop: [Double]
            let span: [[Double]]
        }
        let version: Int
        let fps: Double
        let frameWidth: Int
        let frameHeight: Int
        let frames: [Frame]
    }

    static func load(teamID: String) async throws -> [Analysis] {
        let snapshot = try await Firestore.firestore().collection("teams").document(teamID)
            .collection("stuntAnalyses").getDocuments()
        return snapshot.documents.compactMap { document in
            decode(documentID: document.documentID, fields: document.data(), teamID: teamID)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func decode(documentID: String, fields: [String: Any], teamID: String) -> Analysis? {
            guard fields["ready"] as? Bool == true,
                  let id = UUID(uuidString: documentID),
                  let path = fields["framesPath"] as? String,
                  path == "teams/\(teamID)/stuntAnalyses/\(id.uuidString)/frames.json",
                  let title = fields["recordingTitle"] as? String,
                  let skillID = fields["skillId"] as? String,
                  let onBase = fields["onBasePercent"] as? Int,
                  let hold = fields["holdSeconds"] as? Double,
                  let wobbles = fields["wobbleCount"] as? Int else { return nil }
            return Analysis(id: id, title: title, skillID: skillID,
                stuntGroupID: fields["stuntGroupId"] as? String,
                athleteIDs: fields["athleteIds"] as? [String] ?? [],
                rolesRaw: fields["rolesRaw"] as? String ?? "",
                onBasePercent: onBase, holdSeconds: hold, wobbleCount: wobbles,
                worstWobbleSecond: fields["worstWobbleSecond"] as? Double,
                flightSeconds: fields["flightSeconds"] as? [Double] ?? [],
                framesPath: path,
                updatedAt: (fields["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast)
    }

    static func frames(for analysis: Analysis) async throws -> FrameArchive {
        let reference = Storage.storage().reference(withPath: analysis.framesPath)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            reference.getData(maxSize: 100 * 1024 * 1024) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        let archive = try JSONDecoder().decode(FrameArchive.self, from: data)
        guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return archive
    }
}
