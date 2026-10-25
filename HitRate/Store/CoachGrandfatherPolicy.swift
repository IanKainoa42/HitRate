import Foundation

/// Who keeps HitRate Coach for free after the app goes free on the App Store.
///
/// On iOS, `AppTransaction.originalAppVersion` is the **CFBundleVersion** (build
/// number) from the customer's original download — not the marketing version.
/// Sandbox, TestFlight, and App Review always report `"1.0"` here (Apple DTS).
enum CoachGrandfatherPolicy {
    /// First build listed on the App Store while HitRate is free (v1.9 / build 41).
    /// Paid-era installs (builds 36–40 and anything earlier) stay below this.
    /// Bump in lockstep with `project.yml` when shipping the next free-era build.
    static let firstFreeBuild = 41

    /// True when the original install predates the first free App Store build.
    static func qualifies(originalAppVersion: String) -> Bool {
        // Non-production StoreKit environments — never grandfather (App Review
        // must hit the paywall; TestFlight IAP uses sandbox semantics).
        if originalAppVersion == "1.0" { return false }
        guard let build = Int(originalAppVersion) else { return false }
        return build < firstFreeBuild
    }
}
