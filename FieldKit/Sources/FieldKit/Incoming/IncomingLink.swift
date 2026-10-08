import Foundation

/// A link another app hands Field (Mail, Messages, Notes), checked at the
/// door: it's external input. Only a web address with a host gets in, and it
/// goes through the same clean-up a tapped link gets (the guard's shims and
/// tracking parameters), so a redirect from Mail lands where it was going.
public enum IncomingLink {
    public enum Rejection: Error, Sendable, Equatable {
        /// Not a web address: javascript:, data:, file:, mail, another app's.
        case notWeb
        /// A name or password before the host, the old way to dress one
        /// site up as another.
        case credentials
        /// No host to go to.
        case malformed
    }

    /// Checked, then cleaned by `cleaning` (nil before its rules have
    /// loaded), then checked again: what a redirect was hiding is as foreign
    /// as the link itself. `shieldOn` is the per-site switch, as for a tap.
    public static func accept(_ url: URL, cleaning: Guard?, shieldOn: Bool) -> Result<URL, Rejection> {
        if let rejection = check(url) { return .failure(rejection) }
        guard let cleaning else { return .success(url) }
        let nav = Navigation(url: url, kind: .typed)
        guard case .rewrite(let clean) = cleaning.decide(nav, shieldOn: shieldOn) else { return .success(url) }
        if let rejection = check(clean) { return .failure(rejection) }
        return .success(clean)
    }

    private static func check(_ url: URL) -> Rejection? {
        guard let scheme = url.scheme?.lowercased() else { return .malformed }
        guard scheme == "http" || scheme == "https" else { return .notWeb }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .malformed }
        if parts.percentEncodedUser != nil || parts.percentEncodedPassword != nil { return .credentials }
        guard GuardRules.host(of: url) != nil else { return .malformed }
        return nil
    }
}
