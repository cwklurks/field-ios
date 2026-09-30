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
        /// Nil for a tab Field hasn't timed yet: never stale on age.
        public let viewed: Date?

        public init(id: UUID, url: String, viewed: Date?) {
            self.id = id
            self.url = url
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
        // one looked at last, or else the first.
        var keep: [String: Tab] = [:]
        for tab in tabs {
            guard let address = address(tab.url) else { continue }
            guard let kept = keep[address] else { keep[address] = tab; continue }
            if kept.id == current { continue }
            if tab.id == current || (tab.viewed ?? .distantPast) > (kept.viewed ?? .distantPast) {
                keep[address] = tab
            }
        }
        let duplicates = tabs.filter { tab in
            guard let address = address(tab.url) else { return false }
            return keep[address]?.id != tab.id
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

    /// The address without its fragment: #top is the same page. Nil for a
    /// blank tab.
    private static func address(_ url: String) -> String? {
        guard !url.isEmpty else { return nil }
        return url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }
}
