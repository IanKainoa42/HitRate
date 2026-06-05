import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [PracticeSession]
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]

    @AppStorage("orgName") private var orgName = "Cheer Force San Diego"
    @AppStorage("teamName") private var teamName = "Senior Coed"

    @State private var timeframe: Timeframe = .today
    @State private var groupView = "Ranked"
    @State private var shareOpen = false

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
                            SessionTapeCard(snapshot: d.latest!)
                        }
                        actionRow(d)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.appBG)
        .fullScreenCover(isPresented: $shareOpen) {
            ShareCardsSheet(stats: stats, teamName: teamName, orgName: orgName)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            // Team crest
            Text(initials(of: teamName, max: 2))
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
                Text(orgName.uppercased())
                    .font(Theme.grotesk(9))
                    .tracking(1.26)
                    .foregroundStyle(Theme.label2)
                Text(teamName)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.44)
                    .foregroundStyle(Theme.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            if let url = CSVExport.write(sessions: sessions) {
                ShareLink(item: url) {
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
                Text("Log stunt outcomes from the Log tab during practice. The floor dashboard builds itself from every rep.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)

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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .padding(.top, 40)
    }
}
