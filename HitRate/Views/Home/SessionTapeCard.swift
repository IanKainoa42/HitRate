import SwiftUI

/// "LATEST SESSION" — the chronological tape: one thin bar per attempt,
/// height/color by outcome, with a rough-patch bracket when one exists.
struct SessionTapeCard: View {
    let snapshot: SessionSnapshot

    private let heights: [Outcome: CGFloat] = [
        .hit: 34, .bobble: 26, .buildingFall: 22, .majorFall: 18,
    ]

    var body: some View {
        FeedCard {
            CardHead("LATEST SESSION") {
                Text("\(snapshot.start.tapeTime)–\(snapshot.end.tapeTime)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.label2)
            }

            // Tape — Canvas so any rep count stays visible (gap adapts to density)
            Canvas { ctx, size in
                let n = snapshot.outcomes.count
                guard n > 0 else { return }
                let step = size.width / CGFloat(n)
                let gap = min(2, max(0.4, step * 0.3))
                let barW = max(0.6, step - gap)
                for (i, o) in snapshot.outcomes.enumerated() {
                    let h = heights[o] ?? 20
                    let rect = CGRect(x: CGFloat(i) * step, y: size.height - h, width: barW, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, barW / 2)),
                             with: .color(o.color.opacity(o.isHit ? 0.9 : 1)))
                }
            }
            .frame(height: 36)

            // Rough-patch bracket
            if let patch = snapshot.roughPatch {
                GeometryReader { geo in
                    let n = CGFloat(snapshot.outcomes.count)
                    let x0 = CGFloat(patch.lowerBound) / n * geo.size.width
                    let w = CGFloat(patch.count) / n * geo.size.width
                    UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                        .stroke(Theme.buildingFall, lineWidth: 2)
                        .frame(width: w, height: 8)
                        .offset(x: x0)
                        .mask(Rectangle().padding(.top, 2))
                }
                .frame(height: 8)
                .padding(.top, 3)
            }

            // Timestamps
            HStack {
                Text(snapshot.start.tapeTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.label2)
                Spacer()
                if snapshot.roughPatch != nil {
                    Text("rough patch · \(patchTime)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.buildingFall)
                    Spacer()
                }
                Text(snapshot.end.tapeTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.label2)
            }
            .padding(.top, 4)

            // Outcome legend
            HStack(spacing: 12) {
                ForEach(Outcome.allCases) { o in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(o.color)
                            .frame(width: 8, height: 8)
                        Text(o.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(.top, 11)
        }
    }

    /// Midpoint timestamp of the rough patch, interpolated across the session.
    private var patchTime: String {
        guard let patch = snapshot.roughPatch, !snapshot.outcomes.isEmpty else { return "" }
        let frac = (Double(patch.lowerBound) + Double(patch.count) / 2) / Double(snapshot.outcomes.count)
        let t = snapshot.start.addingTimeInterval(frac * snapshot.end.timeIntervalSince(snapshot.start))
        return t.tapeTime
    }
}
