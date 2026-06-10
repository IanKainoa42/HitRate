import SwiftUI
import SwiftData
import Combine

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

    @State private var selectedGroup: StuntGroup?
    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

    // Wave/Routine staging (grid only): stage one outcome per bucket, then
    // commit the whole batch at once so simultaneous groups — or every skill
    // in a routine — can't get double-logged. `waveMode` persists; `staged`
    // holds the pending outcome per group; `lastWave` is the just-committed
    // batch, kept for one-tap Undo.
    @AppStorage("waveMode") private var waveMode = false
    @State private var staged: [PersistentIdentifier: Outcome] = [:]
    @State private var lastWave: [Attempt] = []

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    /// The group the pad logs into. Validates membership so a selection that
    /// was deleted in the editor can't receive new attempts (deleted SwiftData
    /// models crash on property access).
    private var activeGroup: StuntGroup? {
        if let sel = selectedGroup, groups.contains(where: { $0 === sel }) { return sel }
        return groups.first
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
    /// Staged buckets among the CURRENT roster — a deleted group's stale key
    /// can't false-trigger the all-staged auto-commit.
    private var stagedCount: Int { groups.filter { staged[$0.persistentModelID] != nil }.count }
    /// Coach mental model is a wave of stunt groups; athlete is a routine pass.
    private var waveNoun: String { mode == .coach ? "wave" : "routine" }

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
                        Button {
                            selectedGroup = g
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
                            selectedGroup = group
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
            Text(waveActive ? "TAP CELLS TO STAGE A \(waveNoun.uppercased())" : "TAP A CELL TO LOG A REP")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Column headers — one kind (see gridAvailable), via OutcomeNames.
            HStack(spacing: 6) {
                Color.clear.frame(width: 78, height: 1)
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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(groups) { g in
                        let c = countsFor(group: g, in: attempts)
                        HStack(spacing: 6) {
                            // Row label — colored number badge + name.
                            HStack(spacing: 6) {
                                Text("\(g.number)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(g.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                Text(g.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(width: 78, alignment: .leading)

                            ForEach(Outcome.allCases) { o in
                                let v = c[o.rawValue]
                                let isStaged = waveActive && staged[g.persistentModelID] == o
                                Button {
                                    if waveActive {
                                        toggleStage(g, o)
                                    } else {
                                        context.insert(Attempt(outcome: o, group: g, session: session))
                                        try? context.save()
                                        hapticTrigger += 1
                                        Sounds.shared.play(.outcome(o))
                                    }
                                } label: {
                                    Text("\(v)")
                                        .font(Theme.barlow(20, .extrabold))
                                        .monospacedDigit()
                                        .foregroundStyle(isStaged ? o.color : (v == 0 ? Theme.label3 : Theme.label))
                                        .contentTransition(.numericText(value: Double(v)))
                                        .animation(.spring(duration: 0.3), value: v)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Theme.well
                                                    .shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1))
                                                    .shadow(.inner(color: o.color.opacity(0.85), radius: 1, y: -2)))
                                        )
                                        // Staged cell stays lit until the wave commits.
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(o.color, lineWidth: isStaged ? 2.5 : 0)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(waveActive ? "Stage" : "Log") \(o.label(gridKind)) for \(g.name)")
                                .accessibilityValue("\(v)\(isStaged ? ", staged" : "")")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
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

    /// Docked under the matrix in wave mode. While staging: count + Clear +
    /// Submit (partial commit). After a commit (nothing staged): Undo. The
    /// all-staged auto-commit happens in `toggleStage`; this is the manual
    /// partial-submit and step-back surface.
    private var waveBar: some View {
        HStack(spacing: 10) {
            Text("\(stagedCount) OF \(groups.count) \(mode.nounPlural.uppercased()) STAGED")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label2)
            Spacer()
            if stagedCount > 0 {
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
                    Text("Submit \(stagedCount)")
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

    /// Tap a cell in wave mode: set this group's pending outcome, or clear it
    /// if the same outcome was already staged. Auto-commits once the whole
    /// roster is staged.
    private func toggleStage(_ g: StuntGroup, _ o: Outcome) {
        let id = g.persistentModelID
        if staged[id] == o { staged[id] = nil } else { staged[id] = o }
        hapticTrigger += 1
        Sounds.shared.play(.outcome(o))
        if stagedCount == groups.count && !groups.isEmpty { commitWave() }
    }

    /// Write one Attempt per staged group, then clear the staging row. Keeps
    /// the batch in `lastWave` so it can be pulled back in one tap.
    private func commitWave() {
        let waveID = UUID()   // ties this batch together for the grouped log container
        var committed: [Attempt] = []
        for g in groups {
            if let o = staged[g.persistentModelID] {
                let a = Attempt(outcome: o, group: g, session: session, waveID: waveID)
                context.insert(a)
                committed.append(a)
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
            Spacer()
            if !inWave {
                Text(a.timestamp.tapeTime)
                    .font(Theme.barlow(13, .semibold))
                    .foregroundStyle(Theme.label3)
            }
        }
        .padding(.vertical, 7)
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

    /// The grid's compact bottom recent strip — an ESPN/CheerCenter-style
    /// continuous marquee: a pinned Undo on the left, then the rep chips scroll
    /// right-to-left forever, looping seamlessly (`MarqueeRow`). Wave/routine reps
    /// ride together in a bordered cluster. Display-only motion over HitRate's
    /// engraved floor chips — no scoreboard skin; frees the room for the group rows.
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
                MarqueeRow(spacing: 6, loopGap: 50, speed: 30) {
                    ForEach(segs) { tickerChip($0) }
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
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for a in attempts where a.group === group {
            counts[a.outcomeRaw] += 1
        }
        return counts
    }
}

// MARK: - Marquee

/// ESPN/CheerCenter-style horizontal marquee. Lays its content in a row and
/// scrolls it right-to-left forever, looping seamlessly by drawing the row twice
/// and wrapping the offset at one content-width (+ gap). Display-only — no
/// gestures. The width is read directly from a GeometryReader background (a
/// PreferenceKey would not propagate out of this tree) and fed to a 60fps timer
/// engine that drives the offset.
private struct MarqueeRow<Content: View>: View {
    private let spacing: CGFloat        // gap between chips inside one copy
    private let loopGap: CGFloat        // gap before the loop repeats (CheerCenter: 50)
    private let content: Content
    @StateObject private var engine: MarqueeEngine

    init(spacing: CGFloat = 6, loopGap: CGFloat = 50, speed: CGFloat = 30,
         @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.loopGap = loopGap
        self.content = content()
        _engine = StateObject(wrappedValue: MarqueeEngine(speed: speed))
    }

    var body: some View {
        // GeometryReader is a flexible-width host so the wide content can't stretch
        // the screen. The doubled HStack is a STABLE structure (not regenerated per
        // frame) — its `.offset` is driven by an external timer engine, and its
        // width is measured here and fed to the engine (this is the placement that
        // actually propagates; measuring inside a TimelineView did not).
        GeometryReader { _ in
            HStack(spacing: loopGap) {
                row.background(GeometryReader { g -> Color in
                    let w = g.size.width
                    DispatchQueue.main.async { engine.setWidth(w + loopGap) }
                    return Color.clear
                })
                row
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxHeight: .infinity, alignment: .center)
            .offset(x: engine.offset)
            .animation(nil, value: engine.offset)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var row: some View {
        HStack(spacing: spacing) { content }
    }
}

/// Drives the marquee offset off a 60fps timer; resets seamlessly at one
/// content-width so the duplicated row loops without a seam. Mirrors
/// CheerCenter's ScoringTickerView coordinator.
@MainActor
private final class MarqueeEngine: ObservableObject {
    @Published var offset: CGFloat = 0
    private let speed: CGFloat          // points per second
    private var width: CGFloat = 0
    private var cancellable: AnyCancellable?

    init(speed: CGFloat) { self.speed = speed }

    func setWidth(_ w: CGFloat) {
        guard w != width else { return }
        width = w
        offset = 0
        cancellable?.cancel()
        guard w > 0 else { return }
        cancellable = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.width > 0 else { return }
                self.offset -= self.speed / 60.0
                if self.offset <= -self.width { self.offset = 0 }
            }
    }
}
