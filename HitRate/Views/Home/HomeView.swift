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
    @State private var groupView = "Ranked"
    @State private var shareOpen = false
    @State private var editorOpen = false
    @State private var logSession: PracticeSession?   // non-nil = counter cover up
    @State private var hapticTrigger = 0

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

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

    var body: some View {
        let d = stats
        VStack(spacing: 0) {
            header

            // Timeframe — the global filter; every number below scales to it.
            Picker("Timeframe", selection: $timeframe) {
                ForEach(Timeframe.allCases) { tf in
                    Text(tf.label).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 12) {
                    if d.hasData {
                        SummaryCard(stats: d)
                        TrendCard(stats: d)
                        GroupsCard(stats: d, view: $groupView)
                        TakeawaysCard(stats: d)
                        if d.latest != nil {
                            SessionTapeCard(snapshot: d.latest!, kind: d.aggregateKind)
                        }
                        actionRow(d)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .bottom) { practicePill }
        }
        .background(CourtBackdrop(twinkle: true).ignoresSafeArea())
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

    // MARK: Practice pill (the only way into the counter — no tab bar)

    private var practicePill: some View {
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
            HStack(spacing: 8) {
                if let live = activeSession {
                    Circle()
                        .fill(Theme.hit)
                        .frame(width: 7, height: 7)
                    Text("Resume practice · \(live.attempts.count) rep\(live.attempts.count == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .bold))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start practice")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Theme.accent)
            .clipShape(Capsule())
            .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    /// "End" on a rep-less session leaves it live (deleting a model the cover
    /// is still rendering crashes mid-dismiss) — finish the delete here.
    private func sweepEmptyLiveSessions() {
        let empties = sessions.filter { $0.isActive && $0.attempts.isEmpty }
        guard !empties.isEmpty else { return }
        for s in empties { context.delete(s) }
        try? context.save()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            // Identity crest (team in coach mode, the athlete in athlete mode)
            Text(initials(of: displayTitle, max: 2))
                .font(Theme.grotesk(15))
                .tracking(0.3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [Theme.coral, Theme.coralLight],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Theme.coral.opacity(0.4), radius: 7, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayKicker.uppercased())
                    .font(Theme.grotesk(9))
                    .tracking(1.26)
                    .foregroundStyle(Theme.label2)
                Text(displayTitle)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.44)
                    .foregroundStyle(Theme.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Skills/groups editor — with the Log tab gone, this is the only
            // path to roster + settings outside a live practice.
            Button {
                editorOpen = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 36, height: 36)
                    .background(Theme.fill)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                shareOpen = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.fill)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!stats.hasData)
            .opacity(stats.hasData ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    // MARK: Action row

    private func actionRow(_ d: FloorStats) -> some View {
        HStack(spacing: 8) {
            Button {
                shareOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Create share cards")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let csv = CSVExportItem(sessions: sessions)
            if csv.hasData {
                ShareLink(item: csv, preview: SharePreview("HitRate practice data")) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 15, weight: .semibold))
                        Text("CSV")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Theme.label)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 16)
                    .background(Theme.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
