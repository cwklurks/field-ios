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
        /// An invalid address, port, or redirect chain.
        case malformed
    }

    /// Check every known redirect destination before applying clean-up.
    /// The final destination's shield decides whether to clean the link.
    public static func accept(_ url: URL, cleaning: Guard?, shieldOn: Bool) -> Result<URL, Rejection> {
        accept(url, cleaning: cleaning, shieldOn: { _ in shieldOn })
    }

    public static func accept(_ url: URL, cleaning: Guard?, shieldOn: (String?) -> Bool) -> Result<URL, Rejection> {
        if let rejection = check(url) { return .failure(rejection) }
        guard let cleaning else { return .success(url) }
        var destination = url
        for _ in 0..<Guard.unwrapLimit {
            guard let host = GuardRules.host(of: destination),
                  let next = cleaning.rules.unwraps.target(of: destination, host: host,
                      site: cleaning.rules.suffixes.site(of: host), suffixes: cleaning.rules.suffixes, webOnly: false)
            else { break }
            if let rejection = check(next) { return .failure(rejection) }
            destination = next
        }
        // Don't pass an unchecked tail to a redirector after the bounded walk.
        if let host = GuardRules.host(of: destination),
           cleaning.rules.unwraps.target(of: destination, host: host,
               site: cleaning.rules.suffixes.site(of: host), suffixes: cleaning.rules.suffixes, webOnly: false) != nil {
            return .failure(.malformed)
        }
        guard shieldOn(destination.host(percentEncoded: false)) else { return .success(destination) }
        let nav = Navigation(url: url, kind: .typed)
        guard case .rewrite(let clean) = cleaning.decide(nav, shieldOn: true) else { return .success(url) }
        if let rejection = check(clean) { return .failure(rejection) }
        return .success(clean)
    }

    private static func check(_ url: URL) -> Rejection? {
        guard let scheme = url.scheme?.lowercased() else { return .malformed }
        guard scheme == "http" || scheme == "https" else { return .notWeb }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .malformed }
        if parts.percentEncodedUser != nil || parts.percentEncodedPassword != nil { return .credentials }
        guard GuardRules.host(of: url) != nil,
              let host = url.host(percentEncoded: false),
              !host.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
                      || "/\\@?#".unicodeScalars.contains($0)
              }),
              parts.port.map({ (0...65535).contains($0) }) ?? true,
              !url.absoluteString.contains("%00") else { return .malformed }
        return nil
    }
}
