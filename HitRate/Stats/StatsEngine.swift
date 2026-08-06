import Foundation
import SwiftData
import CheerRulesKit

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

// MARK: - Logger source filter (co-logged folders)

/// Slices a shared folder's reps by WHO logged them — the coach running a
/// private lesson vs the athlete logging their own open-gym work.
///
/// Only meaningful on a co-logged folder. A folder nobody else has joined has
/// no owner/member split to draw, so `ownerUID` nil collapses every scope to
/// "everything" rather than silently zeroing the dashboard — HomeView also
/// hides the control there.
struct LoggerFilter: Equatable {
    enum Scope: String, CaseIterable, Identifiable, Equatable {
        /// Every rep, however it was logged.
        case all
        /// Logged by the folder owner — coach-run reps ("privates").
        case coach
        /// Logged by anyone else — the athlete's own reps ("open gym").
        case selfLogged

        var id: String { rawValue }

        /// Segmented-control wording — the coach's mental model, not the
        /// plumbing's ("who logged it" reads as an audit trail; "privates vs
        /// open gym" reads as the two kinds of practice it actually describes).
        var label: String {
            switch self {
            case .all: "ALL"
            case .coach: "PRIVATES"
            case .selfLogged: "OPEN GYM"
            }
        }
    }

    var scope: Scope = .all
    /// The folder's cloud owner (the coach). nil = not a shared folder.
    var ownerUID: String? = nil
    /// This device's signed-in uid — an unstamped local rep resolves to it, the
    /// same claim SyncEngine makes on upload.
    var currentUID: String? = nil

    static let unfiltered = LoggerFilter()

    /// True when the filter can actually split anything: a scope other than
    /// `.all`, on a folder that has a cloud owner to compare against.
    var isActive: Bool {
        guard scope != .all else { return false }
        guard let owner = ownerUID, !owner.isEmpty else { return false }
        return true
    }

    func matches(_ attempt: Attempt) -> Bool {
        guard isActive else { return true }
        let byCoach = attempt.isCoachLogged(teamOwnerUID: ownerUID, currentUID: currentUID)
        return scope == .coach ? byCoach : !byCoach
    }
}

// MARK: - Derived stat shapes (mirrors buildData() in the handoff prototype)

struct GroupStat: Identifiable {
    let id: PersistentIdentifierBox
    let name: String
    let number: Int
    let colorIndex: Int
    let kind: SkillKind    // picks the outcome wording for this bucket
    let category: SkillCategory        // this skill's real United category — drives the card icon
    let tierDefs: [OutcomeDef]         // this skill's own outcome label+color per tier — drives the card chips
    let counts: [Int]      // indexed by Outcome.rawValue
    let total: Int
    let hits: Int
    let rate: Int          // 0–100
    let delta: Int?        // vs previous comparable period; nil if no prior data

    var falls: Int { counts[Outcome.buildingFall.rawValue] + counts[Outcome.majorFall.rawValue] }
    var bobbles: Int { counts[Outcome.bobble.rawValue] }

    // Clean-hit lens remains available alongside the weighted headline rate.
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

/// One row of the EXECUTION breakdown (Feature B): how often a single United
/// execution driver HELD across the reps where execution was actually scored.
/// The denominator is scored-reps-only, so a driver never reads as "clean" from
/// reps nobody judged (the non-inflating rule made visible).
struct ExecutionDriverStat: Identifiable {
    let key: String
    let name: String            // "Body Control"
    let categoryName: String    // "Standing Tumbling" — groups rows by category
    let scored: Int             // scored reps whose skill carries this driver
    let held: Int               // of those, how many kept the driver

    var id: String { key }
    var lost: Int { scored - held }
    /// Hold rate 0–100 (share of scored reps where the driver stayed clean).
    var holdRate: Int { scored > 0 ? Int((Double(held) / Double(scored) * 100).rounded()) : 0 }
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
    /// Execution breakdown (Feature B), driver rows ordered by category then sheet
    /// order. Empty when no reps in range were execution-scored.
    let execution: [ExecutionDriverStat]
    /// How many reps in range carried a committed execution read — the shared
    /// denominator context for the whole breakdown ("scored on N of M reps").
    let executionScoredReps: Int

    /// True once at least one rep in range was execution-scored — gates the card.
    var hasExecution: Bool { executionScoredReps > 0 && !execution.isEmpty }

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

    /// Highest weighted hit rate — the skill to show off.
    var bestSkill: GroupStat? { rankable.max { $0.rate < $1.rate } }
    /// Lowest weighted hit rate — where to put the reps in. Only when there's a
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

    /// `subject` is the cross-cutting PERSON filter (Phase 4 review): non-nil
    /// confines every number to that athlete/group's reps, on top of the group
    /// (skill) confinement the caller already applies via `groups`. nil = everyone.
    ///
    /// `logger` is the co-logging SOURCE filter: on a shared folder it confines
    /// every number to coach-logged reps (privates) or athlete-logged reps (open
    /// gym). Default is unfiltered, so every existing call site is unchanged.
    static func compute(sessions: [PracticeSession], groups: [StuntGroup],
                        timeframe: Timeframe, now: Date = .now,
                        subject: Subject? = nil,
                        logger: LoggerFilter = .unfiltered) -> FloorStats {
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
        let currentAttempts = attemptsByGroup(
            in: current, allowed: allowed, within: currentInterval,
            subject: subject, logger: logger
        )
        let previousAttempts = attemptsByGroup(
            in: previous, allowed: allowed, within: previousInterval,
            subject: subject, logger: logger
        )
        var groupStats: [GroupStat] = []
        var prevOverall = [0, 0, 0, 0]
        for g in ordered {
            let counts = outcomeCounts(currentAttempts[g.persistentModelID] ?? [])
            let total = counts.reduce(0, +)
            let hits = counts[Outcome.hit.rawValue]
            let rate = weightedRate(counts)

            let prevCounts = outcomeCounts(previousAttempts[g.persistentModelID] ?? [])
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
                kind: g.kind, category: g.category, tierDefs: g.tierOutcomeDefs,
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

        let (execution, executionScoredReps) = executionBreakdown(
            attempts: currentAttempts.values.flatMap { $0 })

        return FloorStats(
            timeframe: timeframe,
            groups: groupStats,
            ranked: groupStats.filter { $0.total > 0 }.sorted { $0.rate > $1.rate }
                + groupStats.filter { $0.total == 0 },
            overall: overall, total: total, hits: hits, rate: rate,
            delta: delta, deltaNote: deltaNote, rangeNote: rangeNote,
            trend: trendSeries(sorted: sorted, allowed: allowed, timeframe: timeframe,
                               now: now, subject: subject, logger: logger),
            latest: latestSnapshot(sorted: sorted, allowed: allowed,
                                   subject: subject, logger: logger),
            execution: execution, executionScoredReps: executionScoredReps)
    }

    // MARK: Execution breakdown (Feature B)

    /// Aggregate the optional execution reads across the passed groups. Only reps
    /// with `executionScored == true` count — an unscored rep contributes NOTHING
    /// (never assumed clean), so the breakdown can't be inflated by untracked work.
    /// Returns the per-driver rows (category → sheet order) and the total number of
    /// execution-scored reps in range.
    private static func executionBreakdown(
        attempts: [Attempt]
    ) -> (rows: [ExecutionDriverStat], scoredReps: Int) {
        // key → (name, category, order, scored, held)
        var scoredByKey: [String: Int] = [:]
        var heldByKey: [String: Int] = [:]
        // Preserve the sheet's driver order: category index, then driver index.
        var order: [String: (cat: Int, idx: Int, name: String, category: String)] = [:]
        var scoredReps = 0

        for a in attempts {
            guard a.executionScored, let g = a.group else { continue }
            let drivers = g.executionDrivers
            guard !drivers.isEmpty else { continue }
            scoredReps += 1
            let lost = Set(a.lostDrivers)
            let catIndex = SkillCategory.allCases.firstIndex(of: g.category) ?? 0
            for (i, d) in drivers.enumerated() {
                scoredByKey[d.key, default: 0] += 1
                if !lost.contains(d.key) { heldByKey[d.key, default: 0] += 1 }
                if order[d.key] == nil {
                    order[d.key] = (catIndex, i, d.name, g.category.displayName)
                }
            }
        }

        let rows = scoredByKey.keys.compactMap { key -> ExecutionDriverStat? in
            guard let o = order[key] else { return nil }
            return ExecutionDriverStat(
                key: key, name: o.name, categoryName: o.category,
                scored: scoredByKey[key] ?? 0, held: heldByKey[key] ?? 0)
        }
        .sorted {
            let a = order[$0.key]!, b = order[$1.key]!
            return a.cat != b.cat ? a.cat < b.cat : a.idx < b.idx
        }
        return (rows, scoredReps)
    }

    // MARK: Trend series

    private static func trendSeries(sorted: [PracticeSession], allowed: Set<PersistentIdentifier>,
                                    timeframe: Timeframe, now: Date, subject: Subject? = nil,
                                    logger: LoggerFilter = .unfiltered) -> [Int] {
        let cal = Calendar.current
        func rate(of sessions: [PracticeSession], within interval: DateInterval? = nil) -> Int? {
            var credit = 0, total = 0
            for s in sessions {
                for a in s.attempts
                    where a.group.map({ allowed.contains($0.persistentModelID) }) ?? false {
                    if let interval, !interval.contains(a.timestamp) { continue }
                    guard subjectMatch(a, subject), logger.matches(a) else { continue }
                    total += 1
                    credit += a.creditValue
                }
            }
            return total > 0 ? Int((Double(credit) / Double(total)).rounded()) : nil
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
                                       allowed: Set<PersistentIdentifier>,
                                       subject: Subject? = nil,
                                       logger: LoggerFilter = .unfiltered) -> SessionSnapshot? {
        // Latest session that has reps of an allowed kind — and only those reps
        // (a mixed session viewed under a kind filter shows just that kind's tape).
        func inKind(_ s: PracticeSession) -> [Attempt] {
            s.sortedAttempts.filter {
                ($0.group.map { allowed.contains($0.persistentModelID) } ?? false)
                    && subjectMatch($0, subject)
                    && logger.matches($0)
            }
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

    /// Index the requested slice once. The previous implementation rescanned
    /// every session for every skill, making dashboard entry O(skills × reps).
    private static func attemptsByGroup(
        in sessions: [PracticeSession], allowed: Set<PersistentIdentifier>,
        within interval: DateInterval?, subject: Subject?,
        logger: LoggerFilter = .unfiltered
    ) -> [PersistentIdentifier: [Attempt]] {
        var result: [PersistentIdentifier: [Attempt]] = [:]
        for session in sessions {
            for attempt in session.attempts {
                guard let group = attempt.group,
                      allowed.contains(group.persistentModelID) else { continue }
                if let interval, !interval.contains(attempt.timestamp) { continue }
                guard subjectMatch(attempt, subject), logger.matches(attempt) else { continue }
                result[group.persistentModelID, default: []].append(attempt)
            }
        }
        return result
    }

    /// A skill's reps bucketed into the 4 credit TIERS (hit/decent/rough/miss),
    /// regardless of how many distinct outcomes it has.
    private static func outcomeCounts(_ attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for attempt in attempts {
            counts[attempt.tierOutcome.rawValue] += 1
        }
        return counts
    }

    /// Cross-cutting person filter: nil subject = everyone; otherwise the rep
    /// must be attributed to that subject. Compares by persistent id so it holds
    /// across model contexts.
    private static func subjectMatch(_ a: Attempt, _ subject: Subject?) -> Bool {
        guard let subject else { return true }
        return a.subject?.persistentModelID == subject.persistentModelID
    }

    /// Weighted hit rate (0–100): average credit across the four fixed credit
    /// tiers (100 / 67 / 33 / 0). Counts are indexed by `Outcome.rawValue`.
    static func weightedRate(_ tierCounts: [Int]) -> Int {
        guard tierCounts.count >= Outcome.allCases.count else { return 0 }
        let total = tierCounts.reduce(0, +)
        guard total > 0 else { return 0 }
        let credit = tierCounts[Outcome.hit.rawValue] * OutcomeCredit.hit.rawValue
            + tierCounts[Outcome.bobble.rawValue] * OutcomeCredit.decent.rawValue
            + tierCounts[Outcome.buildingFall.rawValue] * OutcomeCredit.rough.rawValue
            + tierCounts[Outcome.majorFall.rawValue] * OutcomeCredit.miss.rawValue
        return Int((Double(credit) / Double(total)).rounded())
    }

    /// Trailing run of landings. A rep with at least 50% credit keeps the live
    /// streak active; the first lower-credit rep resets it to zero.
    static func currentLandingStreak(in attempts: [Attempt]) -> Int {
        var run = 0
        for attempt in attempts.reversed() {
            guard attempt.isLandingRep else { break }
            run += 1
        }
        return run
    }
}
