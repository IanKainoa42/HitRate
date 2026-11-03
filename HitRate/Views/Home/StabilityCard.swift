import SwiftUI
import SwiftData

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

    @Query private var subjects: [Subject]
    @State private var hubOpen = false
    @State private var selectedAttempt: Attempt?

    var body: some View {
        if let s = stats.stability {
            FeedCard {
                CardHead("STUNT STABILITY") {
                    HStack(spacing: 8) {
                        Button {
                            hubOpen = true
                        } label: {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                Text("STUNTSCOPE")
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.8)
                                    .foregroundStyle(Theme.accent)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .wellBackground(cornerRadius: 6)
                        }
                        .buttonStyle(.plain)

                        Text("\(s.reps) video rep\(s.reps == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.label3)
                    }
                }

                // Combo Telemetry 3-Up Row
                HStack(spacing: 8) {
                    telemetryTile(
                        title: "ON BASE",
                        val: "\(s.onBase)%",
                        color: Theme.rateColor(s.onBase),
                        caption: "center of mass"
                    )

                    telemetryTile(
                        title: "LOCKED IN",
                        val: "\(s.rockSolidRate)%",
                        color: Theme.rateColor(s.rockSolidRate),
                        caption: "hit · steady · 0 wobble"
                    )

                    telemetryTile(
                        title: "AVG HOLD",
                        val: String(format: "%.1fs", s.avgHoldSeconds),
                        color: Theme.label,
                        caption: s.maxHoldSeconds > 0 ? "max \(String(format: "%.1fs", s.maxHoldSeconds))" : "time in air"
                    )
                }
                .padding(.bottom, 10)

                // Subline explanation
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("share of each hold the flyer's weight sat inside the bases' span")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.label3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)

                    if let maxFlight = s.maxFlightSeconds, maxFlight > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                            Text("\(String(format: "%.2f", maxFlight))s hangtime")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.label2)
                        }
                    }
                }
                .padding(.bottom, 8)

                // Person filter only: the same reps by the position she held, so
                // a flyer's number and a base's number read apart.
                if !s.byRole.isEmpty {
                    roleLine(s.byRole)
                        .padding(.bottom, 10)
                }

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

                // Recent filmed reps quick strip
                if !s.recentAttempts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT VIDEO REPS · TAP TO INSPECT")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Theme.label3)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(s.recentAttempts.prefix(8), id: \.persistentModelID) { attempt in
                                    Button {
                                        selectedAttempt = attempt
                                    } label: {
                                        repPill(attempt)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
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

                HStack(spacing: 6) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.label3)
                    Text("Scored from StuntScope video only — it never changes the hit rate.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.label3)
                    Spacer()
                }
                .padding(.top, 12)
            }
            .sheet(item: $selectedAttempt) { attempt in
                StuntRepTelemetrySheet(attempt: attempt, subjects: subjects)
            }
            .sheet(isPresented: $hubOpen) {
                StuntScopeHubView()
            }
        }
    }

    private func telemetryTile(title: String, val: String, color: Color, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.label3)
            Text(val)
                .font(Theme.barlow(22, .extrabold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.label3)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellBackground(cornerRadius: 8)
    }

    private func repPill(_ attempt: Attempt) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(attempt.outcome.color)
                .frame(width: 6, height: 6)

            Text("\(attempt.onBasePercent ?? 0)%")
                .font(Theme.barlow(14, .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.rateColor(attempt.onBasePercent ?? 0))

            if let hold = attempt.holdSeconds, hold > 0 {
                Text(String(format: "%.1fs", hold))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.label2)
            }

            if (attempt.wobbleCount ?? 0) == 0 {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .wellBackground(cornerRadius: 6)
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

    /// "FLYER 82% · 3 reps   MAIN BASE 71% · 1 rep" — one compact line.
    private func roleLine(_ roles: [StabilityRoleStat]) -> some View {
        HStack(spacing: 14) {
            ForEach(roles) { r in
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(r.role.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(Theme.label3)
                    Text("\(r.onBase)%")
                        .font(Theme.barlow(16, .extrabold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.rateColor(r.onBase))
                    Text("\(r.reps) rep\(r.reps == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.label3)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On base by position")
        .accessibilityValue(roles.map { "\($0.role.label) \($0.onBase) percent over \($0.reps) reps" }
            .joined(separator: ", "))
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
        if row.rockSolidCount > 0 {
            parts.append("\(row.rockSolidCount) locked-in")
        }
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
