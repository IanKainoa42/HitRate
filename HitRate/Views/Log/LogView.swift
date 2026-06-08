import SwiftUI
import SwiftData

/// The counter, presented full-screen from Home's practice pill for the
/// duration of one session. Built for the floor: pick a group once, then
/// hammer one of four giant outcome buttons per rep. Full-surface tap
/// targets, haptics, undo. "End" is the only exit — it returns to Home
/// (an empty session is swept by Home on dismiss instead of being kept).
struct LogView: View {
    let session: PracticeSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StuntGroup.orderIndex) private var groups: [StuntGroup]

    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("practiceLayout") private var practiceLayoutRaw = ""   // "" auto, "grid", "pad"

    @State private var selectedGroup: StuntGroup?
    @State private var hapticTrigger = 0
    @State private var showGroupsEditor = false

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
                set: { practiceLayoutRaw = ($0 == "Grid") ? "grid" : "pad" })
    }

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
                VStack(alignment: .leading, spacing: 1) {
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
                                .stroke(Theme.majorFall.opacity(0.4), lineWidth: 1))
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
            if gridAvailable {
                HStack {
                    Spacer()
                    MiniSeg(options: ["Grid", "Pad"], selection: layoutBinding)
                }
                .padding(.horizontal, 16)
            }

            if useGrid {
                logGrid(attempts)
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
                            .background(on ? Theme.label : Theme.well)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(on ? .clear : Color.white.opacity(0.07), lineWidth: 1))
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

            // Recent + undo (well)
            VStack(spacing: 4) {
                HStack {
                    Text("RECENT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(Theme.label2)
                    Spacer()
                    Button {
                        if let last = attempts.last {
                            context.delete(last)
                            try? context.save()
                            hapticTrigger += 1
                            Sounds.shared.play(.undo)
                        }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(attempts.isEmpty ? Theme.label3 : Theme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(attempts.isEmpty)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(attempts.suffix(12).reversed())) { a in
                            HStack(spacing: 10) {
                                Circle().fill(a.outcome.color).frame(width: 8, height: 8)
                                Text(a.group?.name ?? "—")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(a.outcome.label(a.group?.kind ?? .stunt))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.label2)
                                Spacer()
                                Text(a.timestamp.tapeTime)
                                    .font(Theme.barlow(13, .semibold))
                                    .foregroundStyle(Theme.label3)
                            }
                            .padding(.vertical, 7)
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
            Text("TAP A CELL TO LOG A REP")
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
                                Button {
                                    context.insert(Attempt(outcome: o, group: g, session: session))
                                    try? context.save()
                                    hapticTrigger += 1
                                    Sounds.shared.play(.outcome(o))
                                } label: {
                                    Text("\(v)")
                                        .font(Theme.barlow(20, .extrabold))
                                        .monospacedDigit()
                                        .foregroundStyle(v == 0 ? Theme.label3 : Theme.label)
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
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Log \(o.label(gridKind)) for \(g.name)")
                                .accessibilityValue("\(v)")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
    }

    private func countsFor(group: StuntGroup, in attempts: [Attempt]) -> [Int] {
        var counts = [0, 0, 0, 0]
        for a in attempts where a.group === group {
            counts[a.outcomeRaw] += 1
        }
        return counts
    }
}
