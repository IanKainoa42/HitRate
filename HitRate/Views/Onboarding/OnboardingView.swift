import SwiftUI
import SwiftData

/// First launch: choose who's counting (athlete vs coach), name the identity,
/// and create the first skills/groups. Nothing is pre-seeded — every bucket
/// in the app is one the user made. Rendered in the brand register ("court at
/// night") since it's the app's first impression.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("appMode") private var appModeRaw = AppMode.athlete.rawValue
    @AppStorage("athleteName") private var athleteName = ""
    @AppStorage("orgName") private var orgName = ""
    @AppStorage("teamName") private var teamName = ""

    @State private var mode: AppMode?
    @State private var draft = ""
    @State private var pending: [String] = []   // buckets created on finish

    private let skillSuggestions = ["Lib", "Stretch", "Full up", "Rewind", "Toss hands"]

    var body: some View {
        ZStack {
            backdrop
            if let mode {
                setup(mode)
            } else {
                chooser
            }
        }
        .animation(.easeOut(duration: 0.25), value: mode)
    }

    // MARK: Backdrop (matches the share-sheet court)

    private var backdrop: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0x1B2335), Color(hex: 0x0C1120), Color(hex: 0x06080F)],
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0, endRadius: 700)
            CourtGrid(cell: 30, lineColor: .white.opacity(0.05))
                .mask(RadialGradient(colors: [.white, .clear], center: UnitPoint(x: 0.5, y: 0.3),
                                     startRadius: 100, endRadius: 500))
            Circle()
                .fill(Theme.coral.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -140, y: -260)
            Circle()
                .fill(Theme.electric.opacity(0.13))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: 150, y: 280)
        }
        .ignoresSafeArea()
    }

    // MARK: Step 1 — who's counting

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("HITRATE")
                .font(Theme.grotesk(11))
                .tracking(3.3)
                .foregroundStyle(.white.opacity(0.5))
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
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1))
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

            Text(mode == .athlete ? "Make it yours" : "Set up your floor")
                .font(Theme.grotesk(26))
                .foregroundStyle(.white)
            Text(mode == .athlete
                 ? "Your name goes on your cards. Add the skills you're counting — or add them later."
                 : "Your program goes on the cards. Add your stunt groups — or add them later.")
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

                    Text(mode == .athlete ? "YOUR SKILLS" : "YOUR GROUPS")
                        .font(Theme.grotesk(10))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 6)

                    ForEach(Array(pending.enumerated()), id: \.offset) { i, name in
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Theme.groupColor(i))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
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
                                  prompt: Text(mode == .athlete ? "Skill name" : "Group \(pending.count + 1)")
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

                    if mode == .athlete {
                        // Starter ideas — tapping one still *creates* it; nothing is pre-made.
                        FlowChips(options: skillSuggestions.filter { !pending.contains($0) }) { name in
                            pending.append(name)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            Button {
                finish(mode)
            } label: {
                Text("Start counting")
                    .font(Theme.grotesk(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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

    private func addPending() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        let fallback = mode == .coach ? "Group \(pending.count + 1)" : ""
        let final = name.isEmpty ? fallback : name
        guard !final.isEmpty else { return }
        pending.append(final)
        draft = ""
    }

    private func finish(_ mode: AppMode) {
        for (i, name) in pending.enumerated() {
            context.insert(StuntGroup(name: name, number: i + 1, orderIndex: i))
        }
        try? context.save()
        appModeRaw = mode.rawValue
        didOnboard = true
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
