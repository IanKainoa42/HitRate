import SwiftUI

/// "WEEKLY GAME" — the built-in rotating competition. Each week one of three
/// games is live (RATE CUP / GRIND CUP / STREAK CUP); the card crowns the
/// week's champion, ranks the field, and flips (Week ⇄ Season) to the season
/// league — the local ranking the games build, scored by weekly placements.
/// Lives in the training-floor register: inset well, chalk text, Barlow
/// numerals, group identity for the badge — no foil, no glow.
struct WeeklyTournamentCard: View {
    let tournament: WeeklyTournament
    // Toggle lives in the card, same as GroupsCard's Ranked⇄Grid.
    @State private var view = "Week"

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// "SKILL OF THE WEEK" / "GROUP OF THE WEEK".
    private var crownLabel: String { "\(mode.nounTitle.uppercased()) OF THE WEEK" }

    var body: some View {
        FeedCard {
            CardHead(view == "Week" ? "WEEKLY GAME · \(tournament.game.name)" : "SEASON LEAGUE") {
                MiniSeg(options: ["Week", "Season"], selection: $view)
            }

            if view == "Week" {
                rulesLine

                if let champ = tournament.champion {
                    topBanner(champ, kicker: crownLabel, icon: "trophy.fill", crowned: true)
                    others(excluding: champ)
                } else if let runner = tournament.frontRunner {
                    topBanner(runner, kicker: "FRONT-RUNNER", icon: "flag.checkered", crowned: false)
                    runnerNote(runner)
                    others(excluding: runner)
                } else {
                    openPrompt
                }

                weekFooter
            } else {
                leagueTable
            }
        }
    }

    // MARK: Week — rules line

    private var rulesLine: some View {
        HStack(spacing: 5) {
            Image(systemName: tournament.game.icon)
                .font(.system(size: 9, weight: .bold))
            Text(tournament.game.rules)
                .font(.system(size: 10.5, weight: .semibold))
            Spacer()
            Text(tournament.week.weekLabel)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(Theme.label3)
        .padding(.bottom, 10)
    }

    // MARK: Week — top banner (champion or front-runner)

    private func topBanner(_ s: WeeklyStanding, kicker: String, icon: String, crowned: Bool) -> some View {
        let color = Theme.groupColor(s.colorIndex)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(crowned ? Theme.accent : Theme.label2)
                Text(s.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Text("\(mode.nounTitle) \(s.number) · \(s.total) rep\(s.total == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                bigScore(s)
                if let delta = s.delta {
                    DeltaLabel(delta: delta, font: .system(size: 10, weight: .bold, design: .monospaced), iconSize: 10)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface2)
        )
        .overlay(
            // A hairline of the champion's color along the edge — identity
            // without glow.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(crowned ? 0.5 : 0.25), lineWidth: 1)
        )
        .padding(.bottom, tournament.standings.count > 1 ? 12 : 0)
    }

    /// The banner's big number in the live game's language — % gets the rate
    /// bands, reps/streak stay chalk with a small unit cap.
    private func bigScore(_ s: WeeklyStanding) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text("\(s.score)")
                .font(Theme.barlow(34, .extrabold))
                .monospacedDigit()
            if tournament.game == .rate {
                Text("%").font(Theme.barlow(17, .bold))
            } else {
                Text(tournament.game.unit)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
            }
        }
        .foregroundStyle(tournament.game.scoreUsesRateBands
                         ? Theme.rateColor(s.score) : Theme.label)
    }

    /// Nudge under the front-runner: how many reps to lock the crown.
    private func runnerNote(_ s: WeeklyStanding) -> some View {
        let need = s.repsToQualify(min: tournament.minReps)
        return Text("\(need) more rep\(need == 1 ? "" : "s") to lock the crown — \(tournament.minReps) reps qualifies.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.label2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, tournament.standings.count > 1 ? 12 : 0)
    }

    // MARK: Week — the rest of the field

    @ViewBuilder
    private func others(excluding top: WeeklyStanding) -> some View {
        let rest = tournament.standings.filter { $0.id != top.id }
        if !rest.isEmpty {
            Text("STANDINGS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(rest.enumerated()), id: \.element.id) { i, s in
                    StandingRow(standing: s, game: tournament.game,
                                minReps: tournament.minReps)
                    if i < rest.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Week — empty / open state

    private var openPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 26))
                .foregroundStyle(Theme.label3)
            Text("The \(tournament.game.name) is open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
            Text("Log reps this week to enter — \(tournament.game.rules.lowercased()).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: Week — footer (defending title + next game)

    private var weekFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let d = tournament.defending {
                footRow(icon: "shield.fill",
                        text: "Defending champ: \(d.name) · \(d.scoreDisplay) in last week's \(d.game.name)")
            }
            footRow(icon: "arrow.triangle.2.circlepath",
                    text: "Next week: \(tournament.game.next.name)")
        }
        .padding(.top, 12)
    }

    private func footRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.label3)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.label2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Season — league table

    @ViewBuilder
    private var leagueTable: some View {
        if tournament.league.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "list.number")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.label3)
                Text("No weeks scored yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text("Each week's game pays points when it ends — win 5, 2nd 3, 3rd 2, qualifying 1. The table builds from there.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(tournament.league.enumerated()), id: \.element.id) { i, r in
                    LeagueRow(rank: r)
                    if i < tournament.league.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            footRow(icon: "info.circle",
                    text: "Win 5 · 2nd 3 · 3rd 2 · qualifying 1 — this week scores when it ends.")
                .padding(.top, 12)
        }
    }
}

// MARK: - Standings row (week view)

/// One line beneath the banner. Qualified entrants carry a rank; provisional
/// entrants are dimmed and show how many reps they still owe.
private struct StandingRow: View {
    let standing: WeeklyStanding
    let game: WeeklyGame
    let minReps: Int

    var body: some View {
        HStack(spacing: 10) {
            // Rank for qualified racers; a waiting glyph for those still
            // chasing the minimum.
            Group {
                if standing.qualified {
                    Text("\(standing.rank)")
                        .font(Theme.barlow(14, .extrabold))
                        .foregroundStyle(Theme.label3)
                } else {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.label3)
                }
            }
            .frame(width: 18)

            Text("\(standing.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.groupColor(standing.colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(standing.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                if standing.qualified {
                    StackedBar(counts: standing.counts, total: standing.total, height: 7)
                } else {
                    Text("\(standing.repsToQualify(min: minReps)) rep\(standing.repsToQualify(min: minReps) == 1 ? "" : "s") to qualify")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.label3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if standing.qualified, let delta = standing.delta {
                DeltaLabel(delta: delta)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(standing.score)")
                    .font(Theme.barlow(19, .extrabold))
                    .monospacedDigit()
                if game == .rate {
                    Text("%").font(Theme.barlow(12, .bold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)   // "100%" must not wrap in the fixed column
            .foregroundStyle(game.scoreUsesRateBands
                             ? Theme.rateColor(standing.score, hasData: standing.total > 0)
                             : Theme.label)
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .opacity(standing.qualified ? 1 : 0.55)
    }
}

// MARK: - League row (season view)

/// Shared by the card's Season tab and the Trophy Room's season shelf.
struct LeagueRow: View {
    let rank: SeasonRank

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank.rank)")
                .font(Theme.barlow(14, .extrabold))
                .foregroundStyle(rank.rank == 1 ? Theme.accent : Theme.label3)
                .frame(width: 18)

            Text("\(rank.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.groupColor(rank.colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(rank.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if rank.cups > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("×\(rank.cups)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Theme.label2)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(rank.points)")
                    .font(Theme.barlow(19, .extrabold))
                    .monospacedDigit()
                Text("PTS")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
            }
            .foregroundStyle(Theme.label)
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}
