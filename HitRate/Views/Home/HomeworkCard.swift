import SwiftUI

/// "HOMEWORK" — the offseason accountability well.
///
/// Pro squads don't train together year-round, so a coach's only view of the
/// work is what the athlete logs. This card shows the whole folder the same
/// thing: who's on pace this week and — critically — the SHAPE of their reps.
/// Progress is never stored; `HomeworkEngine` recomputes it from the attempts
/// every render, so it always matches the rest of the dashboard.
///
/// Deliberately outside the timeframe filter (like the weekly tournament):
/// homework is a calendar-week thing, and reading it through a "today" lens
/// would show an athlete a bar that resets every morning.
struct HomeworkCard: View {
    let assignments: [Assignment]
    let roster: [Subject]
    let teamOwnerUID: String?
    let currentUID: String?
    /// Folder owner — only the coach gets the assign/edit affordances.
    let canAssign: Bool
    let onAssign: () -> Void
    let onOpen: (Assignment) -> Void

    /// Local-only "which row is me" so an athlete can find themself in a long
    /// roster. Not synced and not identity — a pin, nothing more.
    @AppStorage("mySubjectID") private var mySubjectID = ""

    private var statuses: [HomeworkEngine.Status] {
        HomeworkEngine.statuses(assignments: assignments, roster: roster,
                                teamOwnerUID: teamOwnerUID, currentUID: currentUID)
    }

    /// Assignment lookup so a tapped block can hand back the model itself.
    private func assignment(_ id: UUID) -> Assignment? {
        assignments.first { $0.id == id }
    }

    var body: some View {
        FeedCard {
            CardHead("HOMEWORK") {
                if canAssign {
                    Button(action: onAssign) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .black))
                            Text("ASSIGN")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1)
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.iconTile))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            let all = statuses
            if all.isEmpty {
                emptyState
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(all.enumerated()), id: \.element.id) { index, status in
                        block(status, divider: index < all.count - 1)
                    }
                }
            }
        }
    }

    // MARK: One assignment

    @ViewBuilder
    private func block(_ status: HomeworkEngine.Status, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if let a = assignment(status.id) { onOpen(a) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.skillName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                        Text("\(status.target) reps this week")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label3)
                    }
                    Spacer(minLength: 0)
                    Text("\(status.completedCount)/\(status.assignedCount)")
                        .font(Theme.barlow(17, .bold))
                        .foregroundStyle(status.isComplete ? Theme.accent : Theme.label)
                    Text("DONE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.label3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !status.note.isEmpty {
                Text(status.note)
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(sortedRows(status.rows)) { row in
                athleteRow(row, status: status)
            }

            // The one way to do the work and get no credit: reps logged on this
            // skill with nobody picked. Say it out loud instead of letting an
            // athlete think the bar is broken.
            if status.unattributedReps > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(status.unattributedReps) rep\(status.unattributedReps == 1 ? "" : "s") this week aren't tagged to anyone — pick your name while logging so they count.")
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.bobble)
            }

            if divider {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
                    .padding(.top, 3)
            }
        }
    }

    /// Roster order, but a pinned "me" row floats to the top so an athlete never
    /// hunts for their own bar.
    private func sortedRows(_ rows: [HomeworkEngine.AthleteWeek]) -> [HomeworkEngine.AthleteWeek] {
        guard let mine = UUID(uuidString: mySubjectID) else { return rows }
        guard rows.contains(where: { $0.subjectID == mine }) else { return rows }
        return rows.filter { $0.subjectID == mine } + rows.filter { $0.subjectID != mine }
    }

    // MARK: One athlete's week

    @ViewBuilder
    private func athleteRow(_ row: HomeworkEngine.AthleteWeek,
                            status: HomeworkEngine.Status) -> some View {
        let isMe = row.subjectID.uuidString == mySubjectID
        Button {
            if let a = assignment(status.id) { onOpen(a) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Theme.groupColor(row.colorIndex))
                        .frame(width: 7, height: 7)
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    if isMe {
                        Text("YOU")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(Theme.label3)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.fill))
                    }
                    Spacer(minLength: 4)
                    if row.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 1) {
                        Text("\(row.reps)")
                            .font(Theme.barlow(15, .bold))
                            .foregroundStyle(row.isComplete ? Theme.accent : Theme.label)
                        Text("/\(row.target)")
                            .font(Theme.barlow(15, .semibold))
                            .foregroundStyle(Theme.label3)
                    }
                }

                progressBar(row)

                HStack(spacing: 8) {
                    dayDots(row)
                    Text(receiptLine(row))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isMe {
                Button("Not me") { mySubjectID = "" }
            } else {
                Button("This is me") { mySubjectID = row.subjectID.uuidString }
            }
        }
    }

    private func progressBar(_ row: HomeworkEngine.AthleteWeek) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule()
                    .fill(row.isComplete ? Theme.accent : Theme.label2)
                    .frame(width: max(row.reps > 0 ? 4 : 0, geo.size.width * row.fraction))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.45), value: row.reps)
    }

    /// Seven dots — one per day of the week, lit where reps landed. The whole
    /// verification story in 60 points of width.
    private func dayDots(_ row: HomeworkEngine.AthleteWeek) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(row.dayFlags.enumerated()), id: \.offset) { _, on in
                Circle()
                    .fill(on ? Theme.label : Theme.separator)
                    .frame(width: 4.5, height: 4.5)
            }
        }
    }

    /// The short receipt under the bar: how spread out the work was, and when it
    /// last happened. Silent praise and silent suspicion both live here.
    private func receiptLine(_ row: HomeworkEngine.AthleteWeek) -> String {
        guard row.reps > 0 else { return "nothing logged yet" }
        var parts = ["\(row.daysPracticed) day\(row.daysPracticed == 1 ? "" : "s")"]
        if let last = row.lastRepAt {
            parts.append(HomeworkFormat.relative(last))
        }
        if let rate = row.rate { parts.append("\(rate)% clean") }
        return parts.joined(separator: " · ")
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No homework assigned.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label)
            Text("Set a weekly rep target on a skill and everyone can see who's putting the work in between practices.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Shared formatting

enum HomeworkFormat {
    /// "2h ago" / "yesterday" / "Tue" — short enough for a receipt line.
    static func relative(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let mins = Int(now.timeIntervalSince(date) / 60)
            if mins < 1 { return "just now" }
            if mins < 60 { return "\(mins)m ago" }
            return "\(mins / 60)h ago"
        }
        if cal.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// "Aug 17 – Aug 23" for a week header.
    static func weekLabel(_ week: DateInterval) -> String {
        let end = week.end.addingTimeInterval(-1)
        let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(week.start.formatted(f)) – \(end.formatted(f))"
    }
}
