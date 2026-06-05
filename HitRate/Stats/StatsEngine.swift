import Foundation

// MARK: - Timeframe (the global Home filter)

enum Timeframe: String, CaseIterable, Identifiable {
    case today, week, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .all: "All-time"
        }
    }
}

// MARK: - Derived stat shapes (mirrors buildData() in the handoff prototype)

struct GroupStat: Identifiable {
    let id: PersistentIdentifierBox
    let name: String
    let number: Int
    let colorIndex: Int
    let counts: [Int]      // indexed by Outcome.rawValue
    let total: Int
    let hits: Int
    let rate: Int          // 0–100
    let delta: Int?        // vs previous comparable period; nil if no prior data

    var falls: Int { counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue] }
}

/// Hashable wrapper so GroupStat can be Identifiable off a SwiftData id.
struct PersistentIdentifierBox: Hashable {
    let raw: String
}

struct SessionSnapshot {
    let outcomes: [Outcome]      // chronological
    let start: Date
    let end: Date
    let roughPatch: Range<Int>?  // index range of the worst stretch, if bad enough
}

struct FloorStats {
    let timeframe: Timeframe
    let groups: [GroupStat]      // display order
    let ranked: [GroupStat]      // by rate desc
    let overall: [Int]           // outcome counts
    let total: Int
    let hits: Int
    let rate: Int
    let delta: Int?
    let deltaNote: String
    let rangeNote: String
    let trend: [Int]
    let latest: SessionSnapshot?

    var falls: Int { overall[Outcome.buildingFall.rawValue] + overall[Outcome.majorFall.rawValue] }
    var best: GroupStat? { ranked.first }
    var worstFalls: GroupStat? { ranked.max { $0.falls < $1.falls } }
    var topMiss: Outcome? {
        let miss = Outcome.allCases.filter { !$0.isHit }.max { overall[$0.rawValue] < overall[$1.rawValue] }
        return (miss.map { overall[$0.rawValue] } ?? 0) > 0 ? miss : nil
    }
    var hasData: Bool { total > 0 }
}

// MARK: - Engine

enum StatsEngine {

    static func compute(sessions: [PracticeSession], groups: [StuntGroup],
                        timeframe: Timeframe, now: Date = .now) -> FloorStats {
        let cal = Calendar.current
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }

        // Partition sessions into current period vs the previous comparable period.
        let current: [PracticeSession]
        let previous: [PracticeSession]
        let deltaNote: String
        let rangeNote: String

        switch timeframe {
        case .today:
            current = sorted.filter { cal.isDateInToday($0.startedAt) }
            previous = sorted.last { !cal.isDateInToday($0.startedAt) }.map { [$0] } ?? []
            deltaNote = "vs last session"
            rangeNote = "last \(min(8, max(sorted.count, 1))) sessions"
        case .week:
            let week = cal.dateInterval(of: .weekOfYear, for: now)!
            current = sorted.filter { week.contains($0.startedAt) }
            let prevRef = cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            let prevWeek = cal.dateInterval(of: .weekOfYear, for: prevRef)!
            previous = sorted.filter { prevWeek.contains($0.startedAt) }
            deltaNote = "vs last week"
            rangeNote = "last 4 weeks"
        case .all:
            current = sorted
            previous = sorted.first.map { [$0] } ?? []
            if let first = sorted.first {
                let f = DateFormatter()
                f.dateFormat = "MMM"
                deltaNote = "since \(f.string(from: first.startedAt))"
            } else {
                deltaNote = "all season"
            }
            rangeNote = "all season"
        }

        // Per-group stats in the current and previous periods.
        let ordered = groups.sorted { $0.orderIndex < $1.orderIndex }
        var groupStats: [GroupStat] = []
        for g in ordered {
            let counts = outcomeCounts(in: current, group: g)
            let total = counts.reduce(0, +)
            let hits = counts[Outcome.hit.rawValue]
            let rate = total > 0 ? Int((Double(hits) / Double(total) * 100).rounded()) : 0

            let prevCounts = outcomeCounts(in: previous, group: g)
            let prevTotal = prevCounts.reduce(0, +)
            var delta: Int?
            if total > 0, prevTotal > 0 {
                // For .all, compare against the first session (season start) — "growth since Sept".
                let prevRate = Int((Double(prevCounts[Outcome.hit.rawValue]) / Double(prevTotal) * 100).rounded())
                delta = rate - prevRate
            }

            groupStats.append(GroupStat(
                id: PersistentIdentifierBox(raw: "\(g.persistentModelID)"),
                name: g.name, number: g.number,
                colorIndex: (g.number - 1) % Theme.groupRainbow.count,
                counts: counts, total: total, hits: hits, rate: rate, delta: delta))
        }

        // Floor rollup.
        var overall = [0, 0, 0, 0]
        for s in groupStats { for i in 0..<4 { overall[i] += s.counts[i] } }
        let total = overall.reduce(0, +)
        let hits = overall[Outcome.hit.rawValue]
        let rate = total > 0 ? Int((Double(hits) / Double(total) * 100).rounded()) : 0

        var prevOverall = [0, 0, 0, 0]
        for s in previous {
            for a in s.attempts { prevOverall[a.outcomeRaw] += 1 }
        }
        let prevTotal = prevOverall.reduce(0, +)
        var delta: Int?
        if total > 0, prevTotal > 0 {
            let prevRate = Int((Double(prevOverall[Outcome.hit.rawValue]) / Double(prevTotal) * 100).rounded())
            delta = rate - prevRate
        }

        return FloorStats(
            timeframe: timeframe,
            groups: groupStats,
            ranked: groupStats.filter { $0.total > 0 }.sorted { $0.rate > $1.rate }
                + groupStats.filter { $0.total == 0 },
            overall: overall, total: total, hits: hits, rate: rate,
            delta: delta, deltaNote: deltaNote, rangeNote: rangeNote,
            trend: trendSeries(sorted: sorted, timeframe: timeframe, now: now),
            latest: latestSnapshot(sorted: sorted))
    }

    // MARK: Trend series

    private static func trendSeries(sorted: [PracticeSession], timeframe: Timeframe, now: Date) -> [Int] {
        let cal = Calendar.current
        func rate(of sessions: [PracticeSession]) -> Int? {
            var hits = 0, total = 0
            for s in sessions {
                for a in s.attempts {
                    total += 1
                    if a.outcome.isHit { hits += 1 }
                }
            }
            return total > 0 ? Int((Double(hits) / Double(total) * 100).rounded()) : nil
        }

        switch timeframe {
        case .today:
            // Last 8 sessions, one point each.
            return sorted.suffix(8).compactMap { rate(of: [$0]) }
        case .week:
            // Last 4 calendar weeks with data, one point each.
            var points: [Int] = []
            for back in stride(from: 3, through: 0, by: -1) {
                guard let ref = cal.date(byAdding: .weekOfYear, value: -back, to: now),
                      let interval = cal.dateInterval(of: .weekOfYear, for: ref) else { continue }
                let inWeek = sorted.filter { interval.contains($0.startedAt) }
                if let r = rate(of: inWeek) { points.append(r) }
            }
            return points
        case .all:
            // Season bucketed into <=8 chronological chunks.
            guard !sorted.isEmpty else { return [] }
            let buckets = min(8, sorted.count)
            let chunk = Int(ceil(Double(sorted.count) / Double(buckets)))
            var points: [Int] = []
            var i = 0
            while i < sorted.count {
                let slice = Array(sorted[i..<min(i + chunk, sorted.count)])
                if let r = rate(of: slice) { points.append(r) }
                i += chunk
            }
            return points
        }
    }

    // MARK: Latest session tape

    private static func latestSnapshot(sorted: [PracticeSession]) -> SessionSnapshot? {
        guard let last = sorted.last(where: { !$0.attempts.isEmpty }) else { return nil }
        let attempts = last.sortedAttempts
        guard !attempts.isEmpty else { return nil }
        let outcomes = attempts.map(\.outcome)
        return SessionSnapshot(
            outcomes: outcomes,
            start: attempts.first!.timestamp,
            end: last.endedAt ?? attempts.last!.timestamp,
            roughPatch: roughPatch(in: outcomes))
    }

    /// Worst sliding window of 7 attempts; flagged if it has >=4 misses.
    static func roughPatch(in outcomes: [Outcome], window: Int = 7, minMisses: Int = 4) -> Range<Int>? {
        guard outcomes.count >= window else { return nil }
        var best = -1
        var bestStart = 0
        for start in 0...(outcomes.count - window) {
            let misses = outcomes[start..<start + window].filter { !$0.isHit }.count
            if misses > best {
                best = misses
                bestStart = start
            }
        }
        return best >= minMisses ? bestStart..<(bestStart + window) : nil
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
