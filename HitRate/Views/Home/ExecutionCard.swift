import SwiftUI

/// "EXECUTION" — the optional advanced breakdown (Feature B). Shows how often
/// each United execution driver HELD across the reps that were actually scored.
/// Deliberately NOT the headline: it sits below the hit-rate cards and its
/// denominator is scored-reps-only, so untracked work never inflates it. Hidden
/// entirely when nothing in range was scored (`stats.hasExecution`).
struct ExecutionCard: View {
    let stats: FloorStats

    /// Group the driver rows by category so a mixed roster reads as sections.
    private var sections: [(category: String, rows: [ExecutionDriverStat])] {
        var order: [String] = []
        var byCat: [String: [ExecutionDriverStat]] = [:]
        for r in stats.execution {
            if byCat[r.categoryName] == nil { order.append(r.categoryName) }
            byCat[r.categoryName, default: []].append(r)
        }
        return order.map { ($0, byCat[$0] ?? []) }
    }

    var body: some View {
        FeedCard {
            CardHead("EXECUTION") {
                Text("scored on \(stats.executionScoredReps) rep\(stats.executionScoredReps == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.label3)
            }

            VStack(spacing: 0) {
                let multi = sections.count > 1
                ForEach(Array(sections.enumerated()), id: \.element.category) { si, section in
                    if multi {
                        Text(section.category.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(Theme.label3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, si == 0 ? 0 : 12)
                            .padding(.bottom, 4)
                    }
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { i, row in
                        driverRow(row)
                        if i < section.rows.count - 1 {
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        }
                    }
                }
            }

            Text("A separate read of what held vs. slipped — it never changes the hit rate.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.label3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private func driverRow(_ row: ExecutionDriverStat) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    if row.lost > 0 {
                        Text("\(row.lost) slipped")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.buildingFall)
                    }
                }
                holdBar(held: row.held, total: row.scored)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(row.holdRate)")
                    .font(Theme.barlow(19, .extrabold))
                    .monospacedDigit()
                Text("%")
                    .font(Theme.barlow(12, .bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.rateColor(row.holdRate, hasData: row.scored > 0))
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    /// Held (green) vs slipped (coral) proportion bar for one driver.
    private func holdBar(held: Int, total: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if total > 0 {
                    let w = CGFloat(held) / CGFloat(total)
                    if w > 0 { Theme.accent.frame(width: w * geo.size.width) }
                    if w < 1 { Theme.majorFall.frame(width: (1 - w) * geo.size.width) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fill)
            .clipShape(Capsule())
        }
        .frame(height: 7)
    }
}
