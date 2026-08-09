import SwiftUI
import SwiftData
import CheerRulesKit

/// The four first-run focus areas. Each maps to a CheerRulesKit `SkillCategory`
/// — which carries that skill's execution drivers (the issues you tag a rep
/// against) — and seeds a set of suggested skill names. Pyramid folds into
/// Stunts and tumbling is one area (standing/running share identical drivers),
/// so the picker stays four wide.
enum OnboardingFocus: String, CaseIterable, Identifiable {
    case stunts, tumbling, jumps, tosses

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stunts: "Stunts"
        case .tumbling: "Tumbling"
        case .jumps: "Jumps"
        case .tosses: "Tosses"
        }
    }

    var category: SkillCategory {
        switch self {
        case .stunts: .stunts
        case .tumbling: .standingTumbling
        case .jumps: .jumps
        case .tosses: .tosses
        }
    }

    var icon: String { category.icon }

    var suggestions: [String] {
        switch self {
        case .stunts: ["Prep", "Extension", "Full up lib", "Released inversion"]
        case .tumbling: ["Roundoff", "Back walkover", "Back handspring", "Roundoff double HS"]
        case .jumps: ["Pencil jump", "Toe touch", "Left hurdler", "Right hurdler", "Pike", "Double toe touch"]
        case .tosses: ["Straight ride", "Full twist", "Kick full basket", "Double basket", "Kick double basket"]
        }
    }
}

/// First launch: choose who's counting (athlete vs coach), name the identity,
/// and create the first skills/groups. Nothing is pre-seeded — every bucket
/// in the app is one the user made. Rendered in the brand register ("court at
/// night") since it's the app's first impression.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.orderIndex) private var teams: [Team]
    @Query private var allGroups: [StuntGroup]
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("replayingIntro") private var replayingIntro = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("teamName") private var teamName = ""
    @AppStorage("currentTeamID") private var currentTeamID = ""

    @EnvironmentObject private var auth: AuthViewModel

    @State private var mode: AppMode?
    @State private var draft = ""
    @State private var focus: OnboardingFocus = .stunts
    @State private var pending: [(name: String, focus: OnboardingFocus)] = []   // skills created on finish

    // Step 0 — save/restore. Front-loaded on purpose: signing in here is the
    // ONLY path that RESTORES a previous install's folders, because
    // `linkOrSignIn` falls back to a plain sign-in on the "credential already
    // in use" collision. Buried in the editor, a returning user never finds it,
    // starts from zero, and mints another orphan team — which is how the cloud
    // ended up with ~4x more teams than users.
    @State private var accountStepDone = false
    /// Sign-in landed; holding the step while the listeners pull any existing
    /// roster down, so a restore doesn't race the "create your skills" flow.
    @State private var restoring = false

    // Step 3 — a real, hands-on first rep before landing on the (now
    // populated) dashboard. Only shown if the user actually added a skill.
    @State private var practiceStep = false
    @State private var practiceGroup: StuntGroup?
    @State private var practiceSession: PracticeSession?
    @State private var practiceTaps = 0

    /// Names already on the current roster — on an intro replay the chips
    /// shouldn't offer buckets the user already has.
    private var existingNames: Set<String> {
        Set(allGroups.inTeam(teams.current(id: currentTeamID) ?? teams.first).map(\.name))
    }
    private func available(_ suggestions: [String]) -> [String] {
        suggestions.filter { name in
            !pending.contains { $0.name == name } && !existingNames.contains(name)
        }
    }

    var body: some View {
        ZStack {
            CourtBackdrop()
                .ignoresSafeArea()
            if showAccountStep {
                accountStep
            } else if practiceStep, let group = practiceGroup, let session = practiceSession {
                practicePreview(group: group, session: session)
            } else if let mode {
                setup(mode)
            } else {
                chooser
            }
        }
        .animation(.easeOut(duration: 0.25), value: mode)
        .animation(.easeOut(duration: 0.25), value: practiceStep)
        .animation(.easeOut(duration: 0.25), value: accountStepDone)
        .onChange(of: auth.isUpgraded) { _, upgraded in
            guard upgraded, !accountStepDone else { return }
            watchForRestoredFolders()
        }
    }

    // MARK: Step 0 — save or restore

    /// An intro REPLAY is not a fresh install (the user still has their data),
    /// and an already-saved account has nothing to offer — skip both. `restoring`
    /// pins the step open so a successful sign-in can't flash past the chooser.
    private var showAccountStep: Bool {
        AccountPromptPolicy.showsOnboardingStep(dismissed: accountStepDone,
                                                isUpgraded: auth.isUpgraded,
                                                replayingIntro: replayingIntro,
                                                restoring: restoring)
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            IconWordmark(size: 34, rateFill: Theme.navy, dotSize: 15)
                .padding(.bottom, 2)
            Text(restoring ? "Looking for your reps…" : "Keep your reps safe")
                .font(Theme.grotesk(30))
                .foregroundStyle(.white)
            Text(restoring
                 ? "Signed in — checking whether you've logged with HitRate before."
                 : "Reps live on this phone unless you save them. Sign in and they follow you to a new phone — and if you've had HitRate before, this is how you get your folders back.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 10)

            if restoring {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("One moment")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.vertical, 6)
            } else {
                AccountSignInButtons()

                Button {
                    accountStepDone = true
                } label: {
                    Text("Not now")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    /// After a sign-in, give the Firestore listeners a window to deliver an
    /// existing roster. If one lands, this WAS a returning user: drop them
    /// straight into their restored folder instead of walking them through
    /// creating a duplicate one. Polls the context rather than the `teams`
    /// @Query because an escaping closure captures the query's value as it was
    /// when the closure was made, which would never show the arriving rows.
    private func watchForRestoredFolders() {
        restoring = true
        let context = self.context
        Task { @MainActor in
            for _ in 0..<32 {                       // ~8s at 250ms
                try? await Task.sleep(nanoseconds: 250_000_000)
                let live = ((try? context.fetch(FetchDescriptor<Team>())) ?? [])
                    .filter { $0.deletedAt == nil }
                guard let restored = live.first else { continue }
                currentTeamID = restored.id.uuidString
                restoring = false
                // Mode isn't recoverable from the cloud (it's device-local and
                // both modes share the same nouns), so keep whatever's stored —
                // it's one toggle in the editor if they had it the other way.
                completeOnboarding(AppMode(rawValue: appModeRaw) ?? .athlete)
                return
            }
            // Nothing came down: a genuinely new account. Carry on with setup —
            // the account is already saved, so their first folder is protected.
            restoring = false
            accountStepDone = true
        }
    }

    // MARK: Step 1 — who's counting

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            IconWordmark(size: 34, rateFill: Theme.navy, dotSize: 15)
                .padding(.bottom, 2)
            Text("Who's counting?")
                .font(Theme.grotesk(30))
                .foregroundStyle(.white)
            Text("Every stunt rep gets logged. Pick how you'll use it — you can switch later.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 10)

            modeCard(
                icon: "figure.gymnastics", tint: Theme.electric,
                title: "Just me",
                sub: "Track my own skills — every hit, bobble, and fall."
            ) { mode = .athlete }

            modeCard(
                icon: "person.3.fill", tint: Theme.coral,
                title: "I coach a team",
                sub: "Track multiple stunt groups across the floor."
            ) { mode = .coach }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func modeCard(icon: String, tint: Color, title: String, sub: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: tint.opacity(0.45), radius: 9, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.grotesk(18))
                        .foregroundStyle(.white)
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(15)
            .background(Theme.iconTile.opacity(0.74))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Theme.iconTileEdge.opacity(0.95), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2 — identity + first buckets

    private func setup(_ mode: AppMode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                self.mode = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            IconWordmark(size: 15, rateFill: Theme.navy, dotSize: 7)
                .padding(.top, 2)

            Text(mode == .athlete ? "Make it yours" : "Set up your floor")
                .font(Theme.grotesk(22))
                .foregroundStyle(.white)
            Text(mode == .athlete
                 ? "Your name goes on your cards."
                 : "Your program goes on the cards.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .athlete {
                        glassField("Your name", text: $athleteName)
                    } else {
                        glassField("Program (e.g. Cheer Force)", text: $orgName)
                        glassField("Team (e.g. Senior Coed)", text: $teamName)
                    }

                    // The headline ask — big and bold, not a faint caption.
                    Text("What skills do you want to track?")
                        .font(Theme.grotesk(22))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    Text("Pick a focus, then tap the skills you do. You can add more anytime.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))

                    focusPicker

                    ForEach(Array(pending.enumerated()), id: \.offset) { i, item in
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Theme.groupColor(i))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(item.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            HStack(spacing: 4) {
                                Image(systemName: item.focus.icon)
                                    .font(.system(size: 8, weight: .semibold))
                                Text(item.focus.label.uppercased())
                            }
                            .font(Theme.grotesk(8))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.07))
                            .clipShape(Capsule())
                            Spacer()
                            Button {
                                pending.remove(at: i)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        TextField("", text: $draft,
                                  prompt: Text("Add your own \(focus.label.lowercased()) skill")
                                    .foregroundStyle(.white.opacity(0.35)))
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .tint(Theme.electric)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1))
                            .onSubmit(addPending)
                        Button(action: addPending) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Suggested skills for the chosen focus. Tapping one still
                    // *creates* it, tagged with that focus's category (so its
                    // execution drivers are right from the first rep); nothing is
                    // pre-made. The field above adds your own.
                    suggestionHeader("\(focus.label.uppercased()) — SUGGESTED")
                    FlowChips(options: available(focus.suggestions)) { name in
                        pending.append((name, focus))
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            Button {
                startCounting(mode)
            } label: {
                HStack(spacing: 9) {
                    BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                    Text("Start counting")
                        .font(Theme.grotesk(16))
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }

    private func glassField(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text,
                  prompt: Text(prompt).foregroundStyle(.white.opacity(0.35)))
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Theme.electric)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func suggestionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.grotesk(9))
            .tracking(1.6)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.top, 2)
    }

    /// The four focus areas — each selects which suggested skills show AND which
    /// execution-driver set a created skill carries.
    private var focusPicker: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingFocus.allCases) { f in
                let on = focus == f
                Button { focus = f } label: {
                    VStack(spacing: 4) {
                        Image(systemName: f.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(f.label)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Theme.navy : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(on ? .white : .white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(on ? 0 : 0.14), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addPending() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        pending.append((name, focus))
        draft = ""
    }

    /// Commits the team + chosen skills, then either drops into a real
    /// first-rep practice step (if any skill was added) or completes
    /// onboarding outright.
    private func startCounting(_ mode: AppMode) {
        // Every bucket lives under a team. First launch creates it; an intro
        // REPLAY (Manage Data → Replay intro) keeps the existing roster and
        // tops it up instead — replaying must never fork a duplicate team.
        let team: Team
        if let existing = teams.current(id: currentTeamID) ?? teams.first {
            team = existing
        } else {
            let firstTeamName = mode == .coach
                ? (teamName.isEmpty ? "My Team" : teamName)
                : (athleteName.isEmpty ? "My Skills" : "\(athleteName)'s Skills")
            team = Team(name: firstTeamName, orderIndex: 0)
            context.insert(team)
        }
        let base = allGroups.filter { $0.team?.id == team.id }.count
        var created: [StuntGroup] = []
        for (i, item) in pending.enumerated() {
            let g = StuntGroup(name: item.name, number: base + i + 1,
                               orderIndex: base + i)
            g.team = team
            // Tag the skill's United category — this both sets the outcome kind
            // and carries the execution drivers (the issues you tag a rep with).
            g.category = item.focus.category
            context.insert(g)
            created.append(g)
        }
        try? context.save()
        currentTeamID = team.id.uuidString

        if let first = created.first {
            let s = PracticeSession()
            context.insert(s)
            try? context.save()
            practiceGroup = first
            practiceSession = s
            practiceStep = true
        } else {
            completeOnboarding(mode)
        }
    }

    private func completeOnboarding(_ mode: AppMode) {
        appModeRaw = mode.rawValue
        replayingIntro = false
        didOnboard = true
    }

    // MARK: Step 3 — try a real rep

    private func practicePreview(group: StuntGroup, session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            IconWordmark(size: 15, rateFill: Theme.navy, dotSize: 7)
                .padding(.top, 8)

            Text("Try logging a rep")
                .font(Theme.grotesk(22))
                .foregroundStyle(.white)
            Text(practiceTaps == 0
                 ? "This is exactly how practice works — tap what happens on \(group.name)."
                 : "Tap it again, or continue whenever you're ready.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 10) {
                Text("\(group.number)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(group.color)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(group.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(group.outcomeDefs.enumerated()), id: \.offset) { slot, def in
                    Button {
                        logPracticeTap(slot: slot, def: def, group: group, session: session)
                    } label: {
                        Text(def.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(def.color.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            Spacer()

            if practiceTaps > 0 {
                Text("\(practiceTaps) rep\(practiceTaps == 1 ? "" : "s") logged — that's the whole app.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 2)
            }

            Button {
                finishPractice()
            } label: {
                HStack(spacing: 9) {
                    BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                    Text(practiceTaps > 0 ? "Continue" : "Skip for now")
                        .font(Theme.grotesk(16))
                }
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }

    private func logPracticeTap(slot: Int, def: OutcomeDef, group: StuntGroup, session: PracticeSession) {
        context.insert(Attempt(slot: slot, group: group, session: session))
        try? context.save()
        Sounds.shared.play(.outcome(def.soundOutcome))
        withAnimation { practiceTaps += 1 }
    }

    private func finishPractice() {
        practiceSession?.endedAt = .now
        try? context.save()
        guard let mode else { return }
        completeOnboarding(mode)
    }
}

/// Tappable suggestion chips, wrapping rows of 3 — minimal flow layout stand-in.
private struct FlowChips: View {
    let options: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { name in
                Button {
                    onTap(name)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
