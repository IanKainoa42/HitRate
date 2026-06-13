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

/// A roster the user tracks separately — a coach's squad or an athlete's
/// gym/team. Each team owns its own buckets and therefore its own stats, cups,
/// and league; the program/org identity is shared app-wide (AppStorage).
@Model
final class Team {
    /// Stable id used to remember the active team in @AppStorage("currentTeamID").
    /// Unique by generation; not a SwiftData unique constraint (avoids upsert
    /// surprises on a freshly added entity).
    var id: UUID = UUID()
    var name: String
    var orderIndex: Int
    var createdAt: Date
    /// Deleting a team takes its roster with it (and each group cascades its
    /// own logged reps) — the team's whole history goes.
    @Relationship(deleteRule: .cascade, inverse: \StuntGroup.team)
    var groups: [StuntGroup] = []

    init(name: String, orderIndex: Int, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }
}

@Model
final class StuntGroup {
    /// Stable cross-device id used by the watch companion. SwiftData's
    /// persistent id is store-local and not a good wire format.
    var id: UUID = UUID()
    var name: String
    var number: Int        // badge number shown in chips/cards
    var orderIndex: Int    // display order
    var createdAt: Date
    /// Stunt vs tumbling — default keeps existing stores migrating lightweight
    /// (every pre-kind bucket was a stunt).
    var kindRaw: String = SkillKind.stunt.rawValue
    /// The team/roster this bucket belongs to. Optional so single-team stores
    /// migrate lightweight; RootView assigns teamless groups to a default team
    /// on launch.
    var team: Team?
    /// Deleting a group deletes its logged attempts with it — stats never see
    /// orphaned reps (which used to leak into deltas/trend but not the rate).
    @Relationship(deleteRule: .cascade, inverse: \Attempt.group)
    var attempts: [Attempt] = []

    init(name: String, number: Int, orderIndex: Int, kind: SkillKind = .stunt,
         id: UUID = UUID(),
         createdAt: Date = .now) {
        self.id = id
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
    /// Reps committed together as one wave/routine share a `waveID`; reps logged
    /// one at a time (pad or immediate grid) leave it nil. Drives the grouped
    /// container in the practice log. Optional → additive lightweight migration.
    var waveID: UUID?

    init(outcome: Outcome, group: StuntGroup?, session: PracticeSession?, timestamp: Date = .now, waveID: UUID? = nil) {
        self.outcomeRaw = outcome.rawValue
        self.group = group
        self.session = session
        self.timestamp = timestamp
        self.waveID = waveID
    }

    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .hit }
}

// MARK: - Team scoping helpers

extension Array where Element == Team {
    /// The active team for a stored `currentTeamID` (uuidString), falling back
    /// to the first team. Nil only when there are no teams at all.
    func current(id: String) -> Team? {
        first { $0.id.uuidString == id } ?? first
    }
}

extension Array where Element == StuntGroup {
    /// The buckets belonging to one team, in display order. With no team yet
    /// (pre-migration), every bucket shows — RootView assigns them to a default
    /// team momentarily.
    func inTeam(_ team: Team?) -> [StuntGroup] {
        let scoped = team.map { t in filter { $0.team?.id == t.id } } ?? self
        return scoped.sorted { $0.orderIndex < $1.orderIndex }
    }
}

// MARK: - Unlocked Milestones

/// A collectible milestone variation earned by the user.
/// Since the core milestone stats are calculated purely on the fly, this model
/// simply saves the fact that a user unlocked a specific milestone, and which
/// of the 4 visual variants they randomly received, so their collection is stable.
@Model
final class UnlockedMilestone {
    var milestoneID: String
    var variantIndex: Int
    var unlockedAt: Date
    
    init(milestoneID: String, variantIndex: Int, unlockedAt: Date = .now) {
        self.milestoneID = milestoneID
        self.variantIndex = variantIndex
        self.unlockedAt = unlockedAt
    }
}
