import SwiftUI

/// "STUNT STABILITY" — the video layer StuntScope writes onto reps. Headline is
/// the mean on-base percent (where the flyer's centre of mass sat over her
/// bases while held), banded with the same `Theme.rateColor` thresholds as the
/// hit rate so a coach reads it without a legend. Under it, on-base over time
/// with the hit rate of the SAME video-scored reps laid behind it, dashed: the
/// gap opening up — stability sliding while hits still land — is the early
/// warning the card exists for. Then one row per skill with video reps.
///
/// Like EXECUTION it sits BELOW the hit-rate cards, counts only reps StuntScope
/// actually scored (a hand-logged practice can't read "steady"), never changes
/// `rate`, and is hidden entirely when nothing in range was filmed
/// (`stats.hasStability`).
struct StabilityCard: View {
    let stats: FloorStats

    var body: some View {
        if let s = stats.stability {
            FeedCard {
                CardHead("STUNT STABILITY") {
                    Text("\(s.reps) video rep\(s.reps == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.label3)
                }

                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(s.onBase)")
                            .font(Theme.barlow(44, .extrabold))
                            .contentTransition(.numericText(value: Double(s.onBase)))
                            .animation(.spring(duration: 0.5), value: s.onBase)
                            .foregroundStyle(Theme.rateColor(s.onBase))
                        Text("%")
                            .font(Theme.barlow(20, .bold))
                            .foregroundStyle(Theme.label2)
                    }
                    .lineLimit(1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("over her bases")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.label)
                        Text("share of each hold the flyer's weight sat inside the bases' span")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.label3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)

                if s.trend.count >= 2 {
                    LineChart(data: s.trend, accent: Theme.accent,
                              secondary: s.hitTrend, secondaryColor: Theme.label2)
                        .frame(height: 96)
                        .accessibilityLabel("Stability over time")
                        .accessibilityValue("\(s.trend.map { "\($0)%" }.joined(separator: ", ")). Latest \(s.trend.last ?? 0)%")
                    HStack(spacing: 12) {
                        legendSwatch(Theme.accent, "ON BASE", dashed: false)
                        legendSwatch(Theme.label2, "HIT RATE, SAME REPS", dashed: true)
                    }
                    .padding(.bottom, 10)
                }

                VStack(spacing: 0) {
                    ForEach(Array(s.groups.enumerated()), id: \.element.id) { i, row in
                        groupRow(row)
                        if i < s.groups.count - 1 {
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        }
                    }
                }

                Text("Scored from StuntScope video only — it never changes the hit rate.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    private func legendSwatch(_ color: Color, _ label: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                              dash: dashed ? [3, 3] : []))
            .frame(width: 14, height: 2)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.label3)
        }
    }

    private func groupRow(_ row: StabilityGroupStat) -> some View {
        HStack(spacing: 10) {
            Text("\(row.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.groupColor(row.colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Text(detail(row))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.label3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(row.onBase)")
                    .font(Theme.barlow(19, .extrabold))
                    .monospacedDigit()
                Text("%")
                    .font(Theme.barlow(12, .bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.rateColor(row.onBase, hasData: row.reps > 0))
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    /// "4 reps · 75% hit · 0.5 wobbles/rep · 3.4 s hold"
    private func detail(_ row: StabilityGroupStat) -> String {
        var parts = ["\(row.reps) rep\(row.reps == 1 ? "" : "s")", "\(row.hitRate)% hit"]
        if row.wobbles > 0 {
            parts.append(String(format: "%.1f wobbles/rep", row.wobblesPerRep))
        } else {
            parts.append("no wobbles")
        }
        if row.longestHoldSeconds > 0 {
            parts.append(String(format: "%.1f s hold", row.longestHoldSeconds))
        }
        return parts.joined(separator: " · ")
    }
}
