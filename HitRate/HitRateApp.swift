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
    @Environment(\.modelContext) private var context
    @Query private var groups: [StuntGroup]

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "chart.bar.fill") }
            LogView()
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }
        }
        .tint(Theme.accent)
        .onAppear { seedDefaultGroupsIfNeeded() }
    }

    /// First launch: give the coach a starting roster of groups to rename.
    private func seedDefaultGroupsIfNeeded() {
        guard groups.isEmpty else { return }
        for i in 1...5 {
            context.insert(StuntGroup(name: "Group \(i)", number: i, orderIndex: i - 1))
        }
        try? context.save()
    }
}
