import SwiftUI

// MARK: - Feed card

struct FeedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
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
                        .background(on ? Theme.surface : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: on ? .black.opacity(0.13) : .clear, radius: 1, y: 1)
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
