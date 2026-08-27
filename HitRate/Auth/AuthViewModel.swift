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

    /// A sign-in is in flight (credential accepted by the provider, Firebase
    /// still working). Drives the button spinner.
    @Published var isSigningIn = false
    /// The last sign-in failure, in words the user can act on. NOTHING in this
    /// class may fail silently: every surface that offers sign-in renders this,
    /// because a provider sheet that succeeds and then leaves the screen
    /// unchanged is indistinguishable from a hung app (App Review 2.1(a),
    /// 1.7 build 34).
    @Published var authError: String?
    /// A sign-in the user JUST completed, in words, shown briefly and then
    /// cleared. Apple's 2.1(a) finding was "the app remained on the login page
    /// after we signed in"; the flow now moves on, but every surface it moves
    /// on FROM disappears at the same moment (the prompt dismisses, onboarding
    /// advances, the editor swaps in the saved row), so without this a
    /// successful sign-in still reads as nothing having happened.
    @Published var signInConfirmation: String?
    /// Cleared by `apply` (or `finish`) the moment the sign-in lands — the flag
    /// is what separates "the user just tapped a provider button" from "a cold
    /// launch restored a saved session", which runs `apply` with
    /// `upgraded == true` too, twice, on every launch.
    private var awaitingUserSignIn = false
    private var confirmationTask: Task<Void, Never>?
    /// The same problem at the other end of the screen: `isUpgraded` flips
    /// false the instant the account dies, so the view swaps straight back to
    /// "Save your account" — which reads exactly like the deletion having
    /// silently failed. Kept separate from `signInConfirmation` because the
    /// sign-in buttons clear THAT on appear, and they are the first thing that
    /// renders after a deletion.
    @Published var deletionConfirmation: String?
    private var deletionNoticeTask: Task<Void, Never>?

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

        /// Erased to the case alone — `AccountDeletionPolicy` reasons about
        /// which states leave the user something to press, not about messages.
        var step: AccountDeletionPolicy.Step {
            switch self {
            case .idle: return .idle
            case .working: return .working
            case .needsRecentLogin: return .needsRecentLogin
            case .reauthenticated: return .reauthenticated
            case .failed: return .failed
            }
        }
    }
    @Published var deletion: AccountDeletion = .idle

    override init() {
        super.init()
        apply(Auth.auth().currentUser)
        // The hop is EXPLICIT. `apply` publishes the state SwiftUI renders, and
        // Firebase does not contract which queue this listener fires on — a
        // callback that lands off-main mutates @Published from a background
        // thread, where the update may never reach the view. That is exactly
        // the shape of "signed in, Firebase kept it, but the screen still
        // offers the buttons until a relaunch".
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    private func apply(_ user: User?) {
        currentUser = user
        uid = user?.uid
        let upgraded = (user.map { !$0.isAnonymous }) ?? false
        isUpgraded = upgraded
        // Landing clears any stale complaint from an earlier attempt — the
        // account IS saved, whatever went wrong on the way.
        if upgraded {
            let confirming = awaitingUserSignIn
            awaitingUserSignIn = false
            authError = nil
            isSigningIn = false
            applePrefersSignIn = false
            pendingNonces.removeAll()
            if confirming { announceSignIn() }
        }
    }

    /// The bootstrap anonymous sign-in, TRACKED so a user-initiated credential
    /// can wait for it instead of racing it.
    ///
    /// Guarding on `currentUser == nil` at call time is not enough: Firebase
    /// replaces `currentUser` wholesale when the request lands, so an anonymous
    /// sign-in still in flight will overwrite an Apple sign-in that completed
    /// in between — the account reads as saved, the confirmation shows, and
    /// then the sign-in buttons quietly come back. The window is wide open
    /// right after account deletion, which starts a bootstrap and then hands
    /// the user a screen whose first offer is "Continue with Apple".
    private var anonymousBootstrap: Task<Void, Never>?

    /// Anonymous-first launch: only signs in if there's no session at all, so we
    /// never clobber an upgraded (Apple/Google) account or a live anonymous one.
    func signInAnonymouslyIfNeeded() {
        guard Auth.auth().currentUser == nil, anonymousBootstrap == nil else { return }
        anonymousBootstrap = Task { @MainActor [weak self] in
            do {
                _ = try await Auth.auth().signInAnonymously()
            } catch {
                print("Anonymous sign-in error: \(error.localizedDescription)")
            }
            self?.anonymousBootstrap = nil
        }
    }

    /// Land every user-initiated credential AFTER the bootstrap, never across
    /// it. Bounded: if the anonymous request is stuck (offline), going ahead
    /// beats blocking the sign-in the user actually asked for.
    private func awaitAnonymousBootstrap() async {
        for _ in 0 ..< 50 {                     // ≤ 5s
            guard anonymousBootstrap != nil else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
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

    /// Which provider a credential came from. Only matters for collision
    /// recovery, where the two behave differently (see `recoverFromCollision`).
    private enum Provider { case apple, google }

    /// Link OR sign in with a credential: if the current session is anonymous we
    /// LINK (so the anonymous account's cloud data carries into the permanent
    /// account); otherwise we sign in fresh. `forcingSignIn` is the second pass
    /// of a collision recovery — the provider account already exists, so skip
    /// straight to signing into it.
    private func linkOrSignIn(_ credential: AuthCredential, provider: Provider,
                              forcingSignIn: Bool = false) {
        if let user = Auth.auth().currentUser, user.isAnonymous, !forcingSignIn {
            user.link(with: credential) { [weak self] _, error in
                Task { @MainActor in
                    guard let self else { return }
                    guard let nsError = error as NSError? else {
                        self.finish(nil)
                        return
                    }
                    if nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        self.recoverFromCollision(nsError, original: credential, provider: provider)
                    } else {
                        self.finish(nsError)
                    }
                }
            }
        } else {
            Auth.auth().signIn(with: credential) { [weak self] _, error in
                Task { @MainActor in self?.finish(error) }
            }
        }
    }

    /// The Apple ID (or Google account) is already attached to a HitRate
    /// account — which is the RESTORE case onboarding step 0 exists for, so it
    /// has to land, not dead-end.
    ///
    /// Firebase 10.28 promises an "updated credential" on this error but only
    /// actually attaches one for phone auth: the OAuth path builds it from a
    /// `FIRVerifyAssertionResponse` that is never populated on an error
    /// response, and `initWithVerifyAssertionResponse:` returns nil when the
    /// token fields are empty. So the old `?? credential` fallback re-sent the
    /// ORIGINAL credential — and an Apple identity token is single-use, already
    /// spent by the link that just failed. Firebase rejected it, the error was
    /// only `print`ed, and the app sat on the login screen forever. That is the
    /// 2.1(a) bug App Review hit on 1.7 (34): it needs an Apple ID that has
    /// signed into HitRate before, which is why it never reproduced locally.
    ///
    /// So: use the updated credential if one is genuinely there; otherwise ask
    /// Apple for a FRESH token and sign in with that. Google id_tokens stay
    /// valid after a failed link, so they can just be re-sent.
    private func recoverFromCollision(_ error: NSError, original: AuthCredential,
                                      provider: Provider) {
        let updated = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential
        let plan = CredentialCollisionPolicy.recovery(
            provider: provider == .apple ? .apple : .google,
            hasUpdatedCredential: updated != nil)

        switch plan {
        case .signInWithUpdated:
            signIn(updated ?? original)
        case .signInWithOriginal:
            signIn(original)
        case .refreshCredential:
            // ONE refresh per user-initiated attempt. A retry runs with
            // `forcingSignIn`, so it signs in rather than links and can't
            // collide again — but if that invariant ever breaks, an ungated
            // recovery would reopen the Apple sheet forever, which to a
            // reviewer looks worse than the bug it replaced.
            guard !appleRetryInFlight else {
                isSigningIn = false
                awaitingUserSignIn = false
                authError = "That Apple ID already has a HitRate account, but the sign-in didn't complete. Try again."
                return
            }
            applePrefersSignIn = true
            appleRetryInFlight = true
            // Fresh token, then sign in. If Apple hands back the SAME token it
            // just minted (it can, when re-asked immediately), the sign-in
            // fails and `finish` turns that into one clear instruction — and
            // `applePrefersSignIn` guarantees the next tap skips the link and
            // succeeds. Either way the user is never stranded.
            startAppleSignIn(for: appleUse, forcingSignIn: true)
        }
    }

    private func signIn(_ credential: AuthCredential) {
        Auth.auth().signIn(with: credential) { [weak self] _, error in
            Task { @MainActor in self?.finish(error) }
        }
    }

    /// Single exit point for every credential path — clears the spinner and
    /// either lands the sign-in or puts a readable reason on screen.
    private func finish(_ error: Error?) {
        let wasRetry = appleRetryInFlight
        isSigningIn = false
        appleRetryInFlight = false
        guard let error else {
            authError = nil
            // LINKING a provider does not change the auth STATE: it is the same
            // uid, so `addStateDidChangeListener` has no event to send and
            // never fires. `isUpgraded` is derived only from `apply`, so
            // without this it stayed false until the next cold launch — the
            // account saved correctly, the confirmation showed, and then the
            // sign-in buttons came straight back. Re-derive from the live user
            // rather than waiting for an event that is not coming.
            apply(Auth.auth().currentUser)
            // Belt and braces: if the user somehow isn't upgraded, `apply`
            // won't have consumed the flag, and a success must never be silent.
            if awaitingUserSignIn {
                awaitingUserSignIn = false
                announceSignIn()
            }
            return
        }
        awaitingUserSignIn = false
        // A failed auto-retry is never a raw Firebase string: the user tapped
        // once, saw two Apple prompts, and needs one instruction — not a nonce
        // hash. `applePrefersSignIn` makes that next tap sign in directly.
        authError = wasRetry
            ? "Almost there — tap Continue with Apple once more to finish signing in to that account."
            : Self.message(for: error)
    }

    /// Firebase's `localizedDescription` is serviceable but occasionally raw;
    /// translate the handful a user can actually act on.
    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case AuthErrorCode.networkError.rawValue:
            return "Couldn't reach the network. Check your connection and try again."
        case AuthErrorCode.providerAlreadyLinked.rawValue:
            return "This account is already saved on this phone."
        case AuthErrorCode.invalidCredential.rawValue, AuthErrorCode.userTokenExpired.rawValue:
            return "That sign-in expired before it went through. Try again."
        case AuthErrorCode.operationNotAllowed.rawValue:
            return "That sign-in method isn't available right now. Try the other one."
        default:
            return nsError.localizedDescription
        }
    }

    private func handle(_ credential: AuthCredential, use: CredentialUse,
                        provider: Provider, forcingSignIn: Bool = false) {
        // Armed synchronously so a landing `apply` can't miss it, then the
        // Firebase call waits out any bootstrap that would clobber it.
        if use == .link { awaitingUserSignIn = true }
        Task { @MainActor in
            await self.awaitAnonymousBootstrap()
            self.route(credential, use: use, provider: provider, forcingSignIn: forcingSignIn)
        }
    }

    private func route(_ credential: AuthCredential, use: CredentialUse,
                       provider: Provider, forcingSignIn: Bool = false) {
        switch use {
        case .link:
            linkOrSignIn(credential, provider: provider, forcingSignIn: forcingSignIn)
        case .reauthenticate:
            guard let user = Auth.auth().currentUser else {
                isSigningIn = false
                deletion = .failed("You're not signed in on this device.")
                return
            }
            user.reauthenticate(with: credential) { [weak self] _, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isSigningIn = false
                    if let error {
                        self.deletion = .failed(error.localizedDescription)
                        self.authError = Self.message(for: error)
                    } else {
                        self.authError = nil
                        self.apply(Auth.auth().currentUser)
                        self.deletion = .reauthenticated
                    }
                }
            }
        }
    }

    /// Names the provider that just landed, and retires the message on its own
    /// so it can't still be sitting there next time the screen is opened.
    private func announceSignIn() {
        let provider = providerName
        signInConfirmation = provider.isEmpty
            ? "Signed in. Your folders follow this account now."
            : "Saved with \(provider). Your folders follow this account now."
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.signInConfirmation = nil
        }
    }

    func clearSignInConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = nil
        signInConfirmation = nil
    }

    /// Says the account is gone AND that the reps aren't — the thing a user is
    /// actually anxious about at that moment.
    private func announceDeletion() {
        deletionConfirmation = "Account deleted. Your reps are still on this phone — save an account any time to back them up again."
        deletionNoticeTask?.cancel()
        deletionNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.deletionConfirmation = nil
        }
    }

    private func clearDeletionConfirmation() {
        deletionNoticeTask?.cancel()
        deletionNoticeTask = nil
        deletionConfirmation = nil
    }

    /// Clears a stale failure so a retry starts from a blank slate.
    func clearAuthError() {
        authError = nil
        clearDeletionConfirmation()
    }

    // MARK: - Google

    func signInWithGoogle(for use: CredentialUse = .link) {
        authError = nil
        clearDeletionConfirmation()
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            authError = "Google sign-in isn't configured in this build."
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let rootViewController = Self.presentingViewController() else {
            authError = "Couldn't open Google sign-in. Try again."
            return
        }

        isSigningIn = true
        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] signInResult, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // The user backing out isn't a failure — just stand down.
                    if (error as NSError).code == GIDSignInError.canceled.rawValue {
                        self.isSigningIn = false
                        self.awaitingUserSignIn = false
                    } else {
                        self.finish(error)
                    }
                    return
                }
                guard let idToken = signInResult?.user.idToken?.tokenString else {
                    self.isSigningIn = false
                    self.awaitingUserSignIn = false
                    self.authError = "Google didn't return a usable sign-in. Try again."
                    return
                }
                let accessToken = signInResult?.user.accessToken.tokenString
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                               accessToken: accessToken ?? "")
                self.handle(credential, use: use, provider: .google)
            }
        }
    }

    /// Topmost view controller of the foreground scene — `windows.first` picks
    /// an arbitrary window and can miss the key one entirely.
    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Apple

    /// Raw nonces for Apple authorizations that MAY still be in flight, newest
    /// first. A single `currentNonce` slot was a race: the collision retry (and
    /// an impatient double tap) each mint a new nonce while an earlier
    /// authorization can still land, and pairing a token with the wrong raw
    /// nonce is exactly what produced "The nonce in ID Token … does not match
    /// the SHA256 hash of the raw nonce …" on device. Apple stamps the nonce it
    /// used into the token, so match on that instead of guessing.
    private var pendingNonces: [String] = []
    private static let maxPendingNonces = 4
    /// Once Apple has told us this Apple ID already owns a HitRate account,
    /// every later Apple tap must SIGN IN rather than link. Linking again would
    /// only collide again and burn another single-use token.
    private var applePrefersSignIn = false
    /// What the credential from the CURRENT Apple request is for. Held because
    /// the programmatic retry (`startAppleSignIn`) answers through the delegate,
    /// which carries no context of its own.
    private var appleUse: CredentialUse = .link
    private var appleForcesSignIn = false
    /// True only while the collision RETRY is the request in flight. Gates the
    /// retry to one attempt, and makes cancelling that second sheet explain
    /// itself — the user tapped one button and got two prompts, so silence
    /// there would rebuild the dead end this whole change exists to remove.
    private var appleRetryInFlight = false
    /// Kept alive for the duration of a programmatic request —
    /// `ASAuthorizationController` is not retained by the system.
    private var appleController: ASAuthorizationController?

    /// Configure a `SignInWithAppleButton` request: stores the raw nonce for
    /// the completion handler and returns its SHA256 for the request.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        pendingNonces.insert(nonce, at: 0)
        if pendingNonces.count > Self.maxPendingNonces { pendingNonces.removeLast() }
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// Runs the Apple flow WITHOUT `SignInWithAppleButton` — used for the
    /// collision retry, which needs a second, unspent identity token and can't
    /// ask the user to find and tap the button again.
    func startAppleSignIn(for use: CredentialUse, forcingSignIn: Bool = false) {
        appleUse = use
        appleForcesSignIn = forcingSignIn
        isSigningIn = true

        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        appleController = controller
        controller.performRequests()
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>,
                             for use: CredentialUse = .link) {
        appleUse = use
        appleForcesSignIn = applePrefersSignIn
        appleRetryInFlight = false
        switch result {
        case .failure(let error):
            appleFailed(error)
        case .success(let authorization):
            appleSucceeded(authorization)
        }
    }

    private func appleSucceeded(_ authorization: ASAuthorization) {
        appleController = nil
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleIDCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            isSigningIn = false
            awaitingUserSignIn = false
            authError = "Apple didn't return a usable sign-in. Try again."
            return
        }
        guard let nonce = rawNonce(matching: idToken) else {
            isSigningIn = false
            awaitingUserSignIn = false
            authError = "That Apple sign-in didn't match this request. Tap Continue with Apple to try again."
            return
        }
        // Each identity token is good for exactly one Firebase call, so retire
        // its nonce the moment it's spent.
        pendingNonces.removeAll { $0 == nonce }
        isSigningIn = true
        let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                  idToken: idToken,
                                                  rawNonce: nonce)
        handle(credential, use: appleUse, provider: .apple, forcingSignIn: appleForcesSignIn)
    }

    private func appleFailed(_ error: Error) {
        appleController = nil
        isSigningIn = false
        awaitingUserSignIn = false
        guard let appleError = error as? ASAuthorizationError else {
            authError = Self.message(for: error)
            return
        }
        let wasRetry = appleRetryInFlight
        appleRetryInFlight = false
        switch appleError.code {
        case .canceled:
            // Backing out of the FIRST sheet is a choice, not a failure. Backing
            // out of the retry is different: from the user's side they tapped
            // Continue with Apple once and nothing happened.
            if wasRetry {
                authError = "That Apple ID already has a HitRate account — finish the Apple prompt to sign back into it."
            }
            return
        case .unknown:
            // What Apple returns when there's no Apple Account on the device.
            // Deliberately NOT silent: the user tapped a button and the sheet
            // vanished, so saying nothing is the same dead end as the 2.1(a)
            // bug, just one layer up.
            authError = "Sign in with Apple isn't available on this device. Check you're signed in to your Apple Account in Settings, or use Google."
        default:
            authError = "Apple couldn't complete the sign-in. Try again, or use Google."
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
        // `.onChange(of: auth.deletion)` re-enters this after a reauth; without
        // the guard a stray republish of `.reauthenticated` would start a
        // second footprint walk on top of the live one.
        guard AccountDeletionPolicy.admitsRequest(current: deletion.step) else { return }
        guard let user = Auth.auth().currentUser else {
            deletion = .failed("You're not signed in on this device.")
            return
        }
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
            // The footprint is gone but the login survived: sync has to come
            // back up so what is still on the phone gets re-pushed.
            SyncEngine.shared.resumeSyncing()
            deletion = .failed(error.localizedDescription)
            return
        }
        GIDSignIn.sharedInstance.signOut()
        SyncEngine.shared.resetLocalCloudLinkage(oldUID: oldUID, context: context)
        deletion = .idle
        announceDeletion()
        signInAnonymouslyIfNeeded()
    }

    /// Backing out of the "Confirm it's you" step. Cancelling either provider
    /// sheet leaves `deletion` at `.needsRecentLogin`, and that branch replaces
    /// the whole Danger zone — no delete button, no way back. Stranding the
    /// user on a screen with nothing to press is the same shape as the 2.1(a)
    /// dead end, one screen over, so the escape is explicit rather than
    /// inferred from a cancelled sheet.
    func cancelDeletion() {
        deletion = .idle
        authError = nil
        isSigningIn = false
        // Reaching the reauth step means the footprint walk already ran and
        // tore sync down. The account is staying, so bring it back — the
        // bootstrap re-pushes whatever is still on this phone.
        SyncEngine.shared.resumeSyncing()
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

    /// The raw nonce THIS token was actually minted with — see
    /// `AppleIdentityToken`, where the matching lives so it can be tested.
    private func rawNonce(matching idToken: String) -> String? {
        AppleIdentityToken.rawNonce(matching: idToken, from: pendingNonces)
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

// MARK: - Programmatic Apple flow

/// Only used by `startAppleSignIn` (the collision retry). The onboarding and
/// account surfaces still drive Apple through `SignInWithAppleButton`, which
/// Apple requires for the visible entry point.
extension AuthViewModel: ASAuthorizationControllerDelegate,
                         ASAuthorizationControllerPresentationContextProviding {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        appleSucceeded(authorization)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        appleFailed(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first ?? UIWindow()
    }
}
