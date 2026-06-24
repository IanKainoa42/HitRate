import SwiftUI
import SwiftData

@main
struct HitRateApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Team.self, StuntGroup.self, PracticeSession.self, Attempt.self, UnlockedMilestone.self, CustomOutcome.self, CustomTally.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Log the error for debugging
            print("❌ Failed to create model container: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // Attempt in-memory fallback for development
            do {
                let schema = Schema([Team.self, StuntGroup.self, PracticeSession.self, Attempt.self, UnlockedMilestone.self, CustomOutcome.self, CustomTally.self])
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [configuration])
                print("⚠️ Using in-memory store as fallback")
            } catch {
                fatalError("Failed to create model container even with in-memory fallback: \(error)")
            }
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
    // The pad's pulled-up skill (written by LogView) — forwarded to the watch
    // so the wrist mirrors whatever the phone has up.
    @AppStorage("selectedGroupID") private var padSelectedGroupID = ""

    /// Which folder's dashboard is open. Nil → the folder-list home (the launch
    /// root). Deliberately @State, not persisted: every cold launch lands on the
    /// folder list, per the "open straight to folders" design.
    @State private var openFolderID: String?

    var body: some View {
        Group {
            // No tab bar — the folder list is home, a folder's dashboard is one
            // tap in, and the counter lives in a cover off the dashboard's pill.
            if didOnboard {
                if let id = openFolderID, teams.contains(where: { $0.id.uuidString == id }) {
                    HomeView(onExit: { openFolderID = nil })
                } else {
                    FolderListView(onOpen: { team in
                        currentTeamID = team.id.uuidString
                        openFolderID = team.id.uuidString
                    })
                }
            } else {
                OnboardingView()
            }
        }
        .tint(Theme.accent)
        // Finishing onboarding drops the user straight into the folder they just
        // built (its dashboard), not back out to the list.
        .onChange(of: didOnboard) { _, now in
            if now { openFolderID = currentTeamID }
        }
        .onAppear {
            CardCatalogRenderer.runIfRequested()
            dedupeSyncIDs()
            migrateExistingInstallIfNeeded()
            migrateGroupsIntoDefaultTeam()
            sweepOrphanedAttempts()
            endStaleSessions()
            configureWatchLogging()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                endStaleSessions()
                syncWatchLogging()
            }
        }
        .onChange(of: watchSnapshot) { _, snapshot in
            WatchSessionBridge.shared.publishSnapshot(snapshot)
        }
    }

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }
    private var currentTeam: Team? { teams.current(id: currentTeamID) }
    private var watchGroups: [StuntGroup] { groups.inTeam(currentTeam) }
    private var activeSession: PracticeSession? {
        sessions.filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }

    private var watchTeamLabel: String {
        currentTeam?.name ?? (mode == .coach ? "My Team" : "My Skills")
    }

    private var watchSnapshot: WatchRosterSnapshot {
        let session = activeSession
        return WatchRosterSnapshot(modeRaw: mode.rawValue,
                                   teamName: watchTeamLabel,
                                   noun: mode.noun,
                                   nounPlural: mode.nounPlural,
                                   groups: watchGroups.map { group in
            WatchGroupSnapshot(id: group.id,
                               name: group.name,
                               number: group.number,
                               kindRaw: group.kindRaw,
                               counts: countsFor(group: group, in: session?.attempts ?? []),
                               outcomes: Outcome.allCases.map { outcome in
                WatchOutcomeSnapshot(rawValue: outcome.rawValue,
                                     label: outcome.label(group.kind),
                                     shortLabel: outcome.short(group.kind))
            })
        },
                                   selectedGroupID: watchGroups.first {
                                       $0.id.uuidString == padSelectedGroupID
                                   }?.id ?? watchGroups.first?.id,
                                   activeSessionReps: session?.attempts.count ?? 0,
                                   isPracticeLive: session != nil,
                                   generatedAt: .now)
    }

    private func configureWatchLogging() {
        WatchSessionBridge.shared.configure(snapshotProvider: { watchSnapshot },
                                            logHandler: handleWatchLog(_:))
    }

    private func syncWatchLogging() {
        WatchSessionBridge.shared.publishSnapshot(watchSnapshot)
    }

    private func handleWatchLog(_ request: WatchLogRequest) -> WatchRosterSnapshot? {
        guard let group = watchGroups.first(where: { $0.id == request.groupID }),
              let outcome = Outcome(rawValue: request.outcomeRaw) else {
            return nil
        }

        let session: PracticeSession
        if let live = activeSession {
            session = live
        } else {
            session = PracticeSession(startedAt: request.timestamp)
            context.insert(session)
        }

        context.insert(Attempt(outcome: outcome,
                               group: group,
                               session: session,
                               timestamp: request.timestamp))
        try? context.save()
        return watchSnapshot
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for attempt in attempts where attempt.group === group {
            guard let outcome = Outcome(rawValue: attempt.outcomeRaw) else { continue }
            counts[outcome.rawValue] += 1
        }
        return counts
    }

    /// `StuntGroup.id`/`Team.id` arrived after stores already had rows, and
    /// SwiftData backfills a `UUID()` default by evaluating it ONCE for the
    /// whole migration — every pre-existing group woke up sharing one id.
    /// Duplicate ids collapse any `ForEach` keyed on them: the practice grid
    /// rendered the first group on every row, so tapping one cell visibly
    /// logged/staged "for everybody". Reassign fresh ids to duplicates once;
    /// runs before the team-pinning migration in case a team id changes.
    private func dedupeSyncIDs() {
        var seen = Set<UUID>()
        var dirty = false
        for t in teams where !seen.insert(t.id).inserted {
            t.id = UUID()
            dirty = true
        }
        seen.removeAll()
        for g in groups where !seen.insert(g.id).inserted {
            g.id = UUID()
            dirty = true
        }
        if dirty { try? context.save() }
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
            if let first = teams.active.first {
                home = first
            } else {
                let name = teamName.isEmpty ? "My Team" : teamName
                home = Team(name: name, orderIndex: 0)
                context.insert(home)
            }
            for g in orphanGroups { g.team = home }
            dirty = true
        }

        // Pin the active team if it's unset or points at a trashed/deleted team.
        if teams.current(id: currentTeamID) == nil, let first = teams.active.first {
            currentTeamID = first.id.uuidString
        } else if currentTeamID.isEmpty, let home = orphanGroups.first?.team {
            currentTeamID = home.id.uuidString
        }

        if dirty { try? context.save() }
    }

    /// NEVER auto-delete reps on launch. (This used to hard-delete every
    /// group-less attempt, which silently destroyed data — a 1,738-rep wipe was
    /// traced to it.) Orphaned attempts are already invisible to stats (those
    /// filter by group membership), so leaving them is harmless; nothing is
    /// destroyed without an explicit user "Delete permanently" from the Trash.
    /// With soft-delete, skills are no longer hard-deleted, so new orphans don't
    /// arise either. Kept as a documented no-op so the call site stays obvious.
    private func sweepOrphanedAttempts() { /* intentionally does nothing */ }

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
