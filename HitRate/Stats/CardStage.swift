import Foundation

// The card ladder — how a stat card earns its chrome. Pure function of
// lifetime attempts + earned milestones + banked cups, recomputed on every
// render exactly like Milestones (no storage of its own).
//
// The governing rule: WORK and ACHIEVEMENTS decorate a card — the hit rate
// never does. Rate only colors the big number, and only once the card has
// `colorMinReps` under it, so a padded 2-for-2 can't out-shine a grinder and
// the retired rate-derived rarity stays retired (see Rarity in Theme.swift).

/// Where a card sits on the ladder. Order is load-bearing: later cases
/// out-rank earlier ones when several conditions hold at once.
enum CardStage: Int {
    case minted      // zero reps — a promise, not a stat
    case inked       // first reps landed on the card
    case proven      // provenReps+: solid edge, the flavor voice unlocks
    case decorated   // holds at least one badge
    case foil        // holds a holo/legendary badge — full foil chrome
}

/// One earned decoration pinned to a card — a power-up stacked on the card
/// that earned it (volume rungs, hit runs, mastery, cups won). Tier drives
/// the pip color; a holo/legendary badge is what sets the whole card foil.
struct CardBadge: Identifiable {
    let id: String
    let icon: String            // SF Symbol
    let label: String
    let tier: Milestone.Tier
}

/// One card's ladder position: lifetime reps + everything it has earned.
struct CardStanding {
    let reps: Int               // lifetime — never the Home timeframe
    let badges: [CardBadge]

    /// The band color waits for a real sample — 4-for-5 isn't 80%.
    static let colorMinReps = 10
    /// Reps before the card is a real record: proven edge + flavor voice.
    static let provenReps = 50

    var hasBandColor: Bool { reps >= Self.colorMinReps }
    var flavorUnlocked: Bool { reps >= Self.provenReps }

    var maxBadgeTier: Milestone.Tier? {
        badges.map(\.tier).max { $0.rawValue < $1.rawValue }
    }

    var stage: CardStage {
        if reps == 0 { return .minted }
        if let t = maxBadgeTier, t.rawValue >= Milestone.Tier.holo.rawValue { return .foil }
        if !badges.isEmpty { return .decorated }
        if reps >= Self.provenReps { return .proven }
        return .inked
    }
}

/// Ladder positions for a whole deck: the team card plus every group card,
/// keyed the same way GroupStat is so the deck builder can join them.
struct CardStandings {
    let team: CardStanding
    private let byGroup: [PersistentIdentifierBox: CardStanding]

    func standing(for id: PersistentIdentifierBox) -> CardStanding? { byGroup[id] }

    /// `groups` must already be team-scoped (the callers' `inTeam` rule);
    /// `milestones` is the full lifetime Milestones.evaluate output and
    /// `cups` the season's WeeklyLeague.cupHistory for the same groups.
    static func compute(groups: [StuntGroup], milestones: [Milestone],
                        cups: [WeeklyCup]) -> CardStandings {
        var by: [PersistentIdentifierBox: CardStanding] = [:]
        for g in groups {
            by[PersistentIdentifierBox(raw: "\(g.persistentModelID)")] = CardStanding(
                reps: g.attempts.count,
                badges: badges(for: g, milestones: milestones, cups: cups))
        }
        let teamReps = groups.reduce(0) { $0 + $1.attempts.count }
        return CardStandings(
            team: CardStanding(reps: teamReps, badges: teamBadges(milestones: milestones)),
            byGroup: by)
    }

    // MARK: Badge derivation

    /// Badges a single skill/group card has earned. Volume and streak show
    /// only their highest rung — a stack of three volume pips is noise.
    static func badges(for g: StuntGroup, milestones: [Milestone],
                       cups: [WeeklyCup]) -> [CardBadge] {
        var out: [CardBadge] = []
        let reps = g.attempts.count

        if reps >= 1000 {
            out.append(CardBadge(id: "vol1000", icon: "square.stack.3d.up.fill",
                                 label: "1,000 reps", tier: .legendary))
        } else if reps >= 500 {
            out.append(CardBadge(id: "vol500", icon: "square.stack.3d.up.fill",
                                 label: "500 reps", tier: .holo))
        } else if reps >= 100 {
            out.append(CardBadge(id: "vol100", icon: "square.stack.3d.up.fill",
                                 label: "100 reps", tier: .rare))
        }

        let run = bestHitRun(g.attempts)
        if run >= 25 {
            out.append(CardBadge(id: "run25", icon: "flame.fill",
                                 label: "25 straight", tier: .holo))
        } else if run >= 10 {
            out.append(CardBadge(id: "run10", icon: "flame.fill",
                                 label: "10 straight", tier: .rare))
        }

        // Mastery is the one per-group milestone family; its id embeds the
        // group's persistentModelID (see Milestones.swift).
        let gid = "\(g.persistentModelID)"
        for m in milestones where m.earned && m.id.hasPrefix("mastery-") && m.id.contains(gid) {
            out.append(CardBadge(id: m.id, icon: m.icon, label: "Mastered", tier: m.tier))
        }

        // Cups this card took home. Ghost weeks carry no winner id — THE
        // SPIRIT doesn't have a card to decorate.
        for cup in cups where cup.winnerGroupID != nil && cup.winnerGroupID == g.id {
            out.append(CardBadge(id: "cup-\(cup.id)", icon: cup.game.icon,
                                 label: cup.game.name.capitalized, tier: .rare))
        }
        return out
    }

    /// The team card collects the team-wide milestones (volume/streak/session
    /// families). Mastery stays on its skill's card, and TOUGH LOVE cards
    /// deliberately never decorate — a crash day shouldn't buy foil.
    static func teamBadges(milestones: [Milestone]) -> [CardBadge] {
        milestones
            .filter { $0.earned && !$0.id.hasPrefix("mastery-") && $0.kicker != "TOUGH LOVE" }
            .map { CardBadge(id: $0.id, icon: $0.icon, label: $0.name, tier: $0.tier) }
    }

    /// Longest run of consecutive clean hits across a card's lifetime —
    /// the same semantic as the streak milestone family (a bobble breaks it).
    static func bestHitRun(_ attempts: [Attempt]) -> Int {
        var best = 0, run = 0
        for a in attempts.sorted(by: { $0.timestamp < $1.timestamp }) {
            if a.isHitRep { run += 1; best = max(best, run) } else { run = 0 }
        }
        return best
    }
}
