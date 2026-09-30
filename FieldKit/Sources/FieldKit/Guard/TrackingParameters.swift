import Foundation

/// Query parameters that exist only to follow you from one site to the next:
/// Brave's query filter (global and per-site) and DuckDuckGo's list, which
/// adds utm_* and has a few sites where stripping breaks them.
struct TrackingParameters: Sendable {
    struct BraveFile: Decodable {
        struct Rule: Decodable {
            let include: [String]
            let params: [String]
        }
        let rules: [Rule]
    }

    struct DuckDuckGoFile: Decodable {
        struct Exception: Decodable { let domain: String }
        struct Settings: Decodable { let parameters: [String] }
        let exceptions: [Exception]
        let settings: Settings
    }

    private let global: Set<Substring>
    /// By the domain they belong to, which covers its subdomains too.
    private let bySite: [Substring: Set<Substring>]
    /// Domains, and so their subdomains, where nothing is stripped.
    private let exceptions: Set<Substring>

    /// Brave's includes are either every address ("*://*/*") or one domain
    /// with or without its subdomains; both of the latter index by domain.
    /// Brave's excludes are empty today and aren't read.
    init(brave: BraveFile, duckDuckGo: DuckDuckGoFile) {
        var global = Set(duckDuckGo.settings.parameters.map { Substring($0) })
        var bySite: [Substring: Set<Substring>] = [:]
        for rule in brave.rules {
            let params = rule.params.map { Substring($0) }
            for include in rule.include {
                guard let host = Unwraps.Pattern.host(of: include) else { continue }
                if host == "*" {
                    global.formUnion(params)
                } else {
                    let domain = host.hasPrefix("*.") ? host.dropFirst(2) : host[...]
                    bySite[domain, default: []].formUnion(params)
                }
            }
        }
        self.global = global
        self.bySite = bySite
        exceptions = Set(duckDuckGo.exceptions.map { Substring($0.domain) })
    }

    /// The address without its tracking parameters, or nil when it has none.
    /// Everything else stays as it was written: order, encoding, empty
    /// pieces and the fragment.
    func stripped(_ url: URL, host: String) -> URL? {
        let text = url.absoluteString
        let end = text.firstIndex(of: "#") ?? text.endIndex
        guard let mark = text[..<end].firstIndex(of: "?") else { return nil }

        var scoped: [Set<Substring>] = []
        for domain in DomainSuffixes(host) {
            if exceptions.contains(domain) { return nil }
            if let params = bySite[domain] { scoped.append(params) }
        }

        let pieces = text[text.index(after: mark)..<end].split(separator: "&", omittingEmptySubsequences: false)
        let kept = pieces.filter { piece in
            let name = piece.prefix { $0 != "=" }
            return !global.contains(name) && !scoped.contains { $0.contains(name) }
        }
        guard kept.count < pieces.count else { return nil }
        let query = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        return URL(string: text[..<mark] + query + text[end...])
    }
}
