import SwiftUI

/// "WEEKLY CUP" — the built-in weekly game. Crowns the skill/group with the
/// best clean-hit rate this week, ranks the field beneath it, and names the
/// title to defend. Lives in the training-floor register: inset well, chalk
/// text, Barlow numerals, group identity for the badge — no foil, no glow.
struct WeeklyTournamentCard: View {
    let tournament: WeeklyTournament

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// "SKILL OF THE WEEK" / "GROUP OF THE WEEK".
    private var crownLabel: String { "\(mode.nounTitle.uppercased()) OF THE WEEK" }

    var body: some View {
        FeedCard {
            CardHead("WEEKLY CUP") {
                Text(tournament.week.weekLabel)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.label3)
            }

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

            footer
        }
    }

    // MARK: Top banner (champion or front-runner)

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
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(s.rate)")
                        .font(Theme.barlow(34, .extrabold))
                        .monospacedDigit()
                    Text("%")
                        .font(Theme.barlow(17, .bold))
                }
                .foregroundStyle(Theme.rateColor(s.rate))
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
            // A hairline of the champion's color along the leading edge — identity
            // without glow.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(crowned ? 0.5 : 0.25), lineWidth: 1)
        )
        .padding(.bottom, tournament.standings.count > 1 ? 12 : 0)
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

    // MARK: The rest of the field

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
                    StandingRow(standing: s, minReps: tournament.minReps, nounTitle: mode.nounTitle)
                    if i < rest.count - 1 {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Empty / open state

    private var openPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 26))
                .foregroundStyle(Theme.label3)
            Text("The cup is open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
            Text("Log reps this week — the \(mode.noun) with the best hit rate (min \(tournament.minReps) reps) takes the crown.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: Footer (defending title + qualify note)

    @ViewBuilder
    private var footer: some View {
        let parts = footerLine
        if !parts.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.label3)
                Text(parts)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        }
    }

    private var footerLine: String {
        guard let d = tournament.defending else { return "" }
        return "Defending champ: \(d.name) · \(d.rate)% last week"
    }
}

// MARK: - Standings row

/// One line beneath the banner. Qualified entrants carry a rank; provisional
/// entrants are dimmed and show how many reps they still owe.
private struct StandingRow: View {
    let standing: WeeklyStanding
    let minReps: Int
    let nounTitle: String

    var body: some View {
        HStack(spacing: 10) {
            // Rank for qualified racers; a dash for those still chasing the minimum.
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
                Text("\(standing.rate)")
                    .font(Theme.barlow(19, .extrabold))
                    .monospacedDigit()
                Text("%")
                    .font(Theme.barlow(12, .bold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.rateColor(standing.rate, hasData: standing.total > 0))
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .opacity(standing.qualified ? 1 : 0.55)
    }
}
