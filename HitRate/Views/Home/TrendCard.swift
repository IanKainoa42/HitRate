import SwiftUI

/// "HIT RATE OVER TIME" — line chart ported from the handoff SVG:
/// dashed gridlines, 8% area fill, 2.5pt accent stroke, emphasized last point + value label.
struct TrendCard: View {
    let stats: FloorStats

    var body: some View {
        FeedCard {
            CardHead("HIT RATE OVER TIME") {
                Text(stats.rangeNote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.label2)
            }
            if stats.trend.count >= 2 {
                LineChart(data: stats.trend, accent: Theme.accent)
                    .frame(height: 116)
                    .accessibilityLabel("Hit rate over time")
                    .accessibilityValue("\(stats.trend.map { "\($0)%" }.joined(separator: ", ")). Latest \(stats.trend.last ?? 0)%")
            } else {
                Text("Not enough sessions yet — the trend appears after two.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            }
        }
    }
}

struct LineChart: View {
    let data: [Int]
    let accent: Color

    private let padTop: CGFloat = 12
    private let padBot: CGFloat = 22
    private let padX: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            chart(in: geo.size)
        }
    }

    private func x(_ i: Int, _ size: CGSize) -> CGFloat {
        padX + CGFloat(i) / CGFloat(max(1, data.count - 1)) * (size.width - padX * 2)
    }

    private func y(_ v: Int, _ size: CGSize) -> CGFloat {
        let lo = Double(data.min() ?? 0) - 5
        let hi = Double(data.max() ?? 100) + 5
        return padTop + (1 - (Double(v) - lo) / (hi - lo)) * (size.height - padTop - padBot)
    }

    private func chart(in size: CGSize) -> some View {
        let W = size.width
        let H = size.height
        let n = data.count
        func x(_ i: Int) -> CGFloat { self.x(i, size) }
        func y(_ v: Int) -> CGFloat { self.y(v, size) }

        return ZStack(alignment: .topLeading) {
                // Dashed gridlines
                Path { p in
                    for g in [0.0, 0.5, 1.0] {
                        let gy = padTop + g * (H - padTop - padBot)
                        p.move(to: CGPoint(x: padX, y: gy))
                        p.addLine(to: CGPoint(x: W - padX, y: gy))
                    }
                }
                .stroke(Theme.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

                // Area fill
                Path { p in
                    p.move(to: CGPoint(x: x(0), y: H - padBot))
                    for (i, v) in data.enumerated() {
                        p.addLine(to: CGPoint(x: x(i), y: y(v)))
                    }
                    p.addLine(to: CGPoint(x: x(n - 1), y: H - padBot))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.08))

                // Line
                Path { p in
                    p.move(to: CGPoint(x: x(0), y: y(data[0])))
                    for (i, v) in data.enumerated().dropFirst() {
                        p.addLine(to: CGPoint(x: x(i), y: y(v)))
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Points (last emphasized)
                ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                    let last = i == n - 1
                    Circle()
                        .fill(last ? accent : Theme.well)   // solid well color — the chart sits in one
                        .stroke(accent, lineWidth: 2)
                        .frame(width: last ? 9 : 5.2, height: last ? 9 : 5.2)
                        .position(x: x(i), y: y(v))
                }

                // Last value label
                Text("\(data[n - 1])%")
                    .font(Theme.barlow(15, .extrabold))
                    .foregroundStyle(accent)
                    .position(x: x(n - 1) - 14, y: y(data.max() ?? data[n - 1]) - 9)
            }
        .frame(width: W, height: H)
    }
}
