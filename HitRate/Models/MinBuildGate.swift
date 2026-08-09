import Foundation
import SwiftUI
import FirebaseFirestore

/// Reads the remote `config/ios` document and decides whether THIS build is
/// still allowed to run. The August 2026 write storm was one old build
/// rewriting every synced document on every save; TestFlight copies can be
/// expired from App Store Connect, but shipped App Store installs have no
/// remote off-switch at all. This is that switch.
///
/// FAILS OPEN by design — an unreachable Firestore, a missing document, or an
/// absent `minBuild` field all leave the app fully usable. The gate exists to
/// stop a known-bad build, never to make normal launches depend on the network.
@MainActor
final class MinBuildGate: ObservableObject {
    static let shared = MinBuildGate()

    @Published private(set) var isBlocked = false

    /// Cached so an offline relaunch of a blocked build stays blocked, and so a
    /// normal launch never waits on the network to render.
    @AppStorage("minBuildCached") private var cachedMinBuild = 0
    @AppStorage("minBuildCheckedAt") private var lastCheckedAt: Double = 0

    private static let recheckInterval: TimeInterval = 60 * 60 * 6

    private init() {}

    var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Apply the cached verdict immediately, then refresh it in the background.
    func evaluate() {
        applyVerdict(minBuild: cachedMinBuild > 0 ? cachedMinBuild : nil)
        guard Date.now.timeIntervalSince1970 - lastCheckedAt > Self.recheckInterval else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard let snapshot = try? await Firestore.firestore()
            .collection("config").document("ios").getDocument() else { return }
        lastCheckedAt = Date.now.timeIntervalSince1970
        guard let minBuild = snapshot.data()?["minBuild"] as? Int else { return }
        cachedMinBuild = minBuild
        applyVerdict(minBuild: minBuild)
    }

    private func applyVerdict(minBuild: Int?) {
        isBlocked = MinBuildPolicy.isBlocked(currentBuild: currentBuild, minBuild: minBuild)
    }
}

/// Terminal state for a build that has been remotely retired. Deliberately
/// offers no dismiss — a blocked build is one whose continued use is the
/// problem. Local data is untouched and returns after updating.
struct UpdateRequiredView: View {
    private let listingURL = URL(string: "https://apps.apple.com/app/id6777192892")!

    var body: some View {
        ZStack {
            FloorBackdrop().ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text("UPDATE REQUIRED")
                    .font(Theme.barlow(30, .extrabold))
                    .foregroundStyle(Theme.label)

                Text("This version of HitRate is no longer supported. Update to keep logging and syncing your reps — nothing you've logged is lost.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.label2)
                    .padding(.horizontal, 8)

                Link(destination: listingURL) {
                    Text("Update on the App Store")
                        .font(.headline)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 4)
            }
            .padding(22)
            .wellBackground(cornerRadius: 16)
            .padding(.horizontal, 28)
        }
    }
}
