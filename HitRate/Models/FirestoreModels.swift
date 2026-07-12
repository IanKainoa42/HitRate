import Foundation
import FirebaseFirestore

// Firestore wire models for cloud sync (Feature: team sharing). These mirror the
// CURRENT SwiftData schema field-for-field, storing the same raw strings/ints the
// @Models already persist (kindRaw, categoryRaw, outcomeDefsRaw, …) so there's no
// lossy re-derivation. Every doc id IS the local model's stable `id.uuidString`,
// so push/pull is a straight upsert keyed by that id. `updatedAt` drives
// last-write-wins; `deletedAt` is a soft-delete tombstone that syncs like any
// other field (so a delete propagates to every device).

struct FTeam: Codable {
    @DocumentID var id: String?
    var name: String
    var ownerUID: String
    var memberIds: [String]
    var orderIndex: Int
    var itemNoun: String
    var joinCode: String?
    var deletedAt: Date?
    var updatedAt: Date
}

struct FSubject: Codable {
    @DocumentID var id: String?
    var teamId: String
    var name: String
    var kindRaw: String
    var orderIndex: Int
    var deletedAt: Date?
    var updatedAt: Date
}

struct FGroup: Codable {
    @DocumentID var id: String?
    var teamId: String
    var name: String
    var number: Int
    var orderIndex: Int
    var kindRaw: String
    var categoryRaw: String
    var typeLabelRaw: String
    var outcomeDefsRaw: String
    var outcomeOverridesRaw: String
    var deletedAt: Date?
    var updatedAt: Date
}

struct FTemplate: Codable {
    @DocumentID var id: String?
    var teamId: String
    var name: String
    var defsRaw: String
    var orderIndex: Int
    var updatedAt: Date
}

struct FAttempt: Codable {
    @DocumentID var id: String?
    var teamId: String
    var groupId: String
    var subjectId: String?
    var outcomeRaw: Int
    var timestamp: Date
    var waveID: String?
    var executionScored: Bool
    var lostDriversRaw: String
    /// The Firebase uid of whoever logged this rep (team-sharing attribution).
    var loggerId: String
    var updatedAt: Date
}
