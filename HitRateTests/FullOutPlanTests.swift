import XCTest
@testable import HitRate

/// The full-out run's assume-hit arithmetic, on plain values.
final class FullOutPlanTests: XCTestCase {
    /// Preset lists read off an unsaved skill, so the tests track the real
    /// presets without importing CheerRulesKit into the test target.
    private let stunt = StuntGroup(name: "Stunt", number: 1, orderIndex: 0).outcomeDefs
    private let tumblingPreset = StuntGroup(name: "Pass", number: 2, orderIndex: 1, kind: .tumbling).outcomeDefs

    private func skill(_ defs: [OutcomeDef]) -> FullOutPlan.Skill {
        FullOutPlan.Skill(id: UUID(), defs: defs)
    }

    private func key(_ label: String) -> String { FullOutPlan.key(label) }

    /// The whole feature: touch nothing, everybody hit.
    func testUntouchedGridLogsAHitInEveryCell() {
        let rows = [UUID(), UUID()]
        let skills = [skill(stunt), skill(stunt), skill(stunt)]

        let run = FullOutPlan.resolve(rows: rows, skills: skills, marks: [:])

        XCTAssertEqual(run.reps.count, 6)
        XCTAssertTrue(run.reps.allSatisfy { $0.slot == 0 })
        XCTAssertEqual(run.deductions, 0)
        XCTAssertEqual(run.skipped, 0)
        XCTAssertEqual(run.hits, 6)
        // Row-major: every skill for the first row, then the second.
        XCTAssertEqual(run.reps.map(\.row), [rows[0], rows[0], rows[0], rows[1], rows[1], rows[1]])
        XCTAssertEqual(Array(run.reps.map(\.skill).prefix(3)), skills.map(\.id))
    }

    /// Seven stunt groups, six skills, three deductions, one group out for two
    /// skills: 42 cells -> 40 reps (37 hits, 3 deductions), 2 not counted.
    func testOnlyMarkedCellsDeviateFromAHit() {
        let rows = (0..<7).map { _ in UUID() }
        let skills = (0..<6).map { _ in skill(stunt) }
        var marks: [FullOutPlan.Cell: FullOutMark] = [:]
        marks[.init(row: rows[0], skill: skills[4].id)] = .deduction(key("Bobble"))
        marks[.init(row: rows[2], skill: skills[4].id)] = .deduction(key("Major fall"))
        marks[.init(row: rows[2], skill: skills[5].id)] = .deduction(key("Out of range"))
        marks[.init(row: rows[6], skill: skills[0].id)] = .skipped
        marks[.init(row: rows[6], skill: skills[1].id)] = .skipped

        let run = FullOutPlan.resolve(rows: rows, skills: skills, marks: marks)

        XCTAssertEqual(run.reps.count, 40)
        XCTAssertEqual(run.deductions, 3)
        XCTAssertEqual(run.hits, 37)
        XCTAssertEqual(run.skipped, 2)
        XCTAssertEqual(run.reps.first { $0.row == rows[0] && $0.skill == skills[4].id }?.slot, 1)
        XCTAssertEqual(run.reps.first { $0.row == rows[2] && $0.skill == skills[4].id }?.slot, 3)
        XCTAssertEqual(run.reps.first { $0.row == rows[2] && $0.skill == skills[5].id }?.slot, 5)
        XCTAssertFalse(run.reps.contains { $0.row == rows[6] && $0.skill == skills[0].id },
                       "did not attempt / absent writes no rep at all")
    }

    /// One armed name resolves to each skill's OWN slot for it.
    func testDeductionResolvesToEachSkillsOwnSlot() {
        let custom = [OutcomeDef("Hit", .green, .hit), OutcomeDef("Out of range", .purple, .miss),
                      OutcomeDef("Bobble", .yellow, .decent)]
        let a = skill(stunt), b = skill(custom)
        let row = UUID()
        let marks: [FullOutPlan.Cell: FullOutMark] = [
            .init(row: row, skill: a.id): .deduction(key("out of range")),
            .init(row: row, skill: b.id): .deduction(key(" Out Of Range "))
        ]

        let run = FullOutPlan.resolve(rows: [row], skills: [a, b], marks: marks)

        XCTAssertEqual(run.reps.map(\.slot), [5, 1])
        XCTAssertEqual(run.deductions, 2)
    }

    /// A mark the skill can't express commits nothing — never a silent hit.
    func testDeductionTheSkillLacksIsNeverRewrittenAsAHit() {
        let other = skill([OutcomeDef("Hit", .green, .hit), OutcomeDef("Miss", .red, .miss)])
        let row = UUID()
        let mark = FullOutMark.deduction(key("Bobble"))

        XCTAssertFalse(FullOutPlan.canApply(mark, to: other))
        let run = FullOutPlan.resolve(rows: [row], skills: [other],
                                      marks: [.init(row: row, skill: other.id): mark])

        XCTAssertTrue(run.reps.isEmpty)
        XCTAssertEqual(run.skipped, 1)
    }

    /// No full-credit outcome on the skill -> nothing to assume.
    func testSkillWithNoHitOutcomeIsNeverAssumedClean() {
        let noHit = skill([OutcomeDef("Low", .yellow, .decent), OutcomeDef("Dropped", .red, .miss)])
        let row = UUID()

        XCTAssertFalse(FullOutPlan.canApply(.hit, to: noHit))
        let run = FullOutPlan.resolve(rows: [row], skills: [noHit], marks: [:])

        XCTAssertTrue(run.reps.isEmpty)
        XCTAssertEqual(run.skipped, 1)
    }

    /// The armed bar: every non-hit name once, good -> bad.
    func testDeductionsAreTheUnionOfNonHitOutcomesGoodToBad() {
        let tumbling = tumblingPreset
        let extra = [OutcomeDef("Hit", .green, .hit), OutcomeDef("bobble", .gray, .decent)]

        let stuntOnly = FullOutPlan.deductions(for: [skill(stunt)])
        XCTAssertEqual(stuntOnly.map(\.label),
                       ["Bobble", "Building fall", "Balk / Missed", "Major fall", "Out of range"])

        let mixed = FullOutPlan.deductions(for: [skill(stunt), skill(extra), skill(tumbling)])
        XCTAssertEqual(mixed.filter { $0.key == "bobble" }.count, 1, "same name, any case, is one mark")
        XCTAssertEqual(mixed.first { $0.key == "bobble" }?.colorRaw, OutcomeColor.yellow.rawValue,
                       "first-seen definition wins")
        XCTAssertEqual(mixed.map(\.credit), mixed.map(\.credit).sorted(by: >))
        XCTAssertTrue(mixed.contains { $0.label == "Balk" })
        XCTAssertFalse(mixed.contains { $0.label == "Stuck" }, "a hit is never a deduction")
    }
}
