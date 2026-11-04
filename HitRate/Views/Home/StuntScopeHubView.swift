import SwiftUI

/// The StuntScope integration hub explains the account connection and shared analysis.
struct StuntScopeHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel

    private var activeUID: String? { auth.uid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusBanner
                    capabilitiesSection
                    comboExplanationSection
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

                    Text("HitRate & StuntScope share identity (`com.ianrichardson.shared`) and sync stunt and tumbling analysis without logging hit/miss reps.")
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
            CardHead("HITRATE + STUNTSCOPE") {
                Text("SYNERGY")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("HitRate tracks if the stunt stays up. StuntScope tracks whether it fought for its life or was rock solid.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.label)

                Text("When you share a filmed stunt, its stability and frame data appear in this folder. It does not add a hit or miss rep or change your hit rate.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.label3)
            }
        }
    }

}
