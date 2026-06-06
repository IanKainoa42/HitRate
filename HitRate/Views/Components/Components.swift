import SwiftUI

// MARK: - Court backdrop (the brand register's "court at night")

/// Radial navy + court grid + coral/electric glows. One source of truth —
/// onboarding, the share sheet, and (since the register unification) the main
/// app all sit on this. Call sites add `.ignoresSafeArea()`.
///
/// `twinkle` adds the ambient star field — Home only, so the counter stays
/// distraction-free and share snapshots stay deterministic.
struct CourtBackdrop: View {
    var twinkle = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x1B2335), Color(hex: 0x0C1120), Color(hex: 0x06080F)],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0, endRadius: 700)
            CourtGrid(cell: 30, lineColor: .white.opacity(0.05))
                .mask(RadialGradient(colors: [.white, .clear], center: UnitPoint(x: 0.5, y: 0.3),
                                     startRadius: 100, endRadius: 500))
            Circle()
                .fill(Theme.coral.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -140, y: -260)
            Circle()
                .fill(Theme.electric.opacity(0.13))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 150, y: 280)
            if twinkle {
                TwinkleField()
            }
        }
    }
}

// MARK: - Twinkle field (ambient stars, eye-candy over the navy)

/// A handful of tiny stars fading in and out, weighted toward the top of the
/// screen where the chart cards sit. Deterministic per-star constants (hash of
/// the index) so there's no Date/random state to manage; only time drives the
/// shimmer. Reduce Motion gets a static faint field instead.
struct TwinkleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let count = 22

    var body: some View {
        if reduceMotion {
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, t: 0, animated: false)
            }
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    draw(ctx: &ctx, size: size, t: t, animated: true)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Classic shader-style hash — cheap, stable, no RNG state.
    private func hash(_ n: Double) -> Double {
        let s = sin(n) * 43758.5453123
        return s - s.rounded(.down)
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double, animated: Bool) {
        for i in 0..<count {
            let fi = Double(i)
            let hx = hash(fi * 12.9898 + 78.233)
            let hy = hash(fi * 39.346 + 11.135)
            let hs = hash(fi * 7.13 + 3.7)

            let x = hx * size.width
            let y = hy * hy * size.height * 0.85   // squared → top-weighted, toward the charts
            // Each star breathes on its own speed/phase; sharpen so it spends
            // most of its life dim and "pops" briefly — a twinkle, not a pulse.
            let speed = 0.5 + hs * 0.9
            let raw = animated ? (sin(t * speed + fi * 2.39) + 1) / 2 : 0.3
            let a = pow(raw, 3) * 0.55
            guard a > 0.02 else { continue }

            let r = 0.8 + hs * 1.3 + raw * 0.8
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let color: Color = hs > 0.85 ? Theme.electric : .white

            // Soft halo + core
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 1.6, dy: -r * 1.6)),
                     with: .color(color.opacity(a * 0.25)))
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(a)))

            // The brightest moments get a 4-point sparkle cross.
            if raw > 0.9 {
                var p = Path()
                let arm = r * 3.2
                p.move(to: CGPoint(x: x - arm, y: y))
                p.addLine(to: CGPoint(x: x + arm, y: y))
                p.move(to: CGPoint(x: x, y: y - arm))
                p.addLine(to: CGPoint(x: x, y: y + arm))
                ctx.stroke(p, with: .color(color.opacity(a * 0.6)), lineWidth: 0.7)
            }
        }
    }
}

// MARK: - Feed card

/// `glow` lights a card up — colored edge + ambient halo. Reserved for the
/// hero data cards (summary, trend) so the eye lands on the charts first;
/// everything else stays flat glass.
struct FeedCard<Content: View>: View {
    var glow: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .shadow(color: (glow ?? .clear).opacity(0.20), radius: 18)
    }

    private var edge: AnyShapeStyle {
        if let glow {
            AnyShapeStyle(LinearGradient(
                colors: [glow.opacity(0.55), .white.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            AnyShapeStyle(Color.white.opacity(0.10))
        }
    }
}

struct CardHead: View {
    let title: String
    var right: AnyView? = nil

    init(_ title: String) {
        self.title = title
    }

    init<R: View>(_ title: String, @ViewBuilder right: () -> R) {
        self.title = title
        self.right = AnyView(right())
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.88)
                .foregroundStyle(Theme.label2)
            Spacer()
            if let right { right }
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Stacked outcome distribution bar

struct StackedBar: View {
    let counts: [Int]            // indexed by Outcome.rawValue
    let total: Int
    var height: CGFloat = 13
    var background: Color = Theme.fill

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if total > 0 {
                    ForEach(Outcome.allCases) { o in
                        let w = CGFloat(counts[o.rawValue]) / CGFloat(total)
                        if w > 0 {
                            o.color.frame(width: w * geo.size.width)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: counts)
    }
}

// MARK: - Small two-option segmented pill (Ranked / Grid)

struct MiniSeg: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = selection == o
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = o }
                } label: {
                    Text(o)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Theme.label : Theme.label2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(on ? Theme.surface2 : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.fill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Delta arrow + value

struct DeltaLabel: View {
    let delta: Int
    var font: Font = .system(size: 11, weight: .bold, design: .monospaced)
    var iconSize: CGFloat = 12

    private var up: Bool { delta >= 0 }
    private var color: Color { up ? Theme.hit : Theme.majorFall }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .font(.system(size: iconSize, weight: .heavy))
            Text("\(abs(delta))")
                .font(font)
        }
        .foregroundStyle(color)
    }
}
