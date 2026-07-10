import Foundation
import FirebaseFirestore

struct FTeam: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var ownerId: String
    var memberIds: [String]?
    var orderIndex: Int
    var joinCode: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId
        case memberIds
        case orderIndex
        case joinCode
    }
}

struct FStuntGroup: Codable, Identifiable {
    @DocumentID var id: String?
    var teamId: String
    var name: String
    var number: Int
    var orderIndex: Int
    var kindRaw: String // Matches SkillKind.rawValue
    var deletedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case teamId
        case name
        case number
        case orderIndex
        case kindRaw
        case deletedAt
    }
}

struct FAttempt: Codable, Identifiable {
    @DocumentID var id: String?
    var groupId: String
    var teamId: String
    var outcomeRaw: Int // Matches Outcome.rawValue
    var timestamp: Date
    var loggerId: String // The user who logged it
    
    enum CodingKeys: String, CodingKey {
        case id
        case groupId
        case teamId
        case outcomeRaw
        case timestamp
        case loggerId
    }
}
