import Foundation

/// What a coach marks on one cell (row × skill) of a FULL-OUT run.
///
/// The full out is the deductions-only logger: every cell starts as an assumed
/// HIT and the coach touches only what went wrong. So there are exactly three
/// things a cell can be.
enum FullOutMark: Hashable {
    /// Untouched — assumed clean. Commits the skill's hit outcome.
    case hit
    /// A deduction, named by outcome (`FullOutPlan.key` of its label) so one
    /// armed mark works across skills whose lists differ; each skill resolves
    /// it to its own slot at commit.
    case deduction(String)
    /// Did not attempt / absent. NOT an attempt: commits NO rep, so it counts
    /// neither for nor against anyone. Deliberately not an outcome on the
    /// skill — an `Attempt` row is "a rep happened" to every consumer (rates,
    /// streaks, cups, milestones, homework, sync, the watch, older builds on a
    /// shared folder), and the only way to keep a non-attempt out of all of
    /// them is to never write one.
    case skipped
}

/// The pure half of the full-out run: which marks exist, which a skill can
/// take, and which reps a marked grid commits. No SwiftData and no views, so
/// the assume-hit arithmetic is unit-testable on plain values
/// (`FullOutPlanTests`).
enum FullOutPlan {

    /// A column: one skill and the outcome list its reps index into.
    struct Skill: Identifiable, Hashable {
        let id: UUID
        let defs: [OutcomeDef]
    }

    /// One grid position. `row` is whoever the rep is attributed to.
    struct Cell: Hashable {
        let row: UUID
        let skill: UUID
    }

    /// An armable deduction — a non-hit outcome at least one column offers.
    struct Deduction: Identifiable, Hashable {
        let key: String
        let label: String
        let colorRaw: String
        let credit: Int

        var id: String { key }
        var short: String { Outcome.deriveShort(label) }
    }

    /// One rep the grid commits: `slot` indexes the skill's outcome list.
    struct Rep: Hashable {
        let row: UUID
        let skill: UUID
        let slot: Int
    }

    struct Resolution: Equatable {
        /// Row-major (row order, then skill order) — the order they're written.
        let reps: [Rep]
        /// Of `reps`, how many are NOT the assumed hit.
        let deductions: Int
        /// Cells that committed nothing: marked `.skipped`, or a cell whose
        /// skill can't express its mark (see `resolve`).
        let skipped: Int

        var hits: Int { reps.count - deductions }
    }

    /// Outcomes match across skills by NAME, case- and edge-space-insensitive.
    static func key(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The slot an assumed hit logs: the skill's first full-credit outcome.
    /// Nil for a list with no 100% outcome — nothing to assume there.
    static func hitSlot(in defs: [OutcomeDef]) -> Int? {
        defs.firstIndex { $0.isHit }
    }

    /// The slot a named deduction logs on this skill, or nil if the skill has
    /// no non-hit outcome by that name.
    static func slot(forDeduction key: String, in defs: [OutcomeDef]) -> Int? {
        defs.firstIndex { !$0.isHit && Self.key($0.label) == key }
    }

    /// Whether a cell on this skill can take the mark. Hit needs a hit
    /// outcome, a deduction needs the skill to have that outcome, and skipped
    /// always applies.
    static func canApply(_ mark: FullOutMark, to skill: Skill) -> Bool {
        switch mark {
        case .hit: hitSlot(in: skill.defs) != nil
        case .deduction(let key): slot(forDeduction: key, in: skill.defs) != nil
        case .skipped: true
        }
    }

    /// Every deduction any column offers — the armed bar. One entry per name
    /// (first-seen label/color/credit wins), ordered good → bad by credit, then
    /// by where it first appears, so the bar reads like the pad does.
    static func deductions(for skills: [Skill]) -> [Deduction] {
        var seen: Set<String> = []
        var out: [Deduction] = []
        for skill in skills {
            for def in skill.defs where !def.isHit {
                let k = key(def.label)
                guard !k.isEmpty, seen.insert(k).inserted else { continue }
                out.append(Deduction(key: k, label: def.label, colorRaw: def.colorRaw, credit: def.credit))
            }
        }
        return out.enumerated()
            .sorted { $0.element.credit != $1.element.credit
                ? $0.element.credit > $1.element.credit : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Turn a marked grid into the reps to write. An unmarked cell is a HIT —
    /// that is the whole feature. A cell commits NOTHING when it is `.skipped`,
    /// and also when its skill cannot express its mark: a skill with no
    /// full-credit outcome is never assumed to have hit, and a deduction the
    /// skill doesn't offer is never quietly rewritten as some other outcome.
    /// Both are counted in `skipped` so the commit button can say so.
    static func resolve(rows: [UUID], skills: [Skill], marks: [Cell: FullOutMark]) -> Resolution {
        var reps: [Rep] = []
        var deductions = 0
        var skipped = 0
        for row in rows {
            for skill in skills {
                switch marks[Cell(row: row, skill: skill.id)] ?? .hit {
                case .skipped:
                    skipped += 1
                case .hit:
                    if let slot = hitSlot(in: skill.defs) {
                        reps.append(Rep(row: row, skill: skill.id, slot: slot))
                    } else {
                        skipped += 1
                    }
                case .deduction(let key):
                    if let slot = slot(forDeduction: key, in: skill.defs) {
                        reps.append(Rep(row: row, skill: skill.id, slot: slot))
                        deductions += 1
                    } else {
                        skipped += 1
                    }
                }
            }
        }
        return Resolution(reps: reps, deductions: deductions, skipped: skipped)
    }
}
