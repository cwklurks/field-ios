import Foundation

/// Link shims and AMP viewers, and where they really go. Every table is in the
/// shape of Brave's debounce.json: address patterns, and an action that says
/// where the target is in the address. As in Brave, a rule applies only when
/// the target is on another site than the shim.
struct Unwraps: Sendable {
    struct File: Decodable {
        struct Rule: Decodable {
            let include: [String]
            let exclude: [String]?
            let action: String
            let param: String
            let prependScheme: String?
            let redirectUrlTemplate: String?
        }
        let rules: [Rule]
    }

    /// An extension match pattern, "scheme://host/path", as Brave writes them.
    struct Pattern: Sendable {
        enum Host: Sendable {
            case exact(String)
            /// "*.example.com": the domain and everything under it.
            case domain(String)
            /// "*.google.*": google under any public suffix.
            case anySuffix(String)
        }
        let httpsOnly: Bool
        let host: Host
        /// Matched against the path and query, "*" standing for anything.
        let path: [UInt8]

        init?(_ text: String) {
            guard let split = text.range(of: "://"), let host = Self.host(of: text) else { return nil }
            let scheme = text[..<split.lowerBound]
            guard scheme == "*" || scheme == "http" || scheme == "https" else { return nil }
            httpsOnly = scheme == "https"
            let rest = text[split.upperBound...]
            path = Array((rest.firstIndex(of: "/").map { rest[$0...] } ?? "/*").utf8)
            if host.hasPrefix("*."), host.hasSuffix(".*") {
                self.host = .anySuffix(String(host.dropFirst(2).dropLast(2)))
            } else if host.hasPrefix("*.") {
                self.host = .domain(String(host.dropFirst(2)))
            } else if !host.contains("*") {
                self.host = .exact(host)
            } else {
                return nil
            }
        }

        static func host(of pattern: String) -> String? {
            guard let split = pattern.range(of: "://") else { return nil }
            let rest = pattern[split.upperBound...]
            return String(rest.prefix { $0 != "/" }).lowercased()
        }

        func matches(scheme: String, pathAndQuery: [UInt8]) -> Bool {
            (!httpsOnly || scheme == "https") && Self.glob(path[...], pathAndQuery[...])
        }

        /// "*" matches any run of bytes, everything else only itself.
        static func glob(_ pattern: ArraySlice<UInt8>, _ text: ArraySlice<UInt8>) -> Bool {
            var p = pattern.startIndex, t = text.startIndex
            var star: Int?, resume = text.startIndex
            while t < text.endIndex {
                if p < pattern.endIndex, pattern[p] == UInt8(ascii: "*") {
                    star = p; resume = t; p += 1
                } else if p < pattern.endIndex, pattern[p] == text[t] {
                    p += 1; t += 1
                } else if let star {
                    p = star + 1; resume += 1; t = resume
                } else {
                    return false
                }
            }
            while p < pattern.endIndex, pattern[p] == UInt8(ascii: "*") { p += 1 }
            return p == pattern.endIndex
        }
    }

    struct Rule: Sendable {
        enum Action: Sendable {
            /// The target is a query parameter, maybe in base64.
            case parameter(String, base64: Bool)
            /// The target is what the expression captures from the path.
            case path(NSRegularExpression)
            /// The target is a template filled from the path's captures.
            case template(NSRegularExpression, String)
        }
        let action: Action
        let prependScheme: String?
        let excludes: [Pattern]
    }

    private let rules: [Rule]
    private let exact: [String: [(rule: Int, pattern: Pattern)]]
    private let byDomain: [Substring: [(rule: Int, pattern: Pattern)]]
    private let anySuffix: [Substring: [(rule: Int, pattern: Pattern)]]

    init(_ file: [File.Rule]) throws {
        var rules: [Rule] = []
        var exact: [String: [(rule: Int, pattern: Pattern)]] = [:]
        var byDomain: [Substring: [(rule: Int, pattern: Pattern)]] = [:]
        var anySuffix: [Substring: [(rule: Int, pattern: Pattern)]] = [:]
        for entry in file {
            let action: Rule.Action
            switch entry.action {
            case "redirect": action = .parameter(entry.param, base64: false)
            case "base64,redirect": action = .parameter(entry.param, base64: true)
            case "regex-path": action = .path(try NSRegularExpression(pattern: entry.param))
            case "regex-path-template":
                guard let template = entry.redirectUrlTemplate else { continue }
                action = .template(try NSRegularExpression(pattern: entry.param), template)
            default: continue   // an action this guard doesn't know yet
            }
            let index = rules.count
            rules.append(Rule(action: action, prependScheme: entry.prependScheme,
                              excludes: (entry.exclude ?? []).compactMap(Pattern.init)))
            for pattern in entry.include.compactMap(Pattern.init) {
                switch pattern.host {
                case .exact(let host): exact[host, default: []].append((index, pattern))
                case .domain(let domain): byDomain[Substring(domain), default: []].append((index, pattern))
                case .anySuffix(let label): anySuffix[Substring(label), default: []].append((index, pattern))
                }
            }
        }
        self.rules = rules
        self.exact = exact
        self.byDomain = byDomain
        self.anySuffix = anySuffix
    }

    /// Where a shim at `url` really goes, if a rule knows and it is on
    /// another site. `site` is the shim's registrable domain.
    func target(of url: URL, host: String, site: Substring, suffixes: PublicSuffixes) -> URL? {
        var candidates = exact[host] ?? []
        for domain in DomainSuffixes(host) {
            if let found = byDomain[domain] { candidates += found }
        }
        if let label = site.split(separator: ".", maxSplits: 1).first, let found = anySuffix[label] {
            candidates += found
        }
        guard !candidates.isEmpty, let scheme = url.scheme?.lowercased() else { return nil }
        candidates.sort { $0.rule < $1.rule }

        let path = url.path(percentEncoded: true)
        let query = url.query(percentEncoded: true)
        let pathAndQuery = Array(((path.isEmpty ? "/" : path) + (query.map { "?" + $0 } ?? "")).utf8)
        var tried = Set<Int>()
        for (index, pattern) in candidates where !tried.contains(index) {
            guard pattern.matches(scheme: scheme, pathAndQuery: pathAndQuery) else { continue }
            tried.insert(index)
            let rule = rules[index]
            guard !rule.excludes.contains(where: { $0.matches(scheme: scheme, pathAndQuery: pathAndQuery) }),
                  let target = Self.apply(rule, path: path, query: query),
                  target.scheme == "http" || target.scheme == "https",
                  let targetHost = GuardRules.host(of: target),
                  suffixes.site(of: targetHost) != site
            else { continue }
            return target
        }
        return nil
    }

    private static func apply(_ rule: Rule, path: String, query: String?) -> URL? {
        var text: String
        switch rule.action {
        case .parameter(let name, let base64):
            guard let raw = query.flatMap({ value(of: name, in: $0) }), var value = raw.removingPercentEncoding,
                  !value.isEmpty else { return nil }
            if base64 {
                guard let decoded = decodeBase64(value) else { return nil }
                value = decoded
            }
            text = value
        case .path(let expression):
            guard let captures = captures(of: expression, in: path),
                  let value = captures.joined().removingPercentEncoding else { return nil }
            text = value
        case .template(let expression, let template):
            guard let captures = captures(of: expression, in: path) else { return nil }
            text = template
            for (number, capture) in captures.enumerated().reversed() {
                text = text.replacingOccurrences(of: "$\(number + 1)", with: capture)
            }
        }
        if let scheme = rule.prependScheme, !text.hasPrefix("http://"), !text.hasPrefix("https://") {
            text = scheme + "://" + text
        }
        return URL(string: text, encodingInvalidCharacters: false)
    }

    /// The raw value of the first parameter with this name.
    private static func value(of name: String, in query: String) -> Substring? {
        for piece in query.split(separator: "&") {
            let equals = piece.firstIndex(of: "=") ?? piece.endIndex
            if piece[..<equals] == name {
                return equals == piece.endIndex ? "" : piece[piece.index(after: equals)...]
            }
        }
        return nil
    }

    private static func captures(of expression: NSRegularExpression, in path: String) -> [Substring]? {
        guard let match = expression.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: path).map { path[$0] } }
    }

    /// Standard or URL-safe, with or without its padding.
    private static func decodeBase64(_ text: String) -> String? {
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        return Data(base64Encoded: standard).flatMap { String(data: $0, encoding: .utf8) }
    }
}
