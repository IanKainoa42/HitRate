import Foundation
import SwiftData

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
    let kind: SkillKind    // picks the outcome wording for this bucket
    let counts: [Int]      // indexed by Outcome.rawValue
    let total: Int
    let hits: Int
    let rate: Int          // 0–100
    let delta: Int?        // vs previous comparable period; nil if no prior data

    var falls: Int { counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue] }
    var bobbles: Int { counts[Outcome.bobble.rawValue] }

    // Clean-hit lens (Ian: stats should center clean hits, not raw hit/bobble).
    // `rate` is already hits/total (a bobble is NOT a hit) — the clean-hit rate.
    /// Times the skill stayed up (clean hit or bobble — didn't hit the mat).
    var standUps: Int { hits + bobbles }
    /// Of the reps that stayed up, the share that were CLEAN (no bobble).
    /// "Cleanest" skill = highest purity.
    var purity: Double { standUps > 0 ? Double(hits) / Double(standUps) : 0 }
    /// Share of all reps that stayed off the mat. "Most consistent" = highest.
    var upRate: Double { total > 0 ? Double(standUps) / Double(total) : 0 }
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

    // MARK: Skill report (highlights / lowlights / improve)
    // Only skills with enough reps to mean something get ranked.

    static let insightMinReps = 6
    private var rankable: [GroupStat] { groups.filter { $0.total >= Self.insightMinReps } }

    /// Highest clean-hit rate — the skill to show off.
    var bestSkill: GroupStat? { rankable.max { $0.rate < $1.rate } }
    /// Lowest clean-hit rate — where to put the reps in. Only when there's a
    /// field to compare against (≥2 rankable skills).
    var worstSkill: GroupStat? {
        rankable.count >= 2 ? rankable.min { $0.rate < $1.rate } : nil
    }
    /// When it stays up, it's clean (fewest bobbles among stand-ups).
    var cleanestSkill: GroupStat? { rankable.max { $0.purity < $1.purity } }
    /// Rarely hits the mat (highest stayed-up share).
    var mostConsistentSkill: GroupStat? { rankable.max { $0.upRate < $1.upRate } }
    /// True once there's at least one skill with enough reps to report on.
    var hasSkillReport: Bool { !rankable.isEmpty }

    /// Which outcome wording aggregate views (legend, tape, team card) use:
    /// tumbling only when every bucket with data is tumbling, stunt otherwise.
    var aggregateKind: SkillKind {
        let withData = groups.filter { $0.total > 0 }
        return !withData.isEmpty && withData.allSatisfy { $0.kind == .tumbling }
            ? .tumbling : .stunt
    }
}

// MARK: - Engine

enum StatsEngine {

    static func compute(sessions: [PracticeSession], groups: [StuntGroup],
                        timeframe: Timeframe, now: Date = .now) -> FloorStats {
        let cal = Calendar.current
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        // Every derived number is confined to the passed groups — so a
        // kind-filtered view (stunt-only / tumbling-only) doesn't leak the
        // other kind's reps into the trend, tape, or rough patch.
        let allowed = Set(groups.map { $0.persistentModelID })

        // Partition attempts by timestamp, not just session start. A live
        // session can span midnight; today's reps still belong to today.
        let current: [PracticeSession]
        let currentInterval: DateInterval?
        let previous: [PracticeSession]
        let previousInterval: DateInterval?
        let deltaNote: String
        let rangeNote: String

        switch timeframe {
        case .today:
            let day = cal.dateInterval(of: .day, for: now)!
            current = sorted
            currentInterval = day
            previous = sorted.last { $0.startedAt < day.start }.map { [$0] } ?? []
            previousInterval = DateInterval(start: .distantPast, end: day.start)
            deltaNote = "vs last session"
            let n = min(8, max(sorted.count, 1))
            rangeNote = n == 1 ? "last session" : "last \(n) sessions"
        case .week:
            let week = cal.dateInterval(of: .weekOfYear, for: now)!
            current = sorted
            currentInterval = week
            let prevRef = cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            let prevWeek = cal.dateInterval(of: .weekOfYear, for: prevRef)!
            previous = sorted
            previousInterval = prevWeek
            deltaNote = "vs last week"
            rangeNote = "last 4 weeks"
        case .all:
            current = sorted
            currentInterval = nil
            previous = sorted.first.map { [$0] } ?? []
            previousInterval = nil
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
        var prevOverall = [0, 0, 0, 0]
        for g in ordered {
            let counts = outcomeCounts(in: current, group: g, within: currentInterval)
            let total = counts.reduce(0, +)
            let hits = counts[Outcome.hit.rawValue]
            let rate = weightedRate(counts)

            let prevCounts = outcomeCounts(in: previous, group: g, within: previousInterval)
            let prevTotal = prevCounts.reduce(0, +)
            for i in 0..<4 { prevOverall[i] += prevCounts[i] }
            var delta: Int?
            if total > 0, prevTotal > 0 {
                // For .all, compare against the first session (season start) — "growth since Sept".
                delta = rate - weightedRate(prevCounts)
            }

            groupStats.append(GroupStat(
                id: PersistentIdentifierBox(raw: "\(g.persistentModelID)"),
                name: g.name, number: g.number,
                colorIndex: (g.number - 1) % Theme.groupRainbow.count,
                kind: g.kind,
                counts: counts, total: total, hits: hits, rate: rate, delta: delta))
        }

        // Floor rollup.
        var overall = [0, 0, 0, 0]
        for s in groupStats { for i in 0..<4 { overall[i] += s.counts[i] } }
        let total = overall.reduce(0, +)
        let hits = overall[Outcome.hit.rawValue]
        let rate = weightedRate(overall)

        // prevOverall is rolled up from per-group counts (not raw session
        // attempts) so the floor delta and the per-group deltas agree — raw
        // attempts could include legacy orphans from before group-delete
        // cascaded.
        let prevTotal = prevOverall.reduce(0, +)
        var delta: Int?
        if total > 0, prevTotal > 0 {
            delta = rate - weightedRate(prevOverall)
        }

        return FloorStats(
            timeframe: timeframe,
            groups: groupStats,
            ranked: groupStats.filter { $0.total > 0 }.sorted { $0.rate > $1.rate }
                + groupStats.filter { $0.total == 0 },
            overall: overall, total: total, hits: hits, rate: rate,
            delta: delta, deltaNote: deltaNote, rangeNote: rangeNote,
            trend: trendSeries(sorted: sorted, allowed: allowed, timeframe: timeframe, now: now),
            latest: latestSnapshot(sorted: sorted, allowed: allowed))
    }

    // MARK: Trend series

    private static func trendSeries(sorted: [PracticeSession], allowed: Set<PersistentIdentifier>,
                                    timeframe: Timeframe, now: Date) -> [Int] {
        let cal = Calendar.current
        func rate(of sessions: [PracticeSession], within interval: DateInterval? = nil) -> Int? {
            var creditSum = 0, total = 0
            for s in sessions {
                for a in s.attempts
                    where a.group.map({ allowed.contains($0.persistentModelID) }) ?? false {
                    if let interval, !interval.contains(a.timestamp) { continue }
                    total += 1
                    creditSum += a.creditValue   // weighted: partial credit for decent/rough
                }
            }
            return total > 0 ? Int((Double(creditSum) / Double(total)).rounded()) : nil
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
                if let r = rate(of: sorted, within: interval) { points.append(r) }
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

    private static func latestSnapshot(sorted: [PracticeSession],
                                       allowed: Set<PersistentIdentifier>) -> SessionSnapshot? {
        // Latest session that has reps of an allowed kind — and only those reps
        // (a mixed session viewed under a kind filter shows just that kind's tape).
        func inKind(_ s: PracticeSession) -> [Attempt] {
            s.sortedAttempts.filter { $0.group.map { allowed.contains($0.persistentModelID) } ?? false }
        }
        guard let last = sorted.last(where: { !inKind($0).isEmpty }) else { return nil }
        let attempts = inKind(last)
        // Tape colors/rough-patch run off the credit tier, not the raw slot.
        let outcomes = attempts.map(\.tierOutcome)
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

    /// A skill's reps bucketed into the 4 credit TIERS (hit/decent/rough/miss),
    /// regardless of how many distinct outcomes it has — so aggregates stay
    /// 4-wide and crash-safe while logging carries any number of outcomes.
    private static func outcomeCounts(in sessions: [PracticeSession], group: StuntGroup,
                                      within interval: DateInterval? = nil) -> [Int] {
        var counts = [0, 0, 0, 0]
        for s in sessions {
            for a in s.attempts where a.group === group {
                if let interval, !interval.contains(a.timestamp) { continue }
                counts[a.tierOutcome.rawValue] += 1
            }
        }
        return counts
    }

    /// Weighted hit rate (0–100) from a 4-tier count array: credit ladder is
    /// hit 100 · decent 67 · rough 33 · miss 0, so a "decent" rep earns partial.
    static func weightedRate(_ tierCounts: [Int]) -> Int {
        let total = tierCounts.reduce(0, +)
        guard total > 0 else { return 0 }
        let credits = [100, 67, 33, 0]
        let sum = zip(tierCounts, credits).reduce(0) { $0 + $1.0 * $1.1 }
        return Int((Double(sum) / Double(total)).rounded())
    }
}
