import SwiftUI
import SwiftData

@main
struct HitRateApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: StuntGroup.self, PracticeSession.self, Attempt.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light) // app UI register is iOS light
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Query private var groups: [StuntGroup]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue

    var body: some View {
        Group {
            if didOnboard {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "chart.bar.fill") }
                    LogView()
                        .tabItem { Label("Log", systemImage: "plus.circle.fill") }
                }
                .tint(Theme.accent)
            } else {
                OnboardingView()
            }
        }
        .onAppear { migrateExistingInstallIfNeeded() }
    }

    /// Pre-onboarding installs already have groups (the old seeded roster).
    /// Treat them as coach installs instead of re-onboarding over their data.
    private func migrateExistingInstallIfNeeded() {
        guard !didOnboard, !groups.isEmpty else { return }
        appModeRaw = AppMode.coach.rawValue
        didOnboard = true
    }
}
