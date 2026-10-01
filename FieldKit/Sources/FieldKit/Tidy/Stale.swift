import Foundation

// Stale tabs (M6), by rule and never by a model: tabs not looked at for a
// span (two weeks unless the setting says otherwise), and second copies of
// one address. The grid offers them in a quiet banner, "12 tabs untouched
// for 2 weeks · Review / Close"; nothing closes itself, and what the person
// closes goes to Recently Closed.

public enum Stale {
    public struct Tab: Sendable, Equatable {
        public let id: UUID
        /// Empty for a blank tab.
        public let url: String
        /// Tells two anchors on one page apart from two pages.
        public let title: String
        /// Nil for a tab Field hasn't timed yet: never stale on age.
        public let viewed: Date?

        public init(id: UUID, url: String, title: String = "", viewed: Date?) {
            self.id = id
            self.url = url
            self.title = title
            self.viewed = viewed
        }
    }

    public struct Found: Sendable, Equatable {
        /// In the order the tabs were given.
        public let untouched: [UUID]
        /// Every copy of an address but the one looked at last.
        public let duplicates: [UUID]

        public init(untouched: [UUID], duplicates: [UUID]) {
            self.untouched = untouched
            self.duplicates = duplicates
        }

        /// Both, each tab once: what Close closes.
        public var all: [UUID] {
            var seen = Set<UUID>()
            return (untouched + duplicates).filter { seen.insert($0).inserted }
        }

        public var isEmpty: Bool { untouched.isEmpty && duplicates.isEmpty }
    }

    public static let defaultDays = 14

    /// `current` is the tab on screen, which is never stale.
    public static func find(_ tabs: [Tab], current: UUID?, now: Date, days: Int = defaultDays) -> Found {
        let span = TimeInterval(days) * 86_400
        let untouched = tabs.filter { tab in
            guard tab.id != current, let viewed = tab.viewed else { return false }
            return now.timeIntervalSince(viewed) >= span
        }.map(\.id)

        // The copy to keep at each address: the one on screen, or else the
        // one looked at last, or else the first. Addresses are compared
        // within a page, a few at most, so this stays a hash lookup.
        var keep: [String: [(tab: Tab, address: Address)]] = [:]
        for tab in tabs {
            guard let address = Address(tab) else { continue }
            guard let i = keep[address.page]?.firstIndex(where: { $0.address.isSame(as: address) }),
                  let kept = keep[address.page]?[i].tab else {
                keep[address.page, default: []].append((tab, address))
                continue
            }
            if kept.id == current { continue }
            if tab.id == current || (tab.viewed ?? .distantPast) > (kept.viewed ?? .distantPast) {
                keep[address.page]?[i] = (tab, address)
            }
        }
        let kept = Set(keep.values.flatMap { $0.map(\.tab.id) })
        let duplicates = tabs.filter { tab in
            !tab.url.isEmpty && !kept.contains(tab.id)
        }.map(\.id)
        return Found(untouched: untouched, duplicates: duplicates)
    }

    /// The banner's sentence; nil when there's nothing to say.
    public static func line(_ found: Found, days: Int = defaultDays) -> String? {
        let old = found.untouched.count, copies = found.duplicates.count
        switch (old, copies) {
        case (0, 0): return nil
        case (0, _): return copies == 1 ? "1 duplicate tab" : "\(copies) duplicate tabs"
        default:
            let first = "\(old) \(old == 1 ? "tab" : "tabs") untouched for \(span(days))"
            guard copies > 0 else { return first }
            return first + ", \(copies) \(copies == 1 ? "duplicate" : "duplicates")"
        }
    }

    /// "2 weeks", "a week", "10 days", "a day".
    static func span(_ days: Int) -> String {
        if days % 7 == 0 { return days == 7 ? "a week" : "\(days / 7) weeks" }
        return days == 1 ? "a day" : "\(days) days"
    }

    /// A tab's address as the duplicate check sees it: the page, normalised,
    /// and the fragment apart from it.
    private struct Address {
        /// Lowercase scheme and host, no default port, no `/` for an empty
        /// path, no tracking parameters; no fragment.
        let page: String
        /// Nil when there is none.
        let fragment: String?
        let title: String

        /// Strips the tracking parameters Field's guard knows. Its bundled
        /// rules are read once, after the first frame, so a grid finds them
        /// ready.
        private static let tracking = Guard(rules: .bundled)

        /// Nil for a blank tab.
        init?(_ tab: Tab) {
            guard !tab.url.isEmpty else { return nil }
            title = tab.title
            guard let url = URL(string: tab.url),
                  var parts = URLComponents(url: Self.tracking.stripped(url), resolvingAgainstBaseURL: false) else {
                // Not an address Foundation reads: the text, less its fragment.
                let pieces = tab.url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                page = String(pieces[0])
                fragment = pieces.count > 1 && !pieces[1].isEmpty ? String(pieces[1]) : nil
                return
            }
            let fragment = parts.percentEncodedFragment
            parts.percentEncodedFragment = nil
            parts.scheme = parts.scheme?.lowercased()
            parts.host = parts.host?.lowercased()
            if let port = parts.port, port == (parts.scheme == "https" ? 443 : parts.scheme == "http" ? 80 : nil) {
                parts.port = nil
            }
            if parts.path == "/" { parts.path = "" }
            page = parts.string ?? tab.url
            self.fragment = fragment?.isEmpty == false ? fragment : nil
        }

        /// `#/inbox` and `#!/x` are where a hash-routed app is.
        private var isRoute: Bool { fragment.map { $0.hasPrefix("/") || $0.hasPrefix("!") } ?? false }

        /// The same address; or, when only a plain in-page anchor tells them
        /// apart (`#intro`, `#usage`), the same page, which the title bears
        /// out. A route is a page of its own.
        func isSame(as other: Address) -> Bool {
            guard page == other.page else { return false }
            if fragment == other.fragment { return true }
            return !isRoute && !other.isRoute && title == other.title
        }
    }
}
