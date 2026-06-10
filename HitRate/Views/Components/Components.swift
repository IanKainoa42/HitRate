import SwiftUI

// MARK: - Court backdrop (the brand register's "court at night")

/// Radial navy + court grid + coral/electric glows. The brand "court at
/// night" register — onboarding and the share sheet sit on this. The main app
/// moved to `FloorBackdrop` (training-floor register) on 2026-06-07.
/// Call sites add `.ignoresSafeArea()`.
struct CourtBackdrop: View {
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
        }
    }
}

// MARK: - Floor backdrop (the app's "training floor" register)

/// Lifted graphite with a tight 1px diagonal hairline — reads as a machined
/// surface, not a void, without the noise of speckle. Static draw, no
/// animation. Call sites add `.ignoresSafeArea()`.
struct FloorBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.appBGTop, Theme.appBG, Theme.appBGBottom],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Theme.iconTile.opacity(0.72), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 40, endRadius: 470)
            Canvas { ctx, size in
                var p = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 10
                }
                ctx.stroke(p, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Feed card

/// The inset-well surface: recessed INTO the floor (inner top shadow +
/// bottom catch-light) instead of floating on it. One material, no glass,
/// no glow — raised treatment is reserved for the practice CTA.
extension View {
    func wellBackground(cornerRadius: CGFloat = 10) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.well
                    .shadow(.inner(color: .black.opacity(0.6), radius: 4, y: 2))
                    .shadow(.inner(color: Theme.iconTileEdge.opacity(0.26), radius: 0.5, y: -1)))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.15), Theme.iconTileEdge.opacity(0.42), .black.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 10, y: 6)
        )
    }
}

// MARK: - Icon-derived brand chrome

struct BrandSignalDot: View {
    var size: CGFloat = 9
    var color: Color = Theme.accent
    var shadowOpacity: Double = 0.34

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: max(0.7, size * 0.08)))
            .shadow(color: color.opacity(shadowOpacity), radius: size * 0.55, y: 0)
            .accessibilityHidden(true)
    }
}

struct IconWordmark: View {
    var size: CGFloat = 17
    var rateFill: Color = Theme.well
    var dotSize: CGFloat? = nil
    var showsDot = true

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.08) {
            Text("HIT")
                .font(.system(size: size, weight: .black))
                .italic()
                .foregroundStyle(Theme.label)
            OutlinedBrandText("RATE", size: size, fill: rateFill)
            if showsDot {
                BrandSignalDot(size: dotSize ?? size * 0.55)
                    .baselineOffset(size * -0.10)
                    .padding(.leading, size * 0.04)
            }
        }
        .tracking(0)
        .accessibilityLabel("Hit Rate")
    }
}

private struct OutlinedBrandText: View {
    let text: String
    let size: CGFloat
    let fill: Color

    init(_ text: String, size: CGFloat, fill: Color) {
        self.text = text
        self.size = size
        self.fill = fill
    }

    private var brandFont: Font {
        .system(size: size, weight: .black)
    }

    var body: some View {
        ZStack {
            ForEach(OutlineOffset.all, id: \.self) { offset in
                Text(text)
                    .font(brandFont)
                    .italic()
                    .foregroundStyle(Theme.label)
                    .offset(x: offset.x * max(0.8, size * 0.055),
                            y: offset.y * max(0.8, size * 0.055))
            }
            Text(text)
                .font(brandFont)
                .italic()
                .foregroundStyle(fill)
        }
        .compositingGroup()
    }
}

private struct OutlineOffset: Hashable {
    let x: CGFloat
    let y: CGFloat

    static let all = [
        OutlineOffset(x: -1, y: -1), OutlineOffset(x: 0, y: -1), OutlineOffset(x: 1, y: -1),
        OutlineOffset(x: -1, y: 0),                                OutlineOffset(x: 1, y: 0),
        OutlineOffset(x: -1, y: 1),  OutlineOffset(x: 0, y: 1),  OutlineOffset(x: 1, y: 1),
    ]
}

/// A dashboard module: content in an inset well.
struct FeedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .wellBackground()
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
            // Engraved kicker — every well leads with one.
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
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
                        .foregroundStyle(on ? Theme.well : Theme.label2)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(on ? Theme.label : .clear)
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
