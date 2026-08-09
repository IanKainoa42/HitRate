import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

@main
struct HitRateApp: App {
    let container: ModelContainer

    init() {
        FirebaseApp.configure()
        if CommandLine.arguments.contains("--run-e2e-tests") {
            QuickClinicTests.runAndExit()
        }
        do {
            let schema = Schema([Team.self, StuntGroup.self, PracticeSession.self, Attempt.self, PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self, CustomTally.self, Subject.self, OutcomeTemplate.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Log the error for debugging
            print("❌ Failed to create model container: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // Attempt in-memory fallback for development
            do {
                let schema = Schema([Team.self, StuntGroup.self, PracticeSession.self, Attempt.self, PendingCloudDeletion.self, UnlockedMilestone.self, CustomOutcome.self, CustomTally.self, Subject.self, OutcomeTemplate.self])
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
                // URL handling lives in RootView — it has to route `hitrate://join`
                // into the join sheet, and two `onOpenURL` handlers on one
                // hierarchy is not a delivery order worth relying on.
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var groups: [StuntGroup]
    @Query private var sessions: [PracticeSession]
    @Query private var allSubjects: [Subject]
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage("teamName") private var teamName = ""
    @AppStorage("replayingIntro") private var replayingIntro = false
    // The pad's pulled-up skill (written by LogView/CaptureView) — forwarded to
    // the watch so the wrist mirrors whatever the phone has up.
    @AppStorage("selectedGroupID") private var padSelectedGroupID = ""
    // CaptureView's pivot state. The watch is skill-only (it logs against a
    // group), so when the phone has a SUBJECT pinned we attribute the wrist tap
    // to that subject; when a SKILL is pinned there's no single subject on the
    // phone, so watch reps stay skill-level (subject nil — still a valid tally).
    @AppStorage("capturePivot") private var capturePivot = "skill"
    @AppStorage("selectedSubjectID") private var padSelectedSubjectID = ""

    /// Which folder's dashboard is open. Nil → the folder-list home (the launch
    /// root). Deliberately @State, not persisted: every cold launch lands on the
    /// folder list, per the "open straight to folders" design.
    @State private var openFolderID: String?

    /// A join code that arrived from a scanned QR / tapped invite link
    /// (`hitrate://join?code=…`). Non-nil presents the join sheet, prefilled.
    @State private var pendingJoinCode: String?

    // Cloud sync (Firebase). Anonymous-FIRST: the app never blocks on a login —
    // a wrist-free anonymous session is created on launch so everything works
    // offline, and the user can later UPGRADE to Apple/Google (claiming the same
    // account) from settings. Sync runs whenever there's any signed-in user.
    @StateObject private var auth = AuthViewModel()
    @StateObject private var sync = SyncEngine.shared
    @StateObject private var minBuild = MinBuildGate.shared

    var body: some View {
        Group {
            // A remotely-retired build stops here: no sync, no logging. Fails
            // open — see MinBuildGate.
            if minBuild.isBlocked {
                UpdateRequiredView()
            } else if didOnboard {
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
            minBuild.evaluate()
            guard !minBuild.isBlocked else { return }
            CardCatalogRenderer.runIfRequested()
            dedupeSyncIDs()
            migrateExistingInstallIfNeeded()
            migrateGroupsIntoDefaultTeam()
            sweepOrphanedAttempts()
            endStaleSessions()
            configureWatchLogging()
            // Anonymous-first: guarantee a signed-in session so cloud sync has a
            // uid to own/join teams, without ever blocking the UI on a login.
            sync.setActiveTeamID(openFolderID)
            auth.signInAnonymouslyIfNeeded()
            if auth.uid != nil { sync.startSyncing(context: context) }
        }
        .onChange(of: openFolderID) { _, teamID in
            sync.setActiveTeamID(teamID)
        }
        // Home can create/switch folders without returning to FolderListView.
        // Keep the navigation identity and the high-volume history listeners
        // pointed at the same folder in that path too.
        .onChange(of: currentTeamID) { _, teamID in
            guard openFolderID != nil, !teamID.isEmpty else { return }
            openFolderID = teamID
        }
        .onChange(of: auth.uid) { _, uid in
            if uid != nil, !minBuild.isBlocked { sync.startSyncing(context: context) }
            else { sync.stopSyncing() }
        }
        // A build retired while the app sat backgrounded stops writing as soon
        // as it comes forward, without waiting for a cold launch.
        .onChange(of: minBuild.isBlocked) { _, blocked in
            if blocked { sync.stopSyncing() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                minBuild.evaluate()
                guard !minBuild.isBlocked else { return }
                endStaleSessions()
                syncWatchLogging()
            }
        }
        .environmentObject(auth)
        // Our own scheme first (`hitrate://join?code=…` — the shared-folder QR);
        // anything else is the Google Sign-In callback coming home.
        .onOpenURL { url in
            if let code = DeepLink.joinCode(from: url) {
                // Clear first, then set on the next runloop pass. Assigning the
                // same value is not a change, so a set-once assignment would
                // never re-present the sheet — and it can genuinely fail to
                // present the first time (SwiftUI won't stack a `.sheet` under a
                // `fullScreenCover`, so a link arriving mid-practice is
                // swallowed). This way the next scan always re-fires.
                pendingJoinCode = nil
                DispatchQueue.main.async { pendingJoinCode = code }
            } else {
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingJoinCode != nil },
            set: { if !$0 { pendingJoinCode = nil } })) {
            JoinFolderSheet(prefilledCode: pendingJoinCode ?? "")
                .presentationDetents([.height(300)])
                .presentationBackground(Theme.appBGBottom)
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
                                     label: outcome.label(for: group),
                                     shortLabel: outcome.short(for: group))
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

        let attempt = Attempt(outcome: outcome,
                              group: group,
                              session: session,
                              subject: watchLogSubject,
                              timestamp: request.timestamp)
        // The wrist is this phone's user logging — stamp the attribution now so
        // co-logged folders read right before anything syncs (same rule as
        // CaptureView's commit).
        attempt.loggerID = auth.uid ?? ""
        context.insert(attempt)
        try? context.save()
        return watchSnapshot
    }

    /// Subject to credit a wrist-logged rep to. The watch only knows the skill
    /// (its `groupID`); the phone owns pivot state, so a wrist tap during "just
    /// Maya today" (subject pinned) credits Maya, while skill-pivot mode leaves
    /// the rep skill-level (nil). Falls back to nil if the pin doesn't resolve.
    private var watchLogSubject: Subject? {
        guard capturePivot == "subject", !padSelectedSubjectID.isEmpty else { return nil }
        return allSubjects.inTeam(currentTeam).first { $0.id.uuidString == padSelectedSubjectID }
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for attempt in attempts where attempt.group === group {
            counts[attempt.tierOutcome.rawValue] += 1   // tier-bucketed → crash-safe for N outcomes
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
    ///
    /// Root cause of "tap Maya's folder, see Lucy's data": this reassigned a
    /// duplicate team's id without ever checking whether `currentTeamID`
    /// pointed at it. `currentTeamID` then named a team that no longer
    /// existed, and `current(id:)` silently fell back to `live.first` —
    /// whichever folder sorts first, shown as if it were the tapped one.
    private func dedupeSyncIDs() {
        var seen = Set<UUID>()
        var dirty = false
        for t in teams where !seen.insert(t.id).inserted {
            let oldID = t.id.uuidString
            t.id = UUID()
            dirty = true
            if currentTeamID == oldID { currentTeamID = t.id.uuidString }
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
