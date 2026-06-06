import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: - App mode (athlete-first vs coach)

/// Who's counting. Athlete mode tracks self-created skills; coach mode tracks
/// stunt groups. Both store buckets as StuntGroup — mode only changes language
/// and whose name goes on the share cards.
enum AppMode: String {
    case athlete, coach

    var noun: String { self == .athlete ? "skill" : "group" }
    var nounPlural: String { self == .athlete ? "skills" : "groups" }
    var nounTitle: String { self == .athlete ? "Skill" : "Group" }
    var nounPluralTitle: String { self == .athlete ? "Skills" : "Groups" }

    /// For non-view code (CSV export). Views should observe @AppStorage("appMode").
    static var current: AppMode {
        AppMode(rawValue: UserDefaults.standard.string(forKey: "appMode") ?? "") ?? .athlete
    }
}

// MARK: - Outcome (the core domain enum)

enum Outcome: Int, Codable, CaseIterable, Identifiable {
    case hit = 0
    case bobble = 1
    case buildingFall = 2
    case majorFall = 3

    var id: Int { rawValue }

    /// UserDefaults key for the user's custom name of this outcome slot.
    /// Severity order and colors are fixed — only the words are renameable.
    static func labelKey(_ slot: Int) -> String { "outcomeLabel\(slot)" }

    var defaultLabel: String {
        switch self {
        case .hit: "Hit"
        case .bobble: "Bobble"
        case .buildingFall: "Building fall"
        case .majorFall: "Major fall"
        }
    }

    var label: String {
        let custom = OutcomeNames.shared.custom[rawValue]
        return custom.isEmpty ? defaultLabel : custom
    }

    var short: String {
        let custom = OutcomeNames.shared.custom[rawValue]
        guard !custom.isEmpty else {
            switch self {
            case .hit: return "HIT"
            case .bobble: return "BOB"
            case .buildingFall: return "BF"
            case .majorFall: return "MF"
            }
        }
        // Derive: initials for multi-word names ("Touch down" → TD),
        // first 3 letters otherwise ("Drop" → DRO).
        let words = custom.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(3).compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(custom.prefix(3)).uppercased()
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

// MARK: - Outcome rename store

/// Custom outcome names (blank slot = standard name), persisted to
/// UserDefaults. @Observable on purpose: every view that renders
/// `Outcome.label`/`short` picks up a tracked dependency just by reading it
/// in body, so renames in the editor re-render the whole app. Raw
/// UserDefaults reads are invisible to SwiftUI — that shipped stale labels
/// on the Log pad and tape legend (QA e2-1/e2-2).
@Observable
final class OutcomeNames {
    static let shared = OutcomeNames()

    var custom: [String] {
        didSet {
            for (i, v) in custom.enumerated() {
                UserDefaults.standard.set(v, forKey: Outcome.labelKey(i))
            }
        }
    }

    private init() {
        custom = (0..<4).map { UserDefaults.standard.string(forKey: Outcome.labelKey($0)) ?? "" }
    }
}

// MARK: - SwiftData models

@Model
final class StuntGroup {
    var name: String
    var number: Int        // badge number shown in chips/cards
    var orderIndex: Int    // display order
    var createdAt: Date
    /// Deleting a group deletes its logged attempts with it — stats never see
    /// orphaned reps (which used to leak into deltas/trend but not the rate).
    @Relationship(deleteRule: .cascade, inverse: \Attempt.group)
    var attempts: [Attempt] = []

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
