import SwiftUI
import SwiftData
import AuthenticationServices

/// Save-your-account + account deletion (editor → Account).
///
/// Anonymous-first: the app runs on a device-bound anonymous Firebase user, so
/// deleting the app orphans every cloud folder that uid owns. This screen lets
/// the user LINK that anonymous user to Apple or Google — same uid, so folders,
/// reps, and shared rosters carry over untouched — and, once saved, delete the
/// account entirely (required by App Review 5.1.1(v) wherever sign-in exists).
/// No sign-out on purpose: signing out would just strand the user on a fresh
/// anonymous orphan account, the exact trap saving exists to prevent.
struct AccountView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var context

    @State private var confirmDelete = false

    private var glassRow: Color { Theme.well }

    var body: some View {
        List {
            if auth.isUpgraded {
                savedSection
                deleteSection
            } else {
                saveSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(FloorBackdrop().ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount(context: context) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and every folder you own are removed from the cloud — teammates who joined them lose access too. Reps saved on this phone stay on this phone. This can't be undone.")
        }
        // Reauth landed mid-deletion — finish the job (the view owns the
        // ModelContext, so the retry has to come from here).
        .onChange(of: auth.deletion) { _, state in
            if state == .reauthenticated {
                Task { await auth.deleteAccount(context: context) }
            }
        }
    }

    // MARK: - Anonymous: save the account

    private var saveSection: some View {
        Section {
            signInButtons(for: .link)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        } header: {
            Text("Save your account")
        } footer: {
            Text("Your folders live under this phone right now — a new phone (or a reinstall) starts from zero. Saving links them to your Apple or Google account so they follow you. Same folders, same reps, nothing moves.")
        }
    }

    // MARK: - Upgraded: saved state + deletion

    private var savedSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.accountLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                    Text("Saved with \(auth.providerName)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.label2)
                }
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Your folders follow this account — sign in with \(auth.providerName) on any phone to pick them up.")
        }
        .listRowBackground(glassRow)
    }

    @ViewBuilder
    private var deleteSection: some View {
        switch auth.deletion {
        case .needsRecentLogin, .reauthenticated:
            Section {
                signInButtons(for: .reauthenticate)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: {
                Text("Confirm it's you")
            } footer: {
                Text("Deleting an account needs a fresh sign-in. Confirm with \(auth.providerName) and the deletion finishes on its own.")
            }
        default:
            Section {
                if auth.deletion == .working {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.accent)
                        Text("Deleting…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.label2)
                    }
                } else {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete account", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            } header: {
                Text("Danger zone")
            } footer: {
                if case .failed(let message) = auth.deletion {
                    Text("Deletion failed: \(message)")
                } else {
                    Text("Removes your account and every folder you own from the cloud, and drops you from folders you joined. Reps on this phone stay on this phone.")
                }
            }
            .listRowBackground(glassRow)
        }
    }

    // MARK: - Provider buttons (shared by save + reauth)

    private func signInButtons(for use: AuthViewModel.CredentialUse) -> some View {
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
            }
            .buttonStyle(.plain)
        }
    }
}
