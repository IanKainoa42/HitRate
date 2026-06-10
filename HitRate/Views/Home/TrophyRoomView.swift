import SwiftUI
import SwiftData

/// The trophy room — a display case for everything earned: the season league
/// standing, every weekly cup banked, and the milestone cards unlocked at
/// practice. Training-floor register (the room is part of the app); the
/// milestone cards bring their own court-at-night chrome as objects on the
/// shelf. Opened from the Home header, read-only — sharing stays on the
/// Stunt Cards sheet.
struct TrophyRoomView: View {
    let sessions: [PracticeSession]
    let groups: [StuntGroup]
    let mode: AppMode
    let orgName: String

    @Environment(\.dismiss) private var dismiss

    private var earned: [Milestone] {
        Milestones.evaluate(sessions: sessions, groups: groups, mode: mode).filter(\.earned)
    }
    private var league: [SeasonRank] {
        WeeklyLeague.compute(sessions: sessions, groups: groups).league
    }
    private var cups: [WeeklyCup] {
        WeeklyLeague.cupHistory(sessions: sessions, groups: groups)
    }

    private var isEmpty: Bool { earned.isEmpty && cups.isEmpty && league.isEmpty }

    var body: some View {
        VStack(spacing: 9) {
            header
            ScrollView {
                VStack(spacing: 9) {
                    if isEmpty {
                        emptyState
                    } else {
                        if !league.isEmpty { seasonSection }
                        if !cups.isEmpty { cupsSection }
                        if !earned.isEmpty { accoladesSection }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(FloorBackdrop().ignoresSafeArea())
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Text("TROPHY ROOM")
                        .font(.system(size: 15, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.label)
                }
                Text("\(seasonString()) season".uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    // MARK: Season league

    private var seasonSection: some View {
        FeedCard {
            CardHead("SEASON LEAGUE") {
                if let leader = league.first {
                    Text("Leader · \(leader.name)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(league.enumerated()), id: \.element.id) { i, r in
                    LeagueRow(rank: r)
                    if i < league.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            Text("Win 5 · 2nd 3 · 3rd 2 · qualifying 1 — points bank when each week ends.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label3)
                .padding(.top, 12)
        }
    }

    // MARK: Cups shelf

    private var cupsSection: some View {
        FeedCard {
            CardHead("CUPS WON") {
                Text("\(cups.count)")
                    .font(Theme.barlow(15, .extrabold))
                    .foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(cups) { cup in
                    CupTile(cup: cup)
                }
            }
        }
    }

    // MARK: Accolades (earned milestone cards)

    private var accoladesSection: some View {
        FeedCard {
            CardHead("ACCOLADES") {
                Text("\(earned.count)")
                    .font(Theme.barlow(15, .extrabold))
                    .foregroundStyle(Theme.accent)
            }
            let scale: CGFloat = 0.62
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(earned.enumerated()), id: \.element.id) { i, m in
                        HoloCardView(card: DeckCard(id: i, content: .milestone(m)),
                                     index: i, count: earned.count,
                                     orgName: orgName, isSnapshot: true)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: 290 * scale, height: 430 * scale)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }
            Text("Share any card from the Share button on Home.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label3)
                .padding(.top, 4)
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        FeedCard {
            VStack(spacing: 14) {
                Image(systemName: "trophy")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.label3)
                Text("Your trophy room is empty")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("Win a weekly cup or unlock a milestone at practice — your cups, league standing, and accolade cards collect here.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
        .padding(.top, 40)
    }
}

// MARK: - Cup tile

private struct CupTile: View {
    let cup: WeeklyCup

    var body: some View {
        let color = Theme.groupColor(cup.colorIndex)
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: cup.game.icon)
                        .font(.system(size: 8, weight: .bold))
                    Text(cup.game.name)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.label2)
                Text(cup.winnerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Text("\(cup.week.weekLabel) · \(cup.scoreDisplay)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.label3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }
}
