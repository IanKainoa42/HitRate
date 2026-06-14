import SwiftUI

/// Wraps a HoloCardView with an interactive 3D drag gesture, allowing the user
/// to physically tilt the card and influence the holographic reflections.
struct InteractiveCardView: View {
    let card: DeckCard
    let index: Int
    let count: Int
    let orgName: String
    
    // Normalized physical tilt (-1...1)
    @State private var tilt: CGSize = .zero
    // The visual rotation in degrees
    @State private var pitch: Double = 0
    @State private var yaw: Double = 0

    var body: some View {
        HoloCardView(card: card, index: index, count: count, orgName: orgName, isSnapshot: false, interactiveTilt: tilt)
            .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let maxPitch: Double = 30
                        let maxYaw: Double = 30
                        
                        let width = 290.0
                        let height = 430.0
                        
                        // Normalized coordinates
                        let normX = min(max((value.location.x - width / 2) / (width / 2), -1.5), 1.5)
                        let normY = min(max((value.location.y - height / 2) / (height / 2), -1.5), 1.5)
                        
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                            pitch = -normY * maxPitch
                            yaw = normX * maxYaw
                            tilt = CGSize(width: normX, height: normY)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            pitch = 0
                            yaw = 0
                            tilt = .zero
                        }
                    }
            )
            .scaleEffect(tilt == .zero ? 1.15 : 1.2)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: tilt == .zero)
            .shadow(color: .black.opacity(tilt == .zero ? 0.3 : 0.6), radius: tilt == .zero ? 20 : 40, y: tilt == .zero ? 10 : 30)
    }
}
