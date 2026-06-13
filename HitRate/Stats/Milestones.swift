import Foundation
import SwiftData

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

    let id: String          // stable key ("reps500-stunt", "mastery-<group>")
    let kind: SkillKind     // stunt or tumbling
    let variantIndex: Int?  // 0-3 if unlocked and synced, nil if locked
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
                         mode: AppMode, unlocked: [UnlockedMilestone] = []) -> [Milestone] {
        var allMilestones: [Milestone] = []
        
        for kind in SkillKind.allCases {
            // Coach mode is stunt-only, skip tumbling.
            if mode == .coach && kind == .tumbling { continue }
            
            let allowed = Set(groups.filter { $0.kind == kind }.map { $0.persistentModelID })
            func inTeam(_ a: Attempt) -> Bool {
                a.group.map { allowed.contains($0.persistentModelID) } ?? false
            }
            let attempts = sessions.flatMap(\.attempts).filter(inTeam)
                .sorted { $0.timestamp < $1.timestamp }
            let total = attempts.count
            let falls = attempts.filter {
                $0.outcome == .buildingFall || $0.outcome == .majorFall
            }.count

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

            struct SessionShape {
                let reps: Int
                let rate: Int
                let falls: Int
                let perfect: Bool
            }
            let shapes: [SessionShape] = sessions.compactMap { s in
                let reps = s.attempts.filter(inTeam)
                let n = reps.count
                guard n > 0 else { return nil }
                let hits = reps.filter(\.outcome.isHit).count
                let f = reps.filter {
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
            
            let suffix = "-\(kind.rawValue)"
let getVariant = { (base: String) -> Int in
                unlocked.first(where: { $0.milestoneID == base + suffix })?.variantIndex ?? 0
            }

let reps10Id = "reps10\(suffix)"
            let reps10V = getVariant("reps10")
            var reps10Flavor = "Ten reps. A journey of a thousand miles..."
            var reps10Icon = "checkmark.seal.fill"
            if reps10V == 1 { reps10Flavor = "Congrats! you're like a wittle baby!"; reps10Icon = "pacifier" } // binky/rattle

            list.append(volume(id: reps10Id, kind: kind, name: "First Ten", icon: reps10Icon,
                               tier: .common, target: 10, total: total,
                               flavor: reps10Flavor, unlocked: unlocked))

            let reps100Id = "reps100\(suffix)"
            let reps100V = getVariant("reps100")
            var reps100Flavor = "Wow, a hundred reps. Do you want a cookie?"
            var reps100Icon = "rosette"
            if reps100V == 1 { reps100Flavor = "Here is your participation trophy."; reps100Icon = "trophy" }

            list.append(volume(id: reps100Id, kind: kind, name: "Century Club", icon: reps100Icon,
                               tier: .rare, target: 100, total: total,
                               flavor: reps100Flavor, unlocked: unlocked))

            let reps500Id = "reps500\(suffix)"
            let reps500V = getVariant("reps500")
            var reps500Flavor = "Five hundred reps. You're officially invested."
            var reps500Icon = "flame.fill"
            if reps500V == 1 { reps500Flavor = "You are cordially invited to use deodorant and body spray."; reps500Icon = "drop.fill" }

            list.append(volume(id: reps500Id, kind: kind, name: "Half a Grand", icon: reps500Icon,
                               tier: .holo, target: 500, total: total,
                               flavor: reps500Flavor, unlocked: unlocked))

            let reps1000Id = "reps1000\(suffix)"
            let reps1000V = getVariant("reps1000")
            var reps1000Flavor = "1,000 reps. I'm legally obligated to tell you to go touch grass."
            var reps1000Icon = "crown.fill"
            if reps1000V == 1 { reps1000Flavor = "RIP your social life."; reps1000Icon = "cross.fill" } // tombstone

            list.append(volume(id: reps1000Id, kind: kind, name: "Four Digits", icon: reps1000Icon,
                               tier: .legendary, target: 1000, total: total,
                               flavor: reps1000Flavor, unlocked: unlocked))

            let streak5Id = "streak5\(suffix)"
            let streak5V = getVariant("streak5")
            var streak5Flavor = "Five in a row. Not bad."
            var streak5Icon = "hand.raised.fill"
            if streak5V == 1 { streak5Flavor = "A single high five."; streak5Icon = "hand.raised.fill" }

            list.append(streak(id: streak5Id, kind: kind, name: "High Five", icon: streak5Icon,
                               tier: .common, target: 5, best: bestHitRun,
                               flavor: streak5Flavor, unlocked: unlocked))

            let streak10Id = "streak10\(suffix)"
            let streak10V = getVariant("streak10")
            var streak10Flavor = "Ten hits. You're heating up."
            var streak10Icon = "bolt.fill"
            if streak10V == 1 { streak10Flavor = "Pure luck."; streak10Icon = "sparkles" }

            list.append(streak(id: streak10Id, kind: kind, name: "Hot Hand", icon: streak10Icon,
                               tier: .rare, target: 10, best: bestHitRun,
                               flavor: streak10Flavor, unlocked: unlocked))

            let streak25Id = "streak25\(suffix)"
            let streak25V = getVariant("streak25")
            var streak25Flavor = "Twenty-five straight. Unstoppable."
            var streak25Icon = "sparkles"
            if streak25V == 1 { streak25Flavor = "There are probably other skills you should be working on."; streak25Icon = "eyes" }

            list.append(streak(id: streak25Id, kind: kind, name: "Untouchable", icon: streak25Icon,
                               tier: .legendary, target: 25, best: bestHitRun,
                               flavor: streak25Flavor, unlocked: unlocked))

            

            let dialedEarned = dialedShape != nil
            let dialedId = "session90\(suffix)"
            let dialedV = getVariant("session90")
            var dialedFlavor = "90+ on real volume. That's not luck twice."
            var dialedIcon = "scope"
            if kind == .stunt {
                if dialedV == 1 { dialedFlavor = "You didn't drop them today. I'm writing this down."; dialedIcon = "session90_calendar" }
                else if dialedV == 3 { dialedFlavor = "Who are you and what did you do with my real athlete?"; dialedIcon = "session90_alien" }
            } else {
                if dialedV == 1 { dialedFlavor = "Gravity decided to take the day off for you."; dialedIcon = "arrow.up.heart" }
                else if dialedV == 3 { dialedFlavor = "You survived 20 reps without a mental block. Is the world ending?"; dialedIcon = "flame.fill" }
            }
            list.append(create(id: dialedId, kind: kind, kicker: "MILESTONE", name: "Dialed In", icon: dialedIcon,
                               tier: .holo, flavor: dialedFlavor,
                               earned: dialedEarned,
                               progress: dialedEarned ? 1
                                   : longestSession >= 20 ? min(1, Double(best20 ?? 0) / 90)
                                   : min(1, Double(longestSession) / 20),
                               detail: dialedEarned
                                   ? "\(dialedShape!.rate)% · \(dialedShape!.reps) reps"
                                   : longestSession >= 20 ? "best 20-rep session: \(best20 ?? 0)%"
                                   : "longest session \(longestSession) / 20 reps", unlocked: unlocked))

            let perfectEarned = perfectShape != nil
            let perfectId = "perfect\(suffix)"
            let perfectV = getVariant("perfect")
            var perfectFlavor = "Not one miss all practice. Frame this one."
            var perfectIcon = "trophy.fill"
            if kind == .stunt {
                if perfectV == 1 { perfectFlavor = "Not one miss. Don't get used to this feeling."; perfectIcon = "medal.fill" }
                else if perfectV == 2 { perfectFlavor = "You peaked today. It's all downhill from here."; perfectIcon = "waveform.path" }
                else if perfectV == 3 { perfectFlavor = "I'm printing this out and putting it on the fridge."; perfectIcon = "doc.plaintext" }
            } else {
                if perfectV == 1 { perfectFlavor = "Not one bust. Who paid you to be good today?"; perfectIcon = "dollarsign.circle.fill" }
                else if perfectV == 2 { perfectFlavor = "You actually pulled every pass. I'm checking the tapes."; perfectIcon = "play.tv.fill" }
            }
            list.append(create(id: perfectId, kind: kind, kicker: "MILESTONE", name: "Perfect Practice", icon: perfectIcon,
                               tier: .legendary, flavor: perfectFlavor,
                               earned: perfectEarned,
                               progress: perfectEarned ? 1
                                   : longestSession >= 15 ? min(1, Double(best15 ?? 0) / 100)
                                   : min(1, Double(longestSession) / 15),
                               detail: perfectEarned
                                   ? "100% · \(perfectShape!.reps) reps"
                                   : longestSession >= 15 ? "best 15-rep session: \(best15 ?? 0)%"
                                   : "longest session \(longestSession) / 15 reps", unlocked: unlocked))

            let masteryGroups = groups.filter { $0.kind == kind }
            let mastery: [(group: StuntGroup, reps: Int, rate: Int, progress: Double)] = masteryGroups.compactMap { g in
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
                    let mastId = "mastery-\(m.group.persistentModelID)\(suffix)"
                    let mastV = unlocked.first(where: { $0.milestoneID == mastId })?.variantIndex ?? 0
                    var mastFlavor = "50+ reps at 90+. This \(mode.noun) is automatic now."
                    var mastIcon = "star.circle.fill"
                    if kind == .stunt {
                        if mastV == 1 { mastFlavor = "Okay, you have ONE reliable skill. Don't let it get lonely."; mastIcon = "wind" }
                        else if mastV == 3 { mastFlavor = "Certified Automatic. Are you a robot?"; mastIcon = "gearshape.fill" }
                    } else {
                        if mastV == 1 { mastFlavor = "You finally unlocked muscle memory. Took long enough."; mastIcon = "brain.head.profile" }
                        else if mastV == 2 { mastFlavor = "You've officially graduated from 'throw and pray'."; mastIcon = "hands.sparkles.fill" }
                        else if mastV == 3 { mastFlavor = "This skill is now your entire personality."; mastIcon = "lanyardcard.fill" }
                    }
                    list.append(create(id: mastId, kind: kind, kicker: "MILESTONE",
                                       name: "Mastered: \(m.group.name)", icon: mastIcon, tier: .legendary,
                                       flavor: mastFlavor,
                                       earned: true, progress: 1,
                                       detail: "\(m.reps) reps @ \(m.rate)%", unlocked: unlocked))
                }
            } else if let closest = mastery.max(by: { $0.progress < $1.progress }) {
                list.append(create(id: "mastery-teaser\(suffix)", kind: kind, kicker: "MILESTONE", name: "Mastery",
                                   icon: "star.circle.fill", tier: .legendary,
                                   flavor: "Own one \(mode.noun): 50 reps at 90 percent.",
                                   earned: false, progress: closest.progress,
                                   detail: "\(closest.group.name): \(closest.reps)/50 reps @ \(closest.rate)%", unlocked: unlocked))
            }

            let fallsId = "falls25\(suffix)"
            let fallsV = getVariant("falls25")
            var fallsFlavor = "Twenty-five falls survived. The mat knows your name."
            var fallsIcon = "arrow.down.circle.fill"
            if fallsV == 1 { fallsFlavor = "Wile E. Coyote wants his gimmick back."; fallsIcon = "smoke.fill" }
            else if fallsV == 2 { fallsFlavor = "RIP to your joints. Gone but not forgotten."; fallsIcon = "cross.fill" }
            list.append(create(id: fallsId, kind: kind, kicker: "DUBIOUS HONOR", name: "Gravity Check",
                               icon: fallsIcon, tier: .common,
                               flavor: fallsFlavor,
                               earned: falls >= 25, progress: min(1, Double(falls) / 25),
                               detail: falls >= 25 ? "\(falls) falls survived" : "\(falls) / 25 falls", unlocked: unlocked))

            let coldId = "coldstreak\(suffix)"
            let coldV = getVariant("coldstreak")
            var coldFlavor = "Five misses in a row. Somebody check the thermostat."
            var coldIcon = "snowflake"
            if coldV == 1 { coldFlavor = "Are you still on the team? Did you quit and not tell anybody?"; coldIcon = "questionmark.square.dashed" }
            list.append(create(id: coldId, kind: kind, kicker: "DUBIOUS HONOR", name: "Cold Streak",
                               icon: coldIcon, tier: .rare,
                               flavor: coldFlavor,
                               earned: bestMissRun >= 5, progress: min(1, Double(bestMissRun) / 5),
                               detail: bestMissRun >= 5 ? "\(bestMissRun) misses in a row"
                                                        : "worst run \(bestMissRun) / 5 misses", unlocked: unlocked))

            let demoId = "demolition\(suffix)"
            let demoV = getVariant("demolition")
            var demoFlavor = "Total demolition."
            var demoIcon = "hammer.fill"
            if demoV == 1 { demoFlavor = "I'm calling the Cheerleading Protective Services hotline."; demoIcon = "phone.fill" }
            else if demoV == 2 { demoFlavor = "You came in like a wrecking ball."; demoIcon = "record.circle.fill" }
            list.append(create(id: demoId, kind: kind, kicker: "DUBIOUS HONOR", name: "Demolition Day",
                               icon: demoIcon, tier: .holo,
                               flavor: demoFlavor,
                               earned: worstFallsSession >= 8, progress: min(1, Double(worstFallsSession) / 8),
                               detail: worstFallsSession >= 8 ? "\(worstFallsSession) falls in one session"
                                                              : "worst session: \(worstFallsSession) / 8 falls", unlocked: unlocked))

            allMilestones.append(contentsOf: list)
        }

        // Earned first (flashy tiers up front), then locked by closeness.
        let earned = allMilestones.filter(\.earned).sorted { $0.tier.rawValue > $1.tier.rawValue }
        let locked = allMilestones.filter { !$0.earned }.sorted { $0.progress > $1.progress }
        return earned + locked
    }
    
    static func sync(sessions: [PracticeSession], groups: [StuntGroup], mode: AppMode, unlocked: [UnlockedMilestone], context: ModelContext) {
        let evaluated = evaluate(sessions: sessions, groups: groups, mode: mode, unlocked: unlocked)
        var dirty = false
        for milestone in evaluated where milestone.earned {
            if !unlocked.contains(where: { $0.milestoneID == milestone.id }) {
                // Determine a variant index for this newly unlocked milestone
                let roll = Int.random(in: 0..<100)
                let variant = roll < 60 ? 0 : roll < 85 ? 1 : roll < 95 ? 2 : 3
                let newUnlock = UnlockedMilestone(milestoneID: milestone.id, variantIndex: variant)
                context.insert(newUnlock)
                dirty = true
            }
        }
        if dirty { try? context.save() }
    }

    // MARK: Builders

    private static func create(id: String, kind: SkillKind, kicker: String, name: String, icon: String, tier: Milestone.Tier, flavor: String, earned: Bool, progress: Double, detail: String, unlocked: [UnlockedMilestone]) -> Milestone {
        let variant = unlocked.first(where: { $0.milestoneID == id })?.variantIndex
        return Milestone(id: id, kind: kind, variantIndex: variant, kicker: kicker, name: name, icon: icon, tier: tier, flavor: flavor, earned: earned, progress: progress, detail: detail)
    }

    private static func volume(id: String, kind: SkillKind, name: String, icon: String, tier: Milestone.Tier,
                               target: Int, total: Int, flavor: String, unlocked: [UnlockedMilestone]) -> Milestone {
        create(id: id, kind: kind, kicker: "MILESTONE", name: name, icon: icon, tier: tier,
               flavor: flavor, earned: total >= target,
               progress: min(1, Double(total) / Double(target)),
               detail: total >= target ? "\(total) reps logged" : "\(total) / \(target) reps", unlocked: unlocked)
    }

    private static func streak(id: String, kind: SkillKind, name: String, icon: String, tier: Milestone.Tier,
                               target: Int, best: Int, flavor: String, unlocked: [UnlockedMilestone]) -> Milestone {
        create(id: id, kind: kind, kicker: "MILESTONE", name: name, icon: icon, tier: tier,
               flavor: flavor, earned: best >= target,
               progress: min(1, Double(best) / Double(target)),
               detail: best >= target ? "\(best) hits in a row" : "best streak \(best) / \(target)", unlocked: unlocked)
    }
}
