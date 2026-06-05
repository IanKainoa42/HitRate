import SwiftUI

/// "GROUPS" — ranked leaderboard ⇄ outcome heatmap, toggled in place.
struct GroupsCard: View {
    let stats: FloorStats
    @Binding var view: String

    var body: some View {
        FeedCard {
            CardHead("GROUPS") {
                MiniSeg(options: ["Ranked", "Grid"], selection: $view)
            }
            if view == "Ranked" {
                VStack(spacing: 0) {
                    let ranked = stats.ranked
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { i, g in
                        RankedRow(stat: g, rank: i + 1)
                        if i < ranked.count - 1 {
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        }
                    }
                }
            } else {
                HeatmapView(groups: stats.groups)
            }
        }
    }
}

// MARK: Ranked row

struct RankedRow: View {
    let stat: GroupStat
    let rank: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(rank == 1 ? Theme.buildingFall : Theme.label3)
                .frame(width: 18)

            Text("\(stat.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.groupColor(stat.colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(stat.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                StackedBar(counts: stat.counts, total: stat.total, height: 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let delta = stat.delta {
                DeltaLabel(delta: delta)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(stat.rate)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.rateColor(stat.rate, hasData: stat.total > 0))
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

// MARK: Heatmap

struct HeatmapView: View {
    let groups: [GroupStat]

    private var maxByCol: [Int] {
        Outcome.allCases.map { o in
            max(1, groups.map { $0.counts[o.rawValue] }.max() ?? 1)
        }
    }

    var body: some View {
        let cols = maxByCol
        VStack(spacing: 4) {
            // Column headers
            HStack(spacing: 4) {
                Color.clear.frame(width: 26, height: 22)
                ForEach(Outcome.allCases) { o in
                    VStack(spacing: 3) {
                        Circle().fill(o.color).frame(width: 7, height: 7)
                        Text(o.short)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.27)
                            .foregroundStyle(Theme.label2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            ForEach(groups) { g in
                HStack(spacing: 4) {
                    Text("\(g.number)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.groupColor(g.colorIndex))
                        .frame(width: 26, height: 26)
                    ForEach(Outcome.allCases) { o in
                        let v = g.counts[o.rawValue]
                        let t = Double(v) / Double(cols[o.rawValue])
                        let alpha = v == 0 ? 0 : 0.11 + t * 0.89
                        Text(v == 0 ? "·" : "\(v)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(v == 0 ? Theme.label3 : (t > 0.55 ? .white : Theme.label))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(v == 0 ? Theme.surface2 : o.color.opacity(alpha))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }

            // Intensity legend
            HStack(spacing: 6) {
                Text("fewer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.label3)
                ForEach([0.15, 0.4, 0.65, 0.9], id: \.self) { t in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: 0x8E8E93).opacity(0.11 + t * 0.89))
                        .frame(width: 18, height: 14)
                }
                Text("more misses")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.label3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }
}
