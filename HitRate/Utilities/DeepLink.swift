import Foundation

/// The app's own URL scheme — `hitrate://`.
///
/// Registered in `project.yml`'s `info:` block (CFBundleURLTypes), NOT by hand
/// in `HitRate/Info.plist` — xcodegen owns that file and regenerates it. Run
/// `xcodegen generate` after changing the scheme or the link stops resolving.
///
/// Today there is exactly one link: the shared-folder join code, which
/// `ShareFolderSheet` renders as a QR so an athlete can point a camera at the
/// coach's phone on the floor instead of retyping six characters.
enum DeepLink {
    static let scheme = "hitrate"

    /// `hitrate://join?code=ABC123` — what a shared folder's QR encodes and what
    /// a texted invite links to.
    static func join(code: String) -> URL {
        let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        // Both fall-throughs are literal, scheme-valid strings — they cannot fail
        // to parse; the second exists only so this returns a non-optional URL.
        return URL(string: "\(scheme)://join?code=\(escaped)")
            ?? URL(string: "\(scheme)://join")!
    }

    /// The join code carried by an incoming URL, or nil when this isn't one of
    /// ours (a Google Sign-In callback comes through the same `onOpenURL`).
    /// Normalized the same way `SyncEngine.joinTeam` normalizes typed codes —
    /// trimmed and upper-cased — so a scanned code and a typed one resolve
    /// identically.
    static func joinCode(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "join" else { return nil }
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value ?? ""
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.isEmpty ? nil : code
    }
}
