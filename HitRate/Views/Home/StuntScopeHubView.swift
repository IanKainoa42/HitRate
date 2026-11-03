import SwiftUI
import SwiftData

/// The StuntScope integration hub: shows connection status, capabilities, and allows
/// loading simulated telemetry so coaches and athletes can test the integration instantly.
struct StuntScopeHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthViewModel

    @Query private var groups: [StuntGroup]
    @Query private var subjects: [Subject]
    @Query private var sessions: [PracticeSession]

    @State private var seededSuccess = false

    private var activeUID: String? { auth.uid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusBanner
                    capabilitiesSection
                    comboExplanationSection
                    testSimulationSection
                }
                .padding(16)
            }
            .background(FloorBackdrop().ignoresSafeArea())
            .navigationTitle("StuntScope Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        FeedCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("PLUGGED IN & READY")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.4)
                            .foregroundStyle(Theme.accent)
                    }

                    Text("Shared Keychain & Neural Pipeline")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.label)

                    Text("HitRate & StuntScope share identity (`com.ianrichardson.shared`) and sync attempts seamlessly.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.label2)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Capabilities

    private var capabilitiesSection: some View {
        FeedCard {
            CardHead("TELEMETRY CAPABILITIES") {
                Text("StuntScope Exclusive")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 10) {
                featureRow(
                    icon: "scope",
                    title: "Flyer Center-of-Mass & Base Span",
                    desc: "Measures where the flyer's gravity line crosses sole height vs base wrist span."
                )
                Rectangle().fill(Theme.separator).frame(height: 1)

                featureRow(
                    icon: "timer",
                    title: "Active Hold & Hangtime Stopwatch",
                    desc: "Precision timing from bases' first hand contact to release, plus free flight hangtime."
                )
                Rectangle().fill(Theme.separator).frame(height: 1)

                featureRow(
                    icon: "waveform.path.ecg",
                    title: "Wobble & Excursion Detection",
                    desc: "Counts every stability dip outside the base of support and stamps the exact worst second."
                )
                Rectangle().fill(Theme.separator).frame(height: 1)

                featureRow(
                    icon: "person.2.badge.gearshape.fill",
                    title: "4-Position Stunt Group Auto-Tagging",
                    desc: "Flyer, Main Base, Side Base, Backspot tagged directly from the video take."
                )
                Rectangle().fill(Theme.separator).frame(height: 1)

                featureRow(
                    icon: "figure.gymnastics",
                    title: "Tumbling Launch & Rotational Kinematics",
                    desc: "Center-of-mass takeoff angles, in/out lean strokes, and flip/twist rotations per second."
                )
            }
        }
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label3)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Combo Explanation

    private var comboExplanationSection: some View {
        FeedCard {
            CardHead("THE HITRATE × STUNTSCOPE COMBO") {
                Text("SYNERGY")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("HitRate tracks if the stunt stays up. StuntScope tracks whether it fought for its life or was rock solid.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.label)

                Text("When you film stunts with StuntScope, HitRate automatically pairs the hit outcome with high-speed stability metrics to calculate your **Rock Solid Combo Rate** — the true mark of competition readiness.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label3)
            }
        }
    }

    // MARK: - Simulation

    private var testSimulationSection: some View {
        FeedCard {
            CardHead("TEST THE COMBO") {
                Text("Instant Simulation")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.label3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Don't have a filmed stunt handy right now? Seed sample StuntScope telemetry into your active session to explore the inspector and combo metrics immediately.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label2)

                Button {
                    seedStuntScopeDemoTelemetry()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 13, weight: .bold))
                        Text(seededSuccess ? "Demo Telemetry Loaded!" : "Load StuntScope Demo Reps")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(seededSuccess ? Theme.accent : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(seededSuccess ? Color.white.opacity(0.08) : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if seededSuccess {
                    Text("✓ Added 5 video-scored reps with flyer stability, wobbles, hold times and toss hangtime. Head to the dashboard to see the combo in action.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func seedStuntScopeDemoTelemetry() {
        // Ensure at least one group and session exists
        let targetGroup: StuntGroup
        if let existing = groups.first {
            targetGroup = existing
        } else {
            let newGroup = StuntGroup(name: "Lib", number: 1, orderIndex: 0)
            modelContext.insert(newGroup)
            targetGroup = newGroup
        }

        let targetSession: PracticeSession
        if let live = sessions.first(where: { $0.endedAt == nil }) ?? sessions.first {
            targetSession = live
        } else {
            let newSession = PracticeSession(startedAt: .now.addingTimeInterval(-1800))
            modelContext.insert(newSession)
            targetSession = newSession
        }

        // Setup subjects for roles if available
        var flyerSubject: Subject? = subjects.first
        if flyerSubject == nil {
            let s = Subject(name: "Ava", orderIndex: 0)
            modelContext.insert(s)
            flyerSubject = s
        }

        // Rep 1: Rock Solid Hit
        let rep1 = Attempt(slot: 0, group: targetGroup, session: targetSession, subject: flyerSubject, timestamp: .now.addingTimeInterval(-600))
        rep1.sourceRaw = "stuntscope"
        rep1.onBasePercent = 92
        rep1.holdSeconds = 4.2
        rep1.wobbleCount = 0
        rep1.flightSeconds = [1.15]
        if let f = flyerSubject {
            rep1.athleteIDs = [f.id]
            rep1.rolesRaw = "flyer=\(f.id.uuidString)"
        }
        modelContext.insert(rep1)

        // Rep 2: Fought-through Hit with 2 wobbles
        let rep2 = Attempt(slot: 0, group: targetGroup, session: targetSession, subject: flyerSubject, timestamp: .now.addingTimeInterval(-450))
        rep2.sourceRaw = "stuntscope"
        rep2.onBasePercent = 76
        rep2.holdSeconds = 3.6
        rep2.wobbleCount = 2
        rep2.worstWobbleSecond = 2.1
        if let f = flyerSubject {
            rep2.athleteIDs = [f.id]
            rep2.rolesRaw = "flyer=\(f.id.uuidString)"
        }
        modelContext.insert(rep2)

        // Rep 3: Steady Bobble
        let rep3 = Attempt(slot: 1, group: targetGroup, session: targetSession, subject: flyerSubject, timestamp: .now.addingTimeInterval(-300))
        rep3.sourceRaw = "stuntscope"
        rep3.onBasePercent = 64
        rep3.holdSeconds = 2.8
        rep3.wobbleCount = 1
        rep3.worstWobbleSecond = 1.8
        modelContext.insert(rep3)

        // Rep 4: Rock Solid Basket Toss
        let rep4 = Attempt(slot: 0, group: targetGroup, session: targetSession, subject: flyerSubject, timestamp: .now.addingTimeInterval(-150))
        rep4.sourceRaw = "stuntscope"
        rep4.onBasePercent = 88
        rep4.holdSeconds = 3.9
        rep4.wobbleCount = 0
        rep4.flightSeconds = [1.32]
        modelContext.insert(rep4)

        try? modelContext.save()
        withAnimation {
            seededSuccess = true
        }
    }
}
