import Foundation

/// Coach-set rep homework, scored from the attempts themselves.
///
/// NO STORED PROGRESS — every number here is recomputed from `Attempt` rows on
/// each render, exactly like `Milestones` and `WeeklyLeague`. A rep that syncs
/// in late, or one the athlete deletes, is reflected immediately with nothing to
/// reconcile.
///
/// Two deliberate rules:
///  • VOLUME COUNTS, quality is shown beside it. Any rep on the assigned skill
///    advances the bar — homework asks "did you put the work in", not "was it
///    clean" — and the clean-hit rate of those same reps rides along so a coach
///    can see both at a glance.
///  • THE RECEIPTS ARE THE VERIFICATION. Nobody can watch an athlete's garage
///    session, so instead of proof this reports the SHAPE of the work: which
///    days it happened on, when the last rep landed, and whether the coach or
///    the athlete logged it. Fifty reps dumped in one minute on Sunday night
///    looks nothing like fifty reps across four days, and that's the point.
///
/// Weeks are `Calendar.current` weeks — the same boundary the weekly tournament
/// uses, so "this week" means one thing across the whole app. Reps are bucketed
/// by their OWN timestamp, never by their session's start, so a practice that
/// runs through midnight still lands each rep in the right week and day.
enum HomeworkEngine {

    // MARK: - Output

    /// One athlete's week against one assignment.
    struct AthleteWeek: Identifiable {
        let subjectID: UUID
        let name: String
        let colorIndex: Int
        /// Reps logged on the assigned skill this week — the bar's numerator.
        let reps: Int
        let target: Int
        /// Clean hits among those reps (quality, shown beside the volume).
        let hits: Int
        /// Reps per day of the week, in week order (7 entries) — the receipt
        /// that separates four honest sessions from one Sunday-night dump.
        let dayCounts: [Int]
        let lastRepAt: Date?
        /// Split by who tapped it in: the athlete themself vs the folder owner.
        let selfLoggedReps: Int
        let coachLoggedReps: Int

        var id: UUID { subjectID }
        var isComplete: Bool { target > 0 && reps >= target }
        var remaining: Int { max(0, target - reps) }
        /// 0…1 for the bar (clamped — 60 of 50 reps is a full bar, not 120%).
        var fraction: Double {
            guard target > 0 else { return reps > 0 ? 1 : 0 }
            return min(1, Double(reps) / Double(target))
        }
        /// Clean-hit rate of the homework reps; nil when nothing was logged.
        var rate: Int? {
            guard reps > 0 else { return nil }
            return Int((Double(hits) / Double(reps) * 100).rounded())
        }
        /// Which days carry at least one rep.
        var dayFlags: [Bool] { dayCounts.map { $0 > 0 } }
        var daysPracticed: Int { dayCounts.filter { $0 > 0 }.count }
        /// The biggest single day, for "32 of 50 in one sitting".
        var busiestDayReps: Int { dayCounts.max() ?? 0 }
        /// The tell that separates real work from a night-before dump: every rep
        /// on one day, with the target actually met.
        var isSingleDayDump: Bool { reps >= target && target > 0 && daysPracticed <= 1 }
    }

    /// One assignment's week across everyone it was given to.
    struct Status: Identifiable {
        let id: UUID
        let skillName: String
        let skillNumber: Int
        let skillKind: SkillKind
        let target: Int
        let note: String
        let week: DateInterval
        /// One row per assigned athlete, in roster order.
        let rows: [AthleteWeek]
        /// Reps logged on this skill this week that are attributed to NOBODY.
        /// Surfaced on the card because it's the one way an athlete can do the
        /// work and see no credit — they logged without picking their own row.
        let unattributedReps: Int

        var completedCount: Int { rows.filter(\.isComplete).count }
        var assignedCount: Int { rows.count }
        var teamReps: Int { rows.reduce(0) { $0 + $1.reps } }
        var isComplete: Bool { assignedCount > 0 && completedCount == assignedCount }
        /// Nobody has touched it yet this week.
        var isUntouched: Bool { teamReps == 0 && unattributedReps == 0 }
    }

    /// One past week for an athlete — the streak of weeks a coach scrolls back
    /// through when deciding whether someone actually works in the offseason.
    struct WeekSummary: Identifiable {
        let week: DateInterval
        let reps: Int
        let target: Int
        let daysPracticed: Int

        var id: Date { week.start }
        var isComplete: Bool { target > 0 && reps >= target }
        var fraction: Double {
            guard target > 0 else { return reps > 0 ? 1 : 0 }
            return min(1, Double(reps) / Double(target))
        }
    }

    // MARK: - This week

    /// Score every live assignment for the current week.
    ///
    /// `teamOwnerUID` / `currentUID` drive the self-vs-coach logging split; pass
    /// nils on a folder with no cloud owner and every rep simply reads as
    /// self-logged (there's no coach/athlete line to draw without an owner).
    static func statuses(assignments: [Assignment], roster: [Subject],
                         teamOwnerUID: String? = nil, currentUID: String? = nil,
                         now: Date = .now) -> [Status] {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 0)
        return assignments.filter(\.isLive).compactMap { assignment in
            status(for: assignment, roster: roster, week: week, cal: cal,
                   teamOwnerUID: teamOwnerUID, currentUID: currentUID)
        }
    }

    private static func status(for assignment: Assignment, roster: [Subject],
                               week: DateInterval, cal: Calendar,
                               teamOwnerUID: String?, currentUID: String?) -> Status? {
        guard let group = assignment.group else { return nil }
        // Reps come from the skill itself, filtered by their own timestamp —
        // sessions are global and untagged, and a session that spans midnight
        // would mis-bucket every rep in it.
        let weekReps = group.attempts.filter { week.contains($0.timestamp) }
        var bySubject: [UUID: [Attempt]] = [:]
        var unattributed = 0
        for rep in weekReps {
            if let id = rep.subject?.id {
                bySubject[id, default: []].append(rep)
            } else {
                unattributed += 1
            }
        }

        let assignees = assignment.assignees(from: roster)
        let rows = assignees.map { subject in
            progress(subject: subject, reps: bySubject[subject.id] ?? [],
                     target: assignment.targetReps, week: week, cal: cal,
                     teamOwnerUID: teamOwnerUID, currentUID: currentUID)
        }

        return Status(
            id: assignment.id,
            skillName: group.displayName,
            skillNumber: group.number,
            skillKind: group.kind,
            target: assignment.targetReps,
            note: assignment.note,
            week: week,
            rows: rows,
            unattributedReps: unattributed
        )
    }

    private static func progress(subject: Subject, reps: [Attempt], target: Int,
                                 week: DateInterval, cal: Calendar,
                                 teamOwnerUID: String?, currentUID: String?) -> AthleteWeek {
        var days = [Int](repeating: 0, count: 7)
        var hits = 0
        var coachLogged = 0
        var last: Date?
        for rep in reps {
            if let slot = dayIndex(of: rep.timestamp, in: week, cal: cal) {
                days[slot] += 1
            }
            if rep.isHitRep { hits += 1 }
            if rep.isCoachLogged(teamOwnerUID: teamOwnerUID, currentUID: currentUID) {
                coachLogged += 1
            }
            if last == nil || rep.timestamp > last! { last = rep.timestamp }
        }
        return AthleteWeek(
            subjectID: subject.id,
            name: subject.displayName,
            colorIndex: subject.orderIndex % Theme.groupRainbow.count,
            reps: reps.count,
            target: target,
            hits: hits,
            dayCounts: days,
            lastRepAt: last,
            selfLoggedReps: reps.count - coachLogged,
            coachLoggedReps: coachLogged
        )
    }

    /// Which of the week's seven day slots a timestamp falls in (0 = the week's
    /// first day in the user's locale). Out-of-week timestamps return nil.
    static func dayIndex(of date: Date, in week: DateInterval, cal: Calendar) -> Int? {
        guard week.contains(date) else { return nil }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: week.start),
                                      to: cal.startOfDay(for: date)).day ?? 0
        return (0..<7).contains(days) ? days : nil
    }

    /// The week's day initials in the user's locale order ("S M T W T F S").
    static func weekdayInitials(for week: DateInterval,
                                cal: Calendar = .current) -> [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "", count: 7) }
        let firstIndex = cal.component(.weekday, from: week.start) - 1
        return (0..<7).map { symbols[(firstIndex + $0) % 7] }
    }

    // MARK: - History (the week-by-week receipt)

    /// The last `weeks` COMPLETED weeks plus the live one, oldest first, for one
    /// athlete (or the whole assignment when `subject` is nil). Never reaches
    /// back before the assignment started — weeks that predate it aren't misses.
    static func history(for assignment: Assignment, subject: Subject?,
                        roster: [Subject], weeks: Int = 6,
                        now: Date = .now) -> [WeekSummary] {
        guard let group = assignment.group else { return [] }
        let cal = Calendar.current
        guard let currentWeek = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }

        // Only reps that count for this view: one athlete's, or everyone the
        // assignment covers (so an "all" row can't be padded by outsiders).
        let assignedIDs = Set(assignment.assignees(from: roster).map(\.id))
        let relevant = group.attempts.filter { rep in
            guard let id = rep.subject?.id else { return false }
            return subject.map { id == $0.id } ?? assignedIDs.contains(id)
        }
        let people = subject == nil ? max(1, assignedIDs.count) : 1

        var out: [WeekSummary] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let ref = cal.date(byAdding: .weekOfYear, value: -offset, to: now),
                  let week = cal.dateInterval(of: .weekOfYear, for: ref),
                  week.end > assignment.startedAt else { continue }
            let reps = relevant.filter { week.contains($0.timestamp) }
            let days = Set(reps.compactMap { dayIndex(of: $0.timestamp, in: week, cal: cal) })
            out.append(WeekSummary(week: week, reps: reps.count,
                                   target: assignment.targetReps * people,
                                   daysPracticed: days.count))
        }
        // Guard against a locale/DST edge producing a duplicate live week.
        return out.filter { $0.week.start <= currentWeek.start }
    }
}
