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

// MARK: - Skill kind (stunt vs tumbling)

/// What kind of skill a bucket counts. Kind changes only the outcome *words*
/// ("Bobble" vs "Stepped out") — severity slots, colors, and rawValue indexing
/// are identical across kinds, so every `counts[o.rawValue]` stays valid.
/// Coach groups are stunts; athletes can mix stunt and tumbling skills.
enum SkillKind: String, CaseIterable, Identifiable {
    case stunt, tumbling

    var id: String { rawValue }
    var label: String { self == .stunt ? "Stunt" : "Tumbling" }
    var icon: String { self == .stunt ? "person.3.fill" : "figure.gymnastics" }
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
    static func labelKey(_ slot: Int, kind: SkillKind) -> String {
        kind == .stunt ? "outcomeLabel\(slot)" : "tumblingOutcomeLabel\(slot)"
    }

    func defaultLabel(_ kind: SkillKind) -> String {
        switch (kind, self) {
        case (.stunt, .hit): "Hit"
        case (.stunt, .bobble): "Bobble"
        case (.stunt, .buildingFall): "Building fall"
        case (.stunt, .majorFall): "Major fall"
        case (.tumbling, .hit): "Stuck"
        case (.tumbling, .bobble): "Stepped out"
        case (.tumbling, .buildingFall): "Touched down"
        case (.tumbling, .majorFall): "Major fall"
        }
    }

    /// Kind-free conveniences for aggregate contexts with no single bucket
    /// (prefer `label(_:)`/`short(_:)` wherever a kind is known).
    var label: String { label(.stunt) }
    var short: String { short(.stunt) }

    func label(_ kind: SkillKind) -> String {
        let custom = OutcomeNames.shared.custom(kind)[rawValue]
        return custom.isEmpty ? defaultLabel(kind) : custom
    }

    func short(_ kind: SkillKind) -> String {
        let custom = OutcomeNames.shared.custom(kind)[rawValue]
        guard !custom.isEmpty else {
            switch (kind, self) {
            case (.stunt, .hit): return "HIT"
            case (.stunt, .bobble): return "BOB"
            case (.stunt, .buildingFall): return "BF"
            case (.stunt, .majorFall): return "MF"
            case (.tumbling, .hit): return "STK"
            case (.tumbling, .bobble): return "SO"
            case (.tumbling, .buildingFall): return "TD"
            case (.tumbling, .majorFall): return "MF"
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

/// Custom outcome names (blank slot = standard name), one 4-slot set per
/// skill kind, persisted to UserDefaults. @Observable on purpose: every view
/// that renders `Outcome.label`/`short` picks up a tracked dependency just by
/// reading it in body, so renames in the editor re-render the whole app. Raw
/// UserDefaults reads are invisible to SwiftUI — that shipped stale labels
/// on the Log pad and tape legend (QA e2-1/e2-2).
@Observable
final class OutcomeNames {
    static let shared = OutcomeNames()

    var stunt: [String] {
        didSet { persist(stunt, kind: .stunt) }
    }

    var tumbling: [String] {
        didSet { persist(tumbling, kind: .tumbling) }
    }

    func custom(_ kind: SkillKind) -> [String] {
        kind == .stunt ? stunt : tumbling
    }

    private func persist(_ values: [String], kind: SkillKind) {
        for (i, v) in values.enumerated() {
            UserDefaults.standard.set(v, forKey: Outcome.labelKey(i, kind: kind))
        }
    }

    private init() {
        stunt = (0..<4).map { UserDefaults.standard.string(forKey: Outcome.labelKey($0, kind: .stunt)) ?? "" }
        tumbling = (0..<4).map { UserDefaults.standard.string(forKey: Outcome.labelKey($0, kind: .tumbling)) ?? "" }
    }
}

// MARK: - SwiftData models

@Model
final class StuntGroup {
    var name: String
    var number: Int        // badge number shown in chips/cards
    var orderIndex: Int    // display order
    var createdAt: Date
    /// Stunt vs tumbling — default keeps existing stores migrating lightweight
    /// (every pre-kind bucket was a stunt).
    var kindRaw: String = SkillKind.stunt.rawValue
    /// Deleting a group deletes its logged attempts with it — stats never see
    /// orphaned reps (which used to leak into deltas/trend but not the rate).
    @Relationship(deleteRule: .cascade, inverse: \Attempt.group)
    var attempts: [Attempt] = []

    init(name: String, number: Int, orderIndex: Int, kind: SkillKind = .stunt,
         createdAt: Date = .now) {
        self.name = name
        self.number = number
        self.orderIndex = orderIndex
        self.kindRaw = kind.rawValue
        self.createdAt = createdAt
    }

    var kind: SkillKind {
        get { SkillKind(rawValue: kindRaw) ?? .stunt }
        set { kindRaw = newValue.rawValue }
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
