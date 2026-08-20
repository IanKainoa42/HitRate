import SwiftUI

/// The receipts behind one assignment — the "are they actually working?" view.
///
/// There is no video proof here and deliberately so: what this shows instead is
/// everything the reps themselves already know. When each rep landed, across how
/// many days, how clean, who tapped it in, and the same picture for the weeks
/// before. Fifty reps spread over four evenings and fifty reps dumped in one
/// ninety-second burst produce very different pages, which is the whole point.
struct HomeworkDetailSheet: View {
    let assignment: Assignment
    let roster: [Subject]
    let teamOwnerUID: String?
    let currentUID: String?
    /// Folder owner — edit/archive live behind this.
    let canManage: Bool
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("mySubjectID") private var mySubjectID = ""
    @State private var confirmArchive = false

    private var status: HomeworkEngine.Status? {
        HomeworkEngine.statuses(assignments: [assignment], roster: roster,
                                teamOwnerUID: teamOwnerUID, currentUID: currentUID).first
    }

    var body: some View {
        VStack(spacing: 9) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    if let status {
                        summary(status)
                        ForEach(sorted(status.rows)) { row in
                            athleteWell(row, week: status.week)
                        }
                        if status.unattributedReps > 0 { untaggedNote(status) }
                    } else {
                        FeedCard {
                            Text("This homework's skill is gone.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.label2)
                        }
                    }
                    if canManage { managementRow }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FloorBackdrop().ignoresSafeArea())
        .confirmationDialog("Archive this homework?", isPresented: $confirmArchive,
                            titleVisibility: .visible) {
            Button("Archive", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops showing on the dashboard. Logged reps are kept.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("HOMEWORK")
                        .font(.system(size: 15, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.label)
                }
                Text(assignment.group?.displayName ?? "Skill removed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: Summary

    private func summary(_ status: HomeworkEngine.Status) -> some View {
        FeedCard {
            CardHead("THIS WEEK") {
                Text(HomeworkFormat.weekLabel(status.week).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.label3)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(status.completedCount)")
                    .font(Theme.barlow(46, .extrabold))
                    .foregroundStyle(status.isComplete ? Theme.accent : Theme.label)
                Text("of \(status.assignedCount) on target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.label2)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text("\(status.target) reps each")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.label3)
                Text("·")
                    .foregroundStyle(Theme.label3)
                Text("\(status.teamReps) logged so far")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.top, 2)
            if !status.note.isEmpty {
                Text(status.note)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: One athlete's receipts

    @ViewBuilder
    private func athleteWell(_ row: HomeworkEngine.AthleteWeek, week: DateInterval) -> some View {
        let subject = roster.first { $0.id == row.subjectID }
        FeedCard {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.groupColor(row.colorIndex))
                    .frame(width: 8, height: 8)
                Text(row.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                if row.subjectID.uuidString == mySubjectID {
                    Text("YOU")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.label3)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.fill))
                }
                Spacer(minLength: 0)
                HStack(spacing: 1) {
                    Text("\(row.reps)")
                        .font(Theme.barlow(22, .bold))
                        .foregroundStyle(row.isComplete ? Theme.accent : Theme.label)
                    Text("/\(row.target)")
                        .font(Theme.barlow(22, .semibold))
                        .foregroundStyle(Theme.label3)
                }
            }
            .padding(.bottom, 10)

            dayChart(row, week: week)

            // The verification lines. Each one is a fact the reps already carry —
            // nothing here asks the athlete to be believed.
            VStack(spacing: 0) {
                receipt(icon: "calendar", label: "Days practiced",
                        value: "\(row.daysPracticed) of 7",
                        tone: row.isSingleDayDump ? Theme.bobble : Theme.label)
                receipt(icon: "clock", label: "Last rep",
                        value: row.lastRepAt.map { HomeworkFormat.relative($0) } ?? "—",
                        tone: Theme.label)
                if let rate = row.rate {
                    receipt(icon: "target", label: "Clean on homework reps",
                            value: "\(rate)%", tone: Theme.rateColor(rate))
                }
                if row.coachLoggedReps > 0 {
                    receipt(icon: "person.2", label: "Logged by",
                            value: "\(row.selfLoggedReps) self · \(row.coachLoggedReps) coach",
                            tone: Theme.label)
                }
            }
            .padding(.top, 10)

            if row.isSingleDayDump {
                Text("All of it in one day — worth a conversation about spacing the reps out.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.bobble)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            history(subject: subject)
        }
    }

    /// Seven columns, one per weekday, height by rep count. Empty days are the
    /// story as much as busy ones, so every column keeps its slot.
    private func dayChart(_ row: HomeworkEngine.AthleteWeek, week: DateInterval) -> some View {
        let peak = max(1, row.busiestDayReps)
        let initials = HomeworkEngine.weekdayInitials(for: week)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(row.dayCounts.enumerated()), id: \.offset) { i, count in
                VStack(spacing: 4) {
                    Text(count > 0 ? "\(count)" : "")
                        .font(Theme.barlow(11, .semibold))
                        .foregroundStyle(Theme.label3)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(count > 0 ? (row.isComplete ? Theme.accent : Theme.label2) : Theme.fill)
                        .frame(height: max(3, 34 * CGFloat(count) / CGFloat(peak)))
                    Text(initials.indices.contains(i) ? initials[i] : "")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.label3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 62, alignment: .bottom)
    }

    private func receipt(icon: String, label: String, value: String, tone: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.label3)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.label2)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone)
        }
        .padding(.vertical, 6)
    }

    /// Week-by-week: the record a coach actually judges on. One good week is
    /// noise; six in a row is a work ethic.
    @ViewBuilder
    private func history(subject: Subject?) -> some View {
        let weeks = HomeworkEngine.history(for: assignment, subject: subject, roster: roster)
        if weeks.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("WEEK BY WEEK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.label3)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(weeks) { w in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(w.isComplete ? Theme.accent : Theme.label2.opacity(0.55))
                                .frame(height: max(2, 24 * CGFloat(w.fraction)))
                            Text("\(w.reps)")
                                .font(Theme.barlow(10, .semibold))
                                .foregroundStyle(Theme.label3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 40, alignment: .bottom)
            }
            .padding(.top, 12)
        }
    }

    private func untaggedNote(_ status: HomeworkEngine.Status) -> some View {
        FeedCard {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.bobble)
                Text("\(status.unattributedReps) rep\(status.unattributedReps == 1 ? "" : "s") on this skill this week aren't tagged to an athlete, so they count for nobody. Pick a name in the capture pad and they'll land on the right bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Owner actions

    private var managementRow: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                Text("Edit")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .wellBackground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { confirmArchive = true } label: {
                Text("Archive")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.majorFall)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .wellBackground()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    /// Archive keeps the row and its history — a coach retiring homework should
    /// never lose the record of who did it.
    private func archive() {
        assignment.archivedAt = .now
        try? context.save()
        dismiss()
    }

    private func sorted(_ rows: [HomeworkEngine.AthleteWeek]) -> [HomeworkEngine.AthleteWeek] {
        guard let mine = UUID(uuidString: mySubjectID),
              rows.contains(where: { $0.subjectID == mine }) else { return rows }
        return rows.filter { $0.subjectID == mine } + rows.filter { $0.subjectID != mine }
    }
}
