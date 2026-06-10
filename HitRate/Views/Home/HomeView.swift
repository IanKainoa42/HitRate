import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [PracticeSession]
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("teamName") private var teamName = ""

    @State private var timeframe: Timeframe = .today
    @State private var shareOpen = false
    @State private var editorOpen = false
    @State private var logSession: PracticeSession?   // non-nil = counter cover up
    @State private var hapticTrigger = 0

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// The stunt/tumbling split only makes sense in athlete mode once BOTH
    /// kinds have logged reps (coach is all-stunt; a single-kind athlete has
    /// nothing to split). When true, the dashboard stacks an OVERALL section
    /// over a STUNT section over a TUMBLING section — not a one-at-a-time tab.
    private var showsKindSplit: Bool {
        guard mode == .athlete else { return false }
        let kinds = Set(groups.filter { !$0.attempts.isEmpty }.map(\.kind))
        return kinds.contains(.stunt) && kinds.contains(.tumbling)
    }

    /// A dashboard scoped to one skill kind — same numbers, confined to the
    /// stunt-only (or tumbling-only) groups.
    private func kindStats(_ kind: SkillKind) -> FloorStats {
        StatsEngine.compute(sessions: sessions,
                            groups: groups.filter { $0.kind == kind },
                            timeframe: timeframe)
    }

    /// A live session survives the app being killed mid-practice — the pill
    /// becomes "Resume" and reopens it instead of creating a duplicate.
    private var activeSession: PracticeSession? {
        sessions.filter(\.isActive).max { $0.startedAt < $1.startedAt }
    }

    /// Header + share-card identity per mode.
    private var displayTitle: String {
        mode == .athlete
            ? (athleteName.isEmpty ? "Me" : athleteName)
            : (teamName.isEmpty ? "My Team" : teamName)
    }

    private var displayKicker: String {
        mode == .athlete
            ? "\(seasonString()) season"
            : (orgName.isEmpty ? "My program" : orgName)
    }

    private var stats: FloorStats {
        StatsEngine.compute(sessions: sessions, groups: groups, timeframe: timeframe)
    }

    /// The weekly cup — always "this week", whatever the dashboard timeframe is.
    private var tournament: WeeklyTournament {
        WeeklyLeague.compute(sessions: sessions, groups: groups)
    }

    /// True once any rep has ever been logged — distinguishes a brand-new app
    /// (show the big empty state) from a timeframe that just happens to be quiet.
    private var lifetimeHasData: Bool {
        sessions.contains { !$0.attempts.isEmpty }
    }

    var body: some View {
        let d = stats
        let cup = tournament
        VStack(spacing: 9) {
            header

            // Timeframe — the global filter; every number below scales to it.
            timeframeTabs

            ScrollView {
                VStack(spacing: 9) {
                    // The weekly game sits at the top, above the timeframe-scoped
                    // dashboard — it's its own always-this-week competition.
                    if cup.isLive {
                        WeeklyTournamentCard(tournament: cup)
                    }

                    if d.hasData {
                        if showsKindSplit {
                            // Overall first, then a stunt-only and tumbling-only
                            // section stacked beneath it (not a one-at-a-time tab).
                            sectionHeader("OVERALL", icon: "square.grid.2x2.fill", reps: d.total)
                            dashboardCards(d)

                            let st = kindStats(.stunt)
                            sectionHeader("STUNT", icon: SkillKind.stunt.icon, reps: st.total)
                            dashboardCards(st)

                            let tu = kindStats(.tumbling)
                            sectionHeader("TUMBLING", icon: SkillKind.tumbling.icon, reps: tu.total)
                            dashboardCards(tu)
                        } else {
                            dashboardCards(d)
                        }

                        // Latest-session recap + actions sit once at the bottom,
                        // below every section.
                        if d.latest != nil {
                            SessionTapeCard(snapshot: d.latest!, kind: d.aggregateKind)
                        }
                        actionRow(d)
                    } else if lifetimeHasData || cup.isLive {
                        // Reps exist (this week's cup, or another timeframe) — the
                        // current timeframe is just quiet. Don't show the big
                        // first-launch empty state under a live dashboard.
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
            .safeAreaInset(edge: .bottom) { practiceCTA }
        }
        .background(FloorBackdrop().ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
        .fullScreenCover(isPresented: $shareOpen) {
            // Milestones are lifetime — deliberately not filtered by timeframe.
            ShareCardsSheet(stats: stats,
                            milestones: Milestones.evaluate(sessions: sessions,
                                                            groups: groups, mode: mode),
                            teamName: displayTitle,
                            orgName: mode == .athlete ? displayTitle : displayKicker,
                            mode: mode)
        }
        .fullScreenCover(item: $logSession, onDismiss: sweepEmptyLiveSessions) { s in
            LogView(session: s)
        }
        .sheet(isPresented: $editorOpen) {
            GroupsEditorView()
        }
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
            }
            hapticTrigger += 1
            logSession = s
        } label: {
            Text(activeSession.map {
                    "RESUME PRACTICE · \($0.attempts.count) REP\($0.attempts.count == 1 ? "" : "S")"
                 } ?? "START PRACTICE")
                .font(.system(size: 13, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 10, y: 3)
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

    // MARK: Header (identity well)

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                // Wordmark — the green RATE is the one brand moment up here.
                HStack(spacing: 0) {
                    Text("HIT").foregroundStyle(Theme.label)
                    Text("RATE").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 17, weight: .black))
                .tracking(0.5)

                Text("\(displayTitle) · \(displayKicker)".uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Skills/groups editor — with the Log tab gone, this is the only
            // path to roster + settings outside a live practice.
            Button {
                editorOpen = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                shareOpen = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    // MARK: Stacked sections (overall / stunt / tumbling)

    /// One dashboard's worth of cards for a given kind scope. Sits empty-aware:
    /// in a split, a kind may have no reps in the current timeframe even though
    /// it has lifetime data.
    @ViewBuilder
    private func dashboardCards(_ d: FloorStats) -> some View {
        if d.hasData {
            SummaryCard(stats: d)
            TrendCard(stats: d)
            GroupsCard(stats: d)
            SkillInsightsCard(stats: d)
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

                // Demo data mirrors the handoff's coach dataset — coach mode only.
                if mode == .coach {
                    Button {
                        DemoData.seed(context: context)
                    } label: {
                        Text("Load demo data")
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .padding(.top, 40)
    }
}
