import Foundation
import Observation
import os
import SwiftData
import SwiftUI
import CheerRulesKit

extension Logger {
    /// Diagnostic-only channel for the "tap folder A, see folder B" report.
    /// Pull via Console.app / `log show` filtered on subsystem
    /// "com.ianrichardson.HitRate", category "team-resolve".
    static let teamResolve = Logger(subsystem: "com.ianrichardson.HitRate", category: "team-resolve")
}

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

// MARK: - Subject kind (who threw the rep)

/// Who a logged rep is attributed to. A `Subject` is the ROW in a recording:
/// an athlete (tumbling / athlete mode) or a stunt group (coach floor). Same
/// slot either way — only the icon/word differ. Orthogonal to `SkillKind`
/// (which is about outcome WORDS): a person can throw a stunt or a tumbling
/// pass, a group can be graded on either.
enum SubjectKind: String, CaseIterable, Identifiable, Codable {
    case person, group

    var id: String { rawValue }
    var label: String { self == .person ? "Athlete" : "Group" }
    var icon: String { self == .person ? "person.fill" : "person.3.fill" }
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

    /// The line between "a landing" and "not". A rep worth THIS or more counts
    /// as landed/stuck (keeps a streak, stays up); below it is a fall/miss/balk
    /// (breaks a streak). Ian: "anything 50% or above is landing at least."
    static let landingThreshold = 50

    var label: String {
        switch self {
        case .hit: "Hit · 100%"
        case .decent: "Decent · 67%"
        case .rough: "Rough · 33%"
        case .miss: "Miss · 0%"
        }
    }

    /// True when a rep of this credit counts as a LANDING (kept it up) — the
    /// same rule streaks use.
    var isLanding: Bool { rawValue >= OutcomeCredit.landingThreshold }

    /// Plain-language meaning, shown in the outcome maker so the credit you pick
    /// is unambiguous — including whether it keeps a streak going.
    var definition: String {
        switch self {
        case .hit:    "Clean — landed with no issues. Keeps a streak."
        case .decent: "Landed — stayed up, just not clean. Still counts, keeps a streak."
        case .rough:  "Off — didn't really land. Breaks a streak."
        case .miss:   "Miss, fall, or balk. Breaks a streak."
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
    /// A "hit" — the green accent / clean-hit milestones (credit 100).
    var isHit: Bool { credit >= 100 }
    /// A "landing" — stayed up (credit ≥ 50%). The rule streaks use, so a
    /// landed-but-not-clean rep keeps a streak alive.
    var isLanding: Bool { credit >= OutcomeCredit.landingThreshold }
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
            // Tumbling is land / didn't / balk: only Stuck (100) and Stepped out
            // (67) are landings. A touchdown is a fall — credit 0 (orange keeps it
            // visually distinct from a major fall), like Major fall and Balk.
            return [.init("Stuck", .green, .hit), .init("Stepped out", .yellow, .decent),
                    .init("Touched down", .orange, .miss), .init("Major fall", .red, .miss),
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
    /// Cloud sync / team sharing (Firebase). `ownerUID` = the Firebase uid that
    /// owns this folder in the cloud (nil = local-only, never pushed). `joinCode`
    /// = the 6-digit code others enter to join this folder's shared roster (nil
    /// until first pushed). Both additive with defaults → lightweight migration.
    var ownerUID: String? = nil
    var joinCode: String? = nil
    /// Firebase uids of everyone who has joined this shared folder (besides the
    /// owner). Owner-authoritative: the owner's device writes this list; members
    /// mirror it. Stored as a plain [String] (SwiftData handles Codable arrays).
    var memberIds: [String] = []
    /// Deleting a team takes its roster with it (and each group cascades its
    /// own logged reps) — the team's whole history goes.
    @Relationship(deleteRule: .cascade, inverse: \StuntGroup.team)
    var groups: [StuntGroup] = []
    /// User-created extra outcomes this folder tracks (alongside the locked 4).
    /// Deleting the folder removes them (and each cascades its tallies).
    @Relationship(deleteRule: .cascade, inverse: \CustomOutcome.team)
    var customOutcomes: [CustomOutcome] = []
    /// User-made skill types (reusable outcome sets) this folder owns.
    @Relationship(deleteRule: .cascade, inverse: \OutcomeTemplate.team)
    var outcomeTemplates: [OutcomeTemplate] = []
    /// The subjects (athletes or stunt groups) this folder attributes reps to —
    /// the ROWS in a recording. Deleting the folder removes them; their reps just
    /// lose attribution (the Attempt.subject relationship nullifies), never delete.
    @Relationship(deleteRule: .cascade, inverse: \Subject.team)
    var subjects: [Subject] = []

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
    /// Display name of a CUSTOM skill type applied to this skill (a user template
    /// or the built-in "Other"). Blank = this skill's type is its United
    /// `category`. Custom types carry no execution drivers. Purely cosmetic — the
    /// actual outcomes always live in `outcomeDefsRaw`.
    var typeLabelRaw: String = ""
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

    /// True when the name still needs reconciling (blank) — mirrors `Subject`, so
    /// a skill can be added blank-first from the capture pad and named later.
    var isUnnamed: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Roster-facing display: the name, or a placeholder while unnamed.
    var displayName: String { isUnnamed ? "Unnamed skill" : name }

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

    /// The label shown for this skill's TYPE: a custom type name if one was
    /// applied, else the United category name.
    var typeName: String { typeLabelRaw.isEmpty ? category.displayName : typeLabelRaw }

    /// True when this skill uses a custom type / "Other" — so it has no
    /// execution drivers (those live only on the 6 United categories).
    var usesCustomType: Bool { !typeLabelRaw.isEmpty }

    /// The execution drivers this skill can be scored against (Feature B): the
    /// United category's judge sub-criteria, used here as BINARY held/lost tags
    /// (the `maxDeduction` is ignored — HitRate never does point math). Custom /
    /// "Other" types carry NONE, so execution scoring is offered only for the 6
    /// United categories.
    var executionDrivers: [ExecutionDriver] { usesCustomType ? [] : category.executionDrivers }

    /// True when this skill supports the optional execution layer.
    var scoresExecution: Bool { !executionDrivers.isEmpty }

    /// Apply a United category as the type: re-link to its preset outcomes and
    /// clear any custom-type label (its execution drivers come back).
    func applyCategory(_ c: SkillCategory) {
        category = c
        outcomeDefsRaw = ""
        typeLabelRaw = ""
    }

    /// Apply a custom type (a template or the built-in "Other"): seed its
    /// outcomes and remember the type name. No execution drivers.
    func applyCustomType(name: String, defs: [OutcomeDef]) {
        setOutcomeDefs(defs)
        // setOutcomeDefs re-links to "" if defs happen to equal the category
        // preset; a named custom type must persist its own list regardless.
        if outcomeDefsRaw.isEmpty, let data = try? JSONEncoder().encode(defs),
           let s = String(data: data, encoding: .utf8) {
            outcomeDefsRaw = s
        }
        typeLabelRaw = name
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
    /// Stable Firestore identity. Empty means a pre-sync local session and is
    /// filled once, immediately before its first upload. These additive defaulted
    /// fields keep existing SwiftData stores on a lightweight migration path.
    var cloudID: String = ""
    var cloudTeamID: String = ""
    var loggerID: String = ""
    var syncStateRaw: String = CloudSyncState.pending.rawValue
    /// When a push was last attempted (success or failure) — lets SyncEngine
    /// cool down a `.failed` push instead of retrying it on every relaunch or
    /// every debounce cycle. Optional → additive lightweight migration.
    var lastSyncAttemptAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Attempt.session)
    var attempts: [Attempt] = []
    @Relationship(deleteRule: .cascade, inverse: \CustomTally.session)
    var customTallies: [CustomTally] = []

    init(startedAt: Date = .now) {
        self.startedAt = startedAt
        self.cloudID = "session-\(UUID().uuidString)"
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
    /// Persistent cloud identity and ownership. Imported attempts retain the
    /// original logger so an owner's device can never rewrite a member's rep as
    /// its own. Existing attempts start pending and adopt their legacy
    /// deterministic document id during the first acknowledged reconciliation.
    var cloudID: String = ""
    var cloudTeamID: String = ""
    var loggerID: String = ""
    var syncStateRaw: String = CloudSyncState.pending.rawValue
    /// When a push was last attempted (success or failure) — lets SyncEngine
    /// cool down a `.failed` push instead of retrying it on every relaunch or
    /// every debounce cycle. Optional → additive lightweight migration.
    var lastSyncAttemptAt: Date?
    var group: StuntGroup?
    var session: PracticeSession?
    /// Who threw this rep — the recording ROW (athlete or group). Optional so
    /// every pre-subject rep stays valid as an un-attributed skill-level tally;
    /// nil means "logged against the skill, no subject picked". Nullify on the
    /// subject's delete so history survives losing a roster member.
    var subject: Subject?
    /// Reps committed together as one wave/routine share a `waveID`; reps logged
    /// one at a time (pad or immediate grid) leave it nil. Drives the grouped
    /// container in the practice log. Optional → additive lightweight migration.
    var waveID: UUID?
    /// Optional EXECUTION layer (Feature B). `false` = execution was NOT scored on
    /// this rep, so it contributes NO execution data — an untracked rep is never
    /// assumed clean and can't inflate the breakdown (the NON-INFLATING rule).
    /// `true` means a coach committed an execution read; `lostDriversRaw` then
    /// holds the driver keys that SLIPPED (empty = every driver held = a clean
    /// execution, and that's real because it was actively scored). Both fields are
    /// additive with defaults → lightweight migration.
    var executionScored: Bool = false
    var lostDriversRaw: String = ""

    init(outcome: Outcome, group: StuntGroup?, session: PracticeSession?, subject: Subject? = nil, timestamp: Date = .now, waveID: UUID? = nil) {
        self.outcomeRaw = outcome.rawValue
        self.group = group
        self.session = session
        self.subject = subject
        self.timestamp = timestamp
        self.waveID = waveID
        self.cloudID = UUID().uuidString
    }

    /// Log a rep by its outcome SLOT index into the skill's flexible list — the
    /// path used now that a skill can have any number of outcomes.
    init(slot: Int, group: StuntGroup?, session: PracticeSession?, subject: Subject? = nil, timestamp: Date = .now, waveID: UUID? = nil) {
        self.outcomeRaw = slot
        self.group = group
        self.session = session
        self.subject = subject
        self.timestamp = timestamp
        self.waveID = waveID
        self.cloudID = UUID().uuidString
    }

    var outcome: Outcome { Outcome(rawValue: outcomeRaw) ?? .hit }

    /// The flexible outcome this rep logged, resolved against its skill's current
    /// list by slot index. Nil if that outcome was later deleted from the skill.
    var outcomeDef: OutcomeDef? { group?.outcomeDef(at: outcomeRaw) }
    /// Credit toward the weighted hit rate (0…100); a deleted outcome → 0.
    var creditValue: Int { outcomeDef?.credit ?? 0 }
    /// A clean hit — the green accent and clean-hit milestones (credit 100).
    var isHitRep: Bool { outcomeDef?.isHit ?? false }
    /// A landing — stayed up (credit ≥ 50%). This is what streaks count, so a
    /// landed-but-not-clean rep keeps a streak going; a fall/miss/balk breaks it.
    var isLandingRep: Bool { creditValue >= OutcomeCredit.landingThreshold }

    var syncState: CloudSyncState {
        get { CloudSyncState(rawValue: syncStateRaw) ?? .pending }
        set { syncStateRaw = newValue.rawValue }
    }

    // MARK: Execution (Feature B — optional binary held/lost tags)

    /// The execution-driver keys that slipped on this rep. Only meaningful when
    /// `executionScored`; empty means every driver held.
    var lostDrivers: [String] {
        get { lostDriversRaw.isEmpty ? [] : lostDriversRaw.components(separatedBy: "\n").filter { !$0.isEmpty } }
        set { lostDriversRaw = newValue.joined(separator: "\n") }
    }
    /// Commit an execution read: the listed driver keys slipped, the rest held.
    func scoreExecution(lost: [String]) {
        executionScored = true
        lostDrivers = lost
    }
    /// Discard this rep's execution read entirely — back to "not scored" (no data).
    func clearExecution() {
        executionScored = false
        lostDriversRaw = ""
    }
    /// The legacy severity `Outcome` this rep maps to by credit TIER (hit/decent/
    /// rough/miss → hit/bobble/buildingFall/majorFall). Used only by aggregate
    /// stats/visuals (tape color, tier histograms) so they stay 4-bucket and
    /// crash-safe regardless of how many outcomes the skill defines.
    var tierOutcome: Outcome {
        Outcome(rawValue: outcomeDef?.creditTier.tierIndex ?? OutcomeCredit.miss.tierIndex) ?? .majorFall
    }
}

/// A tiny durable upload state embedded in append-only cloud records. It is the
/// outbox for reps/sessions: the app retries pending or failed records after a
/// server snapshot and marks them synced only from Firestore's completion.
enum CloudSyncState: String, Codable {
    case pending
    case uploading
    case synced
    case failed
}

/// Deleting a local rep removes it from SwiftData immediately but leaves this
/// durable operation behind until Firestore acknowledges the tombstone. This
/// closes the deletion hole in `ModelContext.didSave`, whose deleted model can
/// no longer be resolved after the save.
@Model
final class PendingCloudDeletion {
    var id: UUID = UUID()
    var teamID: String
    var documentID: String
    var loggerID: String
    var createdAt: Date

    init(teamID: String, documentID: String, loggerID: String, createdAt: Date = .now) {
        self.teamID = teamID
        self.documentID = documentID
        self.loggerID = loggerID
        self.createdAt = createdAt
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

/// A user-made SKILL TYPE — a named, reusable outcome set. The 6 United
/// categories ship their own presets (`SkillCategory.defaultOutcomeDefs`);
/// this is the "make your own pre-made outcomes" path (+ the built-in "Other").
/// Custom types carry NO execution drivers — those stay on the United
/// categories. Applying one just seeds a skill's `outcomeDefsRaw`; the template
/// is the reusable source. Scoped to a folder (`Team`).
@Model
final class OutcomeTemplate {
    var id: UUID = UUID()
    var name: String
    /// JSON-encoded `[OutcomeDef]` — same wire format as `StuntGroup.outcomeDefsRaw`.
    var defsRaw: String = ""
    var orderIndex: Int
    var createdAt: Date
    var team: Team?

    init(name: String, defs: [OutcomeDef] = [], orderIndex: Int,
         id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.defs = defs
    }

    /// Decoded outcome list; empty falls back to a simple good/bad so a fresh
    /// template is always usable.
    var defs: [OutcomeDef] {
        get {
            if !defsRaw.isEmpty, let data = defsRaw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([OutcomeDef].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
            return OutcomeTemplate.otherDefs
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                defsRaw = s
            }
        }
    }

    /// The built-in "Other" set: plain good/bad for non-cheer use.
    static var otherDefs: [OutcomeDef] {
        [.init("Hit", .green, .hit), .init("Miss", .red, .miss)]
    }
}

// MARK: - Subject (the recording ROW: athlete or stunt group)

/// Who reps are attributed to inside a recording. An athlete ("Maya") or a stunt
/// group ("Group 2"). Scoped to a `Team`/folder. Deliberately lightweight: a
/// blank name is allowed (capture-first, name-later — "someone's doing
/// something"), reconciled later from suggestion chips so the same person never
/// double-creates. Soft-deletable like `StuntGroup`/`Team`.
@Model
final class Subject {
    /// Stable id (cross-device / wire-format friendly, like StuntGroup.id).
    var id: UUID = UUID()
    /// Display name; "" = unnamed, shown as a placeholder until reconciled.
    var name: String
    var kindRaw: String = SubjectKind.person.rawValue
    var orderIndex: Int
    var createdAt: Date
    /// Soft-delete tombstone — hidden from rosters/stats, reps kept & restorable.
    var deletedAt: Date? = nil
    var team: Team?
    /// Deleting a subject nullifies its reps' attribution (keeps the reps) — see
    /// `Attempt.subject`.
    @Relationship(deleteRule: .nullify, inverse: \Attempt.subject)
    var attempts: [Attempt] = []

    init(name: String, kind: SubjectKind = .person, orderIndex: Int,
         id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    var kind: SubjectKind {
        get { SubjectKind(rawValue: kindRaw) ?? .person }
        set { kindRaw = newValue.rawValue }
    }

    /// True when the name still needs reconciling (blank).
    var isUnnamed: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Roster-facing display: the name, or a placeholder while unnamed.
    var displayName: String { isUnnamed ? "Unnamed \(kind.label.lowercased())" : name }

    /// Identity color — reuses the formation rainbow, cycled by order.
    var color: Color { Theme.groupColor(orderIndex % Theme.groupRainbow.count) }
}

extension Array where Element == Subject {
    /// Subjects not in the Trash, in display order.
    var active: [Subject] { filter { $0.deletedAt == nil }.sorted { $0.orderIndex < $1.orderIndex } }
    /// Subjects belonging to one team (non-trashed), in order. No team → all active.
    func inTeam(_ team: Team?) -> [Subject] {
        let live = active
        return team.map { t in live.filter { $0.team?.id == t.id } } ?? live
    }
}

// MARK: - Team scoping helpers

extension Array where Element == Team {
    /// Folders not in the Trash, in order.
    var active: [Team] { filter { $0.deletedAt == nil } }
    /// Folders currently in the Trash, most-recently-deleted first.
    var trashed: [Team] { filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }

    /// The active team for a stored `currentTeamID` (uuidString). An empty id
    /// (nothing ever selected — fresh install/onboarding) falls back to the
    /// first ACTIVE team, a harmless default. A NON-empty id that doesn't
    /// match any live team returns nil instead of substituting a different
    /// folder's data — every call site already treats this as `Team?` and
    /// handles nil (HomeView/LogView's "My Skills" fallback, Onboarding's own
    /// `?? teams.first`). Silently serving `live.first` here was the mechanism
    /// behind "tap Maya's folder, see Lucy's data": a stale/dangling
    /// currentTeamID rendered as if the wrong folder were the right one, with
    /// no error. Never resolves to a trashed folder.
    func current(id: String) -> Team? {
        let live = active
        if let match = live.first(where: { $0.id.uuidString == id }) {
            return match
        }
        if id.isEmpty {
            return live.first
        }
        Logger.teamResolve.fault("current(id:) miss — requested=\(id, privacy: .public) liveIDs=\(live.map(\.id.uuidString).joined(separator: ","), privacy: .public)")
        return nil
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
