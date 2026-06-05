import SwiftUI

/// Owns the rate, delta, attempt count, distribution bar and outcome legend.
struct SummaryCard: View {
    let stats: FloorStats

    var body: some View {
        FeedCard {
            HStack(alignment: .bottom) {
                // Big animated hit-rate number, colored by rate band.
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(stats.rate)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText(value: Double(stats.rate)))
                        .animation(.spring(duration: 0.5), value: stats.rate)
                    Text("%")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Theme.rateColor(stats.rate, hasData: stats.hasData))
                .lineLimit(1)

                Spacer()

                if let delta = stats.delta {
                    VStack(alignment: .trailing, spacing: 2) {
                        DeltaLabel(delta: delta,
                                   font: .system(size: 18, weight: .heavy, design: .rounded),
                                   iconSize: 14)
                        Text(stats.deltaNote)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.label2)
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 13)

            HStack(alignment: .firstTextBaseline) {
                Text("FLOOR HIT RATE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.label2)
                Spacer()
                Text("\(stats.total) reps · \(stats.groups.count) groups")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.label2)
            }
            .padding(.bottom, 7)

            StackedBar(counts: stats.overall, total: stats.total, height: 14)
                .padding(.bottom, 13)

            // 2-column outcome legend
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                      alignment: .leading, spacing: 8) {
                ForEach(Outcome.allCases) { o in
                    HStack(spacing: 8) {
                        Circle().fill(o.color).frame(width: 9, height: 9)
                        Text(o.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(stats.overall[o.rawValue])")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.label)
                        Text(stats.total > 0
                             ? "\(Int((Double(stats.overall[o.rawValue]) / Double(stats.total) * 100).rounded()))%"
                             : "–")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label3)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }
}
