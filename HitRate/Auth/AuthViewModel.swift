import Foundation
import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import GoogleSignIn
import GoogleSignInSwift

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    @Published var currentUser: User?
    /// Published separately because FirebaseAuth.User isn't Equatable — SwiftUI
    /// `onChange` observers key off this instead of the user object.
    @Published var uid: String?
    /// True when signed in with a REAL provider (Apple/Google), not anonymous.
    @Published var isUpgraded = false

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

    func signInAnonymously() {
        Auth.auth().signInAnonymously { _, error in
            if let error { print("Error signing in anonymously: \(error.localizedDescription)") }
        }
    }

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
            }
        } else {
            Auth.auth().signIn(with: credential) { _, error in
                if let error { print("Sign-in error: \(error.localizedDescription)") }
            }
        }
    }
    
    // MARK: - Google Auth
    
    func signInWithGoogle() {
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
            Task { @MainActor in self.linkOrSignIn(credential) }
        }
    }
    
    // MARK: - Apple Auth
    
    fileprivate var currentNonce: String?
    
    func startAppleSignIn() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.performRequests()
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    // Helper
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

extension AuthViewModel: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            guard let nonce = currentNonce else { return }
            guard let appleIDToken = appleIDCredential.identityToken else { return }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else { return }
            
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                      idToken: idTokenString,
                                                      rawNonce: nonce)
            self.linkOrSignIn(credential)
        }
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Sign in with Apple errored: \(error.localizedDescription)")
    }
}
