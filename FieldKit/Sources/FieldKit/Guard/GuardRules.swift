import Foundation

/// The guard's tables, read once and indexed by host, so that a decision is a
/// handful of hash lookups however long the lists grow. The snapshot lives in
/// Guard/Rules and is refreshed by scripts/guard/update.sh.
public struct GuardRules: Sendable {
    /// How many entries each table holds, by file name: parameters for the
    /// two parameter lists, address patterns for the three unwrap tables and
    /// rules for the public suffix list.
    public let counts: [String: Int]
    let suffixes: PublicSuffixes
    let unwraps: Unwraps
    let tracking: TrackingParameters

    /// Reads every table in a folder. A missing or unreadable table is an
    /// error rather than a guard that quietly does less. About 9 ms on a Mac, so do
    /// it off the main thread.
    public static func load(from folder: URL) throws -> GuardRules {
        func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
        }
        let psl = try read("public-suffix-list.json", as: PublicSuffixes.File.self)
        let query = try read("brave-query-filter.json", as: TrackingParameters.BraveFile.self)
        let ddg = try read("ddg-tracking-parameters.json", as: TrackingParameters.DuckDuckGoFile.self)
        let shims = try read("shims.json", as: Unwraps.File.self)
        let debounce = try read("brave-debounce.json", as: Unwraps.File.self)
        let amp = try read("amp.json", as: Unwraps.File.self)

        func patterns(_ file: Unwraps.File) -> Int { file.rules.reduce(0) { $0 + $1.include.count } }
        return GuardRules(
            counts: [
                "public-suffix-list.json": psl.rules.count + psl.wildcards.count + psl.exceptions.count,
                "brave-query-filter.json": query.rules.reduce(0) { $0 + $1.params.count },
                "ddg-tracking-parameters.json": ddg.settings.parameters.count,
                "shims.json": patterns(shims),
                "brave-debounce.json": patterns(debounce),
                "amp.json": patterns(amp),
            ],
            suffixes: PublicSuffixes(psl),
            // Field's named shims first, then Brave's table, then AMP, which
            // is step 4 but is the same kind of rewrite.
            unwraps: try Unwraps(shims.rules + debounce.rules + amp.rules),
            tracking: TrackingParameters(brave: query, duckDuckGo: ddg)
        )
    }

    /// The snapshot that ships in FieldKit. It is part of the build, so
    /// failing to read it is a broken build, not a condition to handle.
    public static let bundled: GuardRules = {
        guard let folder = bundledFolder else { fatalError("FieldKit's resource bundle is missing") }
        do { return try load(from: folder) } catch { fatalError("The guard's bundled rules don't load: \(error)") }
    }()

    static let bundledFolder = Bundle.module.resourceURL

    /// The registrable domain (eTLD+1) of a host, or the host itself when it
    /// has none: an address, or a public suffix on its own.
    public func site(of host: String) -> String {
        String(suffixes.site(of: Self.normalized(host)))
    }

    /// A URL's host as the tables spell it: lowercase, without the root's
    /// trailing dot. Nil when there is no host to speak of.
    static func host(of url: URL) -> String? {
        guard let host = url.host(), !host.isEmpty else { return nil }
        let bare = normalized(host)
        return bare.isEmpty ? nil : bare
    }

    private static func normalized(_ host: String) -> String {
        let lower = host.contains(where: \.isUppercase) ? host.lowercased() : host
        return lower.hasSuffix(".") ? String(lower.dropLast()) : lower
    }
}

/// A host, then each domain it sits under: "a.b.com", "b.com", "com".
struct DomainSuffixes: Sequence, IteratorProtocol {
    private var rest: Substring?

    init(_ host: some StringProtocol) {
        rest = Substring(host)
    }

    mutating func next() -> Substring? {
        guard let current = rest else { return nil }
        rest = current.firstIndex(of: ".").map { current[current.index(after: $0)...] }
        return current
    }
}

/// The Public Suffix List, for telling whether two hosts are the same site.
struct PublicSuffixes: Sendable {
    struct File: Decodable {
        let rules: [String]
        let wildcards: [String]
        let exceptions: [String]
    }

    private let rules: Set<Substring>
    /// "*.ck" is kept as "ck".
    private let wildcards: Set<Substring>
    /// "!www.ck" is kept as "www.ck".
    private let exceptions: Set<Substring>

    init(_ file: File) {
        rules = Set(file.rules.map { Substring($0) })
        wildcards = Set(file.wildcards.map { Substring($0) })
        exceptions = Set(file.exceptions.map { Substring($0) })
    }

    /// The registrable domain of a lowercase host. Longest match first, so
    /// the first rule found prevails, as the list's algorithm says; with no
    /// rule, the last label is the suffix.
    func site(of host: String) -> Substring {
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host[...] }
        var owner: Substring?   // the candidate one label longer than this one
        for candidate in DomainSuffixes(host) {
            if exceptions.contains(candidate) { return candidate }
            let parent = candidate.firstIndex(of: ".").map { candidate[candidate.index(after: $0)...] }
            if rules.contains(candidate) || parent.map(wildcards.contains) == true || parent == nil {
                return owner ?? candidate
            }
            owner = candidate
        }
        return host[...]
    }
}
