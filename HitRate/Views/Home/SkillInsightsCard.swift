import SwiftUI

/// "SKILL REPORT" — highlights, lowlights, and where to improve, ranked across
/// the skills in view (so it re-reads per kind filter). Centers CLEAN hits
/// (no bobble), per Ian: best / worst / cleanest / most consistent.
///
/// De-duped: each skill claims at most one row (best framing wins), so one
/// dominant skill doesn't fill every line.
struct SkillInsightsCard: View {
    let stats: FloorStats

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let text: Text
        let skillID: PersistentIdentifierBox
    }

    private var rows: [Row] {
        var out: [Row] = []
        var claimed = Set<PersistentIdentifierBox>()

        func add(_ skill: GroupStat?, icon: String, color: Color, _ make: (GroupStat) -> Text) {
            guard let s = skill, !claimed.contains(s.id) else { return }
            claimed.insert(s.id)
            out.append(Row(icon: icon, color: color, text: make(s), skillID: s.id))
        }

        // Best — the show-off skill.
        add(stats.bestSkill, icon: "star.fill", color: Theme.accent) {
            Text("\(bold($0.name)) is your best — \(bold("\($0.rate)%")) clean \(nounPlural).")
        }
        // Worst — where the reps should go.
        add(stats.worstSkill, icon: "arrow.up.forward", color: Theme.majorFall) {
            Text("\(bold($0.name)) needs the reps — \(bold("\($0.rate)%")) clean. Improve here.")
        }
        // Cleanest — when it stays up, it's clean.
        add(stats.cleanestSkill, icon: "sparkles", color: Theme.bobble) {
            Text("\(bold($0.name)) is cleanest — \(bold("\(pct($0.purity))%")) of stand-ups with no bobble.")
        }
        // Most consistent — rarely hits the mat.
        add(stats.mostConsistentSkill, icon: "shield.fill", color: Theme.groupColor(0)) {
            Text("\(bold($0.name)) is most consistent — stays up \(bold("\(pct($0.upRate))%")) of reps.")
        }
        return out
    }

    var body: some View {
        FeedCard {
            CardHead("SKILL REPORT") {
                Text("min \(FloorStats.insightMinReps) reps")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.label3)
            }
            let r = rows
            if r.isEmpty {
                Text("Log a few more reps on each \(mode.noun) — the report ranks skills once they hit \(FloorStats.insightMinReps).")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(r.enumerated()), id: \.element.id) { i, row in
                        InsightRow(icon: row.icon, color: row.color, divider: i < r.count - 1) {
                            row.text
                        }
                    }
                }
            }
        }
    }

    /// Plural outcome noun — "passes"/"hits" (NOT "pass" + "s" → "passs").
    private var nounPlural: String { stats.aggregateKind == .tumbling ? "passes" : "hits" }
    private func bold(_ s: String) -> Text { Text(s).fontWeight(.bold) }
    private func pct(_ d: Double) -> Int { Int((d * 100).rounded()) }
}
