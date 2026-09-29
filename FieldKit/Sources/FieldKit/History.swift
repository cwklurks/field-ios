// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

// Where you have been, so the field can finish the address for you. A plain
// value: when to write it to its file, and who is told it changed, is the
// app's business.

public struct Suggestion: Identifiable, Equatable, Sendable {
    /// What you would have typed to get here: no scheme, no www.
    public let key: String
    public let title: String
    public let url: URL
    public let kind: Kind
    /// Set when this is a page you already have open somewhere.
    public var tab: UUID?

    public enum Kind: Sendable {
        /// A page that is open right now.
        case open
        /// Somewhere you have actually been.
        case visited
        /// One of the well-known addresses the field knows from the start.
        case known
        /// Not a place at all — words, and an engine to ask.
        case search
    }

    public var id: String { key }

    public init(key: String, title: String, url: URL, kind: Kind, tab: UUID? = nil) {
        self.key = key
        self.title = title
        self.url = url
        self.kind = kind
        self.tab = tab
    }
}

struct Visit: Codable, Equatable, Sendable {
    var url: String
    var key: String
    var title: String
    var count: Int
    var last: Date
}

public struct History: Equatable, Sendable {
    var visits: [String: Visit] = [:]

    public init() {}

    // MARK: - writing

    public mutating func record(_ url: URL, title: String, now: Date = .now) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        // Unlike the Mac, a name and password in an address are never
        // written down.
        guard let url = History.withoutPassword(url) else { return }
        let key = History.key(url)
        guard !key.isEmpty else { return }

        // Reading a deep page is also, in the way that matters here, another
        // visit to the site. Without this, typing three letters offers the
        // article you happened to open last week rather than the front page —
        // and nobody types a domain meaning to land halfway down it.
        if key.contains("/") {
            let root = String(key.prefix { $0 != "/" })
            var home = visits[root] ?? Visit(
                url: History.frontDoor(url, root: root), key: root, title: "", count: 0, last: now
            )
            home.count += 1
            home.last = now
            visits[root] = home
        }

        let aside = History.aside(url, key: key)
        if var seen = visits[key] {
            seen.count += 1
            seen.last = now
            if !aside { seen.url = url.absoluteString }
            if !title.isEmpty, !aside || History.names(url, over: seen.title) { seen.title = title }
            visits[key] = seen
        } else {
            visits[key] = Visit(
                url: aside ? History.frontDoor(url, root: key) : url.absoluteString,
                key: key,
                title: !aside || History.names(url, over: "") ? title : "",
                count: 1,
                last: now
            )
        }
    }

    /// A page's title usually lands a beat after the page does.
    public mutating func retitle(_ url: URL, _ title: String) {
        let key = History.key(url)
        guard !title.isEmpty, var seen = visits[key], seen.title != title,
              !History.aside(url, key: key) || History.names(url, over: seen.title) else { return }
        seen.title = title
        visits[key] = seen
    }

    public mutating func forget() {
        visits = [:]
    }

    /// Everywhere you have been, newest first, for the window that shows it.
    public struct Trace: Identifiable, Equatable, Sendable {
        public let key: String
        public let title: String
        public let url: URL
        public let last: Date
        public let count: Int

        public var id: String { key }
    }

    public func everything(matching typed: String = "") -> [Trace] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return visits.values
            // Every visit to a page also credits its domain, so the address
            // field can offer the front door. Those credits have no title of
            // their own, and in a list of where you have been they are a second
            // copy of every line.
            .filter { !($0.title.isEmpty && !$0.key.contains("/")) }
            .filter {
                needle.isEmpty
                    || $0.key.contains(needle)
                    || $0.title.lowercased().contains(needle)
            }
            .sorted { $0.last > $1.last }
            .compactMap { visit in
                URL(string: visit.url).map {
                    Trace(
                        key: visit.key,
                        title: visit.title,
                        url: $0,
                        last: visit.last,
                        count: visit.count
                    )
                }
            }
    }

    public mutating func forget(_ key: String) {
        visits[key] = nil
    }

    // MARK: - reading

    /// Best matches first. A place you have been always beats a place the app
    /// merely knows the name of, and among places you have been, one you go to
    /// often and recently beats one you saw once in March.
    public func suggestions(for typed: String, limit: Int = 5, now: Date = .now) -> [Suggestion] {
        let needle = strip(typed)
        // An empty field proposes nothing. A list of guesses in front of
        // someone who has not yet said what they want is noise, and it is in
        // the way of the one thing they came here to do.
        guard !needle.isEmpty else { return [] }
        let bytes = History.isPlain(needle) ? Array(needle.utf8) : nil

        // Unlike the Mac, an address is parsed only for the few that are
        // shown: parsing one for every match cost more than the ranking.
        var scored: [(key: String, title: String, url: String, kind: Suggestion.Kind, score: Double)] = []

        for visit in visits.values {
            guard let (rank, bare) = rank(visit.key, against: needle, bytes: bytes) else { continue }
            scored.append((
                visit.key, visit.title, visit.url, .visited,
                // The front door before the room inside it: a bare domain is
                // what a bare domain typed into a field means.
                rank + 4 + frecency(visit, now: now) + (bare ? 1.5 : 0)
            ))
        }

        // Only where memory has nothing to offer. A list of famous websites is
        // a poor substitute for knowing where someone actually goes.
        for known in History.known where visits[known.0] == nil {
            guard let (rank, _) = rank(known.0, against: needle, bytes: bytes) else { continue }
            scored.append((known.0, known.1, "https://" + known.0, .known, rank))
        }

        var shown: [Suggestion] = []
        for place in scored.sorted(by: { $0.score == $1.score ? $0.key.count < $1.key.count : $0.score > $1.score }) {
            guard shown.count < limit else { break }
            guard let url = URL(string: place.url) else { continue }
            shown.append(Suggestion(key: place.key, title: place.title, url: url, kind: place.kind))
        }
        return shown
    }

    /// What the field should draw greyed out after the caret: the rest of the
    /// best match, or nothing if it doesn't carry on from what was typed.
    /// From the first letter, as Safari does.
    /// Unlike the Mac, the match comes back with the ending, so Return goes to
    /// the address it was reached at: read again as typed, printer.local:631
    /// over http came back as https.
    public func completion(for typed: String, among options: [Suggestion]) -> (ending: String, suggestion: Suggestion)? {
        let lower = typed.lowercased()
        guard !lower.isEmpty else { return nil }
        guard let hit = options.first(where: { $0.key.hasPrefix(lower) }) else { return nil }
        let rest = String(hit.key.dropFirst(lower.count))
        return rest.isEmpty ? nil : (rest, hit)
    }

    /// Where the match falls decides most of the ordering: the start of the
    /// host is what people mean, the middle of a path almost never is. Comes
    /// back with whether the key is a bare domain, known by then anyway.
    private func rank(_ key: String, against needle: String, bytes: [UInt8]?) -> (Double, bare: Bool)? {
        // Unlike the Mac, read as bytes when both sides are plain, as an
        // address nearly always is: the same answer, several times sooner.
        if let bytes, History.isPlain(key),
           let read = key.utf8.withContiguousStorageIfAvailable({ History.rank($0, against: bytes) }) {
            return read
        }
        // Read in place: this runs for every place in the history on every
        // key, and splitting each key into new strings was most of its cost.
        let host = key[..<(key.firstIndex(of: "/") ?? key.endIndex)]
        let bare = host.endIndex == key.endIndex
        if key.hasPrefix(needle) { return (6, bare) }
        // "google" finding mail.google.com, once the "mail" has been skipped.
        if let dot = host.firstIndex(of: "."), host[host.index(after: dot)...].hasPrefix(needle) { return (3, bare) }
        // Only from two letters up. A single letter matching anywhere inside
        // a name turns "x" into example.com and netflix.com, which is not what
        // anybody meant by it.
        if needle.count >= 2, host.contains(needle) { return (2, bare) }
        // Deliberately no match on the path. "blog" turning up six articles
        // from three sites is not an answer to anything.
        return nil
    }

    /// The same, byte by byte.
    private static func rank(_ key: UnsafeBufferPointer<UInt8>, against needle: [UInt8]) -> (Double, bare: Bool)? {
        let slash = key.firstIndex(of: UInt8(ascii: "/"))
        let host = key[..<(slash ?? key.endIndex)]
        let bare = slash == nil
        if key.starts(with: needle) { return (6, bare) }
        if let dot = host.firstIndex(of: UInt8(ascii: ".")), host[(dot + 1)...].starts(with: needle) { return (3, bare) }
        if needle.count >= 2, host.count >= needle.count,
           (host.startIndex...(host.endIndex - needle.count)).contains(where: { host[$0...].starts(with: needle) }) {
            return (2, bare)
        }
        return nil
    }

    /// ASCII with no carriage return: text in which every byte is a
    /// character. ("\r\n" is two bytes but one character.)
    private static func isPlain(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 0x80 && $0 != 0x0D }
    }

    /// Often, and lately. A month-old visit counts for about a third of a
    /// fresh one, which is roughly how long a habit takes to stop being one.
    private func frecency(_ visit: Visit, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(visit.last) / 86_400)
        return Double(visit.count) * exp(-days / 30)
    }

    /// What you would have typed to get here. Unlike the Mac, Field keeps a
    /// port other than the scheme's own (localhost:3000 and localhost:8080
    /// are two different places) and the brackets round an IPv6 host, so a
    /// key reads back as an address.
    private static func key(_ url: URL) -> String {
        let pretty = Address.pretty(url).lowercased()
        guard let host = url.host() else { return pretty }
        let end = pretty.firstIndex(of: "/") ?? pretty.endIndex
        var place = String(pretty[..<end])
        if host.contains(":") { place = "[" + place + "]" }
        if let port = port(url) { place += ":\(port)" }
        return place + pretty[end...]
    }

    /// The port, unless it is the scheme's own.
    private static func port(_ url: URL) -> Int? {
        guard let port = url.port else { return nil }
        return port == (url.scheme?.lowercased() == "https" ? 443 : 80) ? nil : port
    }

    /// Where a site's front page is. The Mac always said https. A local
    /// address (a dev server, a router, a printer), or a site on a port of
    /// its own, is plain http as often as not, so Field keeps the scheme,
    /// host and port it was reached on, and nothing else.
    private static func frontDoor(_ url: URL, root: String) -> String {
        guard let host = url.host(), Address.isLocal(host: host) || port(url) != nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return "https://" + root + "/" }
        var home = URLComponents()
        home.scheme = parts.scheme
        home.percentEncodedHost = parts.percentEncodedHost
        home.port = port(url)
        home.path = "/"
        return home.string ?? "https://" + root + "/"
    }

    /// The address with any name and password taken out.
    private static func withoutPassword(_ url: URL) -> URL? {
        guard url.user() != nil || url.password() != nil else { return url }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    /// A front page reached with a query or a fragment: a search, an anchor.
    /// It counts as a visit to the site, but unlike the Mac it doesn't take
    /// the front page's place, or the site's suggestion would open the last
    /// search rather than the site.
    private static func aside(_ url: URL, key: String) -> Bool {
        !key.contains("/") && (url.query() != nil || url.fragment() != nil)
    }

    /// Whether a front page reached aside may still name it. A web app routed
    /// by its fragment alone (app.element.io/#/home) is only ever reached that
    /// way, so its first title names it; a search never does.
    private static func names(_ url: URL, over stored: String) -> Bool {
        url.query() == nil && stored.isEmpty
    }

    private func strip(_ typed: String) -> String {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        return text
    }

    // MARK: - the file

    /// No file is an empty history, and so is a file that isn't one, which is
    /// set aside first. Anything else that stops the file being read (a
    /// protected file before first unlock, a permission) throws. Until a load
    /// has succeeded the app must not save, or it would write an empty history
    /// over a full one; unlike the Mac, which took any failed read for empty.
    public static func load(from file: URL) throws -> History {
        var history = History()
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return history
        }
        guard let list = try? JSONDecoder().decode([Visit].self, from: data) else {
            Store.quarantine(file)
            return history
        }
        // Unlike the Mac, which stopped on a key written twice: the busier
        // visit is kept, then the later one.
        history.visits = Dictionary(list.map { ($0.key, $0) }) { one, other in
            one.count != other.count
                ? (one.count > other.count ? one : other)
                : (one.last >= other.last ? one : other)
        }
        return history
    }

    /// Slow enough on a big history to belong off the main thread.
    public func save(to file: URL, now: Date = .now) throws {
        // A cap, so the file can't grow without end. What goes is what has
        // been visited least and longest ago.
        let list = visits.values
            .sorted { frecency($0, now: now) > frecency($1, now: now) }
            .prefix(2_000)
            .map { $0 }
        let data = try JSONEncoder().encode(list)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }

    /// Somewhere to start on the first day, before there is any history to go
    /// on. Ranked below anything actually visited, and dropped from the list
    /// the moment you have been there yourself.
    static let known: [(String, String)] = [
        ("google.com", "Google"), ("mail.google.com", "Gmail"),
        ("drive.google.com", "Google Drive"), ("calendar.google.com", "Google Calendar"),
        ("maps.google.com", "Google Maps"), ("youtube.com", "YouTube"),
        ("github.com", "GitHub"), ("figma.com", "Figma"), ("vercel.com", "Vercel"),
        ("notion.so", "Notion"), ("linear.app", "Linear"), ("slack.com", "Slack"),
        ("discord.com", "Discord"), ("x.com", "X"), ("linkedin.com", "LinkedIn"),
        ("instagram.com", "Instagram"), ("reddit.com", "Reddit"),
        ("news.ycombinator.com", "Hacker News"), ("stackoverflow.com", "Stack Overflow"),
        ("claude.ai", "Claude"), ("chatgpt.com", "ChatGPT"),
        ("dribbble.com", "Dribbble"), ("behance.net", "Behance"),
        ("awwwards.com", "Awwwards"), ("mobbin.com", "Mobbin"),
        ("siteinspire.com", "SiteInspire"), ("are.na", "Are.na"),
        ("pinterest.com", "Pinterest"), ("framer.com", "Framer"),
        ("webflow.com", "Webflow"), ("developer.apple.com", "Apple Developer"),
        ("swift.org", "Swift"), ("npmjs.com", "npm"), ("supabase.com", "Supabase"),
        ("stripe.com", "Stripe"), ("shopify.com", "Shopify"),
        ("cloudflare.com", "Cloudflare"), ("netlify.com", "Netlify"),
        ("apple.com", "Apple"), ("spotify.com", "Spotify"), ("netflix.com", "Netflix"),
        ("wikipedia.org", "Wikipedia"), ("deepl.com", "DeepL"), ("loom.com", "Loom"),
        ("amazon.fr", "Amazon"), ("leboncoin.fr", "leboncoin"), ("lemonde.fr", "Le Monde"),
    ]
}
