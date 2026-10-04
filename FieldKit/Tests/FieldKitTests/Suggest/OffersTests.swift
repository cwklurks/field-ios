import Foundation
import Testing
@testable import FieldKit

// The rows, put together: places and past searches nearest the field, the
// engine's suggestions beyond them, and the one the field finishes inline.
struct OffersTests {
    let google = Engine.google.template(custom: "")

    func place(_ key: String, _ kind: Suggestion.Kind = .visited) -> Suggestion {
        Suggestion(key: key, title: "", url: URL(string: "https://" + key)!, kind: kind)
    }

    func searched(_ words: String) -> Suggestion {
        Suggestion(key: words, title: "", url: Engine.url(for: words, template: google)!, kind: .searched)
    }

    func keys(_ list: [Suggestion]) -> [String] { list.map(\.key) }

    // MARK: - merging

    @Test func aPlaceYouHaveBeenThatStartsSoWinsInline() {
        let list = Offers.merge(
            places: [place("swift.org")], searches: [searched("swift concurrency")], typed: "swi"
        )
        #expect(keys(list) == ["swift.org", "swift concurrency"])
        #expect(Offers.completion(for: "swi", among: list)?.suggestion.key == "swift.org")
    }

    @Test func yourOwnSearchBeatsAPlaceTheAppMerelyKnows() {
        let list = Offers.merge(
            places: [place("swift.org", .known)], searches: [searched("swift concurrency")], typed: "swi"
        )
        #expect(keys(list) == ["swift concurrency", "swift.org"])
        let hit = Offers.completion(for: "swi", among: list)
        #expect(hit?.ending == "ft concurrency")
        #expect(hit?.suggestion.kind == .searched)
    }

    @Test func aPlaceMatchedInsideComesAfterASearchMatchedFromTheStart() {
        let list = Offers.merge(
            places: [place("mail.google.com"), place("google.com", .known)],
            searches: [searched("google fonts")],
            typed: "goo"
        )
        // mail.google.com doesn't start with "goo"; the search does.
        #expect(keys(list) == ["google fonts", "mail.google.com", "google.com"])
    }

    @Test func aSearchMatchedOnALaterWordComesLast() {
        let list = Offers.merge(
            places: [place("concur.com", .known)],
            searches: [searched("swift concurrency")],
            typed: "conc"
        )
        #expect(keys(list) == ["concur.com", "swift concurrency"])
    }

    @Test func fiveAtMostNearestTheField() {
        let list = Offers.merge(
            places: (0..<5).map { place("s\($0).com") },
            searches: [searched("s one"), searched("s two"), searched("s three")],
            typed: "s"
        )
        #expect(list.count == Offers.nearLimit)
        #expect(Offers.nearLimit == 5)
    }

    @Test func schemeAndWwwDoNotStopAPlaceStartingSo() {
        let list = Offers.merge(
            places: [place("swift.org")], searches: [searched("swift concurrency")], typed: "https://www.swi"
        )
        #expect(keys(list) == ["swift.org", "swift concurrency"])
    }

    // MARK: - inline

    @Test func theEndingKeepsTheSearchAsItWasWritten() {
        let list = [searched("SwiftUI layout")]
        #expect(Offers.completion(for: "swi", among: list)?.ending == "ftUI layout")
    }

    @Test func nothingInlineWhenNothingCarriesOn() {
        #expect(Offers.completion(for: "conc", among: [searched("swift concurrency")]) == nil)
        #expect(Offers.completion(for: "", among: [searched("swift concurrency")]) == nil)
        #expect(Offers.completion(for: "swift concurrency", among: [searched("swift concurrency")]) == nil)
    }

    @Test func neverInlineFromTheEngine() {
        let remote = Offers.remote(["swift concurrency"], typed: "swi", near: [], template: google)
        #expect(Offers.completion(for: "swi", among: remote) == nil)
    }

    @Test func placesFinishAsTheyAlwaysHave() {
        let list = [place("google.com")]
        let hit = Offers.completion(for: "GO", among: list)
        #expect(hit?.ending == "ogle.com")
    }

    // MARK: - the engine's

    @Test func theEnginesSuggestionsAreSearches() {
        let remote = Offers.remote(["swift concurrency", "swift charts"], typed: "swift c", near: [], template: google)
        #expect(keys(remote) == ["swift concurrency", "swift charts"])
        #expect(remote.allSatisfy { $0.kind == .search })
        #expect(remote.first?.url.absoluteString == "https://www.google.com/search?q=swift%20concurrency")
    }

    @Test func whatIsAlreadyThereIsNotSaidTwice() {
        let near = [searched("Swift Concurrency"), place("swift.org")]
        let remote = Offers.remote(
            ["swift c", "swift concurrency", "swift charts", "Swift Charts", "swift.org"],
            typed: "Swift C", near: near, template: google
        )
        // What was typed, a past search, a repeat and an address go.
        #expect(keys(remote) == ["swift charts"])
    }

    @Test func fourAtMostAndNoMoreThanEightInAll() {
        let words = (0..<10).map { "swift \($0)" }
        #expect(Offers.remote(words, typed: "swift", near: [], template: google).count == 4)
        let near = (0..<5).map { place("s\($0).com") }
        #expect(Offers.remote(words, typed: "swift", near: near, template: google).count == 3)
    }

    @Test func aSuggestionThatIsASecretIsNotShown() {
        let remote = Offers.remote(["swift 4111 1111 1111 1111", "swift ok"], typed: "swift", near: [], template: google)
        #expect(keys(remote) == ["swift ok"])
    }

    @Test func aPlaceAndASearchWithTheSameWordsAreTwoRows() {
        let one = place("localhost")
        let other = Suggestion(key: "localhost", title: "", url: URL(string: "https://www.google.com/search?q=localhost")!, kind: .search)
        #expect(one.id != other.id)
        #expect(searched("Swift").id == Offers.remote(["swift"], typed: "s", near: [], template: google).first?.id)
    }

    // MARK: - while the next answer is on its way

    @Test func typingOnKeepsWhatStillFits() {
        let shown = Offers.remote(["swift concurrency", "swift charts", "swiftui"], typed: "swi", near: [], template: google)
        #expect(keys(Offers.kept(shown, asked: "swi", typed: "swift c")) == ["swift concurrency", "swift charts"])
    }

    @Test func anythingButTypingOnClearsThem() {
        let shown = Offers.remote(["swift concurrency", "swift charts"], typed: "swift", near: [], template: google)
        // A letter taken off, a different word, the field emptied.
        #expect(Offers.kept(shown, asked: "swift", typed: "swif").isEmpty)
        #expect(Offers.kept(shown, asked: "swift", typed: "rust").isEmpty)
        #expect(Offers.kept(shown, asked: "swift", typed: "").isEmpty)
    }

    @Test func whatWouldBeTheTypedTextItselfGoes() {
        let shown = Offers.remote(["swift concurrency", "swift c"], typed: "swift", near: [], template: google)
        #expect(keys(Offers.kept(shown, asked: "swift", typed: "swift c")) == ["swift concurrency"])
    }
}
