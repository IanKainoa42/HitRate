import Foundation
import SwiftData

/// Seeds the exact dataset from the design handoff prototype (`BASE` in
/// ckil-review-core.jsx) so the dashboard can be diffed against the
/// handoff screenshots: today = 74% floor rate, 171 reps, 7 groups.
enum DemoData {
    // [hit, bobble, building fall, major fall] per group — today's session.
    private static let base: [(name: String, c: [Int])] = [
        ("Group 1", [23, 2, 0, 0]),
        ("Group 2", [22, 4, 1, 1]),
        ("Group 3", [21, 3, 2, 1]),
        ("Group 4", [15, 4, 2, 1]),
        ("Group 5", [11, 5, 4, 2]),
        ("Group 6", [19, 4, 2, 1]),
        ("Group 7", [16, 3, 1, 1]),
    ]

    // Floor-rate targets for prior sessions (prototype trend: ...60→71, today 74).
    private static let priorRates = [57, 60, 62, 60, 66, 63, 70, 69, 72, 71]

    static func seed(context: ModelContext) {
        // The demo dataset belongs to the active team — resolve (or create) it,
        // and only replace THAT team's roster so other teams' data is untouched.
        let allTeams = (try? context.fetch(FetchDescriptor<Team>())) ?? []
        let currentID = UserDefaults.standard.string(forKey: "currentTeamID") ?? ""
        let team: Team
        if let t = allTeams.first(where: { $0.id.uuidString == currentID }) ?? allTeams.first {
            team = t
        } else {
            team = Team(name: "My Team", orderIndex: 0)
            context.insert(team)
        }

        let allGroups = (try? context.fetch(FetchDescriptor<StuntGroup>())) ?? []
        for g in allGroups where g.team?.id == team.id { context.delete(g) }

        var groups: [StuntGroup] = []
        for (i, row) in base.enumerated() {
            let g = StuntGroup(name: row.name, number: i + 1, orderIndex: i)
            g.team = team
            context.insert(g)
            groups.append(g)
        }

        var rng = SeededRNG(seed: 20260604)
        let cal = Calendar.current

        // Prior sessions: practice days stepping back every ~2-3 days.
        var daysBack = priorRates.count * 3 - 1
        for rate in priorRates {
            let day = cal.date(byAdding: .day, value: -daysBack, to: .now)!
            let start = cal.date(bySettingHour: 18, minute: 41, second: 0, of: day)!
            seedSession(context: context, groups: groups, start: start,
                        totalReps: Int.random(in: 120...160, using: &rng),
                        targetRate: rate, rng: &rng)
            daysBack -= 3
        }

        // Today's session — exact BASE counts, rough patch mid-way.
        seedTodaySession(context: context, groups: groups, rng: &rng)
        try? context.save()
    }

    // MARK: Today (exact handoff counts)

    private static func seedTodaySession(context: ModelContext, groups: [StuntGroup], rng: inout SeededRNG) {
        let cal = Calendar.current
        var start = cal.date(bySettingHour: 18, minute: 41, second: 0, of: .now)!
        if start > .now { start = max(cal.startOfDay(for: .now), Date.now.addingTimeInterval(-43 * 60)) }
        let session = PracticeSession(startedAt: start)
        context.insert(session)

        // Build the multiset of (group, outcome) pairs.
        var pairs: [(Int, Outcome)] = []
        for (gi, row) in base.enumerated() {
            for (oi, n) in row.c.enumerated() {
                for _ in 0..<n { pairs.append((gi, Outcome(rawValue: oi)!)) }
            }
        }
        pairs.shuffle(using: &rng)

        // Cluster misses into a "rough patch" around 55–65% of the session.
        let n = pairs.count
        let patchStart = Int(Double(n) * 0.55)
        let patchEnd = min(n, patchStart + 12)
        var missIdx = pairs.indices.filter { !pairs[$0].1.isHit }
        for target in patchStart..<patchEnd {
            guard let src = missIdx.first(where: { $0 > patchEnd }) else { break }
            pairs.swapAt(target, src)
            missIdx = pairs.indices.filter { !pairs[$0].1.isHit }
        }

        let duration = 43.0 * 60
        for (i, pair) in pairs.enumerated() {
            let t = start.addingTimeInterval(Double(i) / Double(n) * duration)
            context.insert(Attempt(outcome: pair.1, group: groups[pair.0], session: session, timestamp: t))
        }
        session.endedAt = start.addingTimeInterval(duration)
    }

    // MARK: Prior sessions (rate-targeted)

    private static func seedSession(context: ModelContext, groups: [StuntGroup], start: Date,
                                    totalReps: Int, targetRate: Int, rng: inout SeededRNG) {
        let session = PracticeSession(startedAt: start)
        context.insert(session)

        let perGroup = totalReps / groups.count
        var i = 0
        let duration = Double.random(in: 38...48, using: &rng) * 60
        var stamps = 0
        let total = perGroup * groups.count
        for g in groups {
            // Jitter each group's rate around the session target.
            let r = max(20, min(98, targetRate + Int.random(in: -9...9, using: &rng)))
            let hits = Int((Double(perGroup) * Double(r) / 100).rounded())
            var outcomes: [Outcome] = Array(repeating: .hit, count: hits)
            for _ in 0..<(perGroup - hits) {
                let roll = Double.random(in: 0...1, using: &rng)
                outcomes.append(roll < 0.55 ? .bobble : roll < 0.85 ? .buildingFall : .majorFall)
            }
            outcomes.shuffle(using: &rng)
            for o in outcomes {
                let t = start.addingTimeInterval(Double(stamps) / Double(total) * duration)
                context.insert(Attempt(outcome: o, group: g, session: session, timestamp: t))
                stamps += 1
            }
            i += 1
        }
        session.endedAt = start.addingTimeInterval(duration)
    }
}

/// Deterministic RNG so demo data is stable run-to-run.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
