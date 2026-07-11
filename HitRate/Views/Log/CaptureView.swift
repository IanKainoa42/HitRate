import SwiftUI
import SwiftData
import os

/// The unified capture screen (replaces the Pad/Grid split for normal practice).
///
/// An attempt is three dimensions — subject (who) × skill (what) × outcome (how).
/// The screen always shows two as a matrix and pins the third at the top:
/// - **Outcomes are ALWAYS the tap buttons** (columns) — fixed thumb targets.
/// - A PIVOT toggle chooses what's pinned:
///   - Pin a **skill** → rows are subjects ("everyone on back handsprings").
///   - Pin a **subject** → rows are skills ("just Maya today").
///
/// One tap logs one Attempt, no confirm. Subjects can be added unnamed
/// (capture-first, name-later) and renamed inline. Clinic still uses LogView.
struct CaptureView: View {
    let session: PracticeSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Subject.orderIndex) private var allSubjects: [Subject]
    @Query(sort: \Team.orderIndex) private var teams: [Team]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""

    /// What's pinned at the top: "skill" (rows = subjects) or "subject" (rows = skills).
    @AppStorage("capturePivot") private var pivotRaw = "skill"
    /// Pinned skill (skill pivot) / pinned subject (subject pivot). Persisted so the
    /// watch can mirror the pulled-up skill and the screen remembers between practices.
    @AppStorage("selectedGroupID") private var selectedGroupIDRaw = ""
    @AppStorage("selectedSubjectID") private var selectedSubjectIDRaw = ""

    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }
    private var currentTeam: Team? { teams.current(id: currentTeamID) }

    /// Practice logs into the active team's roster only.
    private var groups: [StuntGroup] { allGroups.inTeam(currentTeam) }
    private var subjects: [Subject] { allSubjects.inTeam(currentTeam) }

    private enum Pivot: String { case skill, subject }
    private var pivot: Pivot { Pivot(rawValue: pivotRaw) ?? .skill }

    /// The pinned skill (skill pivot). Resolves the persisted id against the CURRENT
    /// roster so a deleted selection can't receive reps.
    private var pinnedSkill: StuntGroup? {
        groups.first { $0.id.uuidString == selectedGroupIDRaw } ?? groups.first
    }
    /// The pinned subject (subject pivot). Same defensive resolution.
    private var pinnedSubject: Subject? {
        subjects.first { $0.id.uuidString == selectedSubjectIDRaw } ?? subjects.first
    }

    /// New subjects follow the mode: a coach rosters stunt groups, an athlete rosters
    /// people. The USER can still pin either axis regardless.
    private var subjectKind: SubjectKind { mode == .coach ? .group : .person }
    private var subjectNoun: String { subjectKind.label.lowercased() }

    var body: some View {
        NavigationStack {
            content
                .background(FloorBackdrop().ignoresSafeArea())
                .navigationTitle("Practice")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(mode.nounPluralTitle) { showGroupsEditor = true }
                    }
                }
                .sheet(isPresented: $showGroupsEditor) { GroupsEditorView() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: Screen

    @ViewBuilder
    private var content: some View {
        let attempts = session.sortedAttempts

        VStack(spacing: 9) {
            header(attempts)

            if groups.isEmpty {
                emptyRoster
            } else {
                pivotBar
                pinPicker
                matrix(attempts)
                recentTicker(attempts)
            }
        }
    }

    // MARK: Header (reps + weighted rate + END)

    @ViewBuilder
    private func header(_ attempts: [Attempt]) -> some View {
        let rate = attempts.isEmpty ? nil
            : Int((Double(attempts.reduce(0) { $0 + $1.creditValue }) / Double(attempts.count)).rounded())

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    IconWordmark(size: 11, rateFill: Theme.well, dotSize: 5)
                    Text("PRACTICE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label3)
                }
                Text("\(attempts.count)")
                    .font(Theme.barlow(30, .extrabold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(attempts.count)))
                    .animation(.spring(duration: 0.3), value: attempts.count)
                Text(rate.map { "REPS · \($0)% HIT" } ?? "REPS — LOG EACH AS IT LANDS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
            }
            Spacer()
            Button {
                // A session with reps ends here; an empty one stays live and Home
                // sweeps it on dismiss (mutating-then-rendering a deleted model
                // mid-animation crashes).
                if !session.attempts.isEmpty {
                    session.endedAt = .now
                    try? context.save()
                }
                hapticTrigger += 1
                Sounds.shared.play(.end)
                dismiss()
            } label: {
                Text("END")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.majorFall)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.iconTile)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Theme.majorFall.opacity(0.5), lineWidth: 1)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Pivot control

    /// The one control that flips the matrix: pin a skill (rows = subjects) or pin a
    /// subject (rows = skills). Outcomes stay the columns either way.
    private var pivotBar: some View {
        HStack(spacing: 10) {
            Text("PIN")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
            MiniSeg(options: ["Skill", subjectKind.label],
                    selection: Binding(
                        get: { pivot == .skill ? "Skill" : subjectKind.label },
                        set: { pivotRaw = ($0 == "Skill") ? "skill" : "subject"; hapticTrigger += 1 }))
            Spacer()
            Button {
                addSubject()
            } label: {
                Label("Add \(subjectNoun)", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Pin picker (chips for whichever axis is pinned)

    @ViewBuilder
    private var pinPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch pivot {
                case .skill:
                    ForEach(groups) { g in
                        pinChip(number: g.number, name: g.name, color: g.color,
                                on: pinnedSkill === g) {
                            selectedGroupIDRaw = g.id.uuidString; hapticTrigger += 1
                        }
                    }
                case .subject:
                    if subjects.isEmpty {
                        Text("Add \(subjectNoun == "athlete" ? "an athlete" : "a group") to pin")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.label3)
                            .padding(.vertical, 8)
                    }
                    ForEach(subjects) { s in
                        pinChip(number: s.orderIndex + 1, name: s.displayName, color: s.color,
                                on: pinnedSubject === s) {
                            selectedSubjectIDRaw = s.id.uuidString; hapticTrigger += 1
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func pinChip(number: Int, name: String, color: Color, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 7) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? Theme.well : Theme.label)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(on ? Theme.label : Theme.iconTile)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(on ? .clear : Theme.iconTileEdge.opacity(0.65), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Matrix (rows × outcome columns)

    @ViewBuilder
    private func matrix(_ attempts: [Attempt]) -> some View {
        switch pivot {
        case .skill:  skillPinnedMatrix(attempts)
        case .subject: subjectPinnedMatrix(attempts)
        }
    }

    /// Skill pinned: one skill up top, a ROW PER SUBJECT, this skill's outcome
    /// columns. Every row shares the pinned skill so a single outcome header reads.
    @ViewBuilder
    private func skillPinnedMatrix(_ attempts: [Attempt]) -> some View {
        if let skill = pinnedSkill {
            let defs = skill.outcomeDefs
            VStack(spacing: 8) {
                Text("TAP A CELL TO LOG A REP")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.label3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Shared outcome header — valid because every row is this one skill.
                HStack(spacing: 6) {
                    Color.clear.frame(width: rowLabelWidth, height: 1)
                    ForEach(Array(defs.enumerated()), id: \.offset) { _, def in
                        Text(def.short)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(def.color)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }

                if subjects.isEmpty {
                    unnamedRowHint
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: subjects.count > 8 ? 4 : 6) {
                            ForEach(subjects) { s in
                                HStack(spacing: 6) {
                                    subjectRowLabel(s)
                                    ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                                        let v = counts(group: skill, subject: s, in: attempts)[safe: slot] ?? 0
                                        cellButton(v: v, def: def) { log(slot: slot, group: skill, subject: s, def: def) }
                                    }
                                }
                                .frame(maxHeight: 50)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        }
    }

    /// Subject pinned: one subject up top, a ROW PER SKILL, each skill's own outcome
    /// columns (counts vary), so there's no shared header — just the good→bad hint.
    @ViewBuilder
    private func subjectPinnedMatrix(_ attempts: [Attempt]) -> some View {
        if let subject = pinnedSubject {
            VStack(spacing: 8) {
                Text("TAP A CELL TO LOG A REP · \(subject.displayName.uppercased())")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.label3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("← good   ·   bad →")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.label3)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: groups.count > 8 ? 4 : 6) {
                        ForEach(groups) { g in
                            let defs = g.outcomeDefs
                            HStack(spacing: 6) {
                                skillRowLabel(g)
                                ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                                    let v = counts(group: g, subject: subject, in: attempts)[safe: slot] ?? 0
                                    cellButton(v: v, def: def) { log(slot: slot, group: g, subject: subject, def: def) }
                                }
                            }
                            .frame(maxHeight: 50)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        } else {
            unnamedRowHint
        }
    }

    private var rowLabelWidth: CGFloat { 96 }

    /// A subject row label — colored badge + inline-renameable name (name-later).
    private func subjectRowLabel(_ s: Subject) -> some View {
        HStack(spacing: 6) {
            Text("\(s.orderIndex + 1)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(s.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            RenameField(prompt: s.kind.label, value: s.name) { new in
                s.name = new
                try? context.save()
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(s.isUnnamed ? Theme.label3 : Theme.label)
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    /// A skill row label (subject pivot) — colored number badge + name.
    private func skillRowLabel(_ g: StuntGroup) -> some View {
        HStack(spacing: 6) {
            Text("\(g.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(g.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(g.name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    /// One engraved matrix cell — count in chalk Barlow, outcome color in the edge.
    private func cellButton(v: Int, def: OutcomeDef, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 1) {
                Text("\(v)")
                    .font(Theme.barlow(20, .extrabold))
                    .monospacedDigit()
                    .foregroundStyle(v == 0 ? Theme.label3 : Theme.label)
                    .contentTransition(.numericText(value: Double(v)))
                    .animation(.spring(duration: 0.3), value: v)
                Text(def.short)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(def.color.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.well
                        .shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1))
                        .shadow(.inner(color: def.color.opacity(0.85), radius: 1, y: -2)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(def.label)")
        .accessibilityValue("\(v)")
    }

    // MARK: Empty states

    private var emptyRoster: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Add a \(mode.noun) first")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.label)
            Button {
                showGroupsEditor = true
            } label: {
                Text(mode.nounPluralTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.well)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unnamedRowHint: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Add \(subjectNoun == "athlete" ? "an athlete" : "a group") to start logging")
                .font(.system(size: 14))
                .foregroundStyle(Theme.label2)
            Button { addSubject() } label: {
                Label("Add \(subjectNoun)", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.well)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Recent ticker

    @ViewBuilder
    private func recentTicker(_ attempts: [Attempt]) -> some View {
        HStack(spacing: 8) {
            Button { undoLastRep(attempts) } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(attempts.isEmpty ? Theme.label3 : Theme.accent)
                    .frame(width: 38, height: 42)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.well.shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1))))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(attempts.isEmpty)

            if attempts.isEmpty {
                Text("Reps land here as you log them")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label3)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Color.clear.frame(width: 0, height: 1).id("live")
                            ForEach(attempts.reversed()) { repChip($0) }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: attempts.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("live", anchor: .leading) }
                    }
                }
            }
        }
        .frame(height: 54)
        .padding(.horizontal, 10)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Engraved chip: outcome dot + subject/skill context + outcome short word.
    private func repChip(_ a: Attempt) -> some View {
        HStack(spacing: 5) {
            Circle().fill(a.outcomeDef?.color ?? Theme.label3).frame(width: 7, height: 7)
            Text(a.subject?.displayName ?? a.group?.name ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
            Text(a.outcomeDef?.short ?? "—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.label2)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.well.shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1)))
        )
    }

    // MARK: Actions

    /// Log one rep: subject × skill × outcome slot. No confirm.
    private func log(slot: Int, group: StuntGroup, subject: Subject, def: OutcomeDef) {
        context.insert(Attempt(slot: slot, group: group, session: session, subject: subject))
        try? context.save()
        selectedGroupIDRaw = group.id.uuidString
        selectedSubjectIDRaw = subject.id.uuidString
        hapticTrigger += 1
        Sounds.shared.play(.outcome(def.soundOutcome))
    }

    /// Add a subject (unnamed — name-later). Pins it in subject pivot so it's
    /// immediately usable.
    private func addSubject() {
        guard let team = currentTeam else { return }
        let next = (subjects.map { $0.orderIndex }.max() ?? -1) + 1
        let s = Subject(name: "", kind: subjectKind, orderIndex: next)
        s.team = team
        context.insert(s)
        try? context.save()
        selectedSubjectIDRaw = s.id.uuidString
        hapticTrigger += 1
    }

    /// Per-slot session counts for one (skill, subject) pair.
    private func counts(group: StuntGroup, subject: Subject, in attempts: [Attempt]) -> [Int] {
        var counts = Array(repeating: 0, count: group.outcomeDefs.count)
        for a in attempts where a.group === group && a.subject === subject {
            let slot = a.outcomeRaw
            if slot >= 0 && slot < counts.count { counts[slot] += 1 }
        }
        return counts
    }

    private func undoLastRep(_ attempts: [Attempt]) {
        guard let last = attempts.last else { return }
        context.delete(last)
        try? context.save()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
