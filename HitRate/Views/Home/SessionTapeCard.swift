import SwiftUI

/// "LATEST SESSION" — the chronological tape: one thin bar per attempt,
/// height/color by outcome, with a rough-patch bracket when one exists. A rep
/// StuntScope scored from video gets a 1pt chalk-grey tick under its bar
/// (`snapshot.videoScored`) — a marker, not a colour: green stays the hit signal.
struct SessionTapeCard: View {
    let snapshot: SessionSnapshot
    var kind: SkillKind = .stunt   // legend wording (FloorStats.aggregateKind)

    private let heights: [Outcome: CGFloat] = [
        .hit: 34, .bobble: 26, .buildingFall: 22, .majorFall: 18,
    ]
    /// Room under the bars for the video tick (1pt) and its 2pt breathing gap.
    private let tickInset: CGFloat = 3

    private var hasVideo: Bool { snapshot.videoScored.contains(true) }
    private var videoCount: Int { snapshot.videoScored.filter { $0 }.count }

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
                    let rect = CGRect(x: CGFloat(i) * step, y: size.height - tickInset - h,
                                      width: barW, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: min(2, barW / 2)),
                             with: .color(o.color.opacity(o.isHit ? 0.9 : 1)))
                    if i < snapshot.videoScored.count, snapshot.videoScored[i] {
                        let tick = CGRect(x: rect.minX, y: size.height - 1, width: barW, height: 1)
                        ctx.fill(Path(tick), with: .color(Theme.label3))
                    }
                }
            }
            .frame(height: 36 + tickInset)
            .accessibilityLabel("Session tape")
            .accessibilityValue(tapeSummary)

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

            // Outcome legend (+ the video tick, only when a rep in the tape has one)
            HStack(spacing: 12) {
                ForEach(Outcome.allCases) { o in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(o.color)
                            .frame(width: 8, height: 8)
                        Text(o.label(kind))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if hasVideo {
                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(Theme.label3)
                            .frame(width: 8, height: 1)
                        Text("Video")
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

    /// VoiceOver stand-in for the drawn tape: per-outcome counts in order.
    private var tapeSummary: String {
        let counts = Outcome.allCases.map { o in
            snapshot.outcomes.filter { $0 == o }.count
        }
        let parts = Outcome.allCases.compactMap { o in
            counts[o.rawValue] > 0 ? "\(counts[o.rawValue]) \(o.label(kind).lowercased())" : nil
        }
        let video = videoCount > 0 ? ". \(videoCount) scored from video" : ""
        return "\(snapshot.outcomes.count) reps: " + parts.joined(separator: ", ") + video
    }

    /// Midpoint timestamp of the rough patch, interpolated across the session.
    private var patchTime: String {
        guard let patch = snapshot.roughPatch, !snapshot.outcomes.isEmpty else { return "" }
        let frac = (Double(patch.lowerBound) + Double(patch.count) / 2) / Double(snapshot.outcomes.count)
        let t = snapshot.start.addingTimeInterval(frac * snapshot.end.timeIntervalSince(snapshot.start))
        return t.tapeTime
    }
}
