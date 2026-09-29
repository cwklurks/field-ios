// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

// What you type has to be a place. There is no search here, so this either
// hands back a URL or hands back nothing — and nothing is worth saying out
// loud, because the alternative is a browser that silently does something else
// with your keystrokes.
public enum Address {
    /// Schemes the window can show itself. Anything else typed with a scheme —
    /// mailto:, a custom app link — is somebody else's job and gets refused
    /// here rather than opening a blank tab.
    private static let ours: Set<String> = ["http", "https", "file", "about", "data"]

    public static func url(from typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        // Written with a scheme, it is taken at its word. Unlike the Mac, only
        // when what comes before the :// could be a scheme: in
        // "web.archive.org/web/2020/https://example.com" it is part of the path.
        if let split = text.range(of: "://"), isScheme(text[..<split.lowerBound]) {
            let scheme = text[..<split.lowerBound].lowercased()
            guard ours.contains(scheme) else { return nil }
            return URL(string: text)
        }
        if text.lowercased().hasPrefix("about:") || text.lowercased().hasPrefix("data:") {
            return URL(string: text)
        }

        // Everything else has to look like a host before it gets a scheme put
        // in front of it. "hello world" is not a website, and neither is "todo".
        let head = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !head.contains("@") else { return nil }   // an email address
        let host = head.split(separator: ":").first.map(String.init) ?? String(head)
        guard looksLikeHost(host) else { return nil }

        // A local server almost never has a certificate, so https there is a
        // connection failure rather than a page.
        return URL(string: (isLocal(host: host) ? "http://" : "https://") + text)
    }

    /// This machine or the network it is on, by name or by number: somewhere
    /// with no certificate as often as not. Unlike the Mac, which counted any
    /// name starting "10." or "192.168." (so 10.tv got plain http) and only
    /// those two ranges besides 127.0.0.1 and 0.0.0.0.
    static func isLocal(host: String) -> Bool {
        let host = host.lowercased()
        return host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || isPrivateIPv4(host)
            || (host.contains(":") && isPrivateIPv6(host))
    }

    private static func isIPv4(_ host: String) -> Bool {
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == 4 && numbers.allSatisfy { UInt8($0) != nil }
    }

    /// Loopback, the three private ranges and link-local, and 0.0.0.0 as on
    /// the Mac.
    private static func isPrivateIPv4(_ host: String) -> Bool {
        guard isIPv4(host) else { return false }
        let numbers = host.split(separator: ".").compactMap { UInt8($0) }
        switch (numbers[0], numbers[1]) {
        case (127, _), (10, _), (172, 16...31), (192, 168), (169, 254): return true
        default: return numbers == [0, 0, 0, 0]
        }
    }

    /// Loopback (::1), unique local (fc00::/7) and link-local (fe80::/10).
    private static func isPrivateIPv6(_ host: String) -> Bool {
        let address = host.trimmingCharacters(in: ["[", "]"]).prefix { $0 != "%" }
        if address == "::1" { return true }
        guard let first = address.split(separator: ":", omittingEmptySubsequences: false).first,
              let group = UInt16(first, radix: 16) else { return false }
        return group & 0xfe00 == 0xfc00 || group & 0xffc0 == 0xfe80
    }

    /// A letter, then letters, digits, "+", "." or "-".
    private static func isScheme(_ text: Substring) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }
    }

    private static func looksLikeHost(_ host: String) -> Bool {
        if host == "localhost" { return true }

        // Four numbers is an address on the local network as often as not.
        if isIPv4(host) { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        guard labels.allSatisfy({ label in
            !label.isEmpty
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }

        // The last label carries the weight: a dotted thing ending in letters is
        // a domain, a dotted thing ending in digits is a version number.
        let tld = labels[labels.count - 1]
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    /// What the tab says before the page has told us its title: the address,
    /// with the parts nobody reads taken off.
    public static func pretty(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path()
        return path.isEmpty || path == "/" ? bare : bare + path
    }
}
