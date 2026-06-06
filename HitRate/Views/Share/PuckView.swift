import SwiftUI

/// "Cheer puck" — the round collectible render of an earned milestone, sized
/// for stickers/avatars. Saved via ImageRenderer with a transparent backdrop
/// (everything outside the circle stays alpha).
struct PuckView: View {
    let milestone: Milestone
    let orgName: String

    private var rarity: Rarity { Rarity.of(tier: milestone.tier) }

    var body: some View {
        ZStack {
            // Tier ring
            Circle()
                .fill(AngularGradient(colors: rarity.edgeColors + [rarity.edgeColors[0]],
                                      center: .center))
            // Face
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x141A2B), Color(hex: 0x0D1322), Color(hex: 0x0A0F1E)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                CourtGrid(cell: 22, lineColor: .white.opacity(0.06))
                    .clipShape(Circle())

                VStack(spacing: 7) {
                    Text(milestone.kicker)
                        .font(Theme.grotesk(8))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: milestone.icon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(rarity.tag)
                        .shadow(color: rarity.tag.opacity(0.8), radius: 9)
                    Text(milestone.name.uppercased())
                        .font(Theme.grotesk(15))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 30)
                    StarsView(filled: rarity.stars)
                    Text(initials(of: orgName))
                        .font(Theme.grotesk(8))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(9)
        }
        .frame(width: 240, height: 240)
    }
}
