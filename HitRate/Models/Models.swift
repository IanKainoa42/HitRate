import Foundation
import Observation
import SwiftData
import SwiftUI
import CheerRulesKit

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

// MARK: - Skill category (United Scoring System)

/// `SkillCategory` (CheerRulesKit) is the United score-sheet classification a
/// skill belongs to — it carries the execution drivers. The legacy `SkillKind`
/// (stunt/tumbling) stays the *outcome-wording* axis; a category maps onto it so
/// every existing `Outcome.label(_:)`/`OutcomeNames` read keeps working.
extension SkillCategory {
    var hitRateKind: SkillKind {
        switch self {
        case .standingTumbling, .runningTumbling: return .tumbling
        default: return .stunt
        }
    }

    /// A distinct SF Symbol per category (all verified to exist — note
    /// figure.cheerleading does NOT, per the project gotchas).
    var icon: String {
        switch self {
        case .stunts: return "person.3.fill"
        case .pyramid: return "triangle.fill"
        case .tosses: return "arrow.up.circle.fill"
        case .jumps: return "figure.jumprope"
        case .standingTumbling: return "figure.gymnastics"
        case .runningTumbling: return "figure.run"
        }
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
    /// What this folder calls its buckets — "athlete", "skill", "group",
    /// "driver"… Blank (default) = fall back to the global `AppMode` noun, so
    /// existing stores migrate lightweight. Stored singular + lowercase; the
    /// `noun(for:)` helpers derive plural/title forms.
    var itemNoun: String = ""
    /// Deleting a team takes its roster with it (and each group cascades its
    /// own logged reps) — the team's whole history goes.
    @Relationship(deleteRule: .cascade, inverse: \StuntGroup.team)
    var groups: [StuntGroup] = []
    /// User-created extra outcomes this folder tracks (alongside the locked 4).
    /// Deleting the folder removes them (and each cascades its tallies).
    @Relationship(deleteRule: .cascade, inverse: \CustomOutcome.team)
    var customOutcomes: [CustomOutcome] = []

    init(name: String, orderIndex: Int, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    // MARK: Bucket noun — per-folder override of AppMode's wording.
    // Every view that labels buckets should read these (not `mode.noun`
    // directly) so one folder can track "athletes" and another "skills".

    private var customNoun: String? {
        let t = itemNoun.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t.lowercased()
    }

    func noun(for mode: AppMode) -> String { customNoun ?? mode.noun }

    func nounPlural(for mode: AppMode) -> String {
        guard let n = customNoun else { return mode.nounPlural }
        return n.hasSuffix("s") ? n : n + "s"
    }

    func nounTitle(for mode: AppMode) -> String { noun(for: mode).capitalized }
    func nounPluralTitle(for mode: AppMode) -> String { nounPlural(for: mode).capitalized }
}

extension Optional where Wrapped == Team {
    /// Bucket noun for an optional active team — folder override when present,
    /// else the global AppMode noun. Lets views read one call regardless of
    /// whether a team is resolved yet.
    func noun(for mode: AppMode) -> String { self?.noun(for: mode) ?? mode.noun }
    func nounPlural(for mode: AppMode) -> String { self?.nounPlural(for: mode) ?? mode.nounPlural }
    func nounTitle(for mode: AppMode) -> String { self?.nounTitle(for: mode) ?? mode.nounTitle }
    func nounPluralTitle(for mode: AppMode) -> String { self?.nounPluralTitle(for: mode) ?? mode.nounPluralTitle }
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
    /// Stunt vs tumbling — the OUTCOME-WORDING axis (kept in sync when the
    /// United category is set). Default keeps pre-kind stores migrating
    /// lightweight (every pre-kind bucket was a stunt).
    var kindRaw: String = SkillKind.stunt.rawValue
    /// United Scoring System category (carries the execution drivers). Blank
    /// (default) = derive from the legacy `kindRaw`, so existing tumbling skills
    /// keep their kind through migration instead of all collapsing to stunts.
    var categoryRaw: String = ""
    /// The team/roster this bucket belongs to. Optional so single-team stores
    /// migrate lightweight; RootView assigns teamless groups to a default team
    /// on launch.
    var team: Team?
    /// Deleting a group deletes its logged attempts with it — stats never see
    /// orphaned reps (which used to leak into deltas/trend but not the rate).
    @Relationship(deleteRule: .cascade, inverse: \Attempt.group)
    var attempts: [Attempt] = []
    @Relationship(deleteRule: .cascade, inverse: \CustomTally.group)
    var customTallies: [CustomTally] = []

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

    /// United category. Reading derives from the legacy kind when unset; setting
    /// also syncs `kindRaw` so outcome wording follows the category.
    var category: SkillCategory {
        get {
            if let c = SkillCategory(rawValue: categoryRaw) { return c }
            return kind == .tumbling ? .standingTumbling : .stunts
        }
        set {
            categoryRaw = newValue.rawValue
            kindRaw = newValue.hitRateKind.rawValue
        }
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
    @Relationship(deleteRule: .cascade, inverse: \CustomTally.session)
    var customTallies: [CustomTally] = []

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

// MARK: - Custom outcomes (user-created, per folder)

/// An extra outcome the user creates to tally alongside the locked 4 (e.g.
/// "Caught", "Dropped"). Deliberately a SEPARATE model from `Attempt` so it
/// never enters the hit-rate / cards / tournament math — those stay confined to
/// the four severity slots. Scoped to a folder (`Team`).
@Model
final class CustomOutcome {
    var id: UUID = UUID()
    var name: String
    var colorIndex: Int    // into Theme.groupRainbow
    var orderIndex: Int
    var createdAt: Date
    var team: Team?
    @Relationship(deleteRule: .cascade, inverse: \CustomTally.outcome)
    var tallies: [CustomTally] = []

    init(name: String, colorIndex: Int, orderIndex: Int, id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    var color: Color { Theme.groupColor(colorIndex % Theme.groupRainbow.count) }
}

/// One logged tap of a custom outcome — the parallel of `Attempt` for the
/// user's own counters. Tied to the outcome, the group it was logged on, and
/// the live session.
@Model
final class CustomTally {
    var id: UUID = UUID()
    var timestamp: Date
    var outcome: CustomOutcome?
    var group: StuntGroup?
    var session: PracticeSession?

    init(outcome: CustomOutcome?, group: StuntGroup?, session: PracticeSession?, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.outcome = outcome
        self.group = group
        self.session = session
        self.timestamp = timestamp
    }
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
