import SwiftUI
import AuthenticationServices

/// The Apple + Google pair, shared by every surface that offers to save (or
/// restore) an account: the editor's AccountView, the onboarding step, and the
/// after-first-practice prompt. Kept in one place so the providers, ordering,
/// and button chrome can't drift between them — Apple requires Sign in with
/// Apple to be offered wherever a third-party provider is, so these two ship
/// together or not at all.
struct AccountSignInButtons: View {
    @EnvironmentObject private var auth: AuthViewModel
    var use: AuthViewModel.CredentialUse = .link

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.continue) { request in
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
}
