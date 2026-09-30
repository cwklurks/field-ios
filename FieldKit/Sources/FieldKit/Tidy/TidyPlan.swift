import Foundation

// What sits between Tidy's language model and the grid (M6). The model reads
// tabs as numbered lines, and hands back groups of those numbers. Guided
// generation makes the shape right but never the numbers, so every group is
// checked against the tabs it was given: numbers that name no tab, or a tab
// already placed, are dropped, and names are cleaned to a few plain words.
// A small context window reads the tabs in batches, and each batch's groups
// join the last's by name. All of it is plain logic, so it's tested without
// a model; the app owns the model itself.

extension Tidy {
    /// One group as the model proposed it: a name, and tabs by their number
    /// in the batch, counting from 1.
    public struct Proposal: Sendable, Equatable {
        public var name: String
        public var ids: [Int]

        public init(name: String, ids: [Int]) {
            self.name = name
            self.ids = ids
        }
    }

    /// Enough of a title to say what the page is; the rest costs tokens.
    static let titleLimit = 70

    /// The batch as the model reads it, a tab a line: "1 | github.com | Title".
    public static func render(_ batch: [TabInfo]) -> String {
        batch.enumerated().map { i, tab in
            "\(i + 1) | \(host(of: tab.url) ?? "") | \(describe(tab))"
        }.joined(separator: "\n")
    }

    /// The title on one line, or the path when there's no title.
    private static func describe(_ tab: TabInfo) -> String {
        let flat = tab.title
            .replacingOccurrences(of: "|", with: " ")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let text = flat.isEmpty ? tab.url.path() : flat
        return String(text.prefix(titleLimit))
    }

    /// The model's groups for one batch, checked: numbers that name no tab
    /// in it are dropped, and so is any tab's second mention. Names are
    /// cleaned, and one that says nothing gets the rule's own name for those
    /// tabs. Groups named alike are one, and a group needs `minimum` tabs:
    /// one while batches are still being read, since a group's other tabs
    /// may be in the next batch.
    public static func validate(_ proposals: [Proposal], batch: [TabInfo], minimum: Int = 2) -> [TidyGroup] {
        let hosts = batch.map { host(of: $0.url) }
        var placed = Set<Int>()
        var groups: [(name: String, members: [Int])] = []
        for proposal in proposals {
            let members = proposal.ids.filter { $0 >= 1 && $0 <= batch.count && placed.insert($0).inserted }
                .map { $0 - 1 }
            guard !members.isEmpty else { continue }
            let name = clean(name: proposal.name) ?? name(members, tabs: batch, hosts: hosts)
            if let i = groups.firstIndex(where: { key($0.name) == key(name) }) {
                groups[i].members += members
            } else {
                groups.append((name, members))
            }
        }
        return groups.filter { $0.members.count >= minimum }
            .map { TidyGroup(name: $0.name, ids: $0.members.map { batch[$0].id }) }
    }

    /// Words that name no group: a tab put there is as well left loose.
    static let generic: Set<String> = [
        "other", "others", "misc", "miscellaneous", "general", "uncategorized",
        "uncategorised", "various", "tabs", "group", "untitled", "none", "unknown",
    ]

    /// A model's name made plain: no emoji, no quotes or trailing stop, at
    /// most three words, and short enough for a section header. Nil when
    /// nothing is left, or when what's left says nothing ("Misc").
    public static func clean(name: String) -> String? {
        let scalars = name.unicodeScalars.filter { scalar in
            let p = scalar.properties
            let emoji = p.isEmojiPresentation || (p.isEmoji && scalar.value > 0x238C)
            return !emoji && scalar.value != 0xFE0F && scalar.value != 0x200D
        }
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’.,:;!?-–—*()[]"))
        let words = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: edges)
            .split(whereSeparator: \.isWhitespace)
            .prefix(3)
            .map(String.init)
        var kept = words
        while kept.count > 1, kept.joined(separator: " ").count > nameLimit { kept.removeLast() }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: edges)
        guard !joined.isEmpty, !generic.contains(joined.lowercased()) else { return nil }
        return String(joined.prefix(nameLimit))
    }

    /// Two names are the same group when they match but for case and spaces.
    static func key(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// One batch's groups joined to the groups so far: a group named like
    /// one already there adds to it; a tab already placed stays where it is.
    /// A new group needs `minimum` tabs of its own.
    public static func merge(_ groups: [TidyGroup], _ more: [TidyGroup], minimum: Int = 2) -> [TidyGroup] {
        var result = groups
        var placed = Set(groups.flatMap(\.ids))
        for group in more {
            let ids = group.ids.filter { !placed.contains($0) }
            if let i = result.firstIndex(where: { key($0.name) == key(group.name) }) {
                guard !ids.isEmpty else { continue }
                result[i].ids += ids
            } else {
                guard ids.count >= minimum else { continue }
                result.append(TidyGroup(name: group.name, ids: ids))
            }
            placed.formUnion(ids)
        }
        return result
    }

    /// The tabs in runs the model has room for, in order. `count` says how
    /// many tokens a rendered run takes; a run over `budget` is halved until
    /// each half fits, so the counter is asked a few times, not once a tab.
    /// A tab too long even alone still goes on its own: the model's error
    /// then sends it to the fallback.
    public static func batches(_ tabs: [TabInfo], budget: Int,
                               count: (String) async throws -> Int) async rethrows -> [[TabInfo]] {
        guard !tabs.isEmpty else { return [] }
        var out: [[TabInfo]] = []
        try await split(tabs[...], budget: budget, count: count, into: &out)
        return out
    }

    private static func split(_ run: ArraySlice<TabInfo>, budget: Int,
                              count: (String) async throws -> Int, into out: inout [[TabInfo]]) async rethrows {
        if run.count == 1 {
            out.append(Array(run))
            return
        }
        if try await count(render(Array(run))) <= budget {
            out.append(Array(run))
            return
        }
        let mid = run.startIndex + run.count / 2
        try await split(run[..<mid], budget: budget, count: count, into: &out)
        try await split(run[mid...], budget: budget, count: count, into: &out)
    }
}
