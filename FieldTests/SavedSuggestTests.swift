import Foundation
import NaturalLanguage
import Testing
@testable import FieldKit
@testable import Field

/// The save sheet's suggested folder with the phone's own sentence model:
/// a page lands where pages like it are, and one like nothing gets none.
struct SavedSuggestTests {
    func url(_ text: String) -> URL { URL(string: text)! }

    func library() -> Saved {
        var saved = Saved()
        let pages: [(String, String, String)] = [
            ("https://www.seriouseats.com/cookies", "Best chocolate chip cookies", "Recipes"),
            ("https://www.bonappetit.com/pasta", "Easy weeknight pasta", "Recipes"),
            ("https://www.bbcgoodfood.com/curry", "Thai green curry", "Recipes"),
            ("https://www.lonelyplanet.com/lisbon", "Things to do in Lisbon", "Trips"),
            ("https://www.booking.com/porto", "Hotels in Porto", "Trips"),
            ("https://swift.org/concurrency", "Swift concurrency explained", "Code"),
            ("https://developer.apple.com/swiftui", "SwiftUI layout guide", "Code"),
        ]
        for (address, title, folder) in pages { saved.save(url(address), title: title, folder: folder) }
        return saved
    }

    @Test(.enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil))
    func suggestsByMeaning() async {
        let suggester = FolderSuggester()
        let saved = library()
        #expect(await suggester.folder(for: url("https://www.kingarthurbaking.com/pizza"), title: "Homemade pizza dough", in: saved) == "Recipes")
        #expect(await suggester.folder(for: url("https://www.seat61.com/lisbon"), title: "Train from Madrid to Lisbon", in: saved) == "Trips")
        #expect(await suggester.folder(for: url("https://example.com/q"), title: "Quarterly earnings report", in: saved) == nil)
    }

    /// A suggestion is chosen for you, so a wrong one costs more than none:
    /// over pages from all over, each is its right folder or nothing.
    @Test(.enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil))
    func neverSuggestsTheWrongFolder() async {
        let suggester = FolderSuggester()
        var saved = library()
        saved.save(url("https://garden.example/tomatoes"), title: "When to plant tomatoes", folder: "Garden")
        saved.save(url("https://garden.example/roses"), title: "Pruning roses in winter", folder: "Garden")
        saved.save(url("https://money.example/funds"), title: "How index funds work", folder: "Money")
        saved.save(url("https://money.example/taxes"), title: "Filing taxes as a freelancer", folder: "Money")
        let pages: [(String, String?)] = [
            ("Beef stew recipe", "Recipes"), ("Banana bread", "Recipes"), ("Vegan lasagna", "Recipes"),
            ("Cheap flights to Rome", "Trips"), ("Weekend in Barcelona", "Trips"), ("Kyoto travel guide", "Trips"),
            ("Paris metro map", "Trips"), ("Understanding Rust ownership", "Code"), ("Python async tutorial", "Code"),
            ("Git rebase explained", "Code"), ("Growing basil indoors", "Garden"), ("Lawn care tips", "Garden"),
            ("Best compost bins", "Garden"), ("Mortgage calculator", "Money"), ("Roth IRA explained", "Money"),
            ("Retirement savings guide", "Money"), ("Quarterly earnings report", "Money"),
            ("Best hiking boots 2026", nil), ("How to fix a leaky faucet", nil), ("Election results live", nil),
            ("The history of jazz", nil), ("Premier League table", nil), ("iPhone 18 review", nil),
            ("Dog training basics", nil),
        ]
        for (index, (title, right)) in pages.enumerated() {
            let guess = await suggester.folder(for: url("https://site\(index).example/page"), title: title, in: saved)
            #expect(guess == nil || guess == right, "\(title) went to \(guess ?? "")")
        }
    }

    /// Measured in the simulator: the process's first ask for the English
    /// model came back empty, and the next, a moment on, had it. A model
    /// that isn't there is asked for again later, never given up on.
    @Test(.enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil))
    func aModelMissingAtFirstIsAskedForAgain() async throws {
        // The model the second ask gets, loaded here: the system's own ask
        // is the very thing that can come back empty.
        let asks = Asks()
        asks.model = try #require(NLEmbedding.sentenceEmbedding(for: .english))
        let suggester = FolderSuggester(retry: .zero) { _ in
            asks.count += 1
            return asks.count == 1 ? nil : asks.model
        }
        let saved = library()
        let pizza = url("https://www.kingarthurbaking.com/pizza")
        #expect(await suggester.folder(for: pizza, title: "Homemade pizza dough", in: saved) == nil)
        #expect(await suggester.folder(for: pizza, title: "Homemade pizza dough", in: saved) == "Recipes")
    }

    @Test func suggestsBySiteWithoutAModel() async {
        let saved = library()
        #expect(await FolderSuggester().folder(for: url("https://booking.com/lisbon"), title: "Hôtel à Lisbonne", in: saved) == "Trips")
    }
}

nonisolated private final class Asks: @unchecked Sendable {
    var count = 0
    var model: NLEmbedding?
}
