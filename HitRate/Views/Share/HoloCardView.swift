import SwiftUI

/// One card's worth of data, derived from FloorStats.
struct CardSpec: Identifiable {
    let id: Int          // index in the deck (0 = team card)
    let kicker: String   // "FULL FLOOR" / "GROUP N"
    let name: String
    let badge: String    // "★" for team, group number otherwise
    let color: Color     // identity color
    let rate: Int
    let counts: [Int]
    let total: Int
    let delta: Int?

    static func deck(from stats: FloorStats, teamName: String) -> [CardSpec] {
        var cards: [CardSpec] = [
            CardSpec(id: 0, kicker: "FULL FLOOR", name: teamName, badge: "★",
                     color: Theme.electric, rate: stats.rate, counts: stats.overall,
                     total: stats.total, delta: stats.delta)
        ]
        for (i, g) in stats.ranked.enumerated() where g.total > 0 {
            cards.append(CardSpec(
                id: i + 1, kicker: "GROUP \(g.number)", name: g.name, badge: "\(g.number)",
                color: Theme.groupColor(g.colorIndex), rate: g.rate, counts: g.counts,
                total: g.total, delta: g.delta))
        }
        return cards
    }
}

/// The Stunt Card — trading-card proportions (290×430), per-rarity animated
/// foil edge, glowing gauge, energy chips, rarity tag + flavor, set footer.
struct HoloCardView: View {
    let spec: CardSpec
    let index: Int
    let count: Int
    let orgName: String
    var isSnapshot = false   // static rendering for ImageRenderer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rarity: Rarity { Rarity.of(rate: spec.rate) }
    private var animated: Bool { !isSnapshot && !reduceMotion }

    var body: some View {
        ZStack {
            // Metallic foil border — animated gradient sweep (ambient `foilEdge`)
            foilEdge
            // Inner card face
            inner
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(8)
            // Foil sheen overlay for holo/legendary tiers
            if rarity.foil != .none {
                foilSheen
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 290, height: 430)
        .shadow(color: .black.opacity(0.55), radius: 30, y: 22)
    }

    // MARK: Foil edge (the frame)

    private var foilEdge: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { tl in
            let t = animated
                ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                : 0.35
            let phase = CGFloat(t) * 2 * .pi
            let dx = cos(phase) * 0.5
            let dy = sin(phase) * 0.5
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: rarity.edgeColors,
                    startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                    endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        }
    }

    // MARK: Foil sheen (diagonal color sweep, ambient)

    private var foilSheen: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { tl in
            let t = animated
                ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                : 0.4
            let x = CGFloat(t) * 2 - 0.5 // sweeps across
            Group {
                if rarity.foil == .holo {
                    LinearGradient(
                        colors: [.clear, Theme.electric.opacity(0.5), Color(hex: 0x9775FA).opacity(0.5),
                                 Color(hex: 0xFF4D6D).opacity(0.45), Theme.gold.opacity(0.5), .clear],
                        startPoint: UnitPoint(x: x - 0.6, y: CGFloat(t) - 0.6),
                        endPoint: UnitPoint(x: x + 0.6, y: CGFloat(t) + 0.6))
                } else {
                    LinearGradient(
                        colors: [.clear, Theme.gold.opacity(0.55), Color(hex: 0xFFF3B0).opacity(0.6),
                                 Theme.gold.opacity(0.5), .clear],
                        startPoint: UnitPoint(x: x - 0.6, y: CGFloat(t) - 0.6),
                        endPoint: UnitPoint(x: x + 0.6, y: CGFloat(t) + 0.6))
                }
            }
            .blendMode(.colorDodge)
            .opacity(0.6)
        }
    }

    // MARK: Card face

    private var inner: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x141A2B), Color(hex: 0x0D1322), Color(hex: 0x0A0F1E)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            CourtGrid(cell: 30, lineColor: .white.opacity(0.06))
                .mask(RadialGradient(colors: [.white, .clear], center: .center,
                                     startRadius: 40, endRadius: 260))

            VStack(spacing: 0) {
                header
                gauge
                powerBar
                energyChips
                Spacer(minLength: 0)
                rarityAndFlavor
                footer
            }

            // Delta stamp
            if let delta = spec.delta {
                deltaStamp(delta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(11)
            }
        }
    }

    private func deltaStamp(_ delta: Int) -> some View {
        let up = delta >= 0
        let c = up ? Theme.brandGreen : Theme.coral
        return HStack(spacing: 3) {
            Text(up ? "▲" : "▼").font(.system(size: 8))
            Text("\(abs(delta))").font(Theme.grotesk(11))
        }
        .foregroundStyle(up ? Theme.brandGreen : Theme.coralLight)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(c.opacity(0.16))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(c.opacity(0.5), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(spec.badge)
                .font(Theme.grotesk(14))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(spec.color)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: spec.color.opacity(0.53), radius: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(spec.kicker)
                    .font(Theme.grotesk(9))
                    .tracking(1.44)
                    .foregroundStyle(.white.opacity(0.5))
                Text(spec.name)
                    .font(Theme.grotesk(19))
                    .tracking(-0.19)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 13, bottom: 8, trailing: 52))
    }

    private var gauge: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [spec.color.opacity(0.2), .clear],
                                     center: .center, startRadius: 0, endRadius: 63))
                .frame(width: 126, height: 126)
            GaugeRing(rate: spec.rate, color: spec.color)
                .frame(width: 116, height: 116)
        }
        .padding(.top, 2)
    }

    private var powerBar: some View {
        StackedBar(counts: spec.counts, total: spec.total, height: 7,
                   background: .white.opacity(0.08))
            .padding(.horizontal, 13)
            .padding(.top, 8)
    }

    private var energyChips: some View {
        HStack(spacing: 6) {
            ForEach(Outcome.allCases) { o in
                VStack(spacing: 2) {
                    Text("\(spec.counts[o.rawValue])")
                        .font(Theme.grotesk(16))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(o.short)
                        .font(Theme.grotesk(8))
                        .tracking(0.48)
                        .foregroundStyle(o.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(o.color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(o.color.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
    }

    private var rarityAndFlavor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rarity.tier)
                .font(Theme.grotesk(8))
                .tracking(1.12)
                .foregroundStyle(rarity.tag)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(rarity.tag.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(rarity.tag.opacity(0.33), lineWidth: 1))
            Text(rarity.flavor)
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(initials(of: orgName))
                    .font(Theme.grotesk(9))
                    .tracking(1.62)
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(Date.now.cardDate) · \(seasonString())")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                StarsView(filled: rarity.stars)
                Text("\(String(format: "%03d", index + 1))/\(String(format: "%03d", count))")
                    .font(Theme.grotesk(9))
                    .tracking(0.72)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.top, 6)
        .overlay(Rectangle().fill(.white.opacity(0.10)).frame(height: 1), alignment: .top)
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 9, trailing: 12))
    }
}

// MARK: - Gauge ring

struct GaugeRing: View {
    let rate: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 9)
                .padding(9)
            Circle()
                .trim(from: 0, to: CGFloat(rate) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(9)
                .shadow(color: color.opacity(0.9), radius: 3.2)
            VStack(spacing: 4) {
                Text("\(rate)")
                    .font(Theme.grotesk(35))
                    .foregroundStyle(.white)
                Text("HIT RATE")
                    .font(Theme.grotesk(9))
                    .tracking(1.44)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

struct StarsView: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < filled ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(i < filled ? Theme.gold : .white.opacity(0.3))
            }
        }
    }
}

// MARK: - Court grid overlay

struct CourtGrid: View {
    let cell: CGFloat
    let lineColor: Color

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += cell
            }
            ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
    }
}
