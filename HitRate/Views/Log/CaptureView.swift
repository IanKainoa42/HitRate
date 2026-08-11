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
/// One tap logs one Attempt directly to disk with immediate auto-save and undo.
struct CaptureView: View {
    let session: PracticeSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Subject.orderIndex) private var allSubjects: [Subject]
    @Query(sort: \Team.orderIndex) private var teams: [Team]

    /// Co-logging: who's logging. Every rep is stamped with this uid at creation
    /// so the coach/athlete split reads right on the floor, before any sync.
    @EnvironmentObject private var auth: AuthViewModel

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""

    /// What's pinned at the top: "skill" (rows = subjects) or "subject" (rows = skills).
    @AppStorage("capturePivot") private var pivotRaw = "skill"
    /// The pivot the user picked before a 1-on-1 lock borrowed `capturePivot`.
    /// Blank = no lock is holding it. Restored when the lock releases.
    @AppStorage("capturePivotBeforeLock") private var pivotBeforeLockRaw = ""
    /// Pinned skill (skill pivot) / pinned subject (subject pivot). Persisted so the
    /// watch can mirror the pulled-up skill and the screen remembers between practices.
    @AppStorage("selectedGroupID") private var selectedGroupIDRaw = ""
    @AppStorage("selectedSubjectID") private var selectedSubjectIDRaw = ""

    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false
    /// The rep whose optional EXECUTION read (Feature B) is open, if any. Tapping a
    /// recent chip on a United-category skill sets this and presents the sheet.
    @State private var scoringAttempt: Attempt?

    // 1-Tap Auto-Save Logging state: stores last logged rep for floating 3s undo toast.
    @State private var lastLoggedRep: Attempt? = nil
    @State private var lastLoggedToastText: String = ""
    @State private var toastResetTask: Task<Void, Never>? = nil

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }
    private var currentTeam: Team? { teams.current(id: currentTeamID) }

    /// Practice logs into the active team's roster only.
    private var groups: [StuntGroup] { allGroups.inTeam(currentTeam) }
    private var subjects: [Subject] { allSubjects.inTeam(currentTeam) }

    /// A folder MORE THAN ONE PERSON logs into — the only place the coach vs
    /// athlete split means anything.
    private var isCoLogged: Bool {
        guard let team = currentTeam else { return false }
        if !team.memberIds.isEmpty { return true }          // you own it, others joined
        if let owner = team.ownerUID, owner != auth.uid { return true }   // you joined it
        return false
    }

    private enum Pivot: String { case skill, subject }

    /// A 1-on-1 folder — exactly one subject on the roster ("Maya — Privates").
    private var isSingleAthleteFolder: Bool { subjects.count == 1 }

    /// What's pinned. A 1-on-1 folder is LOCKED to its single subject (rows =
    /// skills) regardless of the stored pivot.
    private var pivot: Pivot {
        if isSingleAthleteFolder { return .subject }
        return Pivot(rawValue: pivotRaw) ?? .skill
    }

    /// The pinned skill (skill pivot). Resolves the persisted id against the CURRENT
    /// roster so a deleted selection can't receive reps.
    private var pinnedSkill: StuntGroup? {
        groups.first { $0.id.uuidString == selectedGroupIDRaw } ?? groups.first
    }
    /// The pinned subject (subject pivot). Same defensive resolution.
    private var pinnedSubject: Subject? {
        subjects.first { $0.id.uuidString == selectedSubjectIDRaw } ?? subjects.first
    }

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
                .sheet(item: $scoringAttempt) { ExecutionSheet(attempt: $0) }
                .onAppear {
                    seedFirstSubjectIfNeeded()
                    syncSingleSubjectLock()
                }
                .onChange(of: subjects.count) { _, _ in syncSingleSubjectLock() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private func seedFirstSubjectIfNeeded() {
        guard let team = currentTeam, !groups.isEmpty, subjects.isEmpty else { return }
        let s = Subject(name: "", kind: subjectKind, orderIndex: 0)
        s.team = team
        context.insert(s)
        try? context.save()
        selectedSubjectIDRaw = s.id.uuidString
    }

    private func syncSingleSubjectLock() {
        guard isSingleAthleteFolder, let only = subjects.first else {
            releaseSubjectLock()
            return
        }
        if pivotRaw != Pivot.subject.rawValue {
            pivotBeforeLockRaw = pivotRaw          // stash what the user chose
            pivotRaw = Pivot.subject.rawValue
        }
        if selectedSubjectIDRaw != only.id.uuidString {
            selectedSubjectIDRaw = only.id.uuidString
        }
    }

    private func releaseSubjectLock() {
        guard !pivotBeforeLockRaw.isEmpty else { return }
        pivotRaw = pivotBeforeLockRaw
        pivotBeforeLockRaw = ""
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
                if !customOutcomes.isEmpty, let skill = pinnedSkill,
                   pivot == .skill || isSingleAthleteFolder {
                    customOutcomePad(group: skill, showsSkillPicker: isSingleAthleteFolder)
                }
                autoSaveToastBar
                recentTicker(attempts)
            }
        }
    }

    // MARK: Header (reps + weighted rate + END)

    @ViewBuilder
    private func header(_ attempts: [Attempt]) -> some View {
        let rate = attempts.isEmpty ? nil
            : Int((Double(attempts.filter(\.isHitRep).count) / Double(attempts.count) * 100).rounded())

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
                Text(rate.map { "REPS · \($0)% HIT" } ?? "1-TAP LOGGING · INSTANT AUTO-SAVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.label2)
            }
            Spacer()
            Button {
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

    @ViewBuilder
    private var pivotBar: some View {
        if isSingleAthleteFolder, let only = subjects.first {
            singleAthleteBar(only)
        } else {
            standardPivotBar
        }
    }

    private func singleAthleteBar(_ subject: Subject) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subject.kind == .person ? "person.circle.fill" : "person.3.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(subject.isUnnamed
                 ? "LOGGING FOR ONE \(subject.kind.label.uppercased())"
                 : "LOGGING FOR \(subject.name.uppercased())")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)

            Button { addSubject() } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 34, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.iconTile))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { addSkill() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.iconTile))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var standardPivotBar: some View {
        HStack(spacing: 10) {
            Text("PIN")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
            MiniSeg(options: ["Skill", subjectKind.label],
                    selection: Binding(
                        get: { pivot == .skill ? "Skill" : subjectKind.label },
                        set: { newValue in
                            pivotRaw = (newValue == "Skill") ? "skill" : "subject"
                            hapticTrigger += 1
                        }))
            Spacer()
            Button { pivot == .skill ? addSkill() : addSubject() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.iconTile))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Pin picker

    @ViewBuilder
    private var pinPicker: some View {
        if isSingleAthleteFolder {
            EmptyView()
        } else {
            standardPinPicker
        }
    }

    private var standardPinPicker: some View {
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
                        Text("Add \(subjectNoun == "athlete" ? "an athlete" : "a stunt group") to pin")
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

    private var namingTarget: Subject? {
        subjects.first { $0.id.uuidString == selectedSubjectIDRaw && $0.isUnnamed }
    }

    private var rosterNames: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in subjects where !s.isUnnamed {
            if seen.insert(s.name).inserted { out.append(s.name) }
        }
        return out
    }

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
                    }
                    ForEach(rosterNames, id: \.self) { name in
                        suggestionChip(name, taken: true)
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

    @ViewBuilder
    private func skillPinnedMatrix(_ attempts: [Attempt]) -> some View {
        if let skill = pinnedSkill {
            let defs = skill.outcomeDefs
            VStack(spacing: 8) {
                RenameField(prompt: "Name this skill", value: skill.name) { new in
                    skill.name = new
                    try? context.save()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(skill.isUnnamed ? Theme.label3 : Theme.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                // EXPLICIT OUTCOME HEADERS
                HStack(spacing: 6) {
                    Color.clear.frame(width: rowLabelWidth, height: 1)
                    ForEach(Array(defs.enumerated()), id: \.offset) { _, def in
                        Text(def.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(def.color)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1).minimumScaleFactor(0.5)
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
                                .frame(minHeight: 58)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func subjectPinnedMatrix(_ attempts: [Attempt]) -> some View {
        if let subject = pinnedSubject {
            VStack(spacing: 8) {
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
                            .frame(minHeight: 58)
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

    /// One matrix cell — 1-TAP DIRECT AUTO-SAVE LOGGING.
    @ViewBuilder
    private func matrixCell(group: StuntGroup, subject: Subject, slot: Int, def: OutcomeDef, v: Int) -> some View {
        cellVisual(v: v, def: def)
            .onTapGesture {
                logDirect(group: group, subject: subject, slot: slot, def: def)
            }
            .accessibilityLabel("Log \(def.label) for \(subject.displayName)")
            .accessibilityValue("\(v) logged")
            .accessibilityHint("1-tap to log immediately")
    }

    /// Engraved cell face with explicit outcome label.
    private func cellVisual(v: Int, def: OutcomeDef) -> some View {
        VStack(spacing: 1) {
            Text("\(v)")
                .font(Theme.barlow(20, .extrabold))
                .monospacedDigit()
                .foregroundStyle(v == 0 ? Theme.label3 : Theme.label)
                .contentTransition(.numericText(value: Double(v)))
                .animation(.spring(duration: 0.3), value: v)
            Text(def.label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(def.color.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.5)
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
                .stroke(def.color.opacity(0.4), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: 1-Tap Auto-Save Toast Bar

    private var autoSaveToastBar: some View {
        HStack(spacing: 10) {
            if let lastRep = lastLoggedRep {
                HStack(spacing: 6) {
                    Circle().fill(lastRep.outcomeDef?.color ?? Theme.accent).frame(width: 8, height: 8)
                    Text(lastLoggedToastText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    undoLastDirectLog()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.hit)
                    Text("1-TAP AUTO-SAVE ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.label2)
                }
                Spacer()
                Text("TAP CELL TO LOG")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.label3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .wellBackground()
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: lastLoggedRep != nil)
    }

    // MARK: Direct 1-Tap Auto-Save Logic

    private func logDirect(group: StuntGroup, subject: Subject, slot: Int, def: OutcomeDef) {
        let a = Attempt(slot: slot, group: group, session: session, subject: subject)
        a.loggerID = auth.uid ?? ""
        context.insert(a)
        currentTeam?.isDemo = false
        try? context.save()

        let soundOutcome = def.soundOutcome
        Haptics.shared.play(soundOutcome)
        Sounds.shared.play(.outcome(soundOutcome))

        let targetName = subject.displayName.isEmpty ? group.displayName : subject.displayName
        lastLoggedToastText = "\(def.label.uppercased()) · \(targetName)"
        lastLoggedRep = a

        toastResetTask?.cancel()
        toastResetTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        lastLoggedRep = nil
                    }
                }
            }
        }
    }

    private func undoLastDirectLog() {
        guard let rep = lastLoggedRep else { return }
        SyncEngine.shared.queueDeletion(of: rep, in: context)
        context.delete(rep)
        try? context.save()
        lastLoggedRep = nil
        toastResetTask?.cancel()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
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
            Text("Add \(subjectNoun == "athlete" ? "an athlete" : "a stunt group") to start logging")
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
                            ForEach(attempts.reversed().prefix(15)) { repChip($0) }
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

    @ViewBuilder
    private func repChip(_ a: Attempt) -> some View {
        let scorable = a.group?.scoresExecution ?? false
        let byCoach = isCoLogged
            && a.isCoachLogged(teamOwnerUID: currentTeam?.ownerUID, currentUID: auth.uid)
        let body = HStack(spacing: 5) {
            Circle().fill(a.outcomeDef?.color ?? Theme.label3).frame(width: 7, height: 7)
            Text(a.subject?.displayName ?? a.group?.name ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
            Text(a.outcomeDef?.label.uppercased() ?? "—")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.label2)
                .lineLimit(1)
            if byCoach {
                Text("COACH")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent))
            }
            if a.executionScored {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(a.lostDrivers.isEmpty ? Theme.accent : Theme.buildingFall)
            }
        }
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.well.shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1)))
        )
        if scorable {
            Button { scoringAttempt = a } label: { body }
                .buttonStyle(.plain)
        } else {
            body
        }
    }

    private func addSkill() {
        guard let team = currentTeam else { return }
        let nextNum = (groups.map(\.number).max() ?? 0) + 1
        let nextOrder = (groups.map(\.orderIndex).max() ?? -1) + 1
        let g = StuntGroup(name: "", number: nextNum, orderIndex: nextOrder)
        g.category = pinnedSkill?.category ?? .stunts
        g.team = team
        context.insert(g)
        try? context.save()
        selectedGroupIDRaw = g.id.uuidString
        hapticTrigger += 1
    }

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
        SyncEngine.shared.queueDeletion(of: last, in: context)
        context.delete(last)
        try? context.save()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    private func hotStreak(group: StuntGroup, subject: Subject, in attempts: [Attempt]) -> Int {
        StatsEngine.currentLandingStreak(
            in: attempts.filter { $0.group === group && $0.subject === subject }
        )
    }

    @ViewBuilder
    private func flameBadge(_ streak: Int) -> some View {
        if streak >= 2 {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(streak >= 3 ? Theme.fireHot : Theme.fireWarm)
                .symbolEffect(.pulse, options: .repeating, isActive: streak >= 3)
        }
    }

    private var customOutcomes: [CustomOutcome] {
        (currentTeam?.customOutcomes ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    @ViewBuilder
    private func customOutcomePad(group: StuntGroup, showsSkillPicker: Bool = false) -> some View {
        VStack(spacing: 6) {
            if showsSkillPicker, groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(groups) { g in
                            pinChip(number: g.number, name: g.displayName, color: g.color,
                                    on: g === group) {
                                selectedGroupIDRaw = g.id.uuidString
                                hapticTrigger += 1
                            }
                        }
                    }
                }
            }
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
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func customCount(_ o: CustomOutcome, group: StuntGroup) -> Int {
        session.customTallies.filter { $0.outcome?.id == o.id && $0.group === group }.count
    }

    private func addCustom(_ o: CustomOutcome, _ group: StuntGroup) {
        context.insert(CustomTally(outcome: o, group: group, session: session))
        try? context.save()
        hapticTrigger += 1
    }

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
