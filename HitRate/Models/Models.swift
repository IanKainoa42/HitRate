import Foundation
import SwiftData
import SwiftUI

// MARK: - Outcome (the core domain enum)

enum Outcome: Int, Codable, CaseIterable, Identifiable {
    case hit = 0
    case bobble = 1
    case buildingFall = 2
    case majorFall = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hit: "Hit"
        case .bobble: "Bobble"
        case .buildingFall: "Building fall"
        case .majorFall: "Major fall"
        }
    }

    var short: String {
        switch self {
        case .hit: "HIT"
        case .bobble: "BOB"
        case .buildingFall: "BF"
        case .majorFall: "MF"
        }
    }

    var isHit: Bool { self == .hit }

    var color: Color {
        switch self {
        case .hit: Theme.hit
        case .bobble: Theme.bobble
        case .buildingFall: Theme.buildingFall
        case .majorFall: Theme.majorFall
        }
    }
}

// MARK: - SwiftData models

@Model
final class StuntGroup {
    var name: String
    var number: Int        // badge number shown in chips/cards
    var orderIndex: Int    // display order
    var createdAt: Date

    init(name: String, number: Int, orderIndex: Int, createdAt: Date = .now) {
        self.name = name
        self.number = number
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    /// Group identity color — formation rainbow, cycled by number.
    var color: Color { Theme.groupColor((number - 1) % Theme.groupRainbow.count) }
}

@Model
final class PracticeSession {
    var startedAt: Date
    var endedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Attempt.session)
    var attempts: [Attempt] = []

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    var sortedAttempts: [Attempt] {
        attempts.sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class Attempt {
    var timestamp: Date
    var outcomeRaw: Int
    var group: StuntGroup?
    var session: PracticeSession?

    init(outcome: Outcome, group: StuntGroup?, session: PracticeSession?, timestamp: Date = .now) {
        self.outcomeRaw = outcome.rawValue
        self.group = group
        self.session = session
        self.timestamp = timestamp
    }

    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .hit }
}
