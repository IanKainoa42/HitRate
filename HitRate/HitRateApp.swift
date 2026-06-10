import SwiftUI
import SwiftData

@main
struct HitRateApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Team.self, StuntGroup.self,
                                           PracticeSession.self, Attempt.self)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark) // whole app lives in the brand register now
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var groups: [StuntGroup]
    @Query private var sessions: [PracticeSession]
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage("teamName") private var teamName = ""
    @AppStorage("replayingIntro") private var replayingIntro = false

    var body: some View {
        Group {
            // No tab bar — practice is occasional, the dashboard is the app.
            // The counter lives in a full-screen cover off Home's practice pill.
            if didOnboard {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.accent)
        .onAppear {
            migrateExistingInstallIfNeeded()
            migrateGroupsIntoDefaultTeam()
            sweepOrphanedAttempts()
            endStaleSessions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { endStaleSessions() }
        }
    }

    /// Pre-onboarding installs already have groups (the old seeded roster).
    /// Treat them as coach installs instead of re-onboarding over their data.
    /// A deliberate intro replay (Manage Data → Replay intro) also looks like
    /// "has groups, not onboarded" — the flag keeps this migration out of it.
    private func migrateExistingInstallIfNeeded() {
        guard !didOnboard, !groups.isEmpty, !replayingIntro else { return }
        appModeRaw = AppMode.coach.rawValue
        didOnboard = true
    }

    /// Multi-team arrived after single-roster installs existed: fold any
    /// teamless buckets into a default team (named from the old `teamName`
    /// identity) so every group has a home, and pin the active team if unset.
    private func migrateGroupsIntoDefaultTeam() {
        let orphanGroups = groups.filter { $0.team == nil }
        var dirty = false

        if !orphanGroups.isEmpty {
            let home: Team
            if let first = teams.first {
                home = first
            } else {
                let name = teamName.isEmpty ? "My Team" : teamName
                home = Team(name: name, orderIndex: 0)
                context.insert(home)
            }
            for g in orphanGroups { g.team = home }
            dirty = true
        }

        // Pin the active team if it's unset or points at a deleted team.
        if teams.current(id: currentTeamID) == nil, let first = teams.first {
            currentTeamID = first.id.uuidString
        } else if currentTeamID.isEmpty, let home = orphanGroups.first?.team {
            currentTeamID = home.id.uuidString
        }

        if dirty { try? context.save() }
    }

    /// Group deletes now cascade their attempts, but installs from before the
    /// cascade may hold orphaned attempts (group → nil) that distort the trend
    /// and tape while being invisible in the rate. Deleting the group meant
    /// deleting its reps — finish the job once.
    private func sweepOrphanedAttempts() {
        let orphans = (try? context.fetch(
            FetchDescriptor<Attempt>(predicate: #Predicate { $0.group == nil }))) ?? []
        guard !orphans.isEmpty else { return }
        for a in orphans { context.delete(a) }
        try? context.save()
    }

    /// A session left running from a previous day ends at its last rep —
    /// otherwise reps logged "today" land in a session dated days ago and
    /// silently vanish from Today stats. A session still being logged across
    /// midnight (last attempt is today) is left alive.
    private func endStaleSessions() {
        let cal = Calendar.current
        var dirty = false
        for s in sessions where s.isActive && !cal.isDateInToday(s.startedAt) {
            let lastActivity = s.sortedAttempts.last?.timestamp ?? s.startedAt
            guard !cal.isDateInToday(lastActivity) else { continue }
            s.endedAt = lastActivity
            dirty = true
        }
        if dirty { try? context.save() }
    }
}
