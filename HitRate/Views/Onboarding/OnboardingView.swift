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

/// First launch: name your DECK (one screen — the deck name plus a
/// mine/my-team's toggle that quietly sets AppMode), then MINT the first
/// cards. The old two-screen chooser+identity form dissolved into the card
/// metaphor 2026-08-19: every skill you track gets a card, blank until reps
/// fill it in (see CardStage.swift). Nothing is pre-seeded — every card in
/// the app is one the user minted. Rendered in the brand register ("court at
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
    @State private var pending: [(name: String, focus: OnboardingFocus)] = []   // cards minted on finish

    // Deck cover (step 1) — the deck name is buffered locally (it becomes the
    // Team name at commit, not an AppStorage field), and the mine/team toggle
    // is held as pendingMode until "Mint the first card" advances.
    @State private var deckName = ""
    @State private var pendingMode: AppMode = .athlete
    @State private var seededCover = false

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
    /// Per-outcome tally + a brief flash on the tile just tapped — the first
    /// tap in the app has to visibly land.
    @State private var practiceCounts: [Int: Int] = [:]
    @State private var practiceFlash: Int?
    @State private var practiceFlashTask: Task<Void, Never>?

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
                deckCover
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

    // MARK: Step 1 — the deck cover

    /// One screen instead of the old chooser+identity pair: name the deck,
    /// say whose it is (which quietly IS the athlete/coach mode choice — it
    /// only changes vocabulary and whose name rides the cards), and go mint.
    private var deckCover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            IconWordmark(size: 34, rateFill: Theme.navy, dotSize: 15)
                .padding(.bottom, 2)
            Text("Start your deck")
                .font(Theme.grotesk(30))
                .foregroundStyle(.white)
            Text("Every skill you track gets its own card — blank on day one, filled in by reps. It all lives in this deck.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 6)

            deckBox

            glassField("Name your deck (e.g. Ravens Black)", text: $deckName)

            HStack(spacing: 8) {
                ownershipPill(.coach, "My team's deck", icon: "person.3.fill")
                ownershipPill(.athlete, "Just mine", icon: "figure.gymnastics")
            }

            // The one identity the cards actually print — contextual, on the
            // same screen, no second form.
            if pendingMode == .athlete {
                glassField("Your name (goes on your cards)", text: $athleteName)
            } else {
                glassField("Program (e.g. Cheer Force)", text: $orgName)
            }

            Button {
                mode = pendingMode
            } label: {
                HStack(spacing: 9) {
                    BrandSignalDot(size: 9, color: Theme.accentText, shadowOpacity: 0)
                    Text("Mint the first card")
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
            .padding(.top, 2)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear {
            guard !seededCover else { return }
            seededCover = true
            pendingMode = AppMode(rawValue: appModeRaw) ?? .athlete
            // Intro replay: the deck already exists — show its name, don't
            // pretend it's a fresh mint.
            if deckName.isEmpty, replayingIntro,
               let existing = teams.current(id: currentTeamID) ?? teams.first {
                deckName = existing.name
            }
        }
    }

    /// The live deck-box preview — types along with the name field.
    private var deckBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("DECK")
                .font(Theme.grotesk(9))
                .tracking(1.8)
                .foregroundStyle(Theme.coral)
            Text(deckName.isEmpty ? "Your deck" : deckName)
                .font(Theme.grotesk(21))
                .foregroundStyle(.white.opacity(deckName.isEmpty ? 0.4 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
            Text("\(existingNames.count) card\(existingNames.count == 1 ? "" : "s") · \(seasonString())")
                .font(Theme.grotesk(9))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Color(hex: 0x141A2B), Color(hex: 0x0D1322)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.electric.opacity(0.5), lineWidth: 1.2))
    }

    private func ownershipPill(_ m: AppMode, _ title: String, icon: String) -> some View {
        let on = pendingMode == m
        return Button {
            pendingMode = m
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? Theme.navy : .white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(on ? .white : .white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(on ? 0 : 0.14), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2 — mint the first cards

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

            Text("Mint your cards")
                .font(Theme.grotesk(22))
                .foregroundStyle(.white)
            Text("A card for everything you'd change practice over — blank until reps fill it in. Pick a focus, tap to mint. You can mint more anytime.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    focusPicker

                    if !pending.isEmpty { mintedRail }

                    HStack(spacing: 10) {
                        TextField("", text: $draft,
                                  prompt: Text("Mint your own \(focus.label.lowercased()) card")
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

    // MARK: The minted cards

    /// Cards you've minted so far, as the CARDS they will be — not list rows.
    /// Rendered through the real `HoloCardView` at MINTED stage (no reps yet),
    /// never a second card view: one renderer is why the deck and this screen
    /// can't drift apart. Horizontal because 290×430 doesn't stack.
    private var mintedRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(pending.enumerated()), id: \.offset) { i, item in
                        mintedCard(item, index: i)
                            .id(i)
                    }
                }
                .padding(.vertical, 2)
            }
            // Ride to the card just minted — past three cards the newest one
            // lands off the rail, and an unseen card reads as a dropped tap.
            .onChange(of: pending.count) { _, count in
                guard count > 0 else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(count - 1, anchor: .trailing) }
            }
        }
        .frame(height: 430 * Self.mintScale + 4)
    }

    private static let mintScale: CGFloat = 0.42

    private func mintedCard(_ item: (name: String, focus: OnboardingFocus), index: Int) -> some View {
        let scale = Self.mintScale
        // No per-card rainbow color and no card NUMBER — a fresh card is known
        // by its name; the pip is a neutral mint mark until reps arrive.
        let spec = CardSpec(id: index + 1,
                            kicker: item.focus.label.uppercased(),
                            name: item.name,
                            badge: "◆",
                            color: Theme.electric,
                            rate: 0, counts: [0, 0, 0, 0], total: 0, delta: nil,
                            kind: item.focus.category.hitRateKind,
                            category: item.focus.category,
                            outcomeDefs: item.focus.category.defaultOutcomeDefs,
                            standing: CardStanding(reps: 0, badges: []))
        return HoloCardView(card: DeckCard(id: index, content: .stats(spec)),
                            index: index, count: pending.count,
                            orgName: cardOrgName, isSnapshot: true)
            .scaleEffect(scale)
            .frame(width: 290 * scale, height: 430 * scale)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { pending.remove(at: index) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove \(item.name)")
            }
            .transition(.scale.combined(with: .opacity))
    }

    /// Whose deck these cards belong to — the footer monogram.
    private var cardOrgName: String {
        let deck = deckName.trimmingCharacters(in: .whitespaces)
        if !deck.isEmpty { return deck }
        let identity = pendingMode == .coach ? orgName : athleteName
        return identity.isEmpty ? "My Deck" : identity
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
        // Every card lives under a team (the deck). First launch creates it;
        // an intro REPLAY (Manage Data → Replay intro) keeps the existing
        // roster and tops it up instead — replaying must never fork a
        // duplicate team.
        let namedDeck = deckName.trimmingCharacters(in: .whitespaces)
        let team: Team
        if let existing = teams.current(id: currentTeamID) ?? teams.first {
            team = existing
            // A REPLAY that retitled the deck cover renames the folder — it's
            // the same deck, not a new one. Gated on replayingIntro: outside a
            // replay, an existing team here means a cloud restore landed
            // mid-onboarding, and a blind-typed deck name must not clobber
            // the restored folder's real name.
            if replayingIntro, !namedDeck.isEmpty { team.name = namedDeck }
        } else {
            let fallback = mode == .coach
                ? (teamName.isEmpty ? "My Team" : teamName)
                : (athleteName.isEmpty ? "My Skills" : "\(athleteName)'s Skills")
            team = Team(name: namedDeck.isEmpty ? fallback : namedDeck, orderIndex: 0)
            context.insert(team)
        }
        // Keep the legacy teamName key in step for coach installs — folder
        // migration and the editor's identity section still read it.
        if mode == .coach, !namedDeck.isEmpty { teamName = namedDeck }
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

            Text(group.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Array(group.outcomeDefs.enumerated()), id: \.offset) { slot, def in
                    Button {
                        logPracticeTap(slot: slot, def: def, group: group, session: session)
                    } label: {
                        practiceTile(slot: slot, def: def)
                    }
                    .buttonStyle(PracticeTileStyle())
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

    /// One outcome tile. The running tally per outcome is the proof the rep
    /// LANDED (the caption at the bottom is too far from the thumb to read as
    /// confirmation); the flash ring is the moment it registers.
    private func practiceTile(slot: Int, def: OutcomeDef) -> some View {
        let count = practiceCounts[slot] ?? 0
        let flashing = practiceFlash == slot
        return ZStack(alignment: .topTrailing) {
            Text(def.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(def.color.opacity(flashing ? 1 : 0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(flashing ? 0.95 : 0), lineWidth: 2.5))

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(def.color)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white))
                    .padding(7)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityLabel(count > 0 ? "\(def.label), \(count) logged" : def.label)
    }

    private func logPracticeTap(slot: Int, def: OutcomeDef, group: StuntGroup, session: PracticeSession) {
        context.insert(Attempt(slot: slot, group: group, session: session))
        try? context.save()
        // Haptics first and always: tap sounds follow the ring/silent switch,
        // so on a silenced phone the sound alone left the very first tap in the
        // app with no feedback at all.
        Haptics.shared.play(def.soundOutcome)
        Sounds.shared.play(.outcome(def.soundOutcome))
        withAnimation(.spring(duration: 0.28)) {
            practiceTaps += 1
            practiceCounts[slot, default: 0] += 1
            practiceFlash = slot
        }
        practiceFlashTask?.cancel()
        practiceFlashTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { practiceFlash = nil }
                }
            }
        }
    }

    private func finishPractice() {
        practiceSession?.endedAt = .now
        try? context.save()
        guard let mode else { return }
        completeOnboarding(mode)
    }
}

/// Press feedback for the intro's outcome tiles. `.plain` gives none at all,
/// and this is the first thing anyone taps in the app — it has to feel like a
/// button going down, not a label.
private struct PracticeTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
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
