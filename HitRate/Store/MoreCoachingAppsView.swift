import SwiftUI

/// One of Ian's other App Store apps. Keep in sync with the developer page
/// (apps.apple.com/developer/id1864051409) and with the same list in
/// FormationFlow / CoachCard.
struct CoachingApp: Identifiable {
    let id: String          // App Store numeric ID
    let name: String
    let tagline: String
    let systemImage: String
    let price: String

    var storeURL: URL { URL(string: "https://apps.apple.com/app/id\(id)")! }

    static let others: [CoachingApp] = [
        CoachingApp(id: "6759989262", name: "FormationFlow",
                    tagline: "Plan formations and transitions, animate them, export a printable playbook.",
                    systemImage: "circle.grid.3x3", price: "Free"),
        CoachingApp(id: "6760259826", name: "CoachCard",
                    tagline: "Silent coaching whiteboard for iPad. Flash scores and cues across a loud gym.",
                    systemImage: "rectangle.on.rectangle.angled", price: "$4.99"),
        CoachingApp(id: "6766343275", name: "PracticeMix",
                    tagline: "Turn your competition mix into timed practice blocks with reps and rest.",
                    systemImage: "music.note.list", price: "$7.99"),
        CoachingApp(id: "6763985604", name: "Vid-e-Note",
                    tagline: "Draw on any video with Apple Pencil. Mark up stunts and tumbling frame by frame.",
                    systemImage: "pencil.and.scribble", price: "$4.99")
    ]
}

/// Training-floor register list of the rest of the toolkit. Rows open the App Store.
struct MoreCoachingAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FROM THE SAME COACH")
                            .font(.system(size: 11, weight: .heavy)).tracking(1.6)
                            .foregroundStyle(Theme.accent)
                        Text("More coaching tools")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.label)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.label2)
                            .frame(width: 32, height: 32)
                            .wellBackground(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 4)

                ForEach(CoachingApp.others) { app in
                    Button { openURL(app.storeURL) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: app.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(app.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.label)
                                    Spacer()
                                    Text(app.price).font(Theme.barlow(15, .semibold)).foregroundStyle(Theme.label2)
                                }
                                Text(app.tagline).font(.system(size: 13)).foregroundStyle(Theme.label2)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .wellBackground(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(app.name), \(app.price). Opens the App Store.")
                }

                Text("Built at CheerForce San Diego for real practices. Every app works offline with no account.")
                    .font(.system(size: 12)).foregroundStyle(Theme.label3)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .background(FloorBackdrop().ignoresSafeArea())
    }
}
