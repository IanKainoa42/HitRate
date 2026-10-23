import Foundation
import FirebaseAuth

/// The keychain access group HitRate shares with StuntScope, so both apps wake
/// up as the SAME Firebase user — anonymous or saved — with no sign-in screen
/// in StuntScope and no account-linking flow anywhere.
///
/// Firebase keeps the signed-in user in the keychain. By default each app has
/// its own slot, which is why a HitRate identity was never visible to a
/// sibling app. `useUserAccessGroup` moves Auth onto a group both apps declare
/// in their entitlements (`keychain-access-groups`); both bundle ids sit under
/// the one developer team, so the prefix is the same on each side.
///
/// Switching groups does NOT migrate the user Firebase already holds in the
/// private slot — it simply reads whoever is in the shared one (nobody, on the
/// first launch after this ships). HitRate's uid is what owns every folder
/// and stamps every rep, so losing it would orphan a coach's whole season.
/// `activate` therefore returns the private user when the shared group does
/// not already hold them, and AuthViewModel re-saves that user into the group
/// (`updateCurrentUser`) before anything else runs. HitRate is the identity
/// OWNER: StuntScope only ever reads this group and signs in anonymously when
/// it finds it empty — it must never overwrite a user it finds there.
enum SharedIdentity {
    /// `$(AppIdentifierPrefix)` resolves to the team id plus a dot in the
    /// entitlements file; Firebase wants the resolved string.
    static let teamID = "WC46K49VFA"
    static let accessGroup = "\(teamID).com.ianrichardson.shared"

    /// Point Firebase Auth at the shared group. Returns the user HitRate was
    /// signed in as in its private keychain when that user still needs to be
    /// carried into the group; nil when the group already agrees (or is the
    /// one with an identity) or when the group is unavailable — a build whose
    /// entitlement or provisioning lacks keychain sharing keeps working on the
    /// private keychain exactly as before.
    static func activate(auth: Auth = Auth.auth()) -> User? {
        let privateUser = auth.currentUser
        do {
            try auth.useUserAccessGroup(accessGroup)
        } catch {
            print("Shared keychain unavailable, staying on the private keychain: \(error.localizedDescription)")
            return nil
        }
        switch SharedIdentityPolicy.resolve(privateUID: privateUser?.uid,
                                            sharedUID: auth.currentUser?.uid) {
        case .keepShared: return nil
        case .adoptPrivate: return privateUser
        }
    }
}
