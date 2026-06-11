import Foundation

struct WatchRosterSnapshot: Codable, Equatable {
    var modeRaw: String
    var teamName: String
    var noun: String
    var nounPlural: String
    var groups: [WatchGroupSnapshot]
    /// The skill "pulled up" on the iPhone pad — the watch shows ONLY this
    /// bucket's outcome buttons (no picker on the wrist). Optional so old
    /// payloads still decode; nil falls back to the first group.
    var selectedGroupID: UUID?
    var activeSessionReps: Int
    var generatedAt: Date

    static func == (lhs: WatchRosterSnapshot, rhs: WatchRosterSnapshot) -> Bool {
        lhs.modeRaw == rhs.modeRaw &&
        lhs.teamName == rhs.teamName &&
        lhs.noun == rhs.noun &&
        lhs.nounPlural == rhs.nounPlural &&
        lhs.groups == rhs.groups &&
        lhs.selectedGroupID == rhs.selectedGroupID &&
        lhs.activeSessionReps == rhs.activeSessionReps
    }

    static let empty = WatchRosterSnapshot(modeRaw: "athlete",
                                           teamName: "HitRate",
                                           noun: "skill",
                                           nounPlural: "skills",
                                           groups: [],
                                           selectedGroupID: nil,
                                           activeSessionReps: 0,
                                           generatedAt: .distantPast)
}

struct WatchGroupSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var number: Int
    var kindRaw: String
    var counts: [Int]
    var outcomes: [WatchOutcomeSnapshot]

    var total: Int { counts.reduce(0, +) }
}

struct WatchOutcomeSnapshot: Codable, Equatable, Identifiable {
    var rawValue: Int
    var label: String
    var shortLabel: String

    var id: Int { rawValue }
}

struct WatchLogRequest: Codable, Equatable {
    var id: UUID
    var groupID: UUID
    var outcomeRaw: Int
    var timestamp: Date
}

enum WatchPayloadCodec {
    static let typeKey = "type"
    static let dataKey = "data"

    static let snapshotRequest = "snapshotRequest"
    static let snapshot = "snapshot"
    static let logAttempt = "logAttempt"
    static let error = "error"

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from message: [String: Any]) -> T? {
        guard let data = message[dataKey] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func message<T: Encodable>(type: String, payload: T) -> [String: Any] {
        var message: [String: Any] = [typeKey: type]
        if let data = encode(payload) { message[dataKey] = data }
        return message
    }
}
