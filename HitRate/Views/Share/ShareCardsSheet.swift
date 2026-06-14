import SwiftUI
import UIKit

/// Full-screen "court at night" share sheet: swipeable Stunt Cards carousel,
/// dots, and real share actions (Instagram deep-link, save, copy, pucks).
/// Deck = flat stat cards up front, then milestones — earned holos first,
/// locked teasers (with progress) trailing.
struct ShareCardsSheet: View {
    let stats: FloorStats
    let milestones: [Milestone]
    let teamName: String
    let orgName: String
    let mode: AppMode

    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int? = 0
    @State private var toast = ""
    @State private var toastTask: Task<Void, Never>?
    @State private var photoSaver = PhotoSaver()
    @State private var holdingCard: DeckCard?

    private var cards: [DeckCard] {
        var deck = CardSpec.deck(from: stats, teamName: teamName, mode: mode)
            .map { DeckCard(id: $0.id, content: .stats($0)) }
        for m in milestones {
            deck.append(DeckCard(id: deck.count, content: .milestone(m)))
        }
        return deck
    }

    var body: some View {
        let deck = cards
        ZStack {
            CourtBackdrop()
                .ignoresSafeArea()

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
            
            // Holding Mode Overlay
            if let card = holdingCard {
                ZStack {
                    Color.black.opacity(0.85)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                holdingCard = nil
                            }
                        }
                        
                    InteractiveCardView(card: card, index: card.id, count: deck.count, orgName: orgName)
                        .transition(AnyTransition.scale(scale: 0.8).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("SHARE")
                    .font(Theme.grotesk(10))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.5))
                Text(mode == .athlete ? "Trading Cards" : "Stunt Cards")
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

    private func carousel(_ deck: [DeckCard]) -> some View {
        GeometryReader { geo in
            let scale = min(1.0, geo.size.height / 460)
            let scaledWidth = 290 * scale
            let margin = max(16, (geo.size.width - scaledWidth) / 2)
            
            ScrollView(.horizontal) {
                LazyHStack(spacing: 18) {
                    ForEach(deck) { card in
                        HoloCardView(card: card, index: card.id, count: deck.count, orgName: orgName)
                            .id(card.id)
                            .scaleEffect(scale)
                            .frame(width: scaledWidth, height: 430 * scale)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    holdingCard = card
                                }
                            }
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

    private func dots(_ deck: [DeckCard]) -> some View {
        HStack(spacing: 6) {
            ForEach(deck) { card in
                let on = card.id == (activeIndex ?? 0)
                Button {
                    withAnimation(.easeOut(duration: 0.3)) { activeIndex = card.id }
                } label: {
                    Capsule()
                        .fill(on ? card.color : .white.opacity(0.25))
                        .frame(width: on ? 18 : 6, height: 6)
                        .animation(.easeOut(duration: 0.25), value: activeIndex)
                        .padding(.vertical, 8)   // a 6pt dot is not a tap target
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card \(card.id + 1) of \(deck.count), \(card.name)")
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func actions(_ deck: [DeckCard]) -> some View {
        let active = deck[min(activeIndex ?? 0, deck.count - 1)]
        let locked = active.lockedMilestone != nil
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
                        photoSaver.save(img) { ok in
                            showToast(ok ? "Saved to Photos"
                                         : "Couldn't save — allow Photos access in Settings")
                        }
                    }
                }
                glassButton("Copy image", icon: "doc.on.doc") {
                    if let img = render(active, count: deck.count) {
                        UIPasteboard.general.image = img
                        showToast("Card image copied")
                    }
                }
            }

            // Earned milestones double as round collectible pucks.
            if let m = active.earnedMilestone {
                glassButton("Save cheer puck", icon: "circle.hexagongrid.circle") {
                    if let img = renderPuck(m) {
                        photoSaver.save(img) { ok in
                            showToast(ok ? "Puck saved to Photos"
                                         : "Couldn't save — allow Photos access in Settings")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        // Locked teasers aren't shareable — earn it first.
        .disabled(locked)
        .opacity(locked ? 0.35 : 1)
        .animation(.easeOut(duration: 0.2), value: locked)
        .overlay(alignment: .top) {
            if locked {
                Text("Locked — keep counting to earn this card")
                    .font(Theme.grotesk(12, .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .offset(y: -22)
            }
        }
    }

    private func glassButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                MilestoneIcon(icon: icon)
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
    private func render(_ card: DeckCard, count: Int) -> UIImage? {
        let renderer = ImageRenderer(
            content: HoloCardView(card: card, index: card.id, count: count,
                                  orgName: orgName, isSnapshot: true)
                .frame(width: 290, height: 430))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 290, height: 430)
        return renderer.uiImage
    }

    @MainActor
    private func renderPuck(_ milestone: Milestone) -> UIImage? {
        let renderer = ImageRenderer(
            content: PuckView(milestone: milestone, orgName: orgName)
                .frame(width: 240, height: 240))
        renderer.scale = 3
        renderer.isOpaque = false   // transparent corners — it's a sticker
        renderer.proposedSize = ProposedViewSize(width: 240, height: 240)
        return renderer.uiImage
    }

    /// Save the card image, then deep-link to Instagram (handoff-recommended flow).
    private func shareToInstagram(_ card: DeckCard, count: Int) {
        guard let img = render(card, count: count) else { return }
        photoSaver.save(img) { ok in
            guard ok else {
                showToast("Couldn't save — allow Photos access in Settings")
                return
            }
            if let url = URL(string: "instagram://app"), UIApplication.shared.canOpenURL(url) {
                showToast("Saved card — opening Instagram")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    UIApplication.shared.open(url)
                }
            } else {
                showToast("Saved card to Photos — open Instagram to post")
            }
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

/// Completion-reporting wrapper for UIImageWriteToSavedPhotosAlbum — the
/// fire-and-forget form swallows permission errors, so the toast would claim
/// "Saved to Photos" even when access was denied.
private final class PhotoSaver: NSObject {
    private var completion: ((Bool) -> Void)?

    func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        UIImageWriteToSavedPhotosAlbum(
            image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeRawPointer) {
        completion?(error == nil)
        completion = nil
    }
}
