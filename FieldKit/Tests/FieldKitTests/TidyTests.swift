import Foundation
import Testing
@testable import FieldKit

/// Tidy's fallback: same-site heuristics first, then average-linkage
/// clustering of sentence vectors, named from the titles. Everything here
/// uses a fake `embed`, so the tests never touch NaturalLanguage and always
/// give the same answer.
struct TidyTests {
    // MARK: - fixtures

    /// Readable ids, so a test can say which tab landed where.
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    func tab(_ n: Int, _ title: String, _ url: String) -> TabInfo {
        TabInfo(id: Self.id(n), title: title, url: URL(string: url)!)
    }

    /// The registrable site: the last two labels, as a public-suffix list
    /// would mostly agree with.
    static let site: @Sendable (String) -> String = { host in
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : host
    }

    // Four axes. Words on the same axis are "about the same thing"; words on
    // different axes are unrelated. A title with no known word sits on a
    // fourth axis shared by other unknown titles.
    static let axes: [String: Int] = [
        "lisbon": 0, "flights": 0, "flight": 0, "hotels": 0, "hotel": 0, "trip": 0,
        "recipe": 1, "recipes": 1, "bread": 1, "sourdough": 1, "cake": 1,
        "swift": 2, "github": 2, "code": 2, "python": 2, "testing": 2,
    ]

    /// `embed` in the shape the app passes: it reads the title, ignores the
    /// host appended after the em dash, and returns a fixed vector per topic.
    /// "nomodel" stands in for a language `NLEmbedding` can't handle.
    static let embed: @Sendable (String) -> [Double]? = { text in
        let title = text.components(separatedBy: " — ").first ?? text
        if title.lowercased().contains("nomodel") { return nil }
        var vector = [Double](repeating: 0, count: 4)
        for word in title.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let axis = axes[String(word)] { vector[axis] += 1 }
        }
        if vector.allSatisfy({ $0 == 0 }) { vector[3] = 1 }
        return vector
    }

    func groups(_ tabs: [TabInfo]) -> [TidyGroup] {
        Tidy.suggest(tabs, embed: Self.embed, site: Self.site)
    }

    // MARK: - the edges

    @Test func noTabsNoGroups() {
        #expect(groups([]).isEmpty)
    }

    @Test func oneTabIsNeverAGroup() {
        #expect(groups([tab(1, "Flights to Lisbon", "https://flights.com/a")]).isEmpty)
    }

    // MARK: - same site

    @Test func twoOrMoreTabsOnASiteGroup() {
        let tabs = [
            tab(1, "Repo", "https://github.com/a"),
            tab(2, "Issues", "https://github.com/b"),
            tab(3, "Pulls", "https://github.com/c"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(found[0].name == "GitHub")
        #expect(found[0].ids == [Self.id(1), Self.id(2), Self.id(3)])
    }

    @Test func oneTabOnASiteIsNotASiteGroup() {
        let tabs = [
            tab(1, "GitHub code", "https://github.com/a"),
            tab(2, "Sourdough recipe", "https://cooking.com/a"),
        ]
        #expect(groups(tabs).isEmpty)
    }

    @Test func anUnknownSiteIsNamedByItsDomain() {
        let tabs = [
            tab(1, "One", "https://example.com/a"),
            tab(2, "Two", "https://example.com/b"),
        ]
        #expect(groups(tabs).map(\.name) == ["example.com"])
    }

    /// The www. is not the site: two tabs on it still group, named once.
    @Test func theWwwIsTheSameSite() {
        let tabs = [
            tab(1, "One", "https://www.example.com/a"),
            tab(2, "Two", "https://example.com/b"),
        ]
        #expect(groups(tabs).map(\.name) == ["example.com"])
    }

    // MARK: - duplicates

    /// Exact duplicate addresses count once, so two copies of one page are
    /// not "two tabs on a site" and no group is made.
    @Test func duplicateAddressesCountOnce() {
        let tabs = [
            tab(1, "Flights to Lisbon", "https://flights.com/a"),
            tab(2, "Flights to Lisbon", "https://flights.com/a"),
        ]
        #expect(groups(tabs).isEmpty)
    }

    /// A copy still rides along with the page it duplicates.
    @Test func aSiteGroupKeepsEveryCopy() {
        let tabs = [
            tab(1, "Repo", "https://github.com/a"),
            tab(2, "Repo", "https://github.com/a"),
            tab(3, "Issues", "https://github.com/b"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(found[0].ids == [Self.id(1), Self.id(2), Self.id(3)])
    }

    // MARK: - clustering

    @Test func similarTitlesAcrossSitesCluster() {
        let tabs = [
            tab(1, "Flights to Lisbon", "https://flights.com/a"),
            tab(2, "Lisbon hotels", "https://hotels.net/b"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(Set(found[0].ids) == [Self.id(1), Self.id(2)])
    }

    @Test func dissimilarTabsAreNotGrouped() {
        let tabs = [
            tab(1, "Flights to Lisbon", "https://flights.com/a"),
            tab(2, "Sourdough bread recipe", "https://cooking.com/b"),
        ]
        #expect(groups(tabs).isEmpty)
    }

    @Test func clustersOfOneStayUngrouped() {
        let tabs = [
            tab(1, "Flights to Lisbon", "https://a.com/a"),
            tab(2, "Sourdough bread recipe", "https://b.com/b"),
            tab(3, "Swift testing", "https://c.com/c"),
        ]
        #expect(groups(tabs).isEmpty)
    }

    /// A tab with no vector is left out of clustering, and out of any group.
    @Test func tabsWithoutAVectorSkipClustering() {
        let tabs = [
            tab(1, "nomodel flights", "https://a.com/a"),
            tab(2, "nomodel flights", "https://b.com/b"),
        ]
        #expect(groups(tabs).isEmpty)
    }

    /// The site heuristic needs no vectors: a same-site pair still groups
    /// when the model can't read its titles.
    @Test func aSiteGroupDoesNotNeedAVector() {
        let tabs = [
            tab(1, "nomodel one", "https://example.com/a"),
            tab(2, "nomodel two", "https://example.com/b"),
        ]
        let found = groups(tabs)
        #expect(found.map(\.name) == ["example.com"])
        #expect(found[0].ids.count == 2)
    }

    @Test func aClusterKeepsACopy() {
        let tabs = [
            tab(1, "Flights to Lisbon", "https://a.com/x"),
            tab(2, "Lisbon hotels", "https://b.com/y"),
            tab(3, "Flights to Lisbon", "https://a.com/x"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(Set(found[0].ids) == [Self.id(1), Self.id(2), Self.id(3)])
    }

    // MARK: - naming

    @Test func aClusterIsNamedByItsTopTerms() {
        let tabs = [
            tab(1, "Lisbon Flights", "https://a.com/a"),
            tab(2, "Lisbon Hotels", "https://b.com/b"),
            tab(3, "Sourdough bread", "https://c.com/c"),
            tab(4, "Sourdough recipe", "https://d.com/d"),
            tab(5, "Bread recipe", "https://e.com/e"),
            tab(6, "Swift code", "https://f.com/f"),
            tab(7, "Swift testing", "https://g.com/g"),
            tab(8, "Python code", "https://h.com/h"),
        ]
        let lisbon = groups(tabs).first { $0.ids.contains(Self.id(1)) }
        #expect(lisbon?.name == "Lisbon Flights")
    }

    /// Stop words and words of two letters never name a group.
    @Test func stopWordsAndShortWordsAreIgnored() {
        let tabs = [
            tab(1, "The Lisbon Trip of a Lifetime", "https://a.com/a"),
            tab(2, "A Trip to Lisbon in the Sun", "https://b.com/b"),
        ]
        #expect(groups(tabs).map(\.name) == ["Lisbon Trip"])
    }

    /// Two terms that won't fit in 24 characters drop to one, not to a cut
    /// word.
    @Test func aLongNameFallsBackToOneTerm() {
        let tabs = [
            tab(1, "Internationalization Guide", "https://a.com/a"),
            tab(2, "Internationalization Notes", "https://b.com/b"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(found[0].name == "Internationalization")
        #expect(found[0].name.count <= 24)
    }

    /// A single term longer than the limit is cut to it.
    @Test func aSingleLongTermIsCutToTwentyFour() {
        let tabs = [
            tab(1, "Supercalifragilisticexpialidocious Page", "https://a.com/a"),
            tab(2, "Supercalifragilisticexpialidocious Notes", "https://b.com/b"),
        ]
        let found = groups(tabs)
        #expect(found.count == 1)
        #expect(found[0].name.count == 24)
        #expect(found[0].name.hasPrefix("Supercalifragilistic"))
    }

    /// With nothing worth naming it, a cluster takes its busiest host.
    @Test func aClusterWithNoGoodTermsIsNamedByItsHost() {
        let tabs = [
            tab(1, "the of an", "https://a.com/x"),
            tab(2, "the of an", "https://b.com/y"),
        ]
        #expect(groups(tabs).map(\.name) == ["a.com"])
    }

    // MARK: - the whole answer

    @Test func everyTabIsInAtMostOneGroup() {
        let tabs = [
            tab(1, "Repo", "https://github.com/a"),
            tab(2, "Issues", "https://github.com/b"),
            tab(3, "Flights to Lisbon", "https://flights.com/a"),
            tab(4, "Lisbon hotels", "https://hotels.net/b"),
            tab(5, "Sourdough bread", "https://cooking.com/c"),
            tab(6, "Swift testing", "https://swift.org/d"),
        ]
        let found = groups(tabs)
        let all = found.flatMap(\.ids)
        #expect(Set(all).count == all.count)
        #expect(Set(all).isSubset(of: Set(tabs.map(\.id))))
    }

    @Test func groupsComeBiggestFirstThenByName() {
        let tabs = [
            tab(1, "Repo", "https://github.com/a"),
            tab(2, "Issues", "https://github.com/b"),
            tab(3, "Pulls", "https://github.com/c"),
            tab(4, "Sourdough bread", "https://c1.com/a"),
            tab(5, "Bread recipe", "https://c2.com/b"),
            tab(6, "Swift code", "https://s1.com/a"),
            tab(7, "Swift testing", "https://s2.com/b"),
        ]
        #expect(groups(tabs).map(\.name) == ["GitHub", "Bread Recipe", "Swift Code"])
    }

    @Test func theSameInputGivesTheSameGroups() {
        let tabs = [
            tab(1, "Repo", "https://github.com/a"),
            tab(2, "Issues", "https://github.com/b"),
            tab(3, "Flights to Lisbon", "https://flights.com/a"),
            tab(4, "Lisbon hotels", "https://hotels.net/b"),
            tab(5, "Sourdough bread", "https://cooking.com/c"),
        ]
        #expect(groups(tabs) == groups(tabs))
    }
}
