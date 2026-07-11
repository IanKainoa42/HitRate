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

    // Wave/Routine staging: stage any number of reps per (skill, subject) CELL
    // (tap +1, hold −1), then commit the whole batch at once. A cell can carry
    // several outcomes in one pass, so staging is a slot-count array per cell and
    // commit is MANUAL only — with multi-rep staging there's no "everyone staged"
    // finish line. Works in either pivot: the pinned axis is fixed, the row axis
    // varies, but the key always names both skill and subject.
    @AppStorage("waveMode") private var waveMode = false
    @State private var staged: [StageKey: [Int]] = [:]
    @State private var lastWave: [Attempt] = []

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

    /// Wave staging armed. `waveActive` gates the cells between tap-to-log and
    /// tap-to-stage. Coach mental model is a wave of stunt groups; athlete a
    /// routine pass.
    private var waveActive: Bool { waveMode }
    private var waveNoun: String { mode == .coach ? "wave" : "routine" }
    /// Total staged reps across every cell (a stale key can't over-count — nil rows
    /// contribute nothing).
    private var stagedReps: Int { staged.values.reduce(0) { $0 + $1.reduce(0, +) } }

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
                nameSuggestionBar
                matrix(attempts)
                // Issues tie to a single skill; only the skill pivot pins one.
                if pivot == .skill, !customOutcomes.isEmpty, let skill = pinnedSkill {
                    customOutcomePad(group: skill)
                }
                if waveActive { waveBar }
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
                // Ending must never silently drop staged reps — Submit is easy to
                // miss. Commit any staged batch first.
                if stagedReps > 0 { commitWave() }
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
                        set: { newValue in
                            // Switching the pinned axis with staged-but-unsubmitted
                            // reps: commit them rather than silently dropping.
                            if stagedReps > 0 { commitWave() }
                            pivotRaw = (newValue == "Skill") ? "skill" : "subject"
                            hapticTrigger += 1
                        }))
            Spacer()
            waveToggle
            // The + adds an item of the PINNED axis — the same list the pin picker
            // shows. Pinned on Skill → new skill; pinned on the subject axis → new
            // subject. To add the other kind, flip the pin. (Ian: "on the skill tab
            // it should make a skill, not a group.")
            Button { pivot == .skill ? addSkill() : addSubject() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.iconTile))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pivot == .skill ? "Add skill" : "Add \(subjectNoun)")
        }
        .padding(.horizontal, 16)
    }

    /// Compact caps pill that arms staging — green-filled on, chalk outline off.
    /// Word adapts WAVE / ROUTINE.
    private var waveToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { waveMode.toggle() }
            if !waveMode { staged = [:]; lastWave = [] }   // leaving wave drops pending + undo
            hapticTrigger += 1
        } label: {
            Text(waveNoun.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(waveMode ? Theme.well : Theme.label2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(waveMode ? Theme.accent : Theme.well)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(waveMode ? 0 : 0.1), lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(waveNoun) logging")
        .accessibilityValue(waveMode ? "on" : "off")
    }

    // MARK: Pin picker (chips for whichever axis is pinned)

    @ViewBuilder
    private var pinPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch pivot {
                case .skill:
                    ForEach(groups) { g in
                        pinChip(number: g.number, name: g.displayName, color: g.color,
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

    // MARK: Deferred-naming suggestion chips

    /// The blank subject the chips will name: the currently-pinned/last-added
    /// one, ONLY while still unnamed. nil hides the strip (it self-dismisses the
    /// moment a name lands). Add-a-subject pins the new blank in both pivots, so
    /// the strip appears right where you just tapped "+".
    private var namingTarget: Subject? {
        subjects.first { $0.id.uuidString == selectedSubjectIDRaw && $0.isUnnamed }
    }

    /// Names already on THIS roster — the dedup guard. Shown greyed + checked,
    /// never tappable, so you can see what's taken while naming a blank (kills
    /// the "Mya" vs "Maya" double-create).
    private var rosterNames: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in subjects where !s.isUnnamed {
            if seen.insert(s.name).inserted { out.append(s.name) }
        }
        return out
    }

    /// Names used on your OTHER folders for the SAME kind (people vs groups),
    /// minus names already on this roster — a reusable bank so a name typed once
    /// is one tap away everywhere, never retyped into a variant.
    private var nameBank: [String] {
        let taken = Set(subjects.filter { !$0.isUnnamed }.map(\.name))
        var seen = Set<String>(); var out: [String] = []
        for s in allSubjects.active where s.kind == subjectKind
            && s.team?.id != currentTeam?.id
            && s.team?.deletedAt == nil && !s.isUnnamed {
            if taken.contains(s.name) || !seen.insert(s.name).inserted { continue }
            out.append(s.name)
        }
        return out
    }

    @ViewBuilder
    private var nameSuggestionBar: some View {
        if let target = namingTarget, !nameBank.isEmpty || !rosterNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("NAME")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.label3)
                        .padding(.trailing, 2)
                    ForEach(nameBank, id: \.self) { name in
                        Button {
                            target.name = name
                            try? context.save()
                            hapticTrigger += 1
                        } label: { suggestionChip(name, taken: false) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Name this \(subjectNoun) \(name)")
                    }
                    ForEach(rosterNames, id: \.self) { name in
                        suggestionChip(name, taken: true)
                            .accessibilityLabel("\(name) already used on this roster")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func suggestionChip(_ name: String, taken: Bool) -> some View {
        HStack(spacing: 4) {
            if taken {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(name)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(taken ? Theme.label3 : Theme.label)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(taken ? Theme.well : Theme.iconTile)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Theme.iconTileEdge.opacity(taken ? 0.35 : 0.65), lineWidth: 1))
        .contentShape(Rectangle())
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
                // The pinned skill's name — always editable inline (tap to rename),
                // not just while blank. RenameField carries its own pencil.
                RenameField(prompt: "Name this skill", value: skill.name) { new in
                    skill.name = new
                    try? context.save()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(skill.isUnnamed ? Theme.label3 : Theme.label)
                .lineLimit(1)
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
                                let streakN = hotStreak(group: skill, subject: s, in: attempts)
                                HStack(spacing: 6) {
                                    subjectRowLabel(s, streak: streakN)
                                    ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                                        let v = counts(group: skill, subject: s, in: attempts)[safe: slot] ?? 0
                                        matrixCell(group: skill, subject: s, slot: slot, def: def, v: v)
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
                // The pinned subject's name — editable inline (tap to rename).
                RenameField(prompt: subjectKind.label, value: subject.name) { new in
                    subject.name = new
                    try? context.save()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(subject.isUnnamed ? Theme.label3 : Theme.label)
                .lineLimit(1)
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
                            let streakN = hotStreak(group: g, subject: subject, in: attempts)
                            HStack(spacing: 6) {
                                skillRowLabel(g, streak: streakN)
                                ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                                    let v = counts(group: g, subject: subject, in: attempts)[safe: slot] ?? 0
                                    matrixCell(group: g, subject: subject, slot: slot, def: def, v: v)
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

    /// A subject row label — colored badge + inline-renameable name (name-later),
    /// with the hot-streak flame once the cell strings clean hits together.
    private func subjectRowLabel(_ s: Subject, streak: Int) -> some View {
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
            flameBadge(streak)
        }
        .padding(.horizontal, 4)
        .modifier(FireBorder(active: streak >= 3, cornerRadius: 7))
        .frame(width: rowLabelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    /// A skill row label (subject pivot) — colored number badge + name + flame.
    private func skillRowLabel(_ g: StuntGroup, streak: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(g.number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(g.color)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            RenameField(prompt: "Skill", value: g.name) { new in
                g.name = new
                try? context.save()
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(g.isUnnamed ? Theme.label3 : Theme.label)
            .lineLimit(1).minimumScaleFactor(0.7)
            flameBadge(streak)
        }
        .padding(.horizontal, 4)
        .modifier(FireBorder(active: streak >= 3, cornerRadius: 7))
        .frame(width: rowLabelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    /// One matrix cell — logs immediately, or STAGES a rep in wave mode. In wave
    /// mode the cell is a gesture view, NOT a Button: a Button fires on release
    /// even after a hold, so a long-press decrement would re-increment on lift.
    @ViewBuilder
    private func matrixCell(group: StuntGroup, subject: Subject, slot: Int, def: OutcomeDef, v: Int) -> some View {
        let stagedN = waveActive ? stagedCount(group, subject, slot) : 0
        let visual = cellVisual(v: v, def: def, stagedN: stagedN)
        Group {
            if waveActive {
                visual
                    .onTapGesture { stage(group, subject, slot) }
                    .onLongPressGesture(minimumDuration: 0.4) { unstage(group, subject, slot) }
            } else {
                Button { log(slot: slot, group: group, subject: subject, def: def) } label: { visual }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityLabel("\(waveActive ? "Stage" : "Log") \(def.label)")
        .accessibilityValue("\(v)\(stagedN > 0 ? ", \(stagedN) staged" : "")")
        .accessibilityHint(waveActive ? "Tap to stage one more, hold to remove one" : "")
    }

    /// The engraved cell face — count in chalk Barlow, outcome color in the edge.
    /// While staging, the edge lights and a "+n" pip shows this cell's pending reps.
    private func cellVisual(v: Int, def: OutcomeDef, stagedN: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(v)")
                .font(Theme.barlow(20, .extrabold))
                .monospacedDigit()
                .foregroundStyle(stagedN > 0 ? def.color : (v == 0 ? Theme.label3 : Theme.label))
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
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(def.color, lineWidth: stagedN > 0 ? 2.5 : 0)
        )
        .overlay(alignment: .topTrailing) {
            if stagedN > 0 {
                Text("+\(stagedN)")
                    .font(Theme.barlow(11, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.well)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(def.color))
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
    }

    /// Docked under the matrix in wave mode. While staging: rep count + Clear +
    /// Submit. After a commit (nothing staged): Undo. Commit is ALWAYS manual.
    private var waveBar: some View {
        HStack(spacing: 10) {
            Text("\(stagedReps) REP\(stagedReps == 1 ? "" : "S") STAGED")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label2)
            Spacer()
            if stagedReps > 0 {
                Button { staged = [:]; hapticTrigger += 1 } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { commitWave() } label: {
                    Text("Submit \(stagedReps)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.well)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if !lastWave.isEmpty {
                Button { undoWave() } label: {
                    Label("Undo \(waveNoun)", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .wellBackground()
        .padding(.horizontal, 16)
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
                            ForEach(Array(logSegments(attempts).reversed())) { tickerChip($0) }
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

    /// One chunk of the recent log: a wave (reps committed together, same waveID)
    /// or a lone rep.
    private enum LogSegment: Identifiable {
        case single(Attempt)
        case wave(UUID, [Attempt])
        var id: String {
            switch self {
            case .single(let a): return "s\(a.persistentModelID.hashValue)"
            case .wave(let id, _): return "w\(id.uuidString)"
            }
        }
    }

    /// Collapse the chronological attempts into segments: maximal runs of the same
    /// non-nil `waveID` become one wave; nil-waveID reps stay singletons.
    private func logSegments(_ attempts: [Attempt]) -> [LogSegment] {
        var segs: [LogSegment] = []
        var i = 0
        while i < attempts.count {
            let a = attempts[i]
            if let wid = a.waveID {
                var reps = [a]
                var j = i + 1
                while j < attempts.count, attempts[j].waveID == wid { reps.append(attempts[j]); j += 1 }
                segs.append(.wave(wid, reps))
                i = j
            } else {
                segs.append(.single(a)); i += 1
            }
        }
        return segs
    }

    /// One ticker entry: a lone rep is a single chip; a wave is its chips wrapped in
    /// a hairline cluster so the batch reads as one event.
    @ViewBuilder
    private func tickerChip(_ seg: LogSegment) -> some View {
        switch seg {
        case .single(let a):
            repChip(a)
        case .wave(_, let reps):
            HStack(spacing: 4) { ForEach(reps) { repChip($0) } }
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        }
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

    // MARK: Wave / Routine staging

    private func stagedCount(_ g: StuntGroup, _ s: Subject, _ slot: Int) -> Int {
        guard let arr = staged[StageKey(g, s)], slot >= 0, slot < arr.count else { return 0 }
        return arr[slot]
    }

    /// Tap a cell in wave mode: stage one more rep of that outcome for that cell.
    private func stage(_ g: StuntGroup, _ s: Subject, _ slot: Int) {
        let key = StageKey(g, s)
        let n = g.outcomeDefs.count
        var c = staged[key] ?? Array(repeating: 0, count: n)
        if c.count < n { c += Array(repeating: 0, count: n - c.count) }
        guard slot >= 0, slot < c.count else { return }
        c[slot] += 1
        staged[key] = c
        hapticTrigger += 1
        Sounds.shared.play(.outcome(g.outcomeDef(at: slot)?.soundOutcome ?? .hit))
    }

    /// Hold a cell in wave mode: take one staged rep back off.
    private func unstage(_ g: StuntGroup, _ s: Subject, _ slot: Int) {
        let key = StageKey(g, s)
        guard var c = staged[key], slot >= 0, slot < c.count, c[slot] > 0 else { return }
        c[slot] -= 1
        staged[key] = c.reduce(0, +) == 0 ? nil : c
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    /// Write one Attempt per staged rep (all sharing a `waveID`), then clear the
    /// staging. Keeps the batch in `lastWave` so it can be pulled back in one tap.
    private func commitWave() {
        let waveID = UUID()
        var committed: [Attempt] = []
        for g in groups {
            for s in subjects {
                guard let c = staged[StageKey(g, s)] else { continue }
                for (slot, n) in c.enumerated() where n > 0 {
                    for _ in 0..<n {
                        let a = Attempt(slot: slot, group: g, session: session, subject: s, waveID: waveID)
                        context.insert(a)
                        committed.append(a)
                    }
                }
            }
        }
        guard !committed.isEmpty else { return }
        try? context.save()
        lastWave = committed
        staged = [:]
        hapticTrigger += 1
        Sounds.shared.play(.start)
    }

    /// Delete the whole last committed batch. Guards each attempt against having
    /// already been removed (e.g. via the Recent undo) so we never touch a deleted
    /// model.
    private func undoWave() {
        let live = session.attempts
        for a in lastWave where live.contains(where: { $0 === a }) {
            context.delete(a)
        }
        try? context.save()
        lastWave = []
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    /// Add a skill (unnamed — name-later, like a subject). Pins it so it's the
    /// live one, and inherits the currently-pinned skill's category so a skill
    /// added mid-tumbling stays tumbling (Balk and all). Name it in the header
    /// RenameField or the skills editor; outcomes are editable in the editor.
    private func addSkill() {
        guard let team = currentTeam else { return }
        let nextNum = (groups.map(\.number).max() ?? 0) + 1
        let nextOrder = (groups.map(\.orderIndex).max() ?? -1) + 1
        let g = StuntGroup(name: "", number: nextNum, orderIndex: nextOrder)
        g.category = pinnedSkill?.category ?? .stunts   // sets kindRaw too
        g.team = team
        context.insert(g)
        try? context.save()
        selectedGroupIDRaw = g.id.uuidString
        hapticTrigger += 1
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

    // MARK: Hot streak (heating up / on fire)

    /// Trailing run of clean hits (100%-credit) for one (skill, subject) cell in
    /// this session. Any non-hit breaks it. 2 = heating up, 3+ = on fire. Keys on
    /// the cell so the flame rides whichever axis is the row.
    private func hotStreak(group: StuntGroup, subject: Subject, in attempts: [Attempt]) -> Int {
        var run = 0
        for a in attempts.reversed() {
            guard a.group === group && a.subject === subject else { continue }
            guard a.isHitRep else { break }
            run += 1
        }
        return run
    }

    /// Ember at 2 straight hits, pulsing flame at 3+. Rides next to the row label.
    @ViewBuilder
    private func flameBadge(_ streak: Int) -> some View {
        if streak >= 2 {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(streak >= 3 ? Theme.fireHot : Theme.fireWarm)
                .symbolEffect(.pulse, options: .repeating, isActive: streak >= 3)
                .accessibilityLabel(streak >= 3 ? "On fire — \(streak) hits in a row"
                                                : "Heating up — 2 hits in a row")
        }
    }

    // MARK: Custom-outcome "issues" pad (skill pivot only)

    /// The active folder's user-created outcomes — tallied SEPARATELY from the
    /// hit-rate (a distinct model), shown as a secondary tier under the matrix.
    private var customOutcomes: [CustomOutcome] {
        (currentTeam?.customOutcomes ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// A row of tap buttons under the matrix — the folder's own outcomes, tallied
    /// against the pinned skill (subject-agnostic, matching the legacy semantics).
    /// Tap = +1, hold = −1 (gesture view, not a Button: a Button fires on release
    /// after a hold and would re-increment a decrement).
    @ViewBuilder
    private func customOutcomePad(group: StuntGroup) -> some View {
        VStack(spacing: 6) {
            Text("ISSUES · \(group.name.uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.7)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(customOutcomes) { o in
                    let c = customCount(o, group: group)
                    HStack(spacing: 7) {
                        Circle().fill(o.color).frame(width: 8, height: 8)
                        Text(o.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Text("\(c)")
                            .font(Theme.barlow(18, .bold))
                            .monospacedDigit()
                            .foregroundStyle(c == 0 ? Theme.label3 : Theme.label)
                            .contentTransition(.numericText(value: Double(c)))
                            .animation(.spring(duration: 0.3), value: c)
                    }
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.well.shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1)))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(o.color.opacity(0.35), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { addCustom(o, group) }
                    .onLongPressGesture(minimumDuration: 0.4) { removeCustom(o, group) }
                    .accessibilityLabel("Log \(o.name)")
                    .accessibilityValue("\(c) logged for \(group.name)")
                    .accessibilityHint("Tap to add one, hold to remove one")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// This session's tally count of a custom outcome on one skill.
    private func customCount(_ o: CustomOutcome, group: StuntGroup) -> Int {
        session.customTallies.filter { $0.outcome?.id == o.id && $0.group === group }.count
    }

    private func addCustom(_ o: CustomOutcome, _ group: StuntGroup) {
        context.insert(CustomTally(outcome: o, group: group, session: session))
        try? context.save()
        hapticTrigger += 1
    }

    /// Remove the most recent tally of this outcome+skill (long-press undo).
    private func removeCustom(_ o: CustomOutcome, _ group: StuntGroup) {
        let mine = session.customTallies
            .filter { $0.outcome?.id == o.id && $0.group === group }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = mine.last else { return }
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

/// Staging key: a rep is staged against one (skill, subject) cell. Both pivots
/// use the same key — the pinned axis is fixed, the row axis varies.
private struct StageKey: Hashable {
    let group: PersistentIdentifier
    let subject: PersistentIdentifier
    init(_ g: StuntGroup, _ s: Subject) {
        self.group = g.persistentModelID
        self.subject = s.persistentModelID
    }
}

/// "On fire" chrome: a slow warm gradient sweeping around a row label once its
/// cell has 3+ straight hits. The one sanctioned flame on the training floor
/// (Ian asked for it 2026-06-11) — keep it small and warm, never sparkle.
private struct FireBorder: ViewModifier {
    let active: Bool
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.5) / 2.5
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AngularGradient(
                            colors: [Theme.fireHot, Theme.fireWarm, Theme.fireHot.opacity(0.25),
                                     Theme.fireWarm, Theme.fireHot],
                            center: .center, angle: .degrees(t * 360)), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
