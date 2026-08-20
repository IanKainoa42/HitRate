import SwiftUI
import SwiftData

/// Running a nine-pocket page: the page's cards laid out 3×3, an ARMED
/// outcome bar underneath — arm HIT and every pocket tap logs a hit for that
/// card; arm BOBBLE when someone breaks. Logging is 1-tap direct auto-save
/// with an undo toast, exactly like CaptureView's current idiom (the
/// Submit-wave model was retired 2026-08-11) — coaches call waves, so one
/// armed outcome + one tap per card is the fast path.
///
/// Session lifecycle mirrors CaptureView: the session is created by Home's
/// practice pill flow, END stamps `endedAt` only when reps exist, and Home's
/// cover `onDismiss` sweeps an empty live session (deleting a model the cover
/// still renders crashes mid-dismiss).
struct PageRunView: View {
    let page: PracticePage
    let session: PracticeSession
    let slots: [StuntGroup]           // resolved pocket order, dangling dropped

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @AppStorage("currentTeamID") private var currentTeamID = ""

    /// The armed severity slot (0–3, the fixed legacy-aligned slots every
    /// skill's outcome list leads with). Arming picks WHAT a tap logs; the
    /// pocket picks WHO it logs it for.
    @State private var armed: Outcome = .hit
    @State private var lastLoggedRep: Attempt?
    @State private var lastLoggedToastText = ""
    @State private var toastResetTask: Task<Void, Never>?
    @State private var hapticTrigger = 0

    private var currentTeam: Team? { teams.current(id: currentTeamID) }

    /// Aggregate wording for the armed bar — tumbling words only when every
    /// pocket is tumbling, stunt words otherwise (the FloorStats rule).
    private var barKind: SkillKind {
        slots.allSatisfy { $0.kind == .tumbling } && !slots.isEmpty ? .tumbling : .stunt
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            pocketGrid
            Spacer(minLength: 0)
            undoToastBar
            armedBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(FloorBackdrop().ignoresSafeArea())
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    // MARK: Header (page name + reps + END)

    private var header: some View {
        let attempts = session.attempts
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    IconWordmark(size: 11, rateFill: Theme.well, dotSize: 5)
                    Text("PAGE · \(page.name.uppercased())")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                }
                Text("\(attempts.count)")
                    .font(Theme.barlow(30, .extrabold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(attempts.count)))
                    .animation(.spring(duration: 0.3), value: attempts.count)
                    .foregroundStyle(Theme.label)
                Text("REPS · ARM AN OUTCOME, TAP A CARD")
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
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .wellBackground(cornerRadius: 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: Pockets

    private var pocketGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  spacing: 8) {
            ForEach(slots, id: \.persistentModelID) { g in
                pocket(g)
            }
            ForEach(0..<max(0, PracticePage.capacity - slots.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Theme.label3.opacity(0.25))
                    .frame(height: 104)
            }
        }
    }

    private func pocket(_ g: StuntGroup) -> some View {
        let count = session.attempts.filter { $0.group === g }.count
        let loggable = armedSlot(for: g) != nil
        // A gesture view, not a Button — house rule from the capture grid
        // (a Button fires on release even after a hold).
        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text("\(count)")
                .font(Theme.barlow(26, .extrabold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .animation(.spring(duration: 0.25), value: count)
                .foregroundStyle(count > 0 ? Theme.label : Theme.label3)
            Text(g.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.label2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .wellBackground()
        .opacity(loggable ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { log(g) }
        .accessibilityLabel("\(g.displayName), \(count) reps this session")
        .accessibilityHint("Logs \(armedDef(for: g)?.label ?? armed.label(barKind))")
    }

    // MARK: Armed outcome bar

    private var armedBar: some View {
        HStack(spacing: 6) {
            ForEach(Outcome.allCases) { o in
                let on = armed == o
                Button {
                    armed = o
                    hapticTrigger += 1
                } label: {
                    Text(o.short(barKind))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Theme.well : o.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(on ? AnyShapeStyle(o.color)
                                     : AnyShapeStyle(Theme.well.shadow(
                                        .inner(color: .black.opacity(0.5), radius: 3, y: 1)))))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(o.color.opacity(on ? 0 : 0.35), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(o.label(barKind))\(on ? ", armed" : "")")
            }
        }
    }

    // MARK: Undo toast

    @ViewBuilder
    private var undoToastBar: some View {
        if lastLoggedRep != nil {
            HStack(spacing: 10) {
                Text(lastLoggedToastText)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
                Spacer()
                Button {
                    undoLast()
                } label: {
                    Text("UNDO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .wellBackground()
            .transition(.opacity)
        }
    }

    // MARK: Logging (direct 1-tap auto-save, same contract as CaptureView)

    /// The armed severity's credit tier — for resolving custom outcome sets.
    private var armedTier: OutcomeCredit {
        switch armed {
        case .hit: .hit
        case .bobble: .decent
        case .buildingFall: .rough
        case .majorFall: .miss
        }
    }

    /// Which of this skill's outcome slots the armed severity logs. Category
    /// presets keep the first four slots severity-aligned, so the slot index
    /// is trusted directly. Custom types have NO slot contract (the built-in
    /// "Other" is just [Hit, Miss]) — blindly indexing would log a MISS when
    /// the bar says BOBBLE — so those match by credit tier instead, and a
    /// tier the skill doesn't have no-ops (the 40%-opacity pocket).
    private func armedSlot(for g: StuntGroup) -> Int? {
        let defs = g.outcomeDefs
        if !g.usesCustomType {
            return armed.rawValue < defs.count ? armed.rawValue : nil
        }
        return defs.firstIndex { $0.creditTier == armedTier }
    }

    private func armedDef(for g: StuntGroup) -> OutcomeDef? {
        armedSlot(for: g).flatMap { g.outcomeDef(at: $0) }
    }

    private func log(_ g: StuntGroup) {
        guard let slot = armedSlot(for: g), let def = g.outcomeDef(at: slot) else { return }
        let a = Attempt(slot: slot, group: g, session: session, subject: nil)
        a.loggerID = auth.uid ?? ""
        context.insert(a)
        // Real usage on a demo team resumes sync — same rule as every logger.
        currentTeam?.isDemo = false
        try? context.save()

        let soundOutcome = def.soundOutcome
        Haptics.shared.play(soundOutcome)
        Sounds.shared.play(.outcome(soundOutcome))

        lastLoggedToastText = "\(def.label.uppercased()) · \(g.displayName)"
        withAnimation { lastLoggedRep = a }

        toastResetTask?.cancel()
        toastResetTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled {
                await MainActor.run { withAnimation { lastLoggedRep = nil } }
            }
        }
    }

    private func undoLast() {
        guard let rep = lastLoggedRep else { return }
        SyncEngine.shared.queueDeletion(of: rep, in: context)
        context.delete(rep)
        try? context.save()
        withAnimation { lastLoggedRep = nil }
        toastResetTask?.cancel()
        hapticTrigger += 1
        Sounds.shared.play(.undo)
    }
}
