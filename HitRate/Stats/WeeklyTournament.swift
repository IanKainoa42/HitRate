import Foundation
import SwiftData

// MARK: - Weekly tournament (the "cup")

/// The built-in weekly game: every skill/group competes on its clean-hit rate
/// for the current calendar week, and the best one (with enough reps to count)
/// is crowned champion. Deliberately week-scoped and INDEPENDENT of the Home
/// timeframe filter — the cup is always "this week", whatever the dashboard is
/// showing. Rate is hits/total (a bobble is NOT a hit) so the numbers agree
/// with StatsEngine and the rest of the app.

/// One competitor's line in the weekly standings.
struct WeeklyStanding: Identifiable {
    let id: PersistentIdentifierBox
    let name: String
    let number: Int
    let colorIndex: Int
    let kind: SkillKind
    let counts: [Int]      // indexed by Outcome.rawValue
    let total: Int
    let hits: Int
    let rate: Int          // 0–100, clean-hit rate
    let delta: Int?        // vs the same skill/group last week; nil if no prior reps
    let qualified: Bool    // cleared the rep minimum, so eligible for the crown
    var rank: Int          // 1-based among qualified entrants; 0 = not ranked

    /// Reps still needed to qualify for the crown.
    func repsToQualify(min: Int) -> Int { max(0, min - total) }
}

/// Last week's winner — the title the current week is played to defend.
struct DefendingChampion {
    let name: String
    let number: Int
    let colorIndex: Int
    let rate: Int
}

struct WeeklyTournament {
    let week: DateInterval
    /// Every entrant (≥1 rep this week), qualified first (ranked by rate), then
    /// provisional entrants (by reps) who haven't met the minimum yet.
    let standings: [WeeklyStanding]
    /// Top qualified entrant — the crowned champion. Nil until someone qualifies.
    let champion: WeeklyStanding?
    /// The front-runner shown while no one has qualified yet (most reps logged).
    let frontRunner: WeeklyStanding?
    /// Last week's champion, if one was crowned.
    let defending: DefendingChampion?
    let minReps: Int
    let totalReps: Int

    /// Anyone logged a rep toward the cup this week.
    var hasEntrants: Bool { !standings.isEmpty }
    /// Worth surfacing the cup: there's live action or a title to defend.
    var isLive: Bool { hasEntrants || defending != nil }
    /// Entrants still chasing the rep minimum.
    var provisional: [WeeklyStanding] { standings.filter { !$0.qualified } }
}

enum WeeklyLeague {
    /// Reps a skill/group needs this week to be eligible for the crown — keeps
    /// a single lucky rep from "winning" the week.
    static let minReps = 10

    static func compute(sessions: [PracticeSession], groups: [StuntGroup],
                        now: Date = .now) -> WeeklyTournament {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 0)
        let prevRef = cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        let prevWeek = cal.dateInterval(of: .weekOfYear, for: prevRef) ?? week

        let thisWeekSessions = sessions.filter { week.contains($0.startedAt) }
        let lastWeekSessions = sessions.filter { prevWeek.contains($0.startedAt) }
        let ordered = groups.sorted { $0.orderIndex < $1.orderIndex }

        // Build a standing per group that logged at least one rep this week.
        var entrants: [WeeklyStanding] = []
        for g in ordered {
            let counts = outcomeCounts(in: thisWeekSessions, group: g)
            let total = counts.reduce(0, +)
            guard total > 0 else { continue }
            let hits = counts[Outcome.hit.rawValue]
            let rate = Int((Double(hits) / Double(total) * 100).rounded())

            let prevCounts = outcomeCounts(in: lastWeekSessions, group: g)
            let prevTotal = prevCounts.reduce(0, +)
            let delta: Int? = prevTotal > 0
                ? rate - Int((Double(prevCounts[Outcome.hit.rawValue]) / Double(prevTotal) * 100).rounded())
                : nil

            entrants.append(WeeklyStanding(
                id: PersistentIdentifierBox(raw: "\(g.persistentModelID)"),
                name: g.name, number: g.number,
                colorIndex: (g.number - 1) % Theme.groupRainbow.count,
                kind: g.kind, counts: counts, total: total, hits: hits, rate: rate,
                delta: delta, qualified: total >= minReps, rank: 0))
        }

        // Qualified entrants race on rate (tiebreak: more reps, then fewer falls);
        // provisional entrants sort by who's closest to qualifying (most reps).
        let qualified = entrants.filter(\.qualified).sorted {
            if $0.rate != $1.rate { return $0.rate > $1.rate }
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.falls < $1.falls
        }
        let provisional = entrants.filter { !$0.qualified }.sorted {
            $0.total != $1.total ? $0.total > $1.total : $0.rate > $1.rate
        }

        var standings = qualified
        for i in standings.indices { standings[i].rank = i + 1 }
        standings += provisional   // rank stays 0

        return WeeklyTournament(
            week: week,
            standings: standings,
            champion: standings.first.flatMap { $0.qualified ? $0 : nil },
            frontRunner: provisional.first,
            defending: championOf(sessions: lastWeekSessions, groups: ordered),
            minReps: minReps,
            totalReps: entrants.reduce(0) { $0 + $1.total })
    }

    /// The crowned champion of a given week's sessions, if anyone qualified.
    private static func championOf(sessions: [PracticeSession],
                                   groups: [StuntGroup]) -> DefendingChampion? {
        var best: (rate: Int, total: Int, falls: Int, g: StuntGroup)?
        for g in groups {
            let counts = outcomeCounts(in: sessions, group: g)
            let total = counts.reduce(0, +)
            guard total >= minReps else { continue }
            let rate = Int((Double(counts[Outcome.hit.rawValue]) / Double(total) * 100).rounded())
            let falls = counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue]
            if let b = best {
                let better = rate > b.rate
                    || (rate == b.rate && total > b.total)
                    || (rate == b.rate && total == b.total && falls < b.falls)
                if better { best = (rate, total, falls, g) }
            } else {
                best = (rate, total, falls, g)
            }
        }
        guard let b = best else { return nil }
        return DefendingChampion(name: b.g.name, number: b.g.number,
                                 colorIndex: (b.g.number - 1) % Theme.groupRainbow.count,
                                 rate: b.rate)
    }

    private static func outcomeCounts(in sessions: [PracticeSession], group: StuntGroup) -> [Int] {
        var counts = [0, 0, 0, 0]
        for s in sessions {
            for a in s.attempts where a.group === group {
                counts[a.outcomeRaw] += 1
            }
        }
        return counts
    }
}

extension WeeklyStanding {
    var falls: Int { counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue] }
}

extension DateInterval {
    /// "JUN 8–14" style label for the cup's week.
    var weekLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let cal = Calendar.current
        let last = cal.date(byAdding: .day, value: -1, to: end) ?? end
        let startStr = f.string(from: start).uppercased()
        // Same month → "JUN 8–14"; spanning months → "JUN 29–JUL 5".
        if cal.isDate(start, equalTo: last, toGranularity: .month) {
            let dayOnly = DateFormatter(); dayOnly.dateFormat = "d"
            return "\(startStr)–\(dayOnly.string(from: last))"
        }
        return "\(startStr)–\(f.string(from: last).uppercased())"
    }
}
