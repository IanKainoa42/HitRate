import SwiftUI
import UIKit

/// Full-screen "court at night" share sheet: swipeable Stunt Cards carousel,
/// dots, and real share actions (Instagram deep-link, save, copy).
struct ShareCardsSheet: View {
    let stats: FloorStats
    let teamName: String
    let orgName: String

    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int? = 0
    @State private var toast = ""
    @State private var toastTask: Task<Void, Never>?

    private var cards: [CardSpec] { CardSpec.deck(from: stats, teamName: teamName) }

    var body: some View {
        let deck = cards
        ZStack {
            backdrop

            VStack(spacing: 0) {
                header
                carousel(deck)
                dots(deck)
                actions(deck)
            }

            // Toast
            VStack {
                Spacer()
                Text(toast)
                    .font(Theme.grotesk(13, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0x141A28).opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
                    .opacity(toast.isEmpty ? 0 : 1)
                    .animation(.easeOut(duration: 0.25), value: toast)
                    .padding(.bottom, 128)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Backdrop — radial navy + court grid + color glows

    private var backdrop: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x1B2335), Color(hex: 0x0C1120), Color(hex: 0x06080F)],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0, endRadius: 700)

            CourtGrid(cell: 30, lineColor: .white.opacity(0.05))
                .mask(RadialGradient(colors: [.white, .clear], center: UnitPoint(x: 0.5, y: 0.3),
                                     startRadius: 100, endRadius: 500))

            // coral glow top-left, electric glow bottom-right
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
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("SHARE")
                    .font(Theme.grotesk(10))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Stunt Cards")
                    .font(Theme.grotesk(21))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: Carousel

    private func carousel(_ deck: [CardSpec]) -> some View {
        GeometryReader { geo in
            let margin = max(16, (geo.size.width - 290) / 2)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(deck) { card in
                        HoloCardView(spec: card, index: card.id, count: deck.count, orgName: orgName)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activeIndex)
            .scrollIndicators(.hidden)
            .frame(height: geo.size.height)
        }
    }

    // MARK: Dots

    private func dots(_ deck: [CardSpec]) -> some View {
        HStack(spacing: 6) {
            ForEach(deck) { card in
                let on = card.id == (activeIndex ?? 0)
                Capsule()
                    .fill(on ? card.color : .white.opacity(0.25))
                    .frame(width: on ? 18 : 6, height: 6)
                    .animation(.easeOut(duration: 0.25), value: activeIndex)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    // MARK: Actions

    private func actions(_ deck: [CardSpec]) -> some View {
        let active = deck[min(activeIndex ?? 0, deck.count - 1)]
        return VStack(spacing: 10) {
            Button {
                shareToInstagram(active, count: deck.count)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "camera.circle")
                        .font(.system(size: 19, weight: .semibold))
                    Text("Share to Instagram")
                        .font(Theme.grotesk(16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(
                    colors: [Color(hex: 0x515BD4), Color(hex: 0x8134AF),
                             Color(hex: 0xDD2A7B), Color(hex: 0xF58529)],
                    startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: Color(hex: 0xDD2A7B).opacity(0.4), radius: 15, y: 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                glassButton("Save image", icon: "arrow.down.to.line") {
                    if let img = render(active, count: deck.count) {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                        showToast("Saved to Photos")
                    }
                }
                glassButton("Copy image", icon: "doc.on.doc") {
                    if let img = render(active, count: deck.count) {
                        UIPasteboard.general.image = img
                        showToast("Card image copied")
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private func glassButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(Theme.grotesk(14, .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Share mechanics

    @MainActor
    private func render(_ card: CardSpec, count: Int) -> UIImage? {
        let renderer = ImageRenderer(
            content: HoloCardView(spec: card, index: card.id, count: count,
                                  orgName: orgName, isSnapshot: true)
                .frame(width: 290, height: 430))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 290, height: 430)
        return renderer.uiImage
    }

    /// Save the card image, then deep-link to Instagram (handoff-recommended flow).
    private func shareToInstagram(_ card: CardSpec, count: Int) {
        guard let img = render(card, count: count) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        if let url = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(url) {
            showToast("Saved card — opening Instagram")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                UIApplication.shared.open(url)
            }
        } else {
            showToast("Saved card to Photos — open Instagram to post")
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.9))
            if !Task.isCancelled { toast = "" }
        }
    }
}
