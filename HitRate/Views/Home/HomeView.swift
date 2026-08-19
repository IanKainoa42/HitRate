import SwiftUI
import SwiftData
import os

struct HomeView: View {
    /// Return to the folder-list home. Nil when Home is shown standalone.
    var onExit: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query private var sessions: [PracticeSession]
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Subject.orderIndex) private var allSubjects: [Subject]
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @Query private var unlockedMilestones: [UnlockedMilestone]

    /// Co-logging: needed to tell the folder owner's reps from a member's.
    @EnvironmentObject private var auth: AuthViewModel

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage("hasSeenHomeIconGuide") private var hasSeenHomeIconGuide = false

    @State private var timeframe: Timeframe = .today
    /// Cross-cutting review filters (Phase 4). nil = everyone / all skills.
    @State private var personFilter: Subject?
    @State private var skillFilter: StuntGroup?
    /// Co-logging SOURCE filter — all reps / coach-logged (privates) /
    /// self-logged (open gym). Only offered on a co-logged folder.
    @State private var loggerScope: LoggerFilter.Scope = .all
    @State private var shareOpen = false
    @State private var trophyOpen = false
    @State private var editorOpen = false
    /// Asked at most once per install — a second unprompted ask reads as nagging.
    @AppStorage("askedSaveAccount") private var askedSaveAccount = false
    @State private var savePromptOpen = false
    @State private var watchOpen = false
    @State private var rosterOpen = false
    @State private var addTeamOpen = false
    @State private var newTeamName = ""
    @State private var showIconGuide = false
    @State private var logSession: PracticeSession?   // non-nil = counter cover up
    @State private var hapticTrigger = 0

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// The active team and its roster — every stat below is scoped to it.
    private var currentTeam: Team? { teams.current(id: currentTeamID) }
    private var groups: [StuntGroup] { allGroups.inTeam(currentTeam) }
    private var subjects: [Subject] { allSubjects.inTeam(currentTeam) }

    /// Which axis the person filter runs on — a person (athlete) or a stunt
    /// group (coach), mirroring the capture pivot.
    private var subjectKind: SubjectKind { mode == .coach ? .group : .person }

    /// Filters validated against the current roster (a deleted/other-team pick
    /// falls back to "all"), so a stale @State selection can't dangle.
    private var activePerson: Subject? {
        personFilter.flatMap { sel in
            subjects.contains { $0.persistentModelID == sel.persistentModelID } ? sel : nil
        }
    }
    private var activeSkill: StuntGroup? {
        skillFilter.flatMap { sel in
            groups.contains { $0.persistentModelID == sel.persistentModelID } ? sel : nil
        }
    }
    /// Skill (group) confinement after the skill filter — one skill, or all.
    private var filteredGroups: [StuntGroup] {
        activeSkill.map { [$0] } ?? groups
    }
    private var isFiltered: Bool {
        activePerson != nil || activeSkill != nil || loggerScope != .all
    }

    // MARK: Co-logging source filter

    /// A folder MORE THAN ONE PERSON logs into. Ownership alone isn't the test —
    /// SyncEngine claims an `ownerUID` for every local folder on first sign-in,
    /// so a solo user would otherwise get a filter that can only ever say
    /// "everything" or "nothing".
    private var isCoLogged: Bool {
        guard let team = currentTeam else { return false }
        if !team.memberIds.isEmpty { return true }                       // others joined yours
        if let owner = team.ownerUID, owner != auth.uid { return true }  // you joined theirs
        return false
    }

    /// The live source filter. Inert (`.unfiltered`) on a solo folder so the
    /// dashboard behaves exactly as it did before this existed.
    private var loggerFilter: LoggerFilter {
        guard isCoLogged else { return .unfiltered }
        return LoggerFilter(scope: loggerScope,
                            ownerUID: currentTeam?.ownerUID,
                            currentUID: auth.uid)
    }

    /// The stunt/tumbling split only makes sense in athlete mode once BOTH
    /// kinds have logged reps (coach is all-stunt; a single-kind athlete has
    /// nothing to split). When true, the dashboard stacks an OVERALL section
    /// over a STUNT section over a TUMBLING section — not a one-at-a-time tab.
    private var showsKindSplit: Bool {
        guard mode == .athlete else { return false }
        // A single pinned skill is one kind — no split to show.
        guard activeSkill == nil else { return false }
        let kinds = Set(filteredGroups.filter { !$0.attempts.isEmpty }.map(\.kind))
        return kinds.contains(.stunt) && kinds.contains(.tumbling)
    }

    /// A dashboard scoped to one skill kind — same numbers, confined to the
    /// stunt-only (or tumbling-only) groups, honoring the active person filter.
    private func kindStats(_ kind: SkillKind) -> FloorStats {
        StatsEngine.compute(sessions: sessions,
                            groups: filteredGroups.filter { $0.kind == kind },
                            timeframe: timeframe,
                            subject: activePerson,
                            logger: loggerFilter)
    }

    /// A live session survives the app being killed mid-practice — the pill
    /// becomes "Resume" and reopens it instead of creating a duplicate.
    private var activeSession: PracticeSession? {
        sessions.filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }

    /// The active team's name (the switchable roster).
    private var teamLabel: String {
        currentTeam?.name ?? (mode == .coach ? "My Team" : "My Skills")
    }

    /// The shared identity that rides on every team's cards.
    private var identityLabel: String {
        mode == .athlete
            ? (athleteName.isEmpty ? "Me" : athleteName)
            : (orgName.isEmpty ? "My program" : orgName)
    }

    /// Share/trophy card title. Coach cards carry the squad name; athlete cards
    /// carry the athlete's name (the team only scopes which skills are included).
    /// The crest/org line is always `identityLabel`.
    private var shareTeamName: String { mode == .coach ? teamLabel : identityLabel }

    private var stats: FloorStats {
        StatsEngine.compute(sessions: sessions, groups: filteredGroups,
                            timeframe: timeframe, subject: activePerson,
                            logger: loggerFilter)
    }

    /// Show the review filter bar only when there's something worth slicing:
    /// the team has logged, and there's more than one skill or any subject.
    private var showsFilterBar: Bool {
        lifetimeHasData && (groups.count > 1 || !subjects.isEmpty)
    }

    /// Whether the active team has any buckets to log into yet.
    private var hasRoster: Bool { !groups.isEmpty }

    /// True once this team has logged a rep — distinguishes a team that's never
    /// been practiced (show the big empty state) from a timeframe that's just
    /// quiet. Scoped to the active team's groups.
    private var lifetimeHasData: Bool {
        groups.contains { !$0.attempts.isEmpty }
    }

    var body: some View {
        let d = stats
        VStack(spacing: 9) {
            header

            // Timeframe — the global filter; every number below scales to it.
            timeframeTabs

            // Cross-cutting review filters (person / skill), scaling every number
            // below just like the timeframe does.
            if showsFilterBar { reviewFilterBar }

            // Who logged it — privates vs open gym. Only on a co-logged folder.
            if showsSourceFilter { sourceFilterBar }

            ScrollView {
                VStack(spacing: 9) {
                    // The weekly game + league live in the Trophy Room (header
                    // trophy button), kept separate from the analytics here.
                    if d.hasData {
                        if showsKindSplit {
                            // Overall first, then a stunt-only and tumbling-only
                            // section stacked beneath it (not a one-at-a-time tab).
                            sectionHeader("OVERALL", icon: "square.grid.2x2.fill", reps: d.total)
                            dashboardCards(d, actions: true)

                            let st = kindStats(.stunt)
                            sectionHeader("STUNT", icon: SkillKind.stunt.icon, reps: st.total)
                            dashboardCards(st)

                            let tu = kindStats(.tumbling)
                            sectionHeader("TUMBLING", icon: SkillKind.tumbling.icon, reps: tu.total)
                            dashboardCards(tu)
                        } else {
                            dashboardCards(d, actions: true)
                        }

                        // Latest-session recap sits once at the bottom, below
                        // every section.
                        if d.latest != nil {
                            SessionTapeCard(snapshot: d.latest!, kind: d.aggregateKind)
                        }
                    } else if !hasRoster {
                        // A freshly added team has no buckets yet — guide to the
                        // editor instead of an unusable practice prompt.
                        noRosterState
                    } else if lifetimeHasData {
                        // This team has logged before — the current timeframe is
                        // just quiet. Don't show the big first-launch empty state.
                        FeedCard {
                            Text("No reps logged \(timeframe.label.lowercased()).")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.label2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            // No roster, no practice — the only action is to build one.
            .safeAreaInset(edge: .bottom) { if hasRoster { practiceCTA } }
        }
        .background(FloorBackdrop().ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .fullScreenCover(isPresented: $shareOpen) {
            // Milestones are lifetime — deliberately not filtered by timeframe.
            ShareCardsSheet(stats: stats,
                            milestones: Milestones.evaluate(sessions: sessions,
                                                            groups: groups, mode: mode, unlocked: unlockedMilestones),
                            teamName: shareTeamName,
                            orgName: identityLabel,
                            mode: mode)
        }
        .fullScreenCover(isPresented: $trophyOpen) {
            TrophyRoomView(sessions: sessions, groups: groups, mode: mode,
                           orgName: identityLabel)
        }
        .fullScreenCover(isPresented: $rosterOpen) {
            RosterView(sessions: sessions, groups: groups, subjects: subjects,
                       timeframe: timeframe, subjectKind: subjectKind) { subject in
                personFilter = subject
                rosterOpen = false
            }
        }
        .fullScreenCover(item: $logSession, onDismiss: endOfPractice) { s in
            CaptureView(session: s)
        }
        .sheet(isPresented: $savePromptOpen) {
            SaveAccountPrompt(repCount: loggedRepCount)
                .presentationDetents([.height(430)])
                .presentationBackground(Theme.appBGBottom)
        }
        .sheet(isPresented: $editorOpen) {
            GroupsEditorView()
        }
        .sheet(isPresented: $watchOpen) {
            WatchLoggingSheet(status: WatchSessionBridge.shared.status,
                              groups: groups,
                              activeSessionReps: activeSession?.attempts.count ?? 0,
                              mode: mode)
        }
        .alert("New team", isPresented: $addTeamOpen) {
            TextField(mode == .coach ? "Team name" : "Roster name", text: $newTeamName)
            Button("Add") { addTeam() }
            Button("Cancel", role: .cancel) { newTeamName = "" }
        } message: {
            Text(mode == .coach
                 ? "Track another squad with its own roster and stats."
                 : "Track another team or gym with its own skills and stats.")
        }
        .sheet(isPresented: $showIconGuide) {
            iconGuideSheet
                .presentationDetents([.medium])
                .presentationBackground(Theme.appBGBottom)
        }
        .onAppear {
            syncMilestones()
            if !hasSeenHomeIconGuide { showIconGuide = true }
        }
        .onChange(of: sessions) { _, _ in syncMilestones() }
    }

    // MARK: First-visit icon guide (no tab bar — these icons are the whole nav)

    private var iconGuideSheet: some View {
        VStack(spacing: 18) {
            Text("YOUR DASHBOARD")
                .font(.system(size: 11, weight: .heavy)).tracking(2)
                .foregroundStyle(Theme.label3)
                .padding(.top, 22)

            VStack(alignment: .leading, spacing: 16) {
                iconGuideRow(icon: "slider.horizontal.3", title: "Skills",
                             detail: "Manage what you're tracking and folder settings.")
                iconGuideRow(icon: "applewatch", title: "Watch",
                             detail: "Log reps right from your wrist mid-practice.")
                iconGuideRow(icon: "trophy", title: "Trophy Room",
                             detail: "Cups, streaks, and cards you've earned.")
                if !subjects.isEmpty {
                    iconGuideRow(icon: "person.2",
                                 title: subjectKind == .person ? "Roster" : "Stunt Groups",
                                 detail: "Everyone ranked by hit rate.")
                }
                iconGuideRow(icon: "square.and.arrow.up", title: "Share",
                             detail: "Turn your stats into a card to post or send.")
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            Button {
                hasSeenHomeIconGuide = true
                showIconGuide = false
            } label: {
                Text("Got it")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FloorBackdrop().ignoresSafeArea())
    }

    private func iconGuideRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.iconTile)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label2)
            }
            Spacer(minLength: 0)
        }
    }

    private func syncMilestones() {
        Milestones.sync(sessions: sessions, groups: groups, mode: mode, unlocked: unlockedMilestones, context: context)
    }

    /// Create a team and switch to it. Its roster starts empty — add skills/
    /// groups from the editor.
    private func addTeam() {
        let name = newTeamName.trimmingCharacters(in: .whitespaces)
        let team = Team(name: name.isEmpty ? "Team \(teams.count + 1)" : name,
                        orderIndex: teams.count)
        context.insert(team)
        try? context.save()
        currentTeamID = team.id.uuidString
        newTeamName = ""
    }

    // MARK: Practice CTA (the only way into the counter — no tab bar)

    /// The one RAISED element on the dashboard — everything else is inset.
    private var practiceCTA: some View {
        Button {
            let s: PracticeSession
            if let live = activeSession {
                s = live
            } else {
                s = PracticeSession()
                context.insert(s)
                try? context.save()
                Sounds.shared.play(.start)
                // Wake the Apple Watch app so reps can be logged from the wrist
                // the instant practice begins (no-op without an installed watch).
                PracticeWatchLauncher.launchIfWatchAvailable()
            }
            hapticTrigger += 1
            logSession = s
        } label: {
            HStack(spacing: 9) {
                BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                    .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                Text(activeSession.map {
                        "RESUME PRACTICE · \($0.attempts.count) REP\($0.attempts.count == 1 ? "" : "S")"
                     } ?? "START PRACTICE")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.24), radius: 8, y: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        // Fade the floor in behind the CTA so mid-scroll content doesn't
        // slide visibly through the gaps around the button.
        .background(
            LinearGradient(colors: [Theme.appBGBottom.opacity(0), Theme.appBGBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// "End" on a rep-less session leaves it live (deleting a model the cover
    /// is still rendering crashes mid-dismiss) — finish the delete here.
    private func sweepEmptyLiveSessions() {
        let empties = sessions.filter { $0.isActive && $0.attempts.isEmpty }
        guard !empties.isEmpty else { return }
        for s in empties { context.delete(s) }
        try? context.save()
    }

    private var loggedRepCount: Int { sessions.reduce(0) { $0 + $1.attempts.count } }

    /// Practice just closed. Sweep the empty session first (deleting a model the
    /// cover is still rendering crashes mid-dismiss), then — once, and only once
    /// the user actually has reps to lose — offer to save the account.
    private func endOfPractice() {
        sweepEmptyLiveSessions()
        guard AccountPromptPolicy.offersSaveAfterPractice(isUpgraded: auth.isUpgraded,
                                                          alreadyAsked: askedSaveAccount,
                                                          repCount: loggedRepCount) else { return }
        askedSaveAccount = true
        // Let the cover finish dismissing; presenting a sheet from inside another
        // presentation's onDismiss drops it silently often enough to matter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { savePromptOpen = true }
    }

    // MARK: Header (identity well)

    /// Identity subline: shared name + the active team, tap to switch or add.
    private var sublineText: String {
        mode == .athlete ? "\(identityLabel) · \(teamLabel)"
                         : "\(teamLabel) · \(identityLabel)"
    }

    /// Replaces the old folder dropdown: a clear "Skills" button that opens this
    /// folder's roster/editor. Switching folders happens by exiting to the
    /// folder-list home (the back chevron), not from a header menu.
    private var skillsButton: some View {
        Button { editorOpen = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("SKILLS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.label)
                Text("· \(teamLabel)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Theme.iconTile)
                    .overlay(Capsule().stroke(Theme.iconTileEdge.opacity(0.85), lineWidth: 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Back to the folder list (when Home was opened from it).
            if let onExit {
                Button(action: onExit) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.label2)
                        .frame(width: 34, height: 34)
                        .background(iconButtonBackground)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Wordmark mirrors the app icon: solid HIT, outlined RATE,
                // single green signal dot.
                IconWordmark(size: 17, rateFill: Theme.well, dotSize: 8)

                skillsButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                watchOpen = true
            } label: {
                Image(systemName: "applewatch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(watchStatusColor)
                    .frame(width: 34, height: 34)
                    .background(iconButtonBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Trophy room — cups won, season standing, earned accolade cards.
            Button {
                trophyOpen = true
            } label: {
                Image(systemName: "trophy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 34)
                    .background(iconButtonBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Roster — every athlete/group ranked by clean-hit rate.
            if !subjects.isEmpty {
                Button {
                    rosterOpen = true
                } label: {
                    Image(systemName: "person.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                        .frame(width: 34, height: 34)
                        .background(iconButtonBackground)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                shareOpen = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(iconButtonBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!stats.hasData)
            .opacity(stats.hasData ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private var watchStatusColor: Color {
        switch WatchSessionBridge.shared.status {
        case .ready: Theme.accent
        case .installed: Theme.label
        default: Theme.label2
        }
    }

    private var iconButtonBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.iconTile)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.iconTileEdge.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
    }

    // MARK: Timeframe tabs (well)

    private var timeframeTabs: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases) { tf in
                let on = timeframe == tf
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { timeframe = tf }
                } label: {
                    Text(tf.label.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(on ? Theme.well : Theme.label2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Theme.label : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .wellBackground()
        .padding(.horizontal, 16)
    }

    // MARK: Review filters (person / skill)

    private var everyoneLabel: String { subjectKind == .person ? "Everyone" : "All stunt groups" }

    private var reviewFilterBar: some View {
        HStack(spacing: 6) {
            if !subjects.isEmpty {
                filterChip(title: activePerson?.displayName ?? everyoneLabel,
                           active: activePerson != nil) {
                    Button(everyoneLabel) { personFilter = nil }
                    Divider()
                    ForEach(subjects) { s in
                        Button(s.displayName) { personFilter = s }
                    }
                }
            }
            filterChip(title: activeSkill?.displayName ?? "All skills",
                       active: activeSkill != nil) {
                Button("All skills") { skillFilter = nil }
                Divider()
                ForEach(groups) { g in
                    Button(g.displayName) { skillFilter = g }
                }
            }
            Spacer(minLength: 0)
            if isFiltered {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        personFilter = nil; skillFilter = nil; loggerScope = .all
                    }
                    hapticTrigger += 1
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.label3)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .wellBackground()
        .padding(.horizontal, 16)
    }

    /// Only worth showing once the folder is genuinely co-logged AND has reps to
    /// slice — otherwise it's a control with one possible answer.
    private var showsSourceFilter: Bool { isCoLogged && lifetimeHasData }

    /// Same well/segment treatment as the timeframe tabs — this is the second
    /// global filter, and it should read as a peer of the first, not as a
    /// system segmented control dropped onto the training floor.
    private var sourceFilterBar: some View {
        HStack(spacing: 8) {
            Text("SOURCE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label3)
                .padding(.leading, 5)

            HStack(spacing: 4) {
                ForEach(LoggerFilter.Scope.allCases) { scope in
                    let on = loggerScope == scope
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { loggerScope = scope }
                        hapticTrigger += 1
                    } label: {
                        Text(scope.label)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(on ? Theme.well : Theme.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(on ? Theme.label : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(5)
        .wellBackground()
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rep source")
    }

    @ViewBuilder
    private func filterChip<Content: View>(title: String, active: Bool,
                                           @ViewBuilder menu: () -> Content) -> some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(active ? Theme.well : Theme.label2)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(active ? Theme.label : Theme.iconTile)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(active ? .clear : Theme.iconTileEdge.opacity(0.7), lineWidth: 1))
            .contentShape(Rectangle())
        }
    }

    // MARK: Stacked sections (overall / stunt / tumbling)

    /// One dashboard's worth of cards for a given kind scope. Sits empty-aware:
    /// in a split, a kind may have no reps in the current timeframe even though
    /// it has lifetime data.
    @ViewBuilder
    private func dashboardCards(_ d: FloorStats, actions: Bool = false) -> some View {
        if d.hasData {
            SummaryCard(stats: d)
            // Share/CSV ride directly under the headline number (overall block
            // only) — they were buried below every section at the feed bottom.
            if actions { actionRow(d) }
            TrendCard(stats: d)
            GroupsCard(stats: d)
            SkillInsightsCard(stats: d)
            if d.hasExecution { ExecutionCard(stats: d) }
        } else {
            FeedCard {
                Text("No reps logged \(timeframe.label.lowercased()).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
    }

    /// A floor-level divider that labels each stacked section. Not a well — it
    /// sits ON the floor between the recessed cards.
    private func sectionHeader(_ title: String, icon: String, reps: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.label2)
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.label)
            Text("\(reps) REP\(reps == 1 ? "" : "S")")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.label3)
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
        .padding(.bottom, 1)
    }

    // MARK: Action row

    private func actionRow(_ d: FloorStats) -> some View {
        HStack(spacing: 8) {
            Button {
                shareOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Create share cards")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .wellBackground()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let csv = CSVExportItem(sessions: sessions)
            if csv.hasData {
                ShareLink(item: csv, preview: SharePreview("HitRate practice data")) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                        Text("CSV")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Theme.label)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .wellBackground()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        FeedCard {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.label3)
                Text("No reps logged yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text(mode == .athlete
                     ? "Hit Start practice below and log every rep as it lands. Your dashboard builds itself from there."
                     : "Hit Start practice below and log every outcome as it lands. The floor dashboard builds itself from there.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .padding(.top, 40)
    }

    // MARK: No-roster state (a freshly added team)

    private var noRosterState: some View {
        FeedCard {
            VStack(spacing: 14) {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.label3)
                Text("\(teamLabel) has no \(mode.nounPlural) yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.center)
                Text("Add the \(mode.nounPlural) you'll be counting for this team, then start logging reps.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
                Button {
                    editorOpen = true
                } label: {
                    Text("Add \(mode.nounPlural)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .padding(.top, 40)
    }

}
