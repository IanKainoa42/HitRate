import SwiftUI

/// The FULL-OUT run — deductions-only logging, the original speed idea behind
/// the app: assume everybody hit, mark only what didn't.
///
/// The grid is rows (stunt groups / athletes) × skills, and EVERY cell starts
/// as an assumed hit. The coach arms a mark on the bar underneath and taps the
/// cells it applies to — the same "arm an outcome, tap a card" idiom as
/// `PageRunView`, pointed at exceptions instead of at every rep. One commit
/// then writes the whole run: a rep per cell, untouched cells as hits.
///
/// Three kinds of mark (`FullOutMark`): HIT (clears a cell back), a DEDUCTION
/// (any non-hit outcome a skill offers — bobble, a fall, balk / missed, out of
/// range, a coach-made extra), and DNA — did not attempt / absent — which
/// writes NO rep at all, so it counts neither for nor against anyone.
///
/// This view is pure UI over `FullOutPlan`: it never touches the model
/// context. The presenter (`CaptureView.commitFullOut`) owns the write, so the
/// "every logging path clears `isDemo` / stamps `loggerID`" rules live in one
/// place with the other logger.
struct FullOutView: View {
    let rows: [Subject]
    let skills: [StuntGroup]
    let onCommit: (FullOutPlan.Resolution) -> Void

    private let columns: [FullOutPlan.Skill]
    private let deductions: [FullOutPlan.Deduction]

    @Environment(\.dismiss) private var dismiss

    /// Only the EXCEPTIONS are stored — a cell with no entry is an assumed hit,
    /// so `marks.isEmpty` means an untouched (all-hit) run.
    @State private var marks: [FullOutPlan.Cell: FullOutMark]
    @State private var armed: FullOutMark
    @State private var hapticTrigger = 0

    /// `initialMarks` exists for previews / render checks; the app always
    /// opens an untouched (all-hit) run.
    init(rows: [Subject], skills: [StuntGroup],
         initialMarks: [FullOutPlan.Cell: FullOutMark] = [:],
         onCommit: @escaping (FullOutPlan.Resolution) -> Void) {
        _marks = State(initialValue: initialMarks)
        self.rows = rows
        self.skills = skills
        self.onCommit = onCommit
        let columns = skills.map { FullOutPlan.Skill(id: $0.id, defs: $0.outcomeDefs) }
        let deductions = FullOutPlan.deductions(for: columns)
        self.columns = columns
        self.deductions = deductions
        // Open armed on the mildest deduction — the cells are already hits, so
        // the first thing a coach reaches for is a mark, not HIT.
        _armed = State(initialValue: deductions.first.map { FullOutMark.deduction($0.key) } ?? .skipped)
    }

    private var resolution: FullOutPlan.Resolution {
        FullOutPlan.resolve(rows: rows.map(\.id), skills: columns, marks: marks)
    }

    private let rowLabelWidth: CGFloat = 76
    private let headerHeight: CGFloat = 50
    private let gap: CGFloat = 4

    var body: some View {
        VStack(spacing: 10) {
            header
            grid
            armedHint
            armedBar
            commitButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(FloorBackdrop().ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
        // A marked-up run shouldn't vanish on a stray swipe; CANCEL still works.
        .interactiveDismissDisabled(!marks.isEmpty)
    }

    // MARK: Header (reps this run will write + CANCEL)

    private var header: some View {
        let run = resolution
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FULL OUT · EVERYONE HITS UNTIL YOU MARK IT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(run.reps.count)")
                    .font(Theme.barlow(30, .extrabold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(run.reps.count)))
                    .animation(.spring(duration: 0.3), value: run.reps.count)
                    .foregroundStyle(Theme.label)
                Text(Self.summary(run))
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .wellBackground(cornerRadius: 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }

    /// "REPS · 3 DEDUCTIONS · 2 NOT COUNTED" — what the commit will write.
    static func summary(_ run: FullOutPlan.Resolution) -> String {
        var parts = ["REP\(run.reps.count == 1 ? "" : "S")"]
        parts.append("\(run.deductions) DEDUCTION\(run.deductions == 1 ? "" : "S")")
        if run.skipped > 0 { parts.append("\(run.skipped) NOT COUNTED") }
        return parts.joined(separator: " · ")
    }

    // MARK: Grid (rows × skills)

    /// Columns share the width when they fit (six do on every current
    /// iPhone); past that they hold a tappable minimum and the grid scrolls
    /// sideways.
    private func columnWidth(_ available: CGFloat) -> CGFloat {
        let n = CGFloat(max(columns.count, 1))
        return max(40, ((available - rowLabelWidth - gap * n) / n).rounded(.down))
    }

    /// Rows stretch to use the height a short roster leaves free (bigger
    /// targets), and hold a minimum once the roster needs to scroll.
    private func rowHeight(_ available: CGFloat) -> CGFloat {
        let n = CGFloat(max(rows.count, 1))
        return min(60, max(44, ((available - headerHeight - gap * n) / n).rounded(.down)))
    }

    private var grid: some View {
        GeometryReader { geo in
            let colW = columnWidth(geo.size.width)
            let rowH = rowHeight(geo.size.height)
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(alignment: .bottom, spacing: gap) {
                        Color.clear.frame(width: rowLabelWidth, height: 1)
                        ForEach(skills, id: \.id) { skill in
                            columnHeader(skill).frame(width: colW)
                        }
                    }
                    .frame(height: headerHeight, alignment: .bottom)
                    ForEach(rows, id: \.id) { row in
                        HStack(spacing: gap) {
                            rowLabel(row).frame(height: rowH)
                            ForEach(columns) { column in
                                cell(row: row, column: column)
                                    .frame(width: colW, height: rowH)
                            }
                        }
                    }
                }
                .frame(minWidth: geo.size.width, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        }
    }

    /// Hold a skill to stamp the armed mark down its whole column (a section
    /// nobody threw → arm DNA, hold the skill). A hold, not a tap: one stray
    /// touch must not rewrite a column.
    private func columnHeader(_ skill: StuntGroup) -> some View {
        VStack(spacing: 3) {
            Text(skill.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.label2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            Text("\(skill.number)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(skill.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) { stamp(skill: skill.id) }
        .accessibilityLabel(skill.displayName)
        .accessibilityHint("Hold to mark every row on this skill")
    }

    /// Hold a row's name to stamp the armed mark across it (a group that sat
    /// the run out → arm DNA, hold the name).
    private func rowLabel(_ row: Subject) -> some View {
        HStack(spacing: 5) {
            Text("\(row.orderIndex + 1)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(row.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(row.displayName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(row.isUnnamed ? Theme.label3 : Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) { stamp(row: row.id) }
        .accessibilityLabel(row.displayName)
        .accessibilityHint("Hold to mark every skill for this row")
    }

    /// One cell. A gesture view, not a Button — the capture grid's house rule.
    /// Dimmed while the armed mark can't apply to this skill (it has no outcome
    /// by that name), the same 40% no-op as an unloggable page pocket.
    private func cell(row: Subject, column: FullOutPlan.Skill) -> some View {
        let key = FullOutPlan.Cell(row: row.id, skill: column.id)
        let mark = marks[key] ?? .hit
        return cellFace(mark, column: column)
            .opacity(FullOutPlan.canApply(armed, to: column) ? 1 : 0.4)
            .contentShape(Rectangle())
            .onTapGesture { tap(key, column: column) }
            .accessibilityLabel("\(row.displayName), \(name(of: mark))")
            .accessibilityHint("Marks \(name(of: armed))")
    }

    @ViewBuilder
    private func cellFace(_ mark: FullOutMark, column: FullOutPlan.Skill) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch mark {
        case .hit:
            // Quiet on purpose: a wall of assumed hits is the background, the
            // marks are the signal. A skill with no full-credit outcome can't
            // be assumed clean, so it shows a dash and commits nothing.
            let assumable = FullOutPlan.hitSlot(in: column.defs) != nil
            ZStack {
                shape.fill(Theme.well.shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1)))
                shape.stroke(Theme.hit.opacity(assumable ? 0.22 : 0), lineWidth: 1)
                if assumable {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.hit.opacity(0.5))
                } else {
                    Text("—")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.label3)
                }
            }
        case .deduction(let key):
            let color = self.color(ofDeduction: key)
            ZStack {
                shape.fill(color)
                Text(deductions.first { $0.key == key }?.short ?? "?")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.well)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            }
        case .skipped:
            ZStack {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Theme.outcomeGray.opacity(0.7))
                Text("DNA")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.outcomeGray)
            }
        }
    }

    // MARK: Armed bar (HIT · deductions · DNA)

    private var armable: [FullOutMark] {
        [FullOutMark.hit] + deductions.map { FullOutMark.deduction($0.key) } + [FullOutMark.skipped]
    }

    private var armedBar: some View {
        // Up to seven marks share the width; a busier folder scrolls.
        Group {
            if armable.count <= 7 {
                HStack(spacing: 6) {
                    ForEach(armable, id: \.self) { armChip($0).frame(maxWidth: .infinity) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(armable, id: \.self) { armChip($0).frame(width: 54) }
                    }
                }
            }
        }
    }

    private func armChip(_ mark: FullOutMark) -> some View {
        let on = armed == mark
        let color = self.color(of: mark)
        return Button {
            armed = mark
            hapticTrigger += 1
        } label: {
            Text(short(of: mark))
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? Theme.well : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(on ? AnyShapeStyle(color)
                             : AnyShapeStyle(Theme.well.shadow(
                                .inner(color: .black.opacity(0.5), radius: 3, y: 1)))))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(color.opacity(on ? 0 : 0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name(of: mark))\(on ? ", armed" : "")")
    }

    /// The armed mark spelled out — the chips are short codes (BF, OOR, DNA).
    private var armedHint: some View {
        HStack(spacing: 6) {
            Circle().fill(color(of: armed)).frame(width: 7, height: 7)
            Text(hint(for: armed))
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.label2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }

    private func hint(for mark: FullOutMark) -> String {
        switch mark {
        case .hit:
            "HIT · TAP A CELL TO CLEAR ITS MARK"
        case .deduction(let key):
            deductions.first { $0.key == key }
                .map { "\($0.label.uppercased()) · \($0.credit)% · TAP A CELL · HOLD A NAME FOR ALL" }
                ?? "TAP A CELL TO MARK IT"
        case .skipped:
            "DID NOT ATTEMPT / ABSENT · NOT COUNTED · NO REP LOGGED"
        }
    }

    // MARK: Commit (the one raised control here, like Home's practice CTA)

    private var commitButton: some View {
        let run = resolution
        return Button {
            guard !run.reps.isEmpty else { return }
            onCommit(run)
            dismiss()
        } label: {
            Text("LOG FULL OUT · \(run.reps.count) REP\(run.reps.count == 1 ? "" : "S")")
                .font(.system(size: 13, weight: .heavy))
                .tracking(1.5)
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
        .disabled(run.reps.isEmpty)
        .opacity(run.reps.isEmpty ? 0.4 : 1)
    }

    // MARK: Marking

    /// Tap a cell: stamp the armed mark. Tapping a cell that already carries
    /// it — or tapping with HIT armed — clears the cell back to an assumed hit.
    private func tap(_ key: FullOutPlan.Cell, column: FullOutPlan.Skill) {
        guard FullOutPlan.canApply(armed, to: column) else { return }
        let current = marks[key] ?? .hit
        marks[key] = (armed == .hit || current == armed) ? nil : armed
        hapticTrigger += 1
    }

    private func stamp(row: UUID) {
        for column in columns where FullOutPlan.canApply(armed, to: column) {
            marks[FullOutPlan.Cell(row: row, skill: column.id)] = armed == .hit ? nil : armed
        }
        hapticTrigger += 1
    }

    private func stamp(skill: UUID) {
        guard let column = columns.first(where: { $0.id == skill }),
              FullOutPlan.canApply(armed, to: column) else { return }
        for row in rows {
            marks[FullOutPlan.Cell(row: row.id, skill: skill)] = armed == .hit ? nil : armed
        }
        hapticTrigger += 1
    }

    // MARK: Mark wording + color

    private func color(ofDeduction key: String) -> Color {
        let raw = deductions.first { $0.key == key }?.colorRaw ?? ""
        return (OutcomeColor(rawValue: raw) ?? .gray).color
    }

    private func color(of mark: FullOutMark) -> Color {
        switch mark {
        case .hit: Theme.hit
        case .deduction(let key): color(ofDeduction: key)
        case .skipped: Theme.outcomeGray
        }
    }

    private func short(of mark: FullOutMark) -> String {
        switch mark {
        case .hit: "HIT"
        case .deduction(let key): deductions.first { $0.key == key }?.short ?? "?"
        case .skipped: "DNA"
        }
    }

    private func name(of mark: FullOutMark) -> String {
        switch mark {
        case .hit: "Hit"
        case .deduction(let key): deductions.first { $0.key == key }?.label ?? "Deduction"
        case .skipped: "Did not attempt"
        }
    }
}
