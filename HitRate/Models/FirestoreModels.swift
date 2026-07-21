import Foundation
import FirebaseFirestore

// Firestore wire models for cloud sync (Feature: team sharing). These mirror the
// CURRENT SwiftData schema field-for-field, storing the same raw strings/ints the
// @Models already persist (kindRaw, categoryRaw, outcomeDefsRaw, …) so there's no
// lossy re-derivation. Push/pull is a straight upsert by stable identity:
// attempts and sessions use their cloud ids, while roster documents retain
// model UUID ids. `deletedAt` is a soft-delete tombstone that syncs like any
// other field so a delete propagates to every device.

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

struct FSession: Codable {
    @DocumentID var id: String?
    var teamId: String
    var startedAt: Date
    var endedAt: Date?
    var loggerId: String
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
    /// Added after the first sharing release. Nil decodes legacy documents;
    /// SyncSessionIdentity maps those into a stable per-team/day session.
    var sessionId: String?
    var executionScored: Bool
    var lostDriversRaw: String
    /// The Firebase uid of whoever logged this rep (team-sharing attribution).
    var loggerId: String
    var deletedAt: Date?
    var updatedAt: Date
}
