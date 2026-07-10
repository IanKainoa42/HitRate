import SwiftUI
import AuthenticationServices
import GoogleSignInSwift
import FirebaseAuth

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Text("Sign in to HitRate")
                .font(Theme.grotesk(32, .bold))
                .foregroundColor(.white)
            
            Text("Connect your account to share stats and collaborate with your team.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Apple Sign In
            SignInWithAppleButton(
                onRequest: { request in
                    viewModel.startAppleSignIn()
                },
                onCompletion: { result in
                    // Handled in AuthViewModel
                }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .padding(.horizontal)

            // Google Sign In
            Button(action: {
                viewModel.signInWithGoogle()
            }) {
                HStack {
                    Text("Sign in with Google")
                        .font(.headline)
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Button(action: {
                viewModel.signInAnonymously()
            }) {
                Text("Continue Anonymously")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBG)
        .onChange(of: viewModel.currentUser) { _, newUser in
            if newUser != nil {
                dismiss()
            }
        }
    }
}
