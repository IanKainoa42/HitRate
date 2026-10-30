import FirebaseFirestore
import FirebaseStorage
import Foundation

/// Pulls StuntScope's completed analyses from the same Firebase folder used for
/// stability reps. The manifest names real HitRate athletes; the detailed data
/// stays in Storage because pose frames can exceed Firestore's document limit.
enum TumbleCloudSync {
    struct Recording {
        let archive: TumbleArchive
        let athleteIDs: [String: String]
        let updatedAt: Date
    }

    static func load(teamID: String) async throws -> [Recording] {
        let snapshot = try await Firestore.firestore().collection("teams").document(teamID)
            .collection("tumbles").getDocuments()
        var recordings: [Recording] = []
        for document in snapshot.documents {
            let fields = document.data()
            guard fields["ready"] as? Bool == true,
                  let recordingID = UUID(uuidString: document.documentID),
                  let path = fields["storagePath"] as? String,
                  path == "teams/\(teamID)/tumbles/\(recordingID.uuidString)/analysis.json" else { continue }
            let reference = Storage.storage().reference(withPath: path)
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                reference.getData(maxSize: 100 * 1024 * 1024) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
                }
            }
            let archive = try TumbleArchive.decode(data)
            guard archive.recordingID == recordingID else { continue }
            let mapping = fields["athleteIDs"] as? [String: String] ?? [:]
            let updatedAt = (fields["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            recordings.append(Recording(archive: archive, athleteIDs: mapping, updatedAt: updatedAt))
        }
        return recordings.sorted { $0.updatedAt > $1.updatedAt }
    }
}
