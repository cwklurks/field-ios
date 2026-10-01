import Foundation

// "Add similar tabs" (M6), the Firefox pattern: rather than grouping from
// nothing, start from a group the person already has and find the loose
// tabs that belong with it. Mozilla found this beat clustering everything.
// This is the rule used when there's no language model: a tab joins when
// it's on a site (a product, on a shared domain: Tidy.place) at least half the
// group (and two of its tabs) is on, or
// when its title reads like the group's, by the same average cosine
// distance the fallback's clustering cuts at.

extension Tidy {
    public static func similar(to members: [TabInfo], among candidates: [TabInfo],
                               embed: (String) -> [Double]?,
                               site: (String) -> String) -> [UUID] {
        guard !members.isEmpty else { return [] }
        let memberIDs = Set(members.map(\.id))

        var siteCounts: [String: Int] = [:]
        for tab in members {
            guard let place = place(of: tab.url, site: site) else { continue }
            siteCounts[place.key, default: 0] += 1
        }
        let groupSites = Set(siteCounts.filter { $0.value >= 2 && $0.value * 2 >= members.count }.keys)

        let vectors = members.compactMap { vector(for: $0, embed: embed) }
        return candidates.filter { tab in
            guard !memberIDs.contains(tab.id), let place = place(of: tab.url, site: site) else { return false }
            if groupSites.contains(place.key) { return true }
            guard !vectors.isEmpty, let own = vector(for: tab, embed: embed) else { return false }
            let mean = vectors.reduce(0) { $0 + (1 - cosine(own, $1)) } / Double(vectors.count)
            return mean < mergeBelow
        }.map(\.id)
    }

    /// What the fallback embeds for a tab: its title and host, as `suggest` does.
    private static func vector(for tab: TabInfo, embed: (String) -> [Double]?) -> [Double]? {
        guard let host = host(of: tab.url), let vector = embed("\(tab.title) — \(host)"), !vector.isEmpty else { return nil }
        return vector
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for k in 0..<min(a.count, b.count) { dot += a[k] * b[k] }
        for x in a { na += x * x }
        for x in b { nb += x * x }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}
