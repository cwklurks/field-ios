import Foundation
import NaturalLanguage
import Testing
@testable import FieldKit
@testable import Field

/// What the rules compare tabs by, when there's no language model: the
/// nouns of a title, with the site's own name cut from its end, as averaged
/// word vectors. Measured on two sets of realistic tabs, this put far fewer
/// unrelated tabs together than whole-title sentence vectors did
/// (docs/integration/tidy.md, "The fallback").
struct TidyVectorsTests {
    @Test func cutsTheSiteFromATitle() {
        #expect(TidyVectors.topic(of: "Migrating to Swift 6 | Swift.org") == "Migrating to Swift 6")
        #expect(TidyVectors.topic(of: "Lenovo ThinkPad X1 Carbon G13 review - Notebookcheck.net") == "Lenovo ThinkPad X1 Carbon G13 review")
        #expect(TidyVectors.topic(of: "Which size Dutch oven for a 1kg loaf? : r/Breadit") == "Which size Dutch oven for a 1kg loaf?")
        #expect(TidyVectors.topic(of: "Memmo Alfama Hotel, Lisbon – Booking.com") == "Memmo Alfama Hotel, Lisbon")
        // Too little would be left: kept whole.
        #expect(TidyVectors.topic(of: "useEffect – React") == "useEffect – React")
    }

    /// FieldKit's rules hand over "title — host".
    @Test func dropsTheHostTheRulesAdd() {
        #expect(TidyVectors.topic(of: "Time Out Market Lisboa — timeoutmarket.com") == "Time Out Market Lisboa")
    }

    @Test(.enabled(if: NLEmbedding.wordEmbedding(for: .english) != nil))
    func likeTitlesAreCloserThanUnlike() {
        let vectors = TidyVectors(language: .english)
        let a = vectors.vector("ThinkPad X1 Carbon Gen 13 Aura Edition | Lenovo US — lenovo.com")!
        let b = vectors.vector("X1 Carbon vs T14s Gen 6, which one? : r/thinkpad — reddit.com")!
        let c = vectors.vector("A Beginner's Sourdough Bread Recipe | The Perfect Loaf — theperfectloaf.com")!
        #expect(Tidy.cosine(a, b) > Tidy.cosine(a, c))
    }

    /// On realistic tabs, the rules make groups a person would keep and
    /// leave the odd ones loose rather than lumping them together.
    @Test(.enabled(if: NLEmbedding.wordEmbedding(for: .english) != nil))
    func theRulesGroupRealTabsSensibly() {
        let titles = [
            ("ThinkPad X1 Carbon Gen 13 Aura Edition | Lenovo US", "https://www.lenovo.com/x1"),
            ("Lenovo ThinkPad X1 Carbon G13 review - Notebookcheck.net", "https://www.notebookcheck.net/x1"),
            ("X1 Carbon vs T14s Gen 6, which one? : r/thinkpad", "https://www.reddit.com/r/thinkpad/1"),
            ("Simple Sourdough Starter From Scratch | King Arthur Baking", "https://www.kingarthurbaking.com/s"),
            ("A Beginner's Sourdough Bread Recipe | The Perfect Loaf", "https://www.theperfectloaf.com/b"),
            ("Fed holds rates steady as inflation cools | Reuters", "https://www.reuters.com/f"),
            ("Arsenal 2-1 Benfica: Champions League report - BBC Sport", "https://www.bbc.co.uk/sport/1"),
        ]
        let tabs = titles.enumerated().map { TabInfo(id: TidyEngineTests.id($0.offset + 1), title: $0.element.0, url: URL(string: $0.element.1)!) }
        let vectors = TidyVectors(language: .english)
        let groups = Tidy.suggest(tabs, embed: vectors.vector, site: { $0 })
        let sets = groups.map { Set($0.ids) }
        #expect(sets.contains(Set((1...3).map(TidyEngineTests.id))))
        #expect(sets.contains(Set((4...5).map(TidyEngineTests.id))))
        #expect(!groups.flatMap(\.ids).contains(TidyEngineTests.id(6)))
        #expect(!groups.flatMap(\.ids).contains(TidyEngineTests.id(7)))
    }
}
