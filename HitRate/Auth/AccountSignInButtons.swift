import SwiftUI
import AuthenticationServices

/// The Apple + Google pair, shared by every surface that offers to save (or
/// restore) an account: the editor's AccountView, the onboarding step, and the
/// after-first-practice prompt. Kept in one place so the providers, ordering,
/// and button chrome can't drift between them — Apple requires Sign in with
/// Apple to be offered wherever a third-party provider is, so these two ship
/// together or not at all.
/// Both providers stay tappable while a sign-in is in flight — the ONLY states
/// this pair may be in are "offering" and "offering, with a reason the last try
/// didn't take". Disabling them on `isSigningIn` would rebuild the dead end
/// App Review hit on 1.7 (34), where a request that never came back left the
/// screen frozen with nothing to press.
struct AccountSignInButtons: View {
    @EnvironmentObject private var auth: AuthViewModel
    var use: AuthViewModel.CredentialUse = .link
    /// Onboarding paints on navy; the editor and the save prompt on graphite.
    var onDarkBrandBackground = false

    var body: some View {
        VStack(spacing: 10) {
            if let confirmation = auth.signInConfirmation {
                confirmationBanner(confirmation)
            } else {
                providerButtons
            }

            if auth.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(onDarkBrandBackground ? .white : Theme.accent)
                    Text("Signing in…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(onDarkBrandBackground ? .white.opacity(0.7) : Theme.label2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = auth.authError {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(message)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.majorFall)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeOut(duration: 0.2), value: auth.isSigningIn)
        .animation(.easeOut(duration: 0.2), value: auth.authError)
        .animation(.easeOut(duration: 0.2), value: auth.signInConfirmation)
        // A confirmation left over from an earlier sign-in must never greet
        // someone who just opened this screen to sign in.
        .onAppear { auth.clearSignInConfirmation() }
    }

    private var providerButtons: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
                auth.clearAuthError()
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                auth.completeAppleSignIn(result, for: use)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                auth.signInWithGoogle(for: use)
            } label: {
                Text("Continue with Google")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Replaces the pair rather than sitting under it: the sign-in landed, so
    /// still offering the buttons is exactly the ambiguity this exists to end.
    private func confirmationBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        // Green is the training floor's one signal accent; on the navy brand
        // register (onboarding) it would be off-palette, so plain white there.
        .foregroundStyle(onDarkBrandBackground ? Color.white : Theme.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }
}
