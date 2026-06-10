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
    var isGhost = false    // the synthetic past-self competitor, not a real bucket

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
    var isGhost = false

    var scoreDisplay: String { game.scoreDisplay(score) }
}

/// One line of the season league — the local competitive ranking the weekly
/// games build. Points come from placements in completed weeks.
struct SeasonRank: Identifiable {
    let id: String         // group persistent id raw; "ghost" for the ghost
    let name: String
    let number: Int
    let colorIndex: Int
    let points: Int
    let cups: Int          // weeks won
    var rank: Int          // 1-based by points
    var isGhost = false
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
    var isGhost = false

    var scoreDisplay: String { game.scoreDisplay(score) }
}

// MARK: - The Ghost

/// The synthetic competitor every roster races — a ghost of the team's own
/// past, à la a handicap ghost player. Its baseline is the average WINNING
/// score of completed weeks this season replayed under the live game; a
/// deterministic per-week wobble sits on top, so some weeks the ghost shows
/// up hot and some weeks it's beatable. The wobble is seeded from the week
/// index — pure function, stable across launches and devices, no storage.
struct GhostEntry {
    let score: Int   // the wobbled metric the ghost plays at this week
    let rate: Int    // average winning rate — tiebreaks only
    let total: Int   // average winning volume — tiebreaks only

    // Display name — "spirit" is the cheer word for it; code keeps "ghost".
    static let name = "THE SPIRIT"
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
        // Ghost reps never count toward the week's real volume.
        let liveReps = entrants.reduce(0) { $0 + $1.total }

        // The ghost enters once the season has a completed week to haunt with.
        // Always "qualified" — it's the pace to beat, scored under the live
        // game like everyone else; its delta is vs last week's ghost.
        if let g = ghost(for: week, game: game, sessions: sessions, groups: ordered, cal: cal) {
            let prevGhost = ghost(for: prevWeek, game: game, sessions: sessions, groups: ordered, cal: cal)
            entrants.append(WeeklyStanding(
                id: PersistentIdentifierBox(raw: "ghost"),
                name: GhostEntry.name, number: 0, colorIndex: 0,
                kind: .stunt, counts: [0, 0, 0, 0], total: g.total, hits: 0,
                rate: g.rate, streak: 0, score: g.score,
                delta: prevGhost.map { g.score - $0.score },
                qualified: true, rank: 0, isGhost: true))
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

        // Last week's crown is contested by last week's ghost too (under last
        // week's game) — losing the week to your own pace is a real loss.
        let prevWeekGhost = ghost(for: prevWeek, game: prevGame, sessions: sessions,
                                  groups: ordered, cal: cal)
        let defending = (prevWeek.end > seasonStart(for: now)
            ? championOf(sessions: lastWeekSessions, groups: ordered, game: prevGame,
                         ghost: prevWeekGhost) : nil)
            .map { champ in
                if let g = champ.group {
                    DefendingChampion(name: g.name, number: g.number,
                                      colorIndex: (g.number - 1) % Theme.groupRainbow.count,
                                      game: prevGame, score: champ.score)
                } else {
                    DefendingChampion(name: GhostEntry.name, number: 0, colorIndex: 0,
                                      game: prevGame, score: champ.score, isGhost: true)
                }
            }

        return WeeklyTournament(
            week: week,
            game: game,
            standings: standings,
            champion: standings.first.flatMap { $0.qualified ? $0 : nil },
            frontRunner: provisional.first,
            defending: defending,
            league: seasonLeague(sessions: sessions, groups: ordered, cal: cal, now: now),
            minReps: game.minReps,
            totalReps: liveReps)
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

    /// Each group's qualified tiebreak key under a game — shared by placements
    /// and the ghost's baseline.
    private static func qualifiedEntries(sessions: [PracticeSession], groups: [StuntGroup],
                                         game: WeeklyGame) -> [(key: (Int, Int, Int, Int), g: StuntGroup)] {
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
        return entries
    }

    /// Qualified finishers of a given week's sessions under a given game,
    /// best first — the basis for the crown AND for season points. The ghost
    /// (group == nil) races in the same field; it carries zero falls, so a
    /// tied week goes to the ghost — beat it, don't match it.
    private static func placements(sessions: [PracticeSession], groups: [StuntGroup],
                                   game: WeeklyGame, ghost: GhostEntry?) -> [(group: StuntGroup?, score: Int)] {
        var entries: [(key: (Int, Int, Int, Int), g: StuntGroup?)] = qualifiedEntries(
            sessions: sessions, groups: groups, game: game).map { ($0.key, $0.g) }
        if let ghost {
            entries.append(((ghost.score, ghost.rate, ghost.total, 0), nil))
        }
        return entries.sorted { outranks($0.key, $1.key) }.map { ($0.g, $0.key.0) }
    }

    private static func championOf(sessions: [PracticeSession], groups: [StuntGroup],
                                   game: WeeklyGame, ghost: GhostEntry?) -> (group: StuntGroup?, score: Int)? {
        placements(sessions: sessions, groups: groups, game: game, ghost: ghost).first
    }

    /// The ghost's entry for a given week: average the WINNING score of every
    /// completed week strictly before it (this season, replayed under the
    /// given game), then apply a seeded wobble so the ghost has good weeks and
    /// off weeks. Nil until the season has a completed qualifying week.
    static func ghost(for week: DateInterval, game: WeeklyGame,
                      sessions: [PracticeSession], groups: [StuntGroup],
                      cal: Calendar) -> GhostEntry? {
        guard let firstStart = sessions.map(\.startedAt).min() else { return nil }
        let floor = max(firstStart, seasonStart(for: week.start))
        var winners: [(score: Int, rate: Int, total: Int)] = []
        for back in 1...60 {
            guard let ref = cal.date(byAdding: .weekOfYear, value: -back, to: week.start),
                  let interval = cal.dateInterval(of: .weekOfYear, for: ref) else { continue }
            if interval.end <= floor { break }
            let weekSessions = sessions.filter { interval.contains($0.startedAt) }
            guard !weekSessions.isEmpty else { continue }
            guard let best = qualifiedEntries(sessions: weekSessions, groups: groups, game: game)
                .sorted(by: { outranks($0.key, $1.key) }).first else { continue }
            winners.append((best.key.0, best.key.1, best.key.2))
        }
        guard !winners.isEmpty else { return nil }

        let avg = { (vals: [Int]) in Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded()) }
        let baseline = avg(winners.map(\.score))

        // Deterministic luck: the week index seeds the roll, so the ghost's
        // form for any given week is fixed — recomputes can't reroll it.
        let weekIndex = Int(week.start.timeIntervalSinceReferenceDate / 604_800)
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(weekIndex &* 3 &+ game.rawValue)))
        let wobble = Double.random(in: -1...1, using: &rng)
        let score: Int
        switch game {
        case .rate:
            score = min(100, max(0, baseline + Int((wobble * 6).rounded())))
        case .grind, .streak:
            score = max(1, baseline + Int((wobble * 0.15 * Double(max(7, baseline))).rounded()))
        }
        return GhostEntry(score: score, rate: avg(winners.map(\.rate)), total: avg(winners.map(\.total)))
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
        var acc: [String: (name: String, number: Int, colorIndex: Int, isGhost: Bool,
                           points: Int, cups: Int)] = [:]
        for back in 1...60 {   // a full season's worth of weeks; bounds the replay
            guard let ref = cal.date(byAdding: .weekOfYear, value: -back, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: ref) else { continue }
            if interval.end <= floor { break }
            let weekSessions = sessions.filter { interval.contains($0.startedAt) }
            guard !weekSessions.isEmpty else { continue }
            let game = WeeklyGame.of(week: interval)
            // Each replayed week races the ghost it had at the time — the
            // ghost of week W only knows the weeks before W.
            let weekGhost = ghost(for: interval, game: game, sessions: sessions,
                                  groups: groups, cal: cal)
            for (i, p) in placements(sessions: weekSessions, groups: groups, game: game,
                                     ghost: weekGhost).enumerated() {
                let key = p.group.map { "\($0.persistentModelID)" } ?? "ghost"
                var cur = acc[key] ?? (p.group?.name ?? GhostEntry.name,
                                       p.group?.number ?? 0,
                                       p.group.map { ($0.number - 1) % Theme.groupRainbow.count } ?? 0,
                                       p.group == nil, 0, 0)
                cur.points += i < podiumPoints.count ? podiumPoints[i] : 1
                if i == 0 { cur.cups += 1 }
                acc[key] = cur
            }
        }
        var table = acc.map { SeasonRank(
            id: $0.key, name: $0.value.name, number: $0.value.number,
            colorIndex: $0.value.colorIndex,
            points: $0.value.points, cups: $0.value.cups, rank: 0,
            isGhost: $0.value.isGhost) }
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
            let weekGhost = ghost(for: interval, game: game, sessions: sessions,
                                  groups: ordered, cal: cal)
            guard let champ = championOf(sessions: weekSessions, groups: ordered, game: game,
                                         ghost: weekGhost) else { continue }
            cups.append(WeeklyCup(
                id: "\(interval.start.timeIntervalSinceReferenceDate)",
                week: interval, game: game,
                winnerName: champ.group?.name ?? GhostEntry.name,
                winnerNumber: champ.group?.number ?? 0,
                colorIndex: champ.group.map { ($0.number - 1) % Theme.groupRainbow.count } ?? 0,
                score: champ.score,
                isGhost: champ.group == nil))
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
                guard let outcome = Outcome(rawValue: a.outcomeRaw) else { continue }
                counts[outcome.rawValue] += 1
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
