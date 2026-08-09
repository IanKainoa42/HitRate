import SwiftUI

/// Offered once, right after the first practice that produced reps — the moment
/// the user first has something to lose. Deliberately not a wall: "Not now"
/// closes it for good (the folder-list chip and the editor keep the door open),
/// because App Review 5.1.1(i) doesn't allow gating features that work fine
/// without an account, and HitRate logs perfectly well offline.
struct SaveAccountPrompt: View {
    let repCount: Int
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
                .padding(.top, 26)

            // Words stay SF — Barlow Condensed is the numerals-only face here.
            Text(repCount > 0 ? "Save your \(repCount) reps" : "Save your reps")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.label)

            Text("They're on this phone and nowhere else. Sign in and they follow you — a new phone, or a reinstall, picks up exactly where you left off.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            AccountSignInButtons()

            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FloorBackdrop().ignoresSafeArea())
        // Linking flips this the moment it lands; get out of the way rather than
        // leaving the user staring at buttons they already used.
        .onChange(of: auth.isUpgraded) { _, saved in
            if saved { dismiss() }
        }
    }
}
