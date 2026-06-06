import SwiftUI

/// "TAKEAWAYS" — three story sentences: best bucket, worst-falls bucket, top miss.
struct TakeawaysCard: View {
    let stats: FloorStats

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var periodWord: String {
        switch stats.timeframe {
        case .today: "day"
        case .week: "week"
        case .all: "season"
        }
    }

    var body: some View {
        FeedCard {
            CardHead("TAKEAWAYS")
            VStack(spacing: 0) {
                if let best = stats.best {
                    InsightRow(icon: "trophy", color: Theme.buildingFall, divider: true) {
                        Text("\(Text(best.name).fontWeight(.bold)) led the \(mode == .athlete ? "way" : "floor") at \(Text("\(best.rate)%").fontWeight(.bold)) — cleanest \(mode.noun) of the \(periodWord).")
                    }
                }
                if let worst = stats.worstFalls, stats.falls > 0 {
                    InsightRow(icon: "exclamationmark.triangle.fill", color: Theme.majorFall, divider: true) {
                        Text(mode == .athlete
                             ? "\(Text(worst.name).fontWeight(.bold)) owns \(Text("\(worst.falls) of \(stats.falls)").fontWeight(.bold)) falls — tighten it next."
                             : "\(Text(worst.name).fontWeight(.bold)) owns \(Text("\(worst.falls) of \(stats.falls)").fontWeight(.bold)) floor falls — spot it next.")
                    }
                }
                if let miss = stats.topMiss {
                    InsightRow(icon: "flame", color: Theme.accent, divider: false) {
                        Text("\(Text(miss.label(stats.aggregateKind)).fontWeight(.bold)) is your top miss at \(Text("\(stats.overall[miss.rawValue])").fontWeight(.bold)) reps — most fixable error.")
                    }
                }
            }
        }
    }
}

struct InsightRow: View {
    let icon: String
    let color: Color
    let divider: Bool
    @ViewBuilder var content: Text

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                content
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label)
                    .lineSpacing(2)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            if divider {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }
}
