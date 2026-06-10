import Foundation
import SwiftData

// MARK: - Weekly games (the rotating cup)

/// The built-in weekly competition. Each calendar week one of THREE GAMES is
/// live — the rotation is derived from the week itself (week-of-epoch mod 3),
/// so it's a pure function with no storage and flips automatically at the
/// week boundary:
///   RATE CUP   — best clean-hit rate (min 10 reps)
///   GRIND CUP  — most reps logged, volume wins
///   STREAK CUP — longest run of clean hits (min 5 reps)
/// Deliberately week-scoped and INDEPENDENT of the Home timeframe filter —
/// the cup is always "this week", whatever the dashboard is showing. Rate is
/// hits/total (a bobble is NOT a hit) so the numbers agree with StatsEngine.

enum WeeklyGame: Int, CaseIterable {
    case rate, grind, streak

    /// Which game a given calendar week plays. Floor-divide the week's start
    /// into a week-of-epoch index so the rotation is stable across launches
    /// and devices — no stored state to drift.
    static func of(week: DateInterval) -> WeeklyGame {
        let weekIndex = Int(week.start.timeIntervalSinceReferenceDate / 604_800)
        return WeeklyGame(rawValue: ((weekIndex % 3) + 3) % 3)!
    }

    /// Next week's game — the rotation is rawValue order.
    var next: WeeklyGame { WeeklyGame(rawValue: (rawValue + 1) % 3)! }

    var name: String {
        switch self {
        case .rate: "RATE CUP"
        case .grind: "GRIND CUP"
        case .streak: "STREAK CUP"
        }
    }

    var icon: String {
        switch self {
        case .rate: "percent"
        case .grind: "flame.fill"
        case .streak: "bolt.fill"
        }
    }

    /// Reps a skill/group needs this week to be eligible for the crown — keeps
    /// a lucky handful of reps from "winning" the week. Grind is pure volume,
    /// so any rep enters the race.
    var minReps: Int {
        switch self {
        case .rate: 25
        case .grind: 1
        case .streak: 25
        }
    }

    var rules: String {
        switch self {
        case .rate: "Best clean-hit rate takes the week · min \(minReps) reps"
        case .grind: "Most reps logged takes the week — volume wins"
        case .streak: "Longest run of clean hits takes the week · min \(minReps) reps"
        }
    }

    /// This week's metric for one entrant.
    func score(rate: Int, total: Int, streak: Int) -> Int {
        switch self {
        case .rate: rate
        case .grind: total
        case .streak: streak
        }
    }

    /// Unit chip after the big number ("82%", "64 REPS", "12 STREAK").
    var unit: String {
        switch self {
        case .rate: "%"
        case .grind: "REPS"
        case .streak: "STREAK"
        }
    }

    /// Sentence form for footers ("82%", "64 reps", "12 in a row").
    func scoreDisplay(_ score: Int) -> String {
        switch self {
        case .rate: "\(score)%"
        case .grind: "\(score) rep\(score == 1 ? "" : "s")"
        case .streak: "\(score) in a row"
        }
    }

    /// Only the rate game colors its score with the rate bands — reps and
    /// streaks aren't percentages, they stay chalk.
    var scoreUsesRateBands: Bool { self == .rate }
}

// MARK: - Standings

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
    let streak: Int        // longest clean-hit run this week
    let score: Int         // this week's GAME metric (rate %, reps, or streak)
    let delta: Int?        // score vs the same skill/group last week; nil if it didn't play
    let qualified: Bool    // cleared the game's rep minimum, eligible for the crown
    var rank: Int          // 1-based among qualified entrants; 0 = not ranked

    var falls: Int { counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue] }

    /// Reps still needed to qualify for the crown.
    func repsToQualify(min: Int) -> Int { max(0, min - total) }
}

/// Last week's winner — the title the current week is played to defend.
struct DefendingChampion {
    let name: String
    let number: Int
    let colorIndex: Int
    let game: WeeklyGame   // last week's game, not this week's
    let score: Int

    var scoreDisplay: String { game.scoreDisplay(score) }
}

/// One line of the season league — the local competitive ranking the weekly
/// games build. Points come from placements in completed weeks.
struct SeasonRank: Identifiable {
    let id: String         // group persistent id raw
    let name: String
    let number: Int
    let colorIndex: Int
    let points: Int
    let cups: Int          // weeks won
    var rank: Int          // 1-based by points
}

/// A banked championship — one completed week a skill/group won, under that
/// week's game. The trophy room's cup shelf.
struct WeeklyCup: Identifiable {
    let id: String         // week-start timestamp
    let week: DateInterval
    let game: WeeklyGame
    let winnerName: String
    let winnerNumber: Int
    let colorIndex: Int
    let score: Int

    var scoreDisplay: String { game.scoreDisplay(score) }
}

struct WeeklyTournament {
    let week: DateInterval
    let game: WeeklyGame
    /// Every entrant (≥1 rep this week), qualified first (ranked by the game's
    /// metric), then provisional entrants (by reps) still under the minimum.
    let standings: [WeeklyStanding]
    /// Top qualified entrant — the crowned champion. Nil until someone qualifies.
    let champion: WeeklyStanding?
    /// The front-runner shown while no one has qualified yet (most reps logged).
    let frontRunner: WeeklyStanding?
    /// Last week's champion (of last week's game), if one was crowned.
    let defending: DefendingChampion?
    /// The season league table — points from completed weeks, most first.
    let league: [SeasonRank]
    let minReps: Int
    let totalReps: Int

    /// Anyone logged a rep toward the cup this week.
    var hasEntrants: Bool { !standings.isEmpty }
    /// Worth surfacing the cup: live action, a title to defend, or a season
    /// table worth checking.
    var isLive: Bool { hasEntrants || defending != nil || !league.isEmpty }
    /// Entrants still chasing the rep minimum.
    var provisional: [WeeklyStanding] { standings.filter { !$0.qualified } }
}

// MARK: - Engine

enum WeeklyLeague {

    static func compute(sessions: [PracticeSession], groups: [StuntGroup],
                        now: Date = .now) -> WeeklyTournament {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 0)
        let game = WeeklyGame.of(week: week)
        let prevRef = cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        let prevWeek = cal.dateInterval(of: .weekOfYear, for: prevRef) ?? week
        let prevGame = WeeklyGame.of(week: prevWeek)

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
            let streak = longestStreak(in: thisWeekSessions, group: g)
            let score = game.score(rate: rate, total: total, streak: streak)

            // Delta = the SAME game metric for the same group last week, so the
            // arrow always speaks this week's language (rate pts, reps, streak).
            let prevCounts = outcomeCounts(in: lastWeekSessions, group: g)
            let prevTotal = prevCounts.reduce(0, +)
            var delta: Int?
            if prevTotal > 0 {
                let prevRate = Int((Double(prevCounts[Outcome.hit.rawValue]) / Double(prevTotal) * 100).rounded())
                let prevStreak = longestStreak(in: lastWeekSessions, group: g)
                delta = score - game.score(rate: prevRate, total: prevTotal, streak: prevStreak)
            }

            entrants.append(WeeklyStanding(
                id: PersistentIdentifierBox(raw: "\(g.persistentModelID)"),
                name: g.name, number: g.number,
                colorIndex: (g.number - 1) % Theme.groupRainbow.count,
                kind: g.kind, counts: counts, total: total, hits: hits, rate: rate,
                streak: streak, score: score, delta: delta,
                qualified: total >= game.minReps, rank: 0))
        }

        // Qualified entrants race on the game's metric; provisional entrants
        // sort by who's closest to qualifying (most reps).
        let qualified = entrants.filter(\.qualified)
            .sorted { outranks(($0.score, $0.rate, $0.total, $0.falls),
                               ($1.score, $1.rate, $1.total, $1.falls)) }
        let provisional = entrants.filter { !$0.qualified }.sorted {
            $0.total != $1.total ? $0.total > $1.total : $0.score > $1.score
        }

        var standings = qualified
        for i in standings.indices { standings[i].rank = i + 1 }
        standings += provisional   // rank stays 0

        let defending = (prevWeek.end > seasonStart(for: now)
            ? championOf(sessions: lastWeekSessions, groups: ordered, game: prevGame) : nil)
            .map { DefendingChampion(name: $0.group.name, number: $0.group.number,
                                     colorIndex: ($0.group.number - 1) % Theme.groupRainbow.count,
                                     game: prevGame, score: $0.score) }

        return WeeklyTournament(
            week: week,
            game: game,
            standings: standings,
            champion: standings.first.flatMap { $0.qualified ? $0 : nil },
            frontRunner: provisional.first,
            defending: defending,
            league: seasonLeague(sessions: sessions, groups: ordered, cal: cal, now: now),
            minReps: game.minReps,
            totalReps: entrants.reduce(0) { $0 + $1.total })
    }

    /// Tiebreak chain shared by standings and past-week champions:
    /// game score, then rate, then volume, then fewer falls.
    private static func outranks(_ a: (score: Int, rate: Int, total: Int, falls: Int),
                                 _ b: (score: Int, rate: Int, total: Int, falls: Int)) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.rate != b.rate { return a.rate > b.rate }
        if a.total != b.total { return a.total > b.total }
        return a.falls < b.falls
    }

    /// Qualified finishers of a given week's sessions under a given game,
    /// best first — the basis for the crown AND for season points.
    private static func placements(sessions: [PracticeSession], groups: [StuntGroup],
                                   game: WeeklyGame) -> [(group: StuntGroup, score: Int)] {
        var entries: [(key: (Int, Int, Int, Int), g: StuntGroup)] = []
        for g in groups {
            let counts = outcomeCounts(in: sessions, group: g)
            let total = counts.reduce(0, +)
            guard total >= game.minReps else { continue }
            let rate = Int((Double(counts[Outcome.hit.rawValue]) / Double(total) * 100).rounded())
            let streak = longestStreak(in: sessions, group: g)
            let falls = counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue]
            entries.append(((game.score(rate: rate, total: total, streak: streak), rate, total, falls), g))
        }
        return entries.sorted { outranks($0.key, $1.key) }.map { ($0.g, $0.key.0) }
    }

    private static func championOf(sessions: [PracticeSession], groups: [StuntGroup],
                                   game: WeeklyGame) -> (group: StuntGroup, score: Int)? {
        placements(sessions: sessions, groups: groups, game: game).first
    }

    /// Points by weekly placement: win 5, 2nd 3, 3rd 2, any other qualified
    /// finisher 1 — qualifying at all is worth something.
    static let podiumPoints = [5, 3, 2]

    /// The season league — every COMPLETED week is replayed under ITS game
    /// (the rotation is derivable for any week) and placements pay points, so
    /// the ranking stays correct with zero storage. The live week doesn't
    /// score until it ends; the crown isn't final mid-week.
    private static func seasonLeague(sessions: [PracticeSession], groups: [StuntGroup],
                                     cal: Calendar, now: Date) -> [SeasonRank] {
        guard let firstStart = sessions.map(\.startedAt).min() else { return [] }
        // Reset every season: never replay past the later of first data or the
        // June rollover, so last season's points don't carry over.
        let floor = max(firstStart, seasonStart(for: now))
        var acc: [String: (g: StuntGroup, points: Int, cups: Int)] = [:]
        for back in 1...60 {   // a full season's worth of weeks; bounds the replay
            guard let ref = cal.date(byAdding: .weekOfYear, value: -back, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: ref) else { continue }
            if interval.end <= floor { break }
            let weekSessions = sessions.filter { interval.contains($0.startedAt) }
            guard !weekSessions.isEmpty else { continue }
            let game = WeeklyGame.of(week: interval)
            for (i, p) in placements(sessions: weekSessions, groups: groups, game: game).enumerated() {
                let key = "\(p.group.persistentModelID)"
                var cur = acc[key] ?? (p.group, 0, 0)
                cur.points += i < podiumPoints.count ? podiumPoints[i] : 1
                if i == 0 { cur.cups += 1 }
                acc[key] = cur
            }
        }
        var table = acc.map { SeasonRank(
            id: $0.key, name: $0.value.g.name, number: $0.value.g.number,
            colorIndex: ($0.value.g.number - 1) % Theme.groupRainbow.count,
            points: $0.value.points, cups: $0.value.cups, rank: 0) }
        table.sort {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.cups != $1.cups { return $0.cups > $1.cups }
            return $0.name < $1.name
        }
        for i in table.indices { table[i].rank = i + 1 }
        return table
    }

    /// Every championship banked in COMPLETED weeks this season, most recent
    /// first — each week judged under ITS own game. Drives the trophy room's
    /// cup shelf; the in-progress current week isn't banked until it ends.
    static func cupHistory(sessions: [PracticeSession], groups: [StuntGroup],
                           now: Date = .now) -> [WeeklyCup] {
        let cal = Calendar.current
        guard let firstStart = sessions.map(\.startedAt).min() else { return [] }
        // Reset every season — cups won last season don't carry into this one.
        let floor = max(firstStart, seasonStart(for: now))
        let ordered = groups.sorted { $0.orderIndex < $1.orderIndex }
        var cups: [WeeklyCup] = []
        for back in 1...60 {
            guard let ref = cal.date(byAdding: .weekOfYear, value: -back, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: ref) else { continue }
            if interval.end <= floor { break }
            let weekSessions = sessions.filter { interval.contains($0.startedAt) }
            guard !weekSessions.isEmpty else { continue }
            let game = WeeklyGame.of(week: interval)
            guard let champ = championOf(sessions: weekSessions, groups: ordered, game: game) else { continue }
            cups.append(WeeklyCup(
                id: "\(interval.start.timeIntervalSinceReferenceDate)",
                week: interval, game: game,
                winnerName: champ.group.name, winnerNumber: champ.group.number,
                colorIndex: (champ.group.number - 1) % Theme.groupRainbow.count,
                score: champ.score))
        }
        return cups   // already newest-first (back grows into the past)
    }

    /// Longest run of consecutive clean hits across the week's sessions,
    /// chronological — a fall OR a bobble breaks it (a bobble is not a hit).
    private static func longestStreak(in sessions: [PracticeSession], group: StuntGroup) -> Int {
        let attempts = sessions
            .flatMap { s in s.attempts.filter { $0.group === group } }
            .sorted { $0.timestamp < $1.timestamp }
        var best = 0, run = 0
        for a in attempts {
            if a.outcome.isHit {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
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
