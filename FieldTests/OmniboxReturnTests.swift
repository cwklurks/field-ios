import Foundation
import Testing
import FieldKit
@testable import Field

// Where the field goes, and what it offers on the way: the Omnibox model fed
// edits the way the field's coordinator feeds them, over a history that
// knows a couple of places and settings of its own.
@MainActor struct OmniboxReturnTests {
    let defaults: UserDefaults
    let history: HistoryStore

    init() {
        defaults = UserDefaults(suiteName: "OmniboxReturnTests.\(UUID().uuidString)")!
        history = HistoryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: defaults,
            seed: 0
        )
        history.visited(URL(string: "https://google.com/")!, title: "Google")
        history.visited(URL(string: "https://github.com/field?tab=readme")!, title: "Field")
    }

    private func omnibox(initial: URL? = nil) -> Omnibox {
        Omnibox(initial: initial, history: history, defaults: defaults)
    }

    /// The text typed at the end of the field, as the coordinator reports it.
    @discardableResult
    private func type(_ text: String, into omnibox: Omnibox, cause: Draft.Cause = .typed) -> Draft {
        let end = text.utf16.count
        return omnibox.edited(to: text, selection: end..<end, marked: false, cause: cause)
    }

    /// Copying all of an untouched field copies the page's whole address.
    @Test func theFieldStandsForItsPageUntilTouched() {
        let page = URL(string: "https://github.com/field?tab=readme")!
        let box = omnibox(initial: page)
        #expect(box.page == page)
        type("gi", into: box)
        #expect(box.page == nil)
    }

    // MARK: - Return

    @Test func returnOnABlankFieldIsRefused() {
        let box = omnibox()
        #expect(box.submit() == nil)
        #expect(box.refused)
        #expect(box.refusals == 1)
    }

    @Test func returnOnAFieldEmptiedIsRefusedEachTime() {
        let box = omnibox(initial: URL(string: "https://example.com/page"))
        type("", into: box, cause: .deleted)
        #expect(box.submit() == nil)
        #expect(box.submit() == nil)
        #expect(box.refusals == 2)
    }

    @Test func spacesAloneAreRefused() {
        let box = omnibox()
        type("   ", into: box)
        #expect(box.submit() == nil)
        #expect(box.refused)
    }

    @Test func theNextEditTakesTheRedAway() {
        let box = omnibox()
        _ = box.submit()
        type("g", into: box)
        #expect(!box.refused)
        #expect(box.refusals == 1)
    }

    @Test func returnOnTheUntouchedAddressGoesBackToAllOfIt() {
        let page = URL(string: "https://www.example.com/a/b?q=1#top")!
        let box = omnibox(initial: page)
        #expect(box.draft.text == "example.com/a/b")
        #expect(box.submit() == page)
    }

    @Test func returnTakesTheCompletionsOwnAddress() {
        let box = omnibox()
        // Past the front page, which a deep visit also counts as visited.
        let draft = type("github.com/f", into: box)
        #expect(draft.text == "github.com/field")
        #expect(box.submit() == URL(string: "https://github.com/field?tab=readme"))
    }

    @Test func returnWithoutACompletionGoesToTheAddressTyped() {
        let box = omnibox()
        type("example.org", into: box)
        #expect(box.submit() == URL(string: "https://example.org"))
    }

    @Test func wordsGoToTheChosenEngine() {
        defaults.set(Engine.duckduckgo.rawValue, forKey: "engine")
        let box = omnibox()
        type("weather today", into: box)
        #expect(box.submit() == URL(string: "https://duckduckgo.com/?q=weather%20today"))
    }

    @Test func wordsGoToTheCustomTemplate() {
        defaults.set(Engine.custom.rawValue, forKey: "engine")
        defaults.set("https://search.example/find?w=%s", forKey: "engine.custom")
        let box = omnibox()
        type("field notes", into: box)
        #expect(box.submit() == URL(string: "https://search.example/find?w=field%20notes"))
    }

    @Test func wordsGoToTheStandardEngineWhenNoneIsChosen() {
        let box = omnibox()
        type("field notes", into: box)
        #expect(box.submit() == URL(string: "https://www.google.com/search?q=field%20notes"))
    }

    @Test func aBackspacedCompletionIsNotWhereReturnGoes() {
        let box = omnibox()
        type("goo", into: box)
        type("goo", into: box, cause: .deleted)
        #expect(box.picked == nil)
        #expect(box.submit() == URL(string: "https://www.google.com/search?q=goo"))
    }

    // MARK: - the rows

    @Test func anOpenedFieldOffersNothing() {
        let box = omnibox(initial: URL(string: "https://google.com/"))
        #expect(box.offers.isEmpty)
        #expect(!box.listed)
    }

    @Test func anEmptiedFieldOffersNothing() {
        let box = omnibox()
        type("go", into: box)
        #expect(box.listed)
        type("", into: box, cause: .deleted)
        #expect(box.offers.isEmpty)
        #expect(!box.listed)
        #expect(box.picked == nil)
    }

    @Test func theRowBeingFinishedIsPicked() {
        let box = omnibox()
        type("go", into: box)
        #expect(box.offers.first?.key == "google.com")
        #expect(box.picked == "google.com")
    }
}
