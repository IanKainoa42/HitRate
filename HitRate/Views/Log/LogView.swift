import SwiftUI
import SwiftData
import CheerRulesKit

/// The counter, presented full-screen from Home's practice pill for the
/// duration of one session. Built for the floor: pick a group once, then
/// hammer one of four giant outcome buttons per rep. Full-surface tap
/// targets, haptics, undo. "End" is the only exit — it returns to Home
/// (an empty session is swept by Home on dismiss instead of being kept).
struct LogView: View {
    let session: PracticeSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Team.orderIndex) private var teams: [Team]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage("practiceLayout") private var practiceLayoutRaw = ""   // "" auto, "grid", "pad"

    /// Practice logs into the active team's roster only.
    private var groups: [StuntGroup] { allGroups.inTeam(teams.current(id: currentTeamID)) }

    /// Advanced opt-in (per folder): show the per-rep execution-driver dropdown
    /// in the recent log. Never affects the tap-to-submit pad.
    private var tracksDrivers: Bool { teams.current(id: currentTeamID)?.tracksDrivers ?? false }

    // Persisted (not @State) so the watch can mirror the pulled-up skill via
    // RootView's snapshot — and the pad remembers it between practices.
    @AppStorage("selectedGroupID") private var selectedGroupIDRaw = ""
    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

    // Wave/Routine staging (grid only): stage any number of reps per bucket
    // (tap +1, hold −1), then commit the whole batch at once. A group can
    // carry several outcomes in one pass (2 hits + a bobble), so staging is
    // a 4-slot count array per group, NOT one outcome — and commit is manual
    // only (with multi-staging there is no "everyone staged" finish line).
    // `waveMode` persists; `lastWave` is the just-committed batch for Undo.
    @AppStorage("waveMode") private var waveMode = false
    @State private var staged: [PersistentIdentifier: [Int]] = [:]
    @State private var lastWave: [Attempt] = []

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// The group the pad logs into. Resolves the persisted id against the
    /// CURRENT roster so a selection that was deleted in the editor can't
    /// receive new attempts (deleted SwiftData models crash on property access).
    private var activeGroup: StuntGroup? {
        groups.first { $0.id.uuidString == selectedGroupIDRaw } ?? groups.first
    }

    /// The tap-to-log matrix has ONE outcome-label header row, so it's only
    /// offered when every group shares a kind (coach is always all-stunt; a
    /// single-kind athlete also qualifies). Mixed-kind athletes stay on the
    /// per-skill pad, which labels each skill in its own kind's words.
    private var gridAvailable: Bool {
        !groups.isEmpty && Set(groups.map(\.kind)).count == 1
    }
    private var gridKind: SkillKind { groups.first?.kind ?? .stunt }
    /// Coach defaults to the matrix; athlete to the pad. Either flips via the
    /// Grid⇄Pad toggle (persisted in `practiceLayout`).
    private var useGrid: Bool {
        guard gridAvailable else { return false }
        switch practiceLayoutRaw {
        case "grid": return true
        case "pad": return false
        default: return mode == .coach
        }
    }
    private var layoutBinding: Binding<String> {
        Binding(get: { useGrid ? "Grid" : "Pad" },
                set: { newValue in
                    practiceLayoutRaw = (newValue == "Grid") ? "grid" : "pad"
                    if newValue == "Pad" { staged = [:] }   // leaving the grid drops pending stages
                })
    }

    /// Wave staging is grid-only; the switch is offered whenever the grid is.
    private var waveActive: Bool { useGrid && waveMode }
    /// Total staged reps among the CURRENT roster — a deleted group's stale
    /// key never counts.
    private var stagedReps: Int {
        groups.reduce(0) { $0 + (staged[$1.persistentModelID]?.reduce(0, +) ?? 0) }
    }
    /// Coach mental model is a wave of stunt groups; athlete is a routine pass.
    private var waveNoun: String { mode == .coach ? "wave" : "routine" }
    private var gridNameColumnWidth: CGFloat { 96 }

    var body: some View {
        NavigationStack {
            activeView
                .background(FloorBackdrop().ignoresSafeArea())
                .navigationTitle("Practice")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(mode.nounPluralTitle) { showGroupsEditor = true }
                    }
                }
                .sheet(isPresented: $showGroupsEditor) {
                    GroupsEditorView()
                }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: Active session

    private var activeView: some View {
        let attempts = session.sortedAttempts
        let hits = attempts.filter { $0.outcome.isHit }.count
        let rate = attempts.isEmpty ? nil : Int((Double(hits) / Double(attempts.count) * 100).rounded())

        return VStack(spacing: 9) {
            // Session header (well)
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
                    Text((rate.map { "REPS · \($0)% HIT" } ?? "REPS — LOG EACH AS IT LANDS"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label2)
                }
                Spacer()
                Button {
                    // A session with reps ends here; an empty one stays live
                    // and Home deletes it on dismiss (mutating-then-rendering
                    // a deleted model mid-animation crashes).
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

            // Layout toggle — grid is offered only for single-kind rosters.
            // The Wave/Routine switch rides alongside it, but only in Grid.
            if gridAvailable {
                HStack(spacing: 10) {
                    if useGrid { waveToggle }
                    Spacer()
                    MiniSeg(options: ["Grid", "Pad"], selection: layoutBinding)
                }
                .padding(.horizontal, 16)
            }

            if useGrid {
                logGrid(attempts)
                if waveActive { waveBar }
            } else {
            // Group picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(groups) { g in
                        let on = activeGroup === g
                        let streakN = hotStreak(group: g, in: attempts)
                        Button {
                            selectedGroupIDRaw = g.id.uuidString
                            hapticTrigger += 1
                        } label: {
                            HStack(spacing: 7) {
                                Text("\(g.number)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(g.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(g.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(on ? Theme.well : Theme.label)
                                flameBadge(streakN)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(on ? Theme.label : Theme.iconTile)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(on ? .clear : Theme.iconTileEdge.opacity(0.65), lineWidth: 1))
                            .modifier(FireBorder(active: streakN >= 3))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Outcome pad
            if let group = activeGroup {
                let groupCounts = countsFor(group: group, in: attempts)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(Outcome.allCases) { o in
                        Button {
                            context.insert(Attempt(outcome: o, group: group, session: session))
                            try? context.save()
                            selectedGroupIDRaw = group.id.uuidString
                            hapticTrigger += 1
                            Sounds.shared.play(.outcome(o))
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(groupCounts[o.rawValue])")
                                    .font(Theme.barlow(34, .extrabold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.label)
                                    .contentTransition(.numericText(value: Double(groupCounts[o.rawValue])))
                                    .animation(.spring(duration: 0.3), value: groupCounts[o.rawValue])
                                Text(o.label(group.kind).uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(o.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)   // "STEPPED OUT" must fit the pad button
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 92)
                            // Engraved well — the outcome color lives in the
                            // machined bottom edge + label, one material.
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.well
                                        .shadow(.inner(color: .black.opacity(0.6), radius: 4, y: 2))
                                        .shadow(.inner(color: o.color.opacity(0.9), radius: 1, y: -2)))
                                    .shadow(color: .white.opacity(0.05), radius: 0, y: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(o.label(group.kind))")
                        .accessibilityValue("\(groupCounts[o.rawValue]) logged for \(group.name)")
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Text("Add a \(mode.noun) first (\(mode.nounPluralTitle), top right).")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .padding(.top, 30)
            }
            }   // end of pad layout (else useGrid)

            // Recent — the grid collapses it to a swipeable bottom ticker so the
            // group rows get the room; the pad keeps the taller vertical list.
            if useGrid {
                recentTicker(attempts)
            } else {
                recentWell(attempts)
            }
        }
    }

    /// The taller vertical recent log (pad layout): wave/routine batches in
    /// bordered containers, one-at-a-time reps as flat rows, newest first.
    @ViewBuilder
    private func recentWell(_ attempts: [Attempt]) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.label2)
                Spacer()
                Button { undoLastRep(attempts) } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(attempts.isEmpty ? Theme.label3 : Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(attempts.isEmpty)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(logSegments(attempts).suffix(10).reversed())) { seg in
                        switch seg {
                        case .single(let a): recentRow(a)
                        case .wave(_, let reps): waveContainer(reps)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .wellBackground()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Tap-to-log matrix (groups × outcomes)

    /// The whole roster on one screen: a column per outcome, a row per group,
    /// every cell a tap-to-+1 button into this session. No group selection —
    /// tap "Bobble" on Group 1 and it adds a bobble to Group 1. Cells are the
    /// same engraved wells as the pad (outcome color in the machined edge, the
    /// running count in chalk Barlow); the column header names the outcome.
    @ViewBuilder
    private func logGrid(_ attempts: [Attempt]) -> some View {
        VStack(spacing: 8) {
            Text(waveActive ? "TAP TO STAGE \(waveNoun.uppercased()) REPS · HOLD TO REMOVE ONE" : "TAP A CELL TO LOG A REP")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Column headers — one kind (see gridAvailable), via OutcomeNames.
            HStack(spacing: 6) {
                Color.clear.frame(width: gridNameColumnWidth, height: 1)
                ForEach(Outcome.allCases) { o in
                    VStack(spacing: 3) {
                        Circle().fill(o.color).frame(width: 7, height: 7)
                        Text(o.short(gridKind))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(Theme.label2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            let gridRows = VStack(spacing: groups.count > 8 ? 4 : 6) {
                ForEach(groups) { g in
                        let c = countsFor(group: g, in: attempts)
                        let streakN = hotStreak(group: g, in: attempts)
                        HStack(spacing: 6) {
                            // Row label — colored number badge + name (+ flame
                            // once the group strings clean hits together).
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
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                flameBadge(streakN)
                            }
                            .padding(.vertical, groups.count > 8 ? 1 : 3)
                            .padding(.horizontal, 4)
                            .modifier(FireBorder(active: streakN >= 3, cornerRadius: 7))
                            .frame(width: gridNameColumnWidth, alignment: .leading)
                            .frame(maxHeight: .infinity)

                            ForEach(Outcome.allCases) { o in
                                let v = c[o.rawValue]
                                let stagedN = waveActive
                                    ? (staged[g.persistentModelID]?[o.rawValue] ?? 0) : 0
                                let cell = gridCellLabel(v, outcome: o, stagedN: stagedN)
                                Group {
                                    if waveActive {
                                        // NOT a Button: a Button fires its action on
                                        // release even after a hold, so a long-press
                                        // decrement would be re-incremented on lift.
                                        cell
                                            .onTapGesture { stage(g, o) }
                                            .onLongPressGesture(minimumDuration: 0.4) { unstage(g, o) }
                                    } else {
                                        Button {
                                            context.insert(Attempt(outcome: o, group: g, session: session))
                                            try? context.save()
                                            hapticTrigger += 1
                                            Sounds.shared.play(.outcome(o))
                                        } label: {
                                            cell
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .accessibilityLabel("\(waveActive ? "Stage" : "Log") \(o.label(gridKind)) for \(g.name)")
                                .accessibilityValue("\(v)\(stagedN > 0 ? ", \(stagedN) staged" : "")")
                                .accessibilityHint(waveActive ? "Tap to stage one more, hold to remove one" : "")
                            }
                        }
                        .frame(maxHeight: 50)
                }
            }

            if groups.count > 10 {
                ScrollView(showsIndicators: false) { gridRows }
            } else {
                gridRows
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    /// One engraved matrix cell: the session count in chalk, and — while
    /// staging — a "+n" pip in the outcome color showing this cell's pending
    /// reps. Shared by both the tap-to-log Button and the wave gesture view.
    private func gridCellLabel(_ v: Int, outcome o: Outcome, stagedN: Int) -> some View {
        Text("\(v)")
            .font(Theme.barlow(20, .extrabold))
            .monospacedDigit()
            .foregroundStyle(stagedN > 0 ? o.color : (v == 0 ? Theme.label3 : Theme.label))
            .contentTransition(.numericText(value: Double(v)))
            .animation(.spring(duration: 0.3), value: v)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.well
                        .shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1))
                        .shadow(.inner(color: o.color.opacity(0.85), radius: 1, y: -2)))
            )
            // Staged cell stays lit until the wave commits.
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(o.color, lineWidth: stagedN > 0 ? 2.5 : 0)
            )
            .overlay(alignment: .topTrailing) {
                if stagedN > 0 {
                    Text("+\(stagedN)")
                        .font(Theme.barlow(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.well)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(o.color))
                        .padding(3)
                }
            }
            .contentShape(Rectangle())
    }

    // MARK: Wave / Routine staging

    /// Compact caps pill that arms staging. Green-filled when on, chalk
    /// outline when off — one accent, no candy. Word adapts: WAVE / ROUTINE.
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

    /// Docked under the matrix in wave mode. While staging: rep count + Clear +
    /// Submit. After a commit (nothing staged): Undo. Commit is ALWAYS manual —
    /// with multi-rep staging there is no "everyone staged" finish line to
    /// auto-commit on.
    private var waveBar: some View {
        HStack(spacing: 10) {
            Text("\(stagedReps) REP\(stagedReps == 1 ? "" : "S") STAGED")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label2)
            Spacer()
            if stagedReps > 0 {
                Button {
                    staged = [:]
                    hapticTrigger += 1
                } label: {
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
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

    /// Tap a cell in wave mode: stage one more rep of that outcome for that
    /// group. No cap and no auto-commit — a group can carry several outcomes
    /// in one pass, so only the user knows when the batch is done (Submit).
    private func stage(_ g: StuntGroup, _ o: Outcome) {
        var c = staged[g.persistentModelID] ?? [0, 0, 0, 0]
        c[o.rawValue] += 1
        staged[g.persistentModelID] = c
        hapticTrigger += 1
        Sounds.shared.play(.outcome(o))
    }

    /// Hold a cell in wave mode: take one staged rep of that outcome back off.
    private func unstage(_ g: StuntGroup, _ o: Outcome) {
        guard var c = staged[g.persistentModelID], c[o.rawValue] > 0 else { return }
        c[o.rawValue] -= 1
        staged[g.persistentModelID] = c.reduce(0, +) == 0 ? nil : c
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    /// Write one Attempt per staged rep, then clear the staging row. Keeps
    /// the batch in `lastWave` so it can be pulled back in one tap.
    private func commitWave() {
        let waveID = UUID()   // ties this batch together for the grouped log container
        var committed: [Attempt] = []
        for g in groups {
            guard let c = staged[g.persistentModelID] else { continue }
            for (oi, n) in c.enumerated() where n > 0 {
                guard let o = Outcome(rawValue: oi) else { continue }
                for _ in 0..<n {
                    let a = Attempt(outcome: o, group: g, session: session, waveID: waveID)
                    context.insert(a)
                    committed.append(a)
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

    /// Step back: delete the whole last committed batch. Guards each attempt
    /// against having already been removed (e.g. via the Recent undo) so we
    /// never touch a deleted model.
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

    // MARK: Recent log (wave-grouped)

    /// One chunk of the recent log: either a wave (reps committed together) or a
    /// lone rep. Identifiable so the ForEach diffs cleanly.
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

    /// Collapse the chronological attempts into segments: maximal runs of the
    /// same non-nil `waveID` become one wave; nil-waveID reps stay singletons.
    /// (A wave's reps are always contiguous — committed in one pass.)
    private func logSegments(_ attempts: [Attempt]) -> [LogSegment] {
        var segs: [LogSegment] = []
        var i = 0
        while i < attempts.count {
            let a = attempts[i]
            if let wid = a.waveID {
                var reps = [a]
                var j = i + 1
                while j < attempts.count, attempts[j].waveID == wid {
                    reps.append(attempts[j]); j += 1
                }
                segs.append(.wave(wid, reps))
                i = j
            } else {
                segs.append(.single(a))
                i += 1
            }
        }
        return segs
    }

    /// One rep line. `inWave` drops the per-row time (the container header owns it).
    @ViewBuilder
    private func recentRow(_ a: Attempt, inWave: Bool = false) -> some View {
        HStack(spacing: 10) {
            Circle().fill(a.outcome.color).frame(width: 8, height: 8)
            Text(a.group?.name ?? "—")
                .font(.system(size: 13, weight: .semibold))
            Text(a.outcome.label(a.group?.kind ?? .stunt))
                .font(.system(size: 12))
                .foregroundStyle(Theme.label2)
            // Tagged drivers read inline so the coach sees them without opening
            // the menu.
            if tracksDrivers, !a.driverIDs.isEmpty {
                Text(driverSummary(a))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label3)
                    .lineLimit(1)
            }
            Spacer()
            if tracksDrivers {
                Menu { driverMenuItems(a) } label: { driverTagLabel(a) }
                    .buttonStyle(.plain)
            }
            if !inWave {
                Text(a.timestamp.tapeTime)
                    .font(Theme.barlow(13, .semibold))
                    .foregroundStyle(Theme.label3)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: Execution-driver tagging (advanced, off the tap path)

    /// Menu body shared by the pad row dropdown and the grid chip's long-press
    /// context menu: toggle each of the skill category's execution drivers
    /// (multi-select), with a Clear at the bottom once any are set.
    @ViewBuilder
    private func driverMenuItems(_ a: Attempt) -> some View {
        let drivers = (a.group?.category ?? .stunts).executionDrivers
        ForEach(drivers) { d in
            Button {
                toggleDriver(a, d.key)
            } label: {
                if a.driverIDs.contains(d.key) {
                    Label(d.name, systemImage: "checkmark")
                } else {
                    Text(d.name)
                }
            }
        }
        if !a.driverIDs.isEmpty {
            Divider()
            Button(role: .destructive) {
                a.driverIDs = []
                try? context.save()
                hapticTrigger += 1
            } label: {
                Label("Clear drivers", systemImage: "xmark.circle")
            }
        }
    }

    /// Compact dropdown affordance: a slider glyph, or a tag + count when set.
    private func driverTagLabel(_ a: Attempt) -> some View {
        HStack(spacing: 3) {
            Image(systemName: a.driverIDs.isEmpty ? "slider.horizontal.3" : "tag.fill")
                .font(.system(size: 12, weight: .semibold))
            if !a.driverIDs.isEmpty {
                Text("\(a.driverIDs.count)")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .foregroundStyle(a.driverIDs.isEmpty ? Theme.label3 : Theme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.iconTile))
        .contentShape(Rectangle())
    }

    private func toggleDriver(_ a: Attempt, _ key: String) {
        if let i = a.driverIDs.firstIndex(of: key) {
            a.driverIDs.remove(at: i)
        } else {
            a.driverIDs.append(key)
        }
        try? context.save()
        hapticTrigger += 1
    }

    /// Short names of a rep's tagged drivers, in the category's canonical order.
    private func driverSummary(_ a: Attempt) -> String {
        let drivers = (a.group?.category ?? .stunts).executionDrivers
        return drivers.filter { a.driverIDs.contains($0.key) }
            .map(\.name).joined(separator: ", ")
    }

    /// A committed wave/routine: hairline-bordered container with a batch-summary
    /// header (noun · reps · hit%) and its reps stacked inside.
    @ViewBuilder
    private func waveContainer(_ reps: [Attempt]) -> some View {
        let hits = reps.filter { $0.outcome.isHit }.count
        let pct = reps.isEmpty ? 0 : Int((Double(hits) / Double(reps.count) * 100).rounded())
        VStack(spacing: 1) {
            HStack {
                Text("\(waveNoun.uppercased()) · \(reps.count) REPS · \(pct)% HIT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.label3)
                Spacer()
                Text((reps.last ?? reps.first)?.timestamp.tapeTime ?? "")
                    .font(Theme.barlow(12, .semibold))
                    .foregroundStyle(Theme.label3)
            }
            .padding(.bottom, 2)
            ForEach(reps) { recentRow($0, inWave: true) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    /// Delete the most recent single rep (per-rep undo, shared by both layouts).
    private func undoLastRep(_ attempts: [Attempt]) {
        guard let last = attempts.last else { return }
        context.delete(last)
        try? context.save()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    /// The grid's compact bottom recent strip. A pinned Undo on the left, then a
    /// horizontally swipeable run of rep chips (newest at the leading edge, next
    /// to Undo). A tap — or any new rep — snaps back to the live edge. This keeps
    /// the strip readable and avoids a perpetual animation on the practice screen.
    @ViewBuilder
    private func recentTicker(_ attempts: [Attempt]) -> some View {
        let segs = Array(logSegments(attempts).reversed())   // newest-first
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

            if segs.isEmpty {
                Text("Reps land here as you log them")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label3)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Color.clear.frame(width: 0, height: 1).id("live")
                            ForEach(segs) { tickerChip($0) }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("live", anchor: .leading)
                            }
                        }
                    }
                    .onChange(of: attempts.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("live", anchor: .leading)
                        }
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

    /// One ticker entry: a lone rep is a single chip; a wave is its chips wrapped
    /// in a hairline cluster so the batch reads as one event.
    @ViewBuilder
    private func tickerChip(_ seg: LogSegment) -> some View {
        switch seg {
        case .single(let a):
            repChip(a)
        case .wave(_, let reps):
            HStack(spacing: 4) {
                ForEach(reps) { repChip($0) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1))
            )
        }
    }

    /// Engraved chip: outcome dot + group name + outcome short word.
    private func repChip(_ a: Attempt) -> some View {
        HStack(spacing: 5) {
            Circle().fill(a.outcome.color).frame(width: 7, height: 7)
            Text(a.group?.name ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
            Text(a.outcome.short(a.group?.kind ?? .stunt))
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
        // Grid layout has no per-row dropdown — long-press a chip to tag drivers
        // (an advanced gesture that never competes with tap-to-log).
        .overlay(alignment: .topTrailing) {
            if tracksDrivers, !a.driverIDs.isEmpty {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).padding(2)
            }
        }
        .contextMenu { if tracksDrivers { driverMenuItems(a) } }
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for a in attempts where a.group === group {
            guard let outcome = Outcome(rawValue: a.outcomeRaw) else { continue }
            counts[outcome.rawValue] += 1
        }
        return counts
    }

    // MARK: Hot streak (heating up / on fire)

    /// Trailing run of clean hits for one group in this session — fuel for the
    /// streak indicator. A bobble or fall breaks it (a bobble is NOT a hit,
    /// same rule as everywhere else). 2 = heating up, 3+ = on fire.
    private func hotStreak(group: StuntGroup, in attempts: [Attempt]) -> Int {
        var run = 0
        for a in attempts.reversed() {
            guard a.group === group else { continue }
            guard a.outcome == .hit else { break }
            run += 1
        }
        return run
    }

    /// Ember at 2 straight hits, pulsing flame at 3+. Rides next to the group
    /// name in both layouts.
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
}

/// "On fire" chrome: a slow warm gradient sweeping around the group's chip or
/// row label once it has 3+ straight hits. The one sanctioned flame on the
/// training floor — Ian asked for it (2026-06-11); keep it small and warm,
/// never sparkle.
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
