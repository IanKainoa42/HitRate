import SwiftUI

/// One stat card's worth of data, derived from FloorStats.
struct CardSpec: Identifiable {
    let id: Int          // index in the deck (0 = team/season card)
    let kicker: String   // "FULL FLOOR"/"ALL SKILLS" / "GROUP N"/"SKILL N"
    let name: String
    let badge: String    // "★" for the overall card, bucket number otherwise
    let color: Color     // identity color
    let rate: Int
    let counts: [Int]
    let total: Int
    let delta: Int?
    var flavorNoun = "group"   // word used in stat flavor text
    var kind: SkillKind = .stunt   // outcome wording on the energy chips

    static func deck(from stats: FloorStats, teamName: String, mode: AppMode) -> [CardSpec] {
        var cards: [CardSpec] = [
            CardSpec(id: 0, kicker: mode == .athlete ? "ALL SKILLS" : "FULL FLOOR",
                     name: teamName, badge: "★",
                     color: Theme.electric, rate: stats.rate, counts: stats.overall,
                     total: stats.total, delta: stats.delta, flavorNoun: mode.noun,
                     kind: stats.aggregateKind)
        ]
        for (i, g) in stats.ranked.enumerated() where g.total > 0 {
            cards.append(CardSpec(
                id: i + 1, kicker: "\(mode.nounTitle.uppercased()) \(g.number)",
                name: g.name, badge: "\(g.number)",
                color: Theme.groupColor(g.colorIndex), rate: g.rate, counts: g.counts,
                total: g.total, delta: g.delta, flavorNoun: mode.noun, kind: g.kind))
        }
        return cards
    }
}

/// One swipeable card in the share deck: a flat stat card or a milestone
/// (earned = full holo chrome, locked = desaturated teaser with progress).
struct DeckCard: Identifiable {
    enum Content {
        case stats(CardSpec)
        case milestone(Milestone)
    }

    let id: Int
    let content: Content

    var name: String {
        switch content {
        case .stats(let s): s.name
        case .milestone(let m): m.name
        }
    }

    var color: Color {
        switch content {
        case .stats(let s): s.color
        case .milestone(let m): Rarity.of(tier: m.tier).tag
        }
    }

    var lockedMilestone: Milestone? {
        if case .milestone(let m) = content, !m.earned { return m }
        return nil
    }

    var earnedMilestone: Milestone? {
        if case .milestone(let m) = content, m.earned { return m }
        return nil
    }
}

/// The card — trading-card proportions (290×430). Stat cards render flat
/// (static navy edge, no foil); milestone cards carry the rarity chrome,
/// with foil sweep + sheen reserved for holo/legendary tiers.
struct HoloCardView: View {
    let card: DeckCard
    let index: Int
    let count: Int
    let orgName: String
    var isSnapshot = false   // static rendering for ImageRenderer
    var interactiveTilt: CGSize? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rarity: Rarity {
        switch card.content {
        case .stats(let s): Rarity.stats(rate: s.rate, noun: s.flavorNoun,
                                         stunt: s.kind == .stunt,
                                         seed: s.name.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        case .milestone(let m): Rarity.of(tier: m.tier)
        }
    }

    private var locked: Bool { card.lockedMilestone != nil }

    /// Foil motion only on holo/legendary chrome — flat cards stay still.
    private var animated: Bool {
        !isSnapshot && !reduceMotion && rarity.foil != .none && !locked
    }

    var body: some View {
        ZStack {
            // Edge frame — animated gradient sweep on foil tiers only
            foilEdge
            // Inner card face
            inner
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(8)
            // Foil sheen overlay for earned holo/legendary
            if rarity.foil != .none && !locked {
                foilSheen
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 290, height: 430)
        .saturation(locked ? 0.25 : 1)   // locked teasers sit behind glass
        .shadow(color: .black.opacity(0.55), radius: 30, y: 22)
    }

    // MARK: Foil edge (the frame)

    private var foilEdge: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { tl in
            let dx: CGFloat
            let dy: CGFloat
            if let tilt = interactiveTilt {
                dx = tilt.width * 0.5
                dy = tilt.height * 0.5
            } else {
                let t = animated
                    ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7
                    : 0.35
                let phase = CGFloat(t) * 2 * .pi
                dx = cos(phase) * 0.5
                dy = sin(phase) * 0.5
            }
            
            return RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: rarity.edgeColors,
                    startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                    endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        }
    }

    // MARK: Foil sheen (diagonal color sweep, ambient)

    private var foilSheen: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { tl in
            let x: CGFloat
            let y: CGFloat
            if let tilt = interactiveTilt {
                x = tilt.width * 0.8
                y = tilt.height * 0.8
            } else {
                let t = animated
                    ? tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6
                    : 0.4
                x = CGFloat(t) * 2 - 0.5 // sweeps across
                y = CGFloat(t)
            }
            
            return Group {
                if rarity.foil == .holo {
                    LinearGradient(
                        colors: [.clear, Theme.electric.opacity(0.5), Color(hex: 0x9775FA).opacity(0.5),
                                 Color(hex: 0xFF4D6D).opacity(0.45), Theme.gold.opacity(0.5), .clear],
                        startPoint: UnitPoint(x: x - 0.6, y: y - 0.6),
                        endPoint: UnitPoint(x: x + 0.6, y: y + 0.6))
                } else {
                    LinearGradient(
                        colors: [.clear, Theme.gold.opacity(0.55), Color(hex: 0xFFF3B0).opacity(0.6),
                                 Theme.gold.opacity(0.5), .clear],
                        startPoint: UnitPoint(x: x - 0.6, y: y - 0.6),
                        endPoint: UnitPoint(x: x + 0.6, y: y + 0.6))
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
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1.4)
                .padding(14)
            CourtGrid(cell: 30, lineColor: .white.opacity(0.06))
                .mask(RadialGradient(colors: [.white, .clear], center: .center,
                                     startRadius: 40, endRadius: 260))

            switch card.content {
            case .stats(let spec): statsFace(spec)
            case .milestone(let m): milestoneFace(m)
            }
        }
    }

    // MARK: Stats face (flat)

    private func statsFace(_ spec: CardSpec) -> some View {
        ZStack {
            VStack(spacing: 0) {
                header(badge: Text(spec.badge), color: spec.color,
                       kicker: spec.kicker, name: spec.name,
                       kind: spec.kind)
                gauge(spec)
                powerBar(spec)
                energyChips(spec)
                Spacer(minLength: 0)
                tagAndFlavor(rarity.flavor)
                footer
            }

            // Delta stamp
            if let delta = spec.delta {
                deltaStamp(delta)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 13))
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

    private func gauge(_ spec: CardSpec) -> some View {
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

    private func powerBar(_ spec: CardSpec) -> some View {
        StackedBar(counts: spec.counts, total: spec.total, height: 7,
                   background: .white.opacity(0.08))
            .padding(.horizontal, 13)
            .padding(.top, 8)
    }

    private func energyChips(_ spec: CardSpec) -> some View {
        HStack(spacing: 6) {
            ForEach(Outcome.allCases) { o in
                VStack(spacing: 2) {
                    Text("\(spec.counts[o.rawValue])")
                        .font(Theme.grotesk(16))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(o.short(spec.kind))
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

    // MARK: Milestone face

    private func milestoneFace(_ m: Milestone) -> some View {
        ZStack {
            VStack(spacing: 0) {
                header(badge: MilestoneIcon(icon: m.icon).font(.system(size: 13, weight: .bold)),
                       color: rarity.tag.opacity(m.earned ? 1 : 0.5),
                       kicker: m.kicker, name: m.name,
                       hp: m.currentCount, kind: m.kind)

                // Progress ring with the milestone icon at its center
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [rarity.tag.opacity(m.earned ? 0.22 : 0.08), .clear],
                                             center: .center, startRadius: 0, endRadius: 63))
                        .frame(width: 126, height: 126)
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 9)
                        .padding(9)
                        .frame(width: 116, height: 116)
                    Circle()
                        .trim(from: 0, to: CGFloat(m.progress))
                        .stroke(rarity.tag, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(9)
                        .frame(width: 116, height: 116)
                        .shadow(color: rarity.tag.opacity(m.earned ? 0.9 : 0.3), radius: 3.2)
                    Group {
                        if m.earned {
                            MilestoneIcon(icon: m.icon)
                        } else {
                            Image(systemName: "lock.fill")
                        }
                    }
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(m.earned ? .white : .white.opacity(0.45))
                }
                .padding(.top, 2)

                // The number that earned it (or the distance left)
                Text(m.detail)
                    .font(Theme.grotesk(15, .medium))
                    .foregroundStyle(.white.opacity(m.earned ? 0.92 : 0.6))
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
                tagAndFlavor(m.flavor)
                footer
            }

            if !m.earned {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("LOCKED").font(Theme.grotesk(9)).tracking(1.0)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(EdgeInsets(top: 48, leading: 0, bottom: 0, trailing: 13))
            }
        }
    }

    // MARK: Shared chrome

    private func header(badge: some View, color: Color,
                        kicker: String, name: String,
                        hp: Int? = nil, kind: SkillKind? = nil) -> some View {
        HStack(alignment: .top, spacing: 9) {
            badge
                .font(Theme.grotesk(14))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: color.opacity(0.53), radius: 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(Theme.grotesk(9))
                    .tracking(1.44)
                    .foregroundStyle(.white.opacity(0.5))
                Text(name)
                    .font(Theme.grotesk(19))
                    .tracking(-0.19)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 6) {
                if let hp = hp {
                    HStack(alignment: .top, spacing: 1) {
                        Text("\(hp)")
                            .font(Theme.grotesk(22, .bold))
                            .foregroundStyle(.white)
                    }
                }
                if let kind = kind {
                    Image(systemName: kind == .stunt ? "figure.gymnastics" : "figure.run")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        )
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                        .padding(.top, 1)
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 13, bottom: 8, trailing: 13))
    }

    private func tagAndFlavor(_ flavor: String) -> some View {
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
            Text(flavor)
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
                IconWordmark(size: 10, rateFill: Color(hex: 0x0A0F1E), dotSize: 5)
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
                if rarity.tier != "STATS" {
                    StarsView(filled: rarity.stars)
                }
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
