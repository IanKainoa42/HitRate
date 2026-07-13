import SwiftUI

/// The roster — every athlete (coach mode: every group) ranked by clean-hit
/// rate so a coach can triage who's hitting and who needs reps at a glance.
/// Training-floor register (app UI, like the Trophy Room). Read-only: tapping a
/// row hands the subject back to Home, which re-scopes its per-athlete dashboard
/// via the existing person filter. All numbers reuse StatsEngine.compute(subject:).
struct RosterView: View {
    let sessions: [PracticeSession]
    let groups: [StuntGroup]
    let subjects: [Subject]
    let timeframe: Timeframe
    let subjectKind: SubjectKind
    let onSelect: (Subject) -> Void

    @Environment(\.dismiss) private var dismiss

    /// One computed line per subject: with-data lines ranked by rate desc, then
    /// the zero-rep tail (greyed, unranked).
    private struct Line: Identifiable {
        let subject: Subject
        let stats: FloorStats
        var id: UUID { subject.id }
    }

    private var lines: [Line] {
        let computed = subjects.map { s in
            Line(subject: s,
                 stats: StatsEngine.compute(sessions: sessions, groups: groups,
                                            timeframe: timeframe, subject: s))
        }
        let withData = computed.filter { $0.stats.hasData }
            .sorted { $0.stats.rate > $1.stats.rate }
        let empty = computed.filter { !$0.stats.hasData }
        return withData + empty
    }

    private var title: String { subjectKind == .person ? "ROSTER" : "GROUPS" }

    var body: some View {
        VStack(spacing: 9) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FloorBackdrop().ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.system(size: 15, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.label)
                }
                Text(timeframe.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
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

    // MARK: Row

    @ViewBuilder
    private func row(_ line: Line) -> some View {
        let s = line.stats
        Button { onSelect(line.subject) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.subject.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    if s.hasData {
                        HStack(spacing: 6) {
                            Text("\(s.total) rep\(s.total == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.label3)
                            if let d = s.delta, d != 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("\(abs(d))")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(d > 0 ? Theme.accent : Theme.majorFall)
                            }
                        }
                    } else {
                        Text("No reps logged")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label3)
                    }
                }
                Spacer(minLength: 6)
                if s.hasData {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(s.rate)")
                            .font(Theme.barlow(30, .bold))
                        Text("%")
                            .font(Theme.barlow(15, .semibold))
                    }
                    .foregroundStyle(Theme.rateColor(s.rate))
                } else {
                    Text("—")
                        .font(Theme.barlow(30, .bold))
                        .foregroundStyle(Theme.label3)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .wellBackground()
            .opacity(s.hasData ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
