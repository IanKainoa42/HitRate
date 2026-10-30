import FirebaseAuth
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
        let loggerID: String
        let review: TumbleReview
        let updatedAt: Date

        var reviewedArchive: TumbleArchive { archive.applying(review) }
    }

    static func load(teamID: String) async throws -> [Recording] {
        let team = Firestore.firestore().collection("teams").document(teamID)
        async let manifests = team.collection("tumbles").getDocuments()
        async let reviews = team.collection("tumbleEdits").getDocuments()
        let snapshot = try await manifests
        let reviewDocuments = try await reviews
        let reviewsByID = Dictionary(uniqueKeysWithValues: reviewDocuments.documents.map { ($0.documentID, $0.data()) })
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
            let reviewFields = reviewsByID[document.documentID] ?? [:]
            let review = TumbleReview(
                excludedBlockKeys: Set(reviewFields["excludedBlockKeys"] as? [String] ?? []),
                skillOverrides: reviewFields["skillOverrides"] as? [String: String] ?? [:],
                hiddenRecording: reviewFields["hiddenRecording"] as? Bool ?? false)
            let updatedAt = (fields["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
            recordings.append(Recording(archive: archive, athleteIDs: mapping,
                loggerID: fields["loggerId"] as? String ?? "", review: review, updatedAt: updatedAt))
        }
        return recordings.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func saveReview(teamID: String, recordingID: UUID, review: TumbleReview) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ReviewError.signedOut }
        let fields: [String: Any] = [
            "editorId": uid,
            "excludedBlockKeys": Array(review.excludedBlockKeys).sorted(),
            "skillOverrides": review.skillOverrides,
            "hiddenRecording": review.hiddenRecording,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        let reference = Firestore.firestore().collection("teams").document(teamID)
            .collection("tumbleEdits").document(recordingID.uuidString)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.setData(fields) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    enum ReviewError: LocalizedError {
        case signedOut
        var errorDescription: String? { "Sign in to review this recording." }
    }
}
