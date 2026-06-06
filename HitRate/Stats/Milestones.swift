import Foundation

// MARK: - Milestone (earned card, good or dubious)

/// One unlockable card. Pure value — evaluated fresh from history every time,
/// so milestones never need their own storage or migration: "did 10 hits in a
/// row ever happen" is a function of the attempts.
struct Milestone: Identifiable {
    /// Difficulty tier — maps onto the card rarity *visuals* (foil, edge, tag)
    /// but is set by how hard the milestone is, NOT by hit rate. (Stat cards
    /// are flat; rarity now lives here.)
    enum Tier: Int {
        case common, rare, holo, legendary

        var stars: Int { rawValue }
    }

    let id: String          // stable key ("reps500", "mastery-<group>")
    let kicker: String      // "MILESTONE" / "DUBIOUS HONOR"
    let name: String
    let icon: String        // SF Symbol on the card face + puck
    let tier: Tier
    let flavor: String
    let earned: Bool
    let progress: Double    // 0…1 toward unlocking (1 when earned)
    let detail: String      // "412 / 500 reps" while locked, "523 reps logged" when earned
}

// MARK: - Engine

enum Milestones {

    /// Lifetime evaluation — deliberately ignores the Home timeframe filter.
    /// Earned cards sort by tier (flashiest first), locked teasers by progress.
    static func evaluate(sessions: [PracticeSession], groups: [StuntGroup],
                         mode: AppMode) -> [Milestone] {
        let attempts = sessions.flatMap(\.attempts).sorted { $0.timestamp < $1.timestamp }
        let total = attempts.count
        let falls = attempts.filter {
            $0.outcome == .buildingFall || $0.outcome == .majorFall
        }.count

        // Longest hit / miss runs across every rep ever logged, in order.
        var bestHitRun = 0, bestMissRun = 0
        var hitRun = 0, missRun = 0
        for a in attempts {
            if a.outcome.isHit {
                hitRun += 1; missRun = 0
            } else {
                missRun += 1; hitRun = 0
            }
            bestHitRun = max(bestHitRun, hitRun)
            bestMissRun = max(bestMissRun, missRun)
        }

        // Per-session shapes (sessions with no reps don't count for anything).
        struct SessionShape {
            let reps: Int
            let rate: Int
            let falls: Int
            let perfect: Bool   // hits == reps, NOT rate == 100 (rounding lies)
        }
        let shapes: [SessionShape] = sessions.compactMap { s in
            let n = s.attempts.count
            guard n > 0 else { return nil }
            let hits = s.attempts.filter(\.outcome.isHit).count
            let f = s.attempts.filter {
                $0.outcome == .buildingFall || $0.outcome == .majorFall
            }.count
            return SessionShape(reps: n,
                                rate: Int((Double(hits) / Double(n) * 100).rounded()),
                                falls: f,
                                perfect: hits == n)
        }
        let longestSession = shapes.map(\.reps).max() ?? 0
        let best20 = shapes.filter { $0.reps >= 20 }.map(\.rate).max()
        let dialedShape = shapes.first { $0.reps >= 20 && $0.rate >= 90 }
        let best15 = shapes.filter { $0.reps >= 15 }.map(\.rate).max()
        let perfectShape = shapes.first { $0.reps >= 15 && $0.perfect }
        let worstFallsSession = shapes.map(\.falls).max() ?? 0

        var list: [Milestone] = []

        // Lifetime volume
        list.append(volume(id: "reps10", name: "First Ten", icon: "checkmark.seal.fill",
                           tier: .common, target: 10, total: total,
                           flavor: "Ten on the board. Everyone starts at zero."))
        list.append(volume(id: "reps100", name: "Century Club", icon: "rosette",
                           tier: .rare, target: 100, total: total,
                           flavor: "Triple digits. The grind is officially real."))
        list.append(volume(id: "reps500", name: "Grinder", icon: "flame.fill",
                           tier: .holo, target: 500, total: total,
                           flavor: "Five hundred reps deep — calluses included."))
        list.append(volume(id: "reps1000", name: "Four Digits", icon: "crown.fill",
                           tier: .legendary, target: 1000, total: total,
                           flavor: "A thousand logged reps. Floor royalty."))

        // Hit streaks
        list.append(streak(id: "streak10", name: "Hot Hand", icon: "bolt.fill",
                           tier: .rare, target: 10, best: bestHitRun,
                           flavor: "Ten straight hits. Don't look down."))
        list.append(streak(id: "streak25", name: "Untouchable", icon: "sparkles",
                           tier: .legendary, target: 25, best: bestHitRun,
                           flavor: "Twenty-five in a row. Nobody's touching that."))

        // Session quality
        let dialedEarned = dialedShape != nil
        list.append(Milestone(
            id: "session90", kicker: "MILESTONE", name: "Dialed In", icon: "scope",
            tier: .holo,
            flavor: "90+ on real volume. That's not luck twice.",
            earned: dialedEarned,
            progress: dialedEarned ? 1
                : longestSession >= 20 ? min(1, Double(best20 ?? 0) / 90)
                : min(1, Double(longestSession) / 20),
            detail: dialedEarned
                ? "\(dialedShape!.rate)% · \(dialedShape!.reps) reps"
                : longestSession >= 20 ? "best 20-rep session: \(best20 ?? 0)%"
                : "longest session \(longestSession) / 20 reps"))

        let perfectEarned = perfectShape != nil
        list.append(Milestone(
            id: "perfect", kicker: "MILESTONE", name: "Perfect Practice", icon: "trophy.fill",
            tier: .legendary,
            flavor: "Not one miss all practice. Frame this one.",
            earned: perfectEarned,
            progress: perfectEarned ? 1
                : longestSession >= 15 ? min(1, Double(best15 ?? 0) / 100)
                : min(1, Double(longestSession) / 15),
            detail: perfectEarned
                ? "100% · \(perfectShape!.reps) reps"
                : longestSession >= 15 ? "best 15-rep session: \(best15 ?? 0)%"
                : "longest session \(longestSession) / 15 reps"))

        // Skill mastery — one card per qualifying bucket; if none qualify yet,
        // a single teaser for whichever is closest (one locked card, not N).
        let mastery: [(group: StuntGroup, reps: Int, rate: Int, progress: Double)] = groups.compactMap { g in
            let n = g.attempts.count
            guard n > 0 else { return nil }
            let hits = g.attempts.filter(\.outcome.isHit).count
            let rate = Int((Double(hits) / Double(n) * 100).rounded())
            let p = min(1, Double(n) / 50) * min(1, Double(rate) / 90)
            return (g, n, rate, p)
        }
        let masters = mastery.filter { $0.reps >= 50 && $0.rate >= 90 }
        if !masters.isEmpty {
            for m in masters {
                list.append(Milestone(
                    id: "mastery-\(m.group.persistentModelID)",
                    kicker: "MILESTONE", name: "Mastered: \(m.group.name)",
                    icon: "star.circle.fill", tier: .legendary,
                    flavor: "50+ reps at 90+. This \(mode.noun) is automatic now.",
                    earned: true, progress: 1,
                    detail: "\(m.reps) reps @ \(m.rate)%"))
            }
        } else if let closest = mastery.max(by: { $0.progress < $1.progress }) {
            list.append(Milestone(
                id: "mastery-teaser", kicker: "MILESTONE", name: "Mastery",
                icon: "star.circle.fill", tier: .legendary,
                flavor: "Own one \(mode.noun): 50 reps at 90 percent.",
                earned: false, progress: closest.progress,
                detail: "\(closest.group.name): \(closest.reps)/50 reps @ \(closest.rate)%"))
        }

        // Dubious honors — the bad stats deserve cards too.
        list.append(Milestone(
            id: "falls25", kicker: "DUBIOUS HONOR", name: "Gravity Check",
            icon: "arrow.down.circle.fill", tier: .common,
            flavor: "Twenty-five falls survived. The mat knows your name.",
            earned: falls >= 25, progress: min(1, Double(falls) / 25),
            detail: falls >= 25 ? "\(falls) falls survived" : "\(falls) / 25 falls"))
        list.append(Milestone(
            id: "coldstreak", kicker: "DUBIOUS HONOR", name: "Cold Streak",
            icon: "snowflake", tier: .rare,
            flavor: "Five misses in a row. Somebody check the thermostat.",
            earned: bestMissRun >= 5, progress: min(1, Double(bestMissRun) / 5),
            detail: bestMissRun >= 5 ? "\(bestMissRun) misses in a row"
                                     : "worst run \(bestMissRun) / 5 misses"))
        list.append(Milestone(
            id: "demolition", kicker: "DUBIOUS HONOR", name: "Demolition Day",
            icon: "hammer.fill", tier: .holo,
            flavor: "Eight falls in one practice. Total demolition.",
            earned: worstFallsSession >= 8, progress: min(1, Double(worstFallsSession) / 8),
            detail: worstFallsSession >= 8 ? "\(worstFallsSession) falls in one session"
                                           : "worst session: \(worstFallsSession) / 8 falls"))

        // Earned first (flashy tiers up front), then locked by closeness.
        let earned = list.filter(\.earned).sorted { $0.tier.rawValue > $1.tier.rawValue }
        let locked = list.filter { !$0.earned }.sorted { $0.progress > $1.progress }
        return earned + locked
    }

    // MARK: Builders

    private static func volume(id: String, name: String, icon: String, tier: Milestone.Tier,
                               target: Int, total: Int, flavor: String) -> Milestone {
        Milestone(id: id, kicker: "MILESTONE", name: name, icon: icon, tier: tier,
                  flavor: flavor, earned: total >= target,
                  progress: min(1, Double(total) / Double(target)),
                  detail: total >= target ? "\(total) reps logged" : "\(total) / \(target) reps")
    }

    private static func streak(id: String, name: String, icon: String, tier: Milestone.Tier,
                               target: Int, best: Int, flavor: String) -> Milestone {
        Milestone(id: id, kicker: "MILESTONE", name: name, icon: icon, tier: tier,
                  flavor: flavor, earned: best >= target,
                  progress: min(1, Double(best) / Double(target)),
                  detail: best >= target ? "\(best) hits in a row"
                                         : "best streak \(best) / \(target)")
    }
}
