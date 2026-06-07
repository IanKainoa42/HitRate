import SwiftUI

/// Owns the rate, delta, attempt count, distribution bar and outcome legend.
struct SummaryCard: View {
    let stats: FloorStats

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var rateColor: Color {
        Theme.rateColor(stats.rate, hasData: stats.hasData)
    }

    var body: some View {
        FeedCard {
            CardHead(mode == .athlete ? "MY HIT RATE" : "FLOOR HIT RATE") {
                Text("\(stats.total) reps · \(stats.groups.count) \(stats.groups.count == 1 ? mode.noun : mode.nounPlural)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label2)
            }

            HStack(alignment: .center, spacing: 10) {
                // Big rate numeral — Barlow, colored by rate band.
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(stats.rate)")
                        .font(Theme.barlow(64, .extrabold))
                        .contentTransition(.numericText(value: Double(stats.rate)))
                        .animation(.spring(duration: 0.5), value: stats.rate)
                        .foregroundStyle(rateColor)
                    Text("%")
                        .font(Theme.barlow(28, .bold))
                        .foregroundStyle(Theme.label2)
                }
                .lineLimit(1)

                if let delta = stats.delta {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(delta >= 0 ? Theme.accentText : .white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(delta >= 0 ? Theme.accent : Theme.majorFall)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(stats.deltaNote)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.label2)
                    }
                    .padding(.top, 6)
                }

                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            StackedBar(counts: stats.overall, total: stats.total, height: 12)
                .padding(.bottom, 12)

            // 2-column outcome legend
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                      alignment: .leading, spacing: 8) {
                ForEach(Outcome.allCases) { o in
                    HStack(spacing: 8) {
                        Circle().fill(o.color).frame(width: 8, height: 8)
                        Text(o.label(stats.aggregateKind))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)   // "Building fall" must not truncate beside big counts
                        Spacer(minLength: 4)
                        Text("\(stats.overall[o.rawValue])")
                            .font(Theme.barlow(16, .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.label)
                        Text(stats.total > 0
                             ? "\(Int((Double(stats.overall[o.rawValue]) / Double(stats.total) * 100).rounded()))%"
                             : "–")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.label3)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }
}
