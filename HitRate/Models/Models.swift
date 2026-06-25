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

    // Buckets are "skills" universally now (athlete AND coach — a coach just
    // makes a skill per stunt group). The mode still differs on identity and
    // whose name rides the cards, but never on the bucket word.
    var noun: String { "skill" }
    var nounPlural: String { "skills" }
    var nounTitle: String { "Skill" }
    var nounPluralTitle: String { "Skills" }

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

    /// The default 4 outcome words for a skill in this category (slot 0 = the
    /// clean hit — the hit-rate spine; slots 1–3 = the issues). Stunts/pyramid
    /// and the tumblings keep the established severity words; jumps/tosses use
    /// their execution drivers. Per-skill swaps (`StuntGroup.outcomeWords`)
    /// override these.
    var defaultOutcomeWords: [String] {
        switch self {
        case .stunts, .pyramid:
            return ["Hit", "Bobble", "Building fall", "Major fall"]
        case .standingTumbling, .runningTumbling:
            return ["Stuck", "Stepped out", "Touched down", "Major fall"]
        case .jumps:
            return ["Hit", "Legs", "Arms", "Sync"]
        case .tosses:
            return ["Hit", "Top", "Bases", "Height"]
        }
    }

    /// True for the categories whose default words ARE the legacy stunt/tumbling
    /// kind words — only those honor the per-kind `OutcomeNames` custom renames.
    /// Jumps/tosses have their own words and never borrow stunt renames.
    var usesKindWords: Bool {
        switch self {
        case .stunts, .pyramid, .standingTumbling, .runningTumbling: return true
        case .jumps, .tosses: return false
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

// MARK: - Flexible outcomes (label + color + credit)

/// The fixed credit ladder that drives the weighted hit rate. Color is chosen
/// SEPARATELY (see `OutcomeColor`) so e.g. a blue "Balk" still counts as a miss.
enum OutcomeCredit: Int, CaseIterable, Codable, Identifiable {
    case hit = 100, decent = 67, rough = 33, miss = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .hit: "Hit · 100%"
        case .decent: "Decent · 67%"
        case .rough: "Rough · 33%"
        case .miss: "Miss · 0%"
        }
    }
    var defaultColor: OutcomeColor {
        switch self {
        case .hit: .green
        case .decent: .yellow
        case .rough: .orange
        case .miss: .red
        }
    }
    /// Aggregate-histogram bucket (0 = hit … 3 = miss). Aligns with the legacy
    /// `Outcome.rawValue` order so existing tier-indexed stats keep working while
    /// individual skills carry any number of outcomes.
    var tierIndex: Int {
        switch self {
        case .hit: 0
        case .decent: 1
        case .rough: 2
        case .miss: 3
        }
    }
}

/// The outcome color palette — assignable independently of credit.
enum OutcomeColor: String, CaseIterable, Codable, Identifiable {
    case green, yellow, orange, red, blue, purple, gray
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .green: Theme.hit
        case .yellow: Theme.bobble
        case .orange: Theme.buildingFall
        case .red: Theme.majorFall
        case .blue: Theme.outcomeBlue
        case .purple: Theme.outcomePurple
        case .gray: Theme.outcomeGray
        }
    }
}

/// One tap target on a skill's pad: a user word, a palette color, and a credit
/// weight. Stored as a small Codable list on the skill (NOT a @Model — that
/// avoids a relationship migration; `Attempt.outcomeRaw` keeps indexing by
/// slot into this list, so existing reps stay valid).
struct OutcomeDef: Codable, Hashable, Identifiable {
    var label: String
    var colorRaw: String
    var credit: Int           // 0 / 33 / 67 / 100

    var id: String { "\(label)|\(colorRaw)|\(credit)" }
    var color: Color { (OutcomeColor(rawValue: colorRaw) ?? .gray).color }
    var creditTier: OutcomeCredit { OutcomeCredit(rawValue: credit) ?? .miss }
    /// A "hit" for streaks / the green accent / hit milestones.
    var isHit: Bool { credit >= 100 }
    var short: String { Outcome.deriveShort(label) }
    /// Maps the credit tier onto a legacy `Outcome` purely to pick a tap sound.
    var soundOutcome: Outcome {
        switch creditTier {
        case .hit: .hit
        case .decent: .bobble
        case .rough: .buildingFall
        case .miss: .majorFall
        }
    }

    init(_ label: String, _ color: OutcomeColor, _ credit: OutcomeCredit) {
        self.label = label; self.colorRaw = color.rawValue; self.credit = credit.rawValue
    }
    init(label: String, colorRaw: String, credit: Int) {
        self.label = label; self.colorRaw = colorRaw; self.credit = credit
    }
}

extension SkillCategory {
    /// The default flexible outcome set for a new skill in this category. The
    /// first four slots stay aligned with the legacy severity order so existing
    /// reps (which index by slot via `Attempt.outcomeRaw`) keep their meaning;
    /// any extra outcome (e.g. tumbling "Balk") is APPENDED after them.
    var defaultOutcomeDefs: [OutcomeDef] {
        switch self {
        case .stunts, .pyramid:
            return [.init("Hit", .green, .hit), .init("Bobble", .yellow, .decent),
                    .init("Building fall", .orange, .rough), .init("Major fall", .red, .miss)]
        case .standingTumbling, .runningTumbling:
            return [.init("Stuck", .green, .hit), .init("Stepped out", .yellow, .decent),
                    .init("Touched down", .orange, .rough), .init("Major fall", .red, .miss),
                    .init("Balk", .blue, .miss)]
        case .jumps:
            return [.init("Hit", .green, .hit), .init("Low", .yellow, .decent),
                    .init("Bent", .orange, .rough), .init("Missed", .red, .miss)]
        case .tosses:
            return [.init("Caught", .green, .hit), .init("Bobble", .yellow, .decent),
                    .init("Low", .orange, .rough), .init("Dropped", .red, .miss)]
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
        return Self.deriveShort(custom)
    }

    /// Short code for an arbitrary word: initials for multi-word ("Touch down"
    /// → TD), first three letters otherwise ("Drop" → DRO).
    static func deriveShort(_ word: String) -> String {
        let words = word.split(separator: " ")
        if words.count >= 2 {
            return words.prefix(3).compactMap { $0.first.map(String.init) }.joined().uppercased()
        }
        return String(word.prefix(3)).uppercased()
    }

    /// Per-skill label/short — the PAD, GRID, and a skill's own tape read these
    /// so each skill shows ITS own outcome words (a jump row shows jump words, a
    /// tumbling row tumbling words). Aggregate legends/cards keep `label(_:kind)`.
    func label(for group: StuntGroup) -> String { group.outcomeWords[rawValue] }
    func short(for group: StuntGroup) -> String { Self.deriveShort(group.outcomeWords[rawValue]) }

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
    /// Soft-delete tombstone. Non-nil = in the Trash: hidden from every roster/
    /// stat but its skills and reps are KEPT and restorable. Nothing is hard-
    /// deleted without an explicit "Delete permanently" from the Trash.
    var deletedAt: Date? = nil
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

    // The per-folder noun override was retired (it produced nonsense like an
    // athlete folder's "Add athlete"). Buckets are "skill" everywhere now; the
    // stored `itemNoun` is ignored for wording and kept only so old stores
    // migrate lightweight. Always nil → every `noun(for:)` falls back to the
    // (now universal) AppMode word.
    private var customNoun: String? { nil }

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
    /// Soft-delete tombstone — see `Team.deletedAt`. Non-nil = trashed: hidden
    /// from rosters/stats but the skill and its reps are kept and restorable.
    var deletedAt: Date? = nil
    /// Per-skill outcome-word swaps along the good→bad scale. Newline-joined,
    /// one entry per severity slot (0 = clean/good … 3 = worst/bad); a blank
    /// entry falls back to the category default. Additive field → lightweight
    /// migration; blank = every slot uses `category.defaultOutcomeWords`.
    var outcomeOverridesRaw: String = ""
    /// The skill's flexible outcome list (label + color + credit), JSON-encoded.
    /// Blank = use `category.defaultOutcomeDefs`. `Attempt.outcomeRaw` indexes
    /// into the resolved list, so the first four slots must stay legacy-aligned.
    var outcomeDefsRaw: String = ""
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

    // MARK: Flexible outcome list (label + color + credit)

    /// The skill's outcome tap targets, resolved: decoded per-skill list, else
    /// the category preset. Always at least the preset (never empty).
    var outcomeDefs: [OutcomeDef] {
        if !outcomeDefsRaw.isEmpty,
           let data = outcomeDefsRaw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([OutcomeDef].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return category.defaultOutcomeDefs
    }

    /// Persist a new outcome list (pass the category preset's contents to "reset"
    /// by clearing back to defaults).
    func setOutcomeDefs(_ defs: [OutcomeDef]) {
        if defs == category.defaultOutcomeDefs {
            outcomeDefsRaw = ""   // stay linked to the preset
        } else if let data = try? JSONEncoder().encode(defs),
                  let s = String(data: data, encoding: .utf8) {
            outcomeDefsRaw = s
        }
    }

    /// The outcome at a slot index (an `Attempt.outcomeRaw`), or nil if the list
    /// shrank below it (a deleted outcome — the rep is then uncredited).
    func outcomeDef(at slot: Int) -> OutcomeDef? {
        let defs = outcomeDefs
        return slot >= 0 && slot < defs.count ? defs[slot] : nil
    }

    // MARK: Per-skill outcome words (the good→bad scale)

    /// This skill's four outcome words, slot 0 (good/clean) → slot 3 (bad).
    /// A per-skill swap wins; a blank slot falls back to the category default
    /// (which itself honors the per-kind `OutcomeNames` rename for the
    /// stunt/tumbling families).
    var outcomeWords: [String] {
        let overrides = outcomeOverridesRaw.isEmpty ? [] : outcomeOverridesRaw.components(separatedBy: "\n")
        let defaults = category.defaultOutcomeWords
        return (0..<4).map { i in
            let o = i < overrides.count ? overrides[i].trimmingCharacters(in: .whitespaces) : ""
            if !o.isEmpty { return o }
            if category.usesKindWords {
                let custom = OutcomeNames.shared.custom(kind)[i]
                if !custom.isEmpty { return custom }
            }
            return defaults[i]
        }
    }

    /// The raw per-skill override for a slot (empty = using the default).
    func outcomeOverride(_ slot: Int) -> String {
        let parts = outcomeOverridesRaw.isEmpty ? [] : outcomeOverridesRaw.components(separatedBy: "\n")
        return slot < parts.count ? parts[slot] : ""
    }

    /// Set (or clear, with "") a per-skill outcome word at one severity slot.
    func setOutcomeWord(_ word: String, slot: Int) {
        var parts = (0..<4).map { outcomeOverride($0) }
        guard slot >= 0, slot < 4 else { return }
        parts[slot] = word.trimmingCharacters(in: .whitespaces)
        // Collapse to "" when nothing is overridden, so the row stays on defaults.
        outcomeOverridesRaw = parts.contains { !$0.isEmpty } ? parts.joined(separator: "\n") : ""
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

    /// Log a rep by its outcome SLOT index into the skill's flexible list — the
    /// path used now that a skill can have any number of outcomes.
    init(slot: Int, group: StuntGroup?, session: PracticeSession?, timestamp: Date = .now, waveID: UUID? = nil) {
        self.outcomeRaw = slot
        self.group = group
        self.session = session
        self.timestamp = timestamp
        self.waveID = waveID
    }

    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .hit }

    /// The flexible outcome this rep logged, resolved against its skill's current
    /// list by slot index. Nil if that outcome was later deleted from the skill.
    var outcomeDef: OutcomeDef? { group?.outcomeDef(at: outcomeRaw) }
    /// Credit toward the weighted hit rate (0…100); a deleted outcome → 0.
    var creditValue: Int { outcomeDef?.credit ?? 0 }
    /// A clean hit — drives streaks, the green accent, and hit milestones.
    var isHitRep: Bool { outcomeDef?.isHit ?? false }
    /// The legacy severity `Outcome` this rep maps to by credit TIER (hit/decent/
    /// rough/miss → hit/bobble/buildingFall/majorFall). Used only by aggregate
    /// stats/visuals (tape color, tier histograms) so they stay 4-bucket and
    /// crash-safe regardless of how many outcomes the skill defines.
    var tierOutcome: Outcome {
        Outcome(rawValue: outcomeDef?.creditTier.tierIndex ?? OutcomeCredit.miss.tierIndex) ?? .majorFall
    }
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
    /// Folders not in the Trash, in order.
    var active: [Team] { filter { $0.deletedAt == nil } }
    /// Folders currently in the Trash, most-recently-deleted first.
    var trashed: [Team] { filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    /// The active team for a stored `currentTeamID` (uuidString), falling back
    /// to the first ACTIVE team. Never resolves to a trashed folder.
    func current(id: String) -> Team? {
        let live = active
        return live.first { $0.id.uuidString == id } ?? live.first
    }
}

extension Array where Element == StuntGroup {
    /// Skills not in the Trash.
    var active: [StuntGroup] { filter { $0.deletedAt == nil } }
    /// Skills in the Trash, most-recently-deleted first.
    var trashed: [StuntGroup] { filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    /// The (non-trashed) buckets belonging to one team, in display order. With
    /// no team yet (pre-migration), every active bucket shows — RootView assigns
    /// them to a default team momentarily. Trashed skills never appear.
    func inTeam(_ team: Team?) -> [StuntGroup] {
        let live = active
        let scoped = team.map { t in live.filter { $0.team?.id == t.id } } ?? live
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
