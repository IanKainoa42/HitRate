import Foundation
import SwiftData
import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import GoogleSignIn

/// Identity backbone (anonymous-first). Every install gets an anonymous
/// Firebase user on launch (`signInAnonymouslyIfNeeded`); `uid` is what team
/// ownership and rep attribution key on. AccountView lets the user LINK that
/// anonymous user to Apple/Google — same uid, so folders and shared rosters
/// carry over — and, once saved, delete the account (App Review 5.1.1(v)).
@MainActor
class AuthViewModel: NSObject, ObservableObject {
    @Published var currentUser: User?
    /// Published separately because FirebaseAuth.User isn't Equatable — SwiftUI
    /// `onChange` observers key off this instead of the user object.
    @Published var uid: String?
    /// True when signed in with a REAL provider (Apple/Google), not anonymous.
    @Published var isUpgraded = false

    /// Whether a fresh credential should LINK the current session or prove the
    /// user's identity again (Firebase demands a recent login before
    /// `user.delete()`). Threaded through explicitly — no stored mode flag to
    /// go stale between the sheet opening and the credential landing.
    enum CredentialUse { case link, reauthenticate }

    /// Account-deletion state machine, driven by AccountView.
    enum AccountDeletion: Equatable {
        case idle
        case working
        /// `user.delete()` was refused (stale login). The view shows the
        /// sign-in buttons in reauthenticate mode.
        case needsRecentLogin
        /// Reauth landed — the view re-runs `deleteAccount` (it owns the
        /// ModelContext this class deliberately doesn't hold).
        case reauthenticated
        case failed(String)
    }
    @Published var deletion: AccountDeletion = .idle

    override init() {
        super.init()
        apply(Auth.auth().currentUser)
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.apply(user)
        }
    }

    private func apply(_ user: User?) {
        currentUser = user
        uid = user?.uid
        isUpgraded = (user.map { !$0.isAnonymous }) ?? false
    }

    /// Anonymous-first launch: only signs in if there's no session at all, so we
    /// never clobber an upgraded (Apple/Google) account or a live anonymous one.
    func signInAnonymouslyIfNeeded() {
        guard Auth.auth().currentUser == nil else { return }
        Auth.auth().signInAnonymously { _, error in
            if let error { print("Anonymous sign-in error: \(error.localizedDescription)") }
        }
    }

    // MARK: - Display

    /// "Apple" / "Google" for the saved-account row.
    var providerName: String {
        let ids = currentUser?.providerData.map(\.providerID) ?? []
        if ids.contains("apple.com") { return "Apple" }
        if ids.contains("google.com") { return "Google" }
        return ""
    }

    /// Best display handle for the saved account. Apple can withhold the email
    /// (Hide My Email relays still count); fall back to a name, then generic.
    var accountLabel: String {
        let providers = currentUser?.providerData ?? []
        if let email = providers.compactMap(\.email).first ?? currentUser?.email,
           !email.isEmpty { return email }
        if let name = providers.compactMap(\.displayName).first ?? currentUser?.displayName,
           !name.isEmpty { return name }
        return "Account saved"
    }

    // MARK: - Credential routing

    /// Link OR sign in with a credential: if the current session is anonymous we
    /// LINK (so the anonymous account's cloud data carries into the permanent
    /// account); otherwise we sign in fresh. On the "already in use" collision
    /// (the provider account exists), fall back to a plain sign-in.
    private func linkOrSignIn(_ credential: AuthCredential) {
        if let user = Auth.auth().currentUser, user.isAnonymous {
            user.link(with: credential) { [weak self] result, error in
                if let nsError = error as NSError?,
                   nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                    let updated = (nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
                    Auth.auth().signIn(with: updated) { _, err in
                        if let err { print("Sign-in after link collision: \(err.localizedDescription)") }
                    }
                } else if let error {
                    print("Link error: \(error.localizedDescription)")
                }
                _ = result
                _ = self
            }
        } else {
            Auth.auth().signIn(with: credential) { _, error in
                if let error { print("Sign-in error: \(error.localizedDescription)") }
            }
        }
    }

    private func handle(_ credential: AuthCredential, use: CredentialUse) {
        switch use {
        case .link:
            linkOrSignIn(credential)
        case .reauthenticate:
            guard let user = Auth.auth().currentUser else { return }
            user.reauthenticate(with: credential) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.deletion = .failed(error.localizedDescription)
                    } else {
                        self?.deletion = .reauthenticated
                    }
                }
            }
        }
    }

    // MARK: - Google

    func signInWithGoogle(for use: CredentialUse = .link) {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { signInResult, error in
            if let error = error {
                print("Google Sign In Error: \(error.localizedDescription)")
                return
            }
            guard let idToken = signInResult?.user.idToken?.tokenString else { return }
            let accessToken = signInResult?.user.accessToken.tokenString

            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: accessToken ?? "")
            Task { @MainActor in self.handle(credential, use: use) }
        }
    }

    // MARK: - Apple

    private var currentNonce: String?

    /// Configure a `SignInWithAppleButton` request: stores the raw nonce for
    /// the completion handler and returns its SHA256 for the request.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>,
                             for use: CredentialUse = .link) {
        switch result {
        case .failure(let error):
            // Includes the user just dismissing the sheet — not an app error.
            print("Sign in with Apple: \(error.localizedDescription)")
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let tokenData = appleIDCredential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else { return }
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                      idToken: idToken,
                                                      rawNonce: nonce)
            handle(credential, use: use)
        }
    }

    // MARK: - Account deletion

    /// Cloud footprint first, auth account second — so a half-finished run can
    /// never leave reachable cloud data behind a deleted login. Idempotent: a
    /// retry after `needsRecentLogin` finds an already-empty footprint and goes
    /// straight to `user.delete()`. On success the device drops back to a fresh
    /// anonymous session and local folders go local-only (re-adopted by the new
    /// uid via the normal bootstrap).
    func deleteAccount(context: ModelContext) async {
        guard let user = Auth.auth().currentUser else { return }
        deletion = .working
        let oldUID = user.uid

        if let message = await SyncEngine.shared.deleteCloudFootprint(uid: oldUID) {
            deletion = .failed(message)
            return
        }
        do {
            try await user.delete()
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            deletion = .needsRecentLogin
            return
        } catch {
            deletion = .failed(error.localizedDescription)
            return
        }
        GIDSignIn.sharedInstance.signOut()
        SyncEngine.shared.resetLocalCloudLinkage(oldUID: oldUID, context: context)
        deletion = .idle
        signInAnonymouslyIfNeeded()
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}
