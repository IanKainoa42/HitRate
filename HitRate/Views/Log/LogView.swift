import SwiftUI
import SwiftData
import os

/// The counter, presented full-screen from Home's practice pill for the
/// duration of one session. Built for the floor: pick a group once, then
/// hammer one of four giant outcome buttons per rep. Full-surface tap
/// targets, haptics, undo. "End" is the only exit — it returns to Home
/// (an empty session is swept by Home on dismiss instead of being kept).
struct LogView: View {
    let session: PracticeSession
    var isClinic: Bool = false
    var goalRate: Int = 80
    var onArchive: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var allGroups: [StuntGroup]
    @Query(sort: \Team.orderIndex) private var teams: [Team]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("currentTeamID") private var currentTeamID = ""
    @AppStorage("practiceLayout") private var practiceLayoutRaw = ""   // "" auto, "grid", "pad"

    @State private var showSummary = false

    /// Practice logs into the active team's roster only.
    private var groups: [StuntGroup] { allGroups.inTeam(teams.current(id: currentTeamID)) }

    private var currentTeam: Team? { teams.current(id: currentTeamID) }

    /// The active folder's user-created outcomes (tap buttons below the 4).
    private var customOutcomes: [CustomOutcome] {
        (teams.current(id: currentTeamID)?.customOutcomes ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    @AppStorage("selectedGroupID") private var selectedGroupIDRaw = ""
    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

    @State private var staged: [PersistentIdentifier: [Int]] = [:]
    @State private var lastWave: [Attempt] = []

    private var mode: AppMode { AppMode(rawValue: appModeRaw) ?? .athlete }

    private var activeGroup: StuntGroup? {
        groups.first { $0.id.uuidString == selectedGroupIDRaw } ?? groups.first
    }

    private var gridAvailable: Bool { !groups.isEmpty }
    private var gridKind: SkillKind { groups.first?.kind ?? .stunt }
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
                    if newValue == "Pad", stagedReps > 0 { commitWave() }
                    practiceLayoutRaw = (newValue == "Grid") ? "grid" : "pad"
                })
    }

    private var waveActive: Bool { useGrid }
    private var stagedReps: Int {
        groups.reduce(0) { $0 + (staged[$1.persistentModelID]?.reduce(0, +) ?? 0) }
    }
    private var waveNoun: String { mode == .coach ? "wave" : "routine" }
    private var gridNameColumnWidth: CGFloat { 96 }

    var body: some View {
        NavigationStack {
            activeView
                .background(FloorBackdrop().ignoresSafeArea())
                .navigationTitle(isClinic ? "" : "Practice")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Text(isClinic ? "Clinic:" : "Practice")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.label)
                            if isClinic, let team = currentTeam {
                                RenameField(prompt: "Camp Name", value: team.name) { new in
                                    team.name = new
                                    try? context.save()
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: 150)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(mode.nounPluralTitle) { showGroupsEditor = true }
                    }
                }
                .sheet(isPresented: $showGroupsEditor) {
                    GroupsEditorView()
                }
                .fullScreenCover(isPresented: $showSummary, onDismiss: {
                    if isClinic {
                        dismiss()
                    }
                }) {
                    QuickClinicSummaryView(session: session, groups: groups, goalRate: goalRate) {
                        onArchive?()
                    } onDiscard: {
                    }
                }
        }
        .onAppear {
            let logger = Logger(subsystem: "com.ianrichardson.HitRate", category: "Clinic")
            logger.notice("🔵 LogView onAppear - isClinic: \(isClinic), groups: \(groups.count), allGroups: \(allGroups.count), teams: \(teams.count)")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: Active session

    private var activeView: some View {
        let attempts = session.sortedAttempts
        let hits = attempts.filter { $0.isHitRep }.count
        let rate = attempts.isEmpty ? nil
            : Int((Double(attempts.reduce(0) { $0 + $1.creditValue }) / Double(attempts.count)).rounded())

        return VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        IconWordmark(size: 11, rateFill: Theme.well, dotSize: 5)
                        Text(isClinic ? "CLINIC" : "PRACTICE")
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
                
                if isClinic, attempts.count > 0, let rate = rate {
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.fill)
                                Capsule()
                                    .fill(rate >= goalRate ? Theme.hit : Theme.buildingFall)
                                    .frame(width: geo.size.width * CGFloat(min(1.0, Double(rate) / Double(max(1, goalRate)))))
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(rate)% / \(goalRate)% GOAL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.label2)
                    }
                    .frame(width: 100)
                }
                
                Spacer()
                Button {
                    if stagedReps > 0 { commitWave() }
                    if !session.attempts.isEmpty {
                        session.endedAt = .now
                        try? context.save()
                    }
                    hapticTrigger += 1
                    Sounds.shared.play(.end)
                    if isClinic {
                        showSummary = true
                    } else {
                        dismiss()
                    }
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

            if gridAvailable {
                HStack(spacing: 10) {
                    Spacer()
                    MiniSeg(options: ["Grid", "Pad"], selection: layoutBinding)
                }
                .padding(.horizontal, 16)
            }

            if useGrid {
                logGrid(attempts)
                waveBar
            } else {
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

            if let group = activeGroup {
                let defs = group.outcomeDefs
                let groupCounts = countsFor(group: group, in: attempts)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                        let v = slot < groupCounts.count ? groupCounts[slot] : 0
                        Button {
                            context.insert(Attempt(slot: slot, group: group, session: session))
                            try? context.save()
                            selectedGroupIDRaw = group.id.uuidString
                            Haptics.shared.play(def.soundOutcome)
                            Sounds.shared.play(.outcome(def.soundOutcome))
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(v)")
                                    .font(Theme.barlow(34, .extrabold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.label)
                                    .contentTransition(.numericText(value: Double(v)))
                                    .animation(.spring(duration: 0.3), value: v)
                                Text(def.label.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(def.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 92)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.well
                                        .shadow(.inner(color: .black.opacity(0.6), radius: 4, y: 2))
                                        .shadow(.inner(color: def.color.opacity(0.9), radius: 1, y: -2)))
                                    .shadow(color: .white.opacity(0.05), radius: 0, y: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(def.label)")
                        .accessibilityValue("\(v) logged for \(group.name)")
                    }
                }
                .padding(.horizontal, 16)

                if !customOutcomes.isEmpty {
                    customOutcomePad(group: group)
                }
            } else {
                Text("Add a \(mode.noun) first (\(mode.nounPluralTitle), top right).")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.label2)
                    .padding(.top, 30)
            }
            }

            if useGrid {
                recentTicker(attempts)
            } else {
                recentWell(attempts)
            }
        }
    }

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

    @ViewBuilder
    private func logGrid(_ attempts: [Attempt]) -> some View {
        VStack(spacing: 8) {
            Text("1-TAP AUTO-SAVE LOGGING · TAP ANY CELL TO LOG REPS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("← good   ·   bad →")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .trailing)

            let gridRows = VStack(spacing: groups.count > 8 ? 4 : 6) {
                ForEach(groups) { g in
                        let defs = g.outcomeDefs
                        let c = countsFor(group: g, in: attempts)
                        let streakN = hotStreak(group: g, in: attempts)
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text("\(g.number)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(g.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                if isClinic {
                                    RenameField(prompt: "Mat Name", value: g.name) { new in
                                        g.name = new
                                        try? context.save()
                                    }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.label)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                                } else {
                                    Text(g.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(Theme.label)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.7)
                                }
                                flameBadge(streakN)
                            }
                            .padding(.vertical, groups.count > 8 ? 1 : 3)
                            .padding(.horizontal, 4)
                            .modifier(FireBorder(active: streakN >= 3, cornerRadius: 7))
                            .frame(width: gridNameColumnWidth, alignment: .leading)
                            .frame(maxHeight: .infinity)

                            ForEach(Array(defs.enumerated()), id: \.offset) { slot, def in
                                let v = slot < c.count ? c[slot] : 0
                                gridCellLabel(v, def: def)
                                    .onTapGesture {
                                        context.insert(Attempt(slot: slot, group: g, session: session))
                                        try? context.save()
                                        Haptics.shared.play(def.soundOutcome)
                                        Sounds.shared.play(.outcome(def.soundOutcome))
                                    }
                                    .accessibilityLabel("Log \(def.label) for \(g.name)")
                                    .accessibilityValue("\(v) logged")
                                    .accessibilityHint("Tap to log 1 rep immediately")
                            }
                        }
                        .frame(minHeight: 58)
                }
            }

            ScrollView(showsIndicators: false) { gridRows }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    private func gridCellLabel(_ v: Int, def: OutcomeDef) -> some View {
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
                .lineLimit(1)
                .minimumScaleFactor(0.5)
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
                    .stroke(def.color.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }

    private var waveBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.hit)
            Text("AUTO-SAVE LOGGING ACTIVE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.label2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .wellBackground()
        .padding(.horizontal, 16)
    }

    private func stagedCount(_ g: StuntGroup, _ slot: Int) -> Int {
        guard let arr = staged[g.persistentModelID], slot >= 0, slot < arr.count else { return 0 }
        return arr[slot]
    }

    private func stage(_ g: StuntGroup, _ slot: Int) {
        let n = g.outcomeDefs.count
        var c = staged[g.persistentModelID] ?? Array(repeating: 0, count: n)
        if c.count < n { c += Array(repeating: 0, count: n - c.count) }
        guard slot >= 0, slot < c.count else { return }
        c[slot] += 1
        staged[g.persistentModelID] = c
        let o = g.outcomeDef(at: slot)?.soundOutcome ?? .hit
        Haptics.shared.play(o)
        Sounds.shared.play(.outcome(o))
    }

    private func unstage(_ g: StuntGroup, _ slot: Int) {
        guard var c = staged[g.persistentModelID], slot >= 0, slot < c.count, c[slot] > 0 else { return }
        c[slot] -= 1
        staged[g.persistentModelID] = c.reduce(0, +) == 0 ? nil : c
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    private func commitWave() {
        let waveID = UUID()
        var committed: [Attempt] = []
        for g in groups {
            guard let c = staged[g.persistentModelID] else { continue }
            for (slot, n) in c.enumerated() where n > 0 {
                for _ in 0..<n {
                    let a = Attempt(slot: slot, group: g, session: session, waveID: waveID)
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

    private func undoWave() {
        let live = session.attempts
        for a in lastWave where live.contains(where: { $0 === a }) {
            SyncEngine.shared.queueDeletion(of: a, in: context)
            context.delete(a)
        }
        try? context.save()
        lastWave = []
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

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

    @ViewBuilder
    private func recentRow(_ a: Attempt, inWave: Bool = false) -> some View {
        HStack(spacing: 10) {
            Circle().fill(a.outcomeDef?.color ?? Theme.label3).frame(width: 8, height: 8)
            Text(a.group?.name ?? "—")
                .font(.system(size: 13, weight: .semibold))
            Text(a.outcomeDef?.label ?? "—")
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

    @ViewBuilder
    private func waveContainer(_ reps: [Attempt]) -> some View {
        let hits = reps.filter { $0.isHitRep }.count
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

    private func undoLastRep(_ attempts: [Attempt]) {
        guard let last = attempts.last else { return }
        SyncEngine.shared.queueDeletion(of: last, in: context)
        context.delete(last)
        try? context.save()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }

    @ViewBuilder
    private func recentTicker(_ attempts: [Attempt]) -> some View {
        let segs = Array(logSegments(attempts).reversed())
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

    private func repChip(_ a: Attempt) -> some View {
        HStack(spacing: 5) {
            Circle().fill(a.outcomeDef?.color ?? Theme.label3).frame(width: 7, height: 7)
            Text(a.group?.name ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
            Text(a.outcomeDef?.label.uppercased() ?? "—")
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

    @ViewBuilder
    private func customOutcomePad(group: StuntGroup) -> some View {
        VStack(spacing: 6) {
            Text("ISSUES")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Theme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(customOutcomes) { o in
                    let c = customCount(o, group: group)
                    HStack(spacing: 7) {
                        Circle().fill(o.color).frame(width: 8, height: 8)
                        Text(o.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
                            .fill(Theme.well
                                .shadow(.inner(color: .black.opacity(0.5), radius: 3, y: 1)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(o.color.opacity(0.35), lineWidth: 1)
                    )
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
        selectedGroupIDRaw = group.id.uuidString
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

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = Array(repeating: 0, count: group.outcomeDefs.count)
        for a in attempts where a.group === group {
            let slot = a.outcomeRaw
            if slot >= 0 && slot < counts.count { counts[slot] += 1 }
        }
        return counts
    }

    private func hotStreak(group: StuntGroup, in attempts: [Attempt]) -> Int {
        var run = 0
        for a in attempts.reversed() {
            guard a.group === group else { continue }
            guard a.isHitRep else { break }
            run += 1
        }
        return run
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
