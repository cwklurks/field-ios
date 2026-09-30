import Foundation

// Tidy's fallback (M6): suggesting tab groups with no language model. A first
// pass uses the shape of the tabs — pages on one site belong together; then
// pages whose titles read alike are clustered by average linkage on sentence
// vectors. A plain function of its inputs: the app supplies the embedding
// (NLEmbedding on the phone) and the registrable-domain rule, so the logic is
// testable and nothing here touches a language model.

public struct TabInfo: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let url: URL

    public init(id: UUID, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public struct TidyGroup: Sendable, Equatable {
    public var name: String
    public var ids: [UUID]

    public init(name: String, ids: [UUID]) {
        self.name = name
        self.ids = ids
    }
}

public enum Tidy {
    /// Two clusters merge while their average cosine distance is below this.
    /// The midpoint of the cosine range, chosen against measurement rather
    /// than taste: on this machine NLEmbedding's English sentence vectors run
    /// high, so a plainly related pair of titles sat as low as 0.39
    /// similarity (0.61 distance) while unrelated short titles reached 0.58
    /// (0.42 distance). No single cut separates those, so the midpoint is the
    /// honest compromise, and average linkage is what keeps one close pair
    /// from dragging two clusters together the way single linkage would. The
    /// preview sheet, where a name can be fixed before anything moves, is the
    /// real answer to the noise.
    static let mergeBelow = 0.5

    /// A group's name, no longer than this. Long enough for two words.
    static let nameLimit = 24

    /// Suggests groups for the given tabs. `embed` turns text into a vector
    /// (in the app: NLEmbedding.sentenceEmbedding); it's injected so tests
    /// can pass a deterministic fake. Tabs that fit nowhere go in no group.
    public static func suggest(_ tabs: [TabInfo],
                               embed: (String) -> [Double]?,
                               site: (String) -> String) -> [TidyGroup] {
        guard !tabs.isEmpty else { return [] }
        let hosts = tabs.map { host(of: $0.url) }

        // Exact duplicate addresses count once. The first tab at an address
        // stands for it; the rest ride along with it, so they are never lost
        // and never counted as two tabs on a site.
        var reps: [Int] = []
        var firstOf: [String: Int] = [:]
        var copies: [Int: [Int]] = [:]
        for (i, tab) in tabs.enumerated() {
            let address = tab.url.absoluteString
            if let first = firstOf[address] { copies[first, default: []].append(i) }
            else { firstOf[address] = i; reps.append(i) }
        }

        var groups: [(name: String, members: [Int])] = []
        var placed = Set<Int>()

        // 1. Same site, two or more different addresses. Kept in first-seen
        // order so the answer never depends on dictionary iteration.
        var bySite: [String: [Int]] = [:]
        var sites: [String] = []
        for i in reps {
            guard let host = hosts[i] else { continue }
            let key = site(host)
            if bySite[key] == nil { sites.append(key) }
            bySite[key, default: []].append(i)
        }
        for key in sites {
            let members = bySite[key]!
            guard members.count >= 2 else { continue }
            for i in members { placed.insert(i) }
            groups.append((cap(displayName(key)), members))
        }

        // 2. Everything else, by meaning.
        let rest = reps.filter { !placed.contains($0) }
        var points: [(rep: Int, vector: [Double])] = []
        for i in rest {
            guard let host = hosts[i],
                  let vector = embed("\(tabs[i].title) — \(host)"), !vector.isEmpty else { continue }
            points.append((i, vector))
        }
        for cluster in clusters(of: points) {
            let members = cluster.map { points[$0].rep }
            groups.append((name(members, tabs: tabs, hosts: hosts), members))
        }

        // Copies follow the tab they duplicate, and each group's ids read in
        // the order the tabs were given.
        let built = groups.map { group -> TidyGroup in
            var indices = Set(group.members)
            for member in group.members { indices.formUnion(copies[member] ?? []) }
            return TidyGroup(name: group.name, ids: indices.sorted().map { tabs[$0].id })
        }
        return built.sorted {
            if $0.ids.count != $1.ids.count { return $0.ids.count > $1.ids.count }
            if $0.name != $1.name { return $0.name < $1.name }
            return ($0.ids.first?.uuidString ?? "") < ($1.ids.first?.uuidString ?? "")
        }
    }

    // MARK: - clustering

    /// Average-linkage agglomerative clustering, cut at `mergeBelow` rather
    /// than at a fixed number of clusters: whichever two clusters are closest
    /// merge, over and over, until the closest pair is too far apart.
    /// Clusters of one are left out.
    static func clusters(of points: [(rep: Int, vector: [Double])]) -> [[Int]] {
        let n = points.count
        guard n >= 2 else { return [] }

        // Cosine distance for every pair, once. Average linkage needs each
        // pair again and again, so paying for the dot products here keeps the
        // whole group under the frame budget.
        var distance = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var norm = [Double](repeating: 0, count: n)
        for i in 0..<n { norm[i] = points[i].vector.reduce(0) { $0 + $1 * $1 }.squareRoot() }
        for i in 0..<n {
            let one = points[i].vector
            for j in (i + 1)..<n {
                let other = points[j].vector
                var dot = 0.0
                for k in 0..<min(one.count, other.count) { dot += one[k] * other[k] }
                let similarity = (norm[i] > 0 && norm[j] > 0) ? dot / (norm[i] * norm[j]) : 0
                distance[i][j] = 1 - similarity
                distance[j][i] = 1 - similarity
            }
        }

        var size = [Double](repeating: 1, count: n)
        var members: [[Int]] = (0..<n).map { [$0] }
        var alive = [Bool](repeating: true, count: n)

        while true {
            var best = Double.infinity
            var one = -1, other = -1
            for i in 0..<n where alive[i] {
                for j in (i + 1)..<n where alive[j] {
                    if distance[i][j] < best { best = distance[i][j]; one = i; other = j }
                }
            }
            guard best < mergeBelow, one >= 0 else { break }

            // The merged cluster's distance to each of the rest is the
            // weighted mean of the two, which is average linkage exactly.
            let a = size[one], b = size[other]
            for c in 0..<n where alive[c] && c != one && c != other {
                let merged = (a * distance[one][c] + b * distance[other][c]) / (a + b)
                distance[one][c] = merged
                distance[c][one] = merged
            }
            size[one] = a + b
            members[one].append(contentsOf: members[other])
            alive[other] = false
        }

        return (0..<n).filter { alive[$0] && members[$0].count >= 2 }.map { members[$0] }
    }

    // MARK: - naming

    /// The top one or two title terms, by TF-IDF across every tab so a word
    /// that only this cluster shares stands out. Smoothed, so a term common
    /// to every tab still names the group rather than every score being zero.
    /// No good term leaves the busiest host.
    static func name(_ members: [Int], tabs: [TabInfo], hosts: [String?]) -> String {
        var documents: [String: Int] = [:]
        for tab in tabs {
            for term in Set(terms(in: tab.title)) { documents[term, default: 0] += 1 }
        }
        var counts: [String: Int] = [:]
        for i in members {
            for term in terms(in: tabs[i].title) { counts[term, default: 0] += 1 }
        }
        let total = Double(tabs.count)
        let ranked = counts.map { term, count -> (String, Double) in
            let idf = log((total + 1) / (Double(documents[term] ?? 1) + 1)) + 1
            return (term, Double(count) * idf)
        }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }

        let chosen = ranked.prefix(2).map { capitalised($0.0) }
        if let joined = fit(chosen) { return joined }
        return cap(dominantHost(members, hosts: hosts) ?? "Untitled")
    }

    /// Two terms if they fit the limit, one if they don't, and a cut term if
    /// even one is too long.
    private static func fit(_ chosen: [String]) -> String? {
        guard let first = chosen.first else { return nil }
        let both = chosen.prefix(2).joined(separator: " ")
        if both.count <= nameLimit { return both }
        return first.count <= nameLimit ? first : String(first.prefix(nameLimit))
    }

    /// The host with the most tabs in the cluster; the first one when tied.
    private static func dominantHost(_ members: [Int], hosts: [String?]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for i in members {
            guard let host = hosts[i] else { continue }
            if counts[host] == nil { order.append(host) }
            counts[host, default: 0] += 1
        }
        var best: String?
        for host in order where best == nil || counts[host]! > counts[best!]! { best = host }
        return best
    }

    /// Words of three letters or more, lowercased, stop words aside.
    static func terms(in title: String) -> [String] {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    private static func capitalised(_ word: String) -> String {
        word.isEmpty ? word : word.prefix(1).uppercased() + word.dropFirst()
    }

    /// The site's name when it is a well-known one (github.com is GitHub),
    /// and the site itself otherwise: guessing a brand from a domain is not
    /// something a rule does well.
    private static func displayName(_ site: String) -> String {
        History.known.first { $0.0 == site }?.1 ?? site
    }

    private static func cap(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= nameLimit ? trimmed : String(trimmed.prefix(nameLimit))
    }

    /// A URL's host, lowercased, without the root's trailing dot or a leading
    /// www.; nil when there is no host at all.
    static func host(of url: URL) -> String? {
        guard var host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// The words that name nothing: the small English list Firefox's and the
    /// web's keyword tools use, plus the pronouns and forms of "to be" that
    /// turn up in page titles.
    static let stopWords: Set<String> = [
        "a", "about", "after", "all", "also", "am", "an", "and", "any", "are", "as", "at",
        "be", "been", "being", "but", "by", "can", "come", "did", "do", "does", "done",
        "down", "each", "for", "from", "get", "had", "has", "have", "he", "her", "here",
        "him", "his", "how", "if", "in", "into", "is", "it", "its", "just", "like", "may",
        "me", "more", "most", "my", "new", "no", "not", "now", "of", "off", "on", "one",
        "only", "or", "other", "our", "out", "over", "own", "said", "same", "she", "should",
        "so", "some", "such", "than", "that", "the", "their", "them", "then", "there",
        "these", "they", "this", "those", "through", "to", "too", "under", "up", "us",
        "use", "very", "was", "we", "were", "what", "when", "where", "which", "while",
        "who", "why", "will", "with", "would", "you", "your",
    ]
}
