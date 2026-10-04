import Foundation
import Testing
import FieldKit
@testable import Field

// Past searches and the engine's suggestions, through the Omnibox the field
// feeds: what is offered, what is remembered, and what is sent. The network
// is a fake that answers at once, or after a delay, and says what it was
// asked.
@MainActor @Suite(.serialized) struct OmniboxSuggestTests {
    actor Network: SuggestFetching {
        var asked: [String] = []
        let delays: [String: Duration]

        init(delays: [String: Duration] = [:]) { self.delays = delays }

        func data(for url: URL) async throws -> Data {
            let words = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            asked.append(words)
            try await Task.sleep(for: delays[words] ?? .zero)
            return Data(#"["\#(words)",["\#(words)one","\#(words) two","\#(words) three"]]"#.utf8)
        }
    }

    let defaults: UserDefaults
    let history: HistoryStore

    init() {
        defaults = UserDefaults(suiteName: "OmniboxSuggestTests.\(UUID().uuidString)")!
        history = HistoryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: defaults,
            seed: 0
        )
        history.visited(URL(string: "https://google.com/")!, title: "Google")
    }

    private func omnibox(_ network: Network = Network(), privately: Bool = false) -> Omnibox {
        Omnibox(
            initial: nil, history: history, defaults: defaults,
            privately: { privately }, suggester: Suggester(fetch: network, wait: .zero)
        )
    }

    @discardableResult
    private func type(_ text: String, into omnibox: Omnibox, cause: Draft.Cause = .typed) -> Draft {
        let end = text.utf16.count
        return omnibox.edited(to: text, selection: end..<end, marked: false, cause: cause)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - past searches

    @Test func aSearchMadeIsOfferedAndFinishedNextTime() {
        let box = omnibox()
        type("swift concurrency", into: box)
        #expect(box.submit() == URL(string: "https://www.google.com/search?q=swift%20concurrency"))

        let next = omnibox()
        let draft = type("swi", into: next)
        #expect(next.offers.first?.key == "swift concurrency")
        #expect(next.offers.first?.kind == .searched)
        #expect(draft.ending == "ft concurrency")
        #expect(next.picked == "?swift concurrency")
        #expect(next.submit() == URL(string: "https://www.google.com/search?q=swift%20concurrency"))
    }

    @Test func aPlaceYouHaveBeenStillWinsInline() {
        let box = omnibox()
        type("google fonts", into: box)
        _ = box.submit()
        let next = omnibox()
        let draft = type("go", into: next)
        #expect(draft.match?.key == "google.com")
        #expect(next.offers.map(\.key).prefix(2) == ["google.com", "google fonts"])
    }

    @Test func anAddressIsNotRememberedAsASearch() {
        let box = omnibox()
        type("example.com", into: box)
        _ = box.submit()
        #expect(history.searches.isEmpty)
    }

    @Test func aTappedSearchIsRemembered() {
        let box = omnibox()
        let row = Suggestion(key: "swift charts", title: "", url: URL(string: "https://www.google.com/search?q=swift%20charts")!, kind: .search)
        box.chose(row)
        #expect(!history.searches.isEmpty)
    }

    @Test func privateRemembersNothing() {
        let box = omnibox(privately: true)
        type("swift concurrency", into: box)
        _ = box.submit()
        box.chose(Suggestion(key: "swift charts", title: "", url: URL(string: "https://www.google.com/search?q=swift%20charts")!, kind: .search))
        #expect(history.searches.isEmpty)
    }

    // MARK: - the engine's suggestions

    @Test func theEnginesSuggestionsArriveBeyondTheFieldsOwn() async throws {
        let network = Network()
        let box = omnibox(network)
        var late = 0
        box.onLate = { late += 1 }
        type("go", into: box)  // google.com, a place: not sent.
        type("goat cheese", into: box)
        try await settle()
        #expect(await network.asked == ["goat cheese"])
        #expect(late == 1)
        #expect(box.offers.map(\.key) == ["goat cheeseone", "goat cheese two", "goat cheese three"])
        #expect(box.offers.allSatisfy { $0.kind == .search })
        #expect(box.listed)
    }

    @Test func nothingIsSentInPrivate() async throws {
        let network = Network()
        let box = omnibox(network, privately: true)
        type("goat cheese", into: box)
        try await settle()
        #expect(await network.asked.isEmpty)
        #expect(box.offers.isEmpty)
    }

    @Test func nothingIsSentWithTheSwitchOff() async throws {
        defaults.set(false, forKey: Suggest.defaultsKey)
        let network = Network()
        let box = omnibox(network)
        type("goat cheese", into: box)
        try await settle()
        #expect(await network.asked.isEmpty)
    }

    @Test func anAddressOrOneLetterIsNeverSent() async throws {
        let network = Network()
        let box = omnibox(network)
        type("x", into: box)
        type("example.com/private/page", into: box, cause: .pasted)
        try await settle()
        #expect(await network.asked.isEmpty)
    }

    @Test func theEngineChosenIsAsked() async throws {
        defaults.set(Engine.startpage.rawValue, forKey: "engine")
        let network = Network()
        let box = omnibox(network)
        type("goat cheese", into: box)
        try await settle()
        // Startpage has nothing to offer, so it isn't asked.
        #expect(await network.asked.isEmpty)
    }

    @Test func anOldAnswerNeverShowsForNewWords() async throws {
        let network = Network(delays: ["goat": .milliseconds(100)])
        let box = omnibox(network)
        type("goat", into: box)
        try await Task.sleep(for: .milliseconds(20))
        type("rust", into: box, cause: .pasted)
        try await Task.sleep(for: .milliseconds(300))
        #expect(box.offers.map(\.key).allSatisfy { $0.hasPrefix("rust") })
        #expect(!box.offers.isEmpty)
    }

    @Test func typingOnKeepsTheRowsThatStillFit() async throws {
        let network = Network(delays: ["goat c": .seconds(5)])
        let box = omnibox(network)
        type("goat", into: box)
        try await settle()
        #expect(box.offers.map(\.key) == ["goatone", "goat two", "goat three"])
        type("goat ", into: box)
        // Only "goat two" and "goat three" carry on from "goat ".
        #expect(box.offers.map(\.key) == ["goat two", "goat three"])
        type("goat c", into: box)
        #expect(box.offers.isEmpty)
        type("goat", into: box, cause: .deleted)
        #expect(box.offers.isEmpty)
    }

    @Test func goingStopsTheAsking() async throws {
        let network = Network(delays: ["goat cheese": .milliseconds(80)])
        let box = omnibox(network)
        type("goat cheese", into: box)
        _ = box.submit()
        try await settle()
        #expect(box.offers.allSatisfy { $0.kind != .search })
    }

    @Test func closingTheFieldStopsTheAsking() async throws {
        let box = Omnibox(
            initial: nil, history: history, defaults: defaults,
            privately: { false }, suggester: Suggester(fetch: Network(), wait: .milliseconds(80))
        )
        type("goat cheese", into: box)
        box.ended()
        try await settle()
        #expect(box.offers.isEmpty)
    }

    @Test func fillPutsTheWordsInTheField() {
        let box = omnibox()
        var filled: [String] = []
        box.onFill = { filled.append($0) }
        box.fill(Suggestion(key: "goat cheese", title: "", url: URL(string: "https://www.google.com/search?q=goat%20cheese")!, kind: .search))
        #expect(filled == ["goat cheese"])
    }

    @Test func untilToldOtherwiseItIsPrivate() async throws {
        let network = Network()
        let box = Omnibox(initial: nil, history: history, defaults: defaults, suggester: Suggester(fetch: network, wait: .zero))
        type("goat cheese", into: box)
        _ = box.submit()
        try await settle()
        #expect(await network.asked.isEmpty)
        #expect(history.searches.isEmpty)
    }
}
