import Foundation
import Testing
import FieldKit
@testable import Field

// The field's inline completion, edit by edit. Each edit is made the way
// UIKit makes it (the selection replaced, or the letter before the caret
// taken off), then handed to the draft the way the field's coordinator
// hands it on. Completions come from FieldKit's own rule, so "g" alone
// finishes the first place it starts and "GO" finds google.com.
struct OmniboxTests {
    // MARK: - typing

    @Test func typingFinishesTheBestMatchAndSelectsTheRest() {
        var field = Typist()
        field.type("go")
        #expect(field.text == "google.com")
        #expect(field.selected == "ogle.com")
        #expect(field.draft.ending == "ogle.com")
        #expect(field.draft.match?.key == "google.com")
    }

    /// As Safari does: the first letter already proposes somewhere.
    @Test func oneLetterIsEnoughToGuessFrom() {
        var field = Typist()
        field.type("g")
        #expect(field.text == "google.com")
        #expect(field.selected == "oogle.com")
        #expect(field.draft.match?.key == "google.com")
    }

    @Test func typingOverTheCompletionCarriesOnMatching() {
        var field = Typist()
        field.type("go")
        field.type("o")
        #expect(field.text == "google.com")
        #expect(field.selected == "gle.com")
        #expect(field.draft.typed == "goo")
    }

    @Test func typingOnPastTheCompletionFindsAnotherPlace() {
        var field = Typist()
        field.type("gi")
        #expect(field.text == "github.com")
        field.type("thub.com/")
        #expect(field.text == "github.com/field")
        #expect(field.selected == "field")
        #expect(field.draft.match?.url == URL(string: "https://github.com/field"))
    }

    @Test func aCompletionThatNoLongerMatchesIsDropped() {
        var field = Typist()
        field.type("goo")
        #expect(field.text == "google.com")
        field.type("x")
        #expect(field.text == "goox")
        #expect(field.caret == 4)
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.match == nil)
    }

    @Test func uppercaseKeepsWhatWasTypedAndFinishesInTheKeysCase() {
        var field = Typist()
        field.type("GO")
        #expect(field.text == "GOogle.com")
        #expect(field.selected == "ogle.com")
        #expect(field.draft.match?.url == URL(string: "https://google.com/"))
    }

    // MARK: - taking letters off

    @Test func backspaceRemovesOnlyTheCompletion() {
        var field = Typist()
        field.type("goo")
        field.backspace()
        #expect(field.text == "goo")
        #expect(field.caret == 3)
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.match == nil)
    }

    @Test func aSecondBackspaceTakesALetterAndStillDoesNotComplete() {
        var field = Typist()
        field.type("goo")
        field.backspace()
        field.backspace()
        #expect(field.text == "go")
        #expect(field.caret == 2)
        #expect(field.draft.ending.isEmpty)
    }

    @Test func typingAgainAfterABackspaceCompletesAgain() {
        var field = Typist()
        field.type("goo")
        field.backspace()
        field.backspace()
        field.type("o")
        #expect(field.text == "google.com")
        #expect(field.selected == "gle.com")
    }

    @Test func deleteForwardRemovesOnlyTheCompletion() {
        var field = Typist()
        field.type("goo")
        field.deleteForward()
        #expect(field.text == "goo")
        #expect(field.caret == 3)
        #expect(field.draft.ending.isEmpty)
    }

    @Test func deleteForwardInTheMiddleDoesNotComplete() {
        var field = Typist()
        field.paste("gxoogle.com")
        field.tap(at: 1)
        field.deleteForward()
        #expect(field.text == "google.com")
        #expect(field.caret == 1)
        #expect(field.draft.ending.isEmpty)
    }

    // MARK: - pasting

    @Test func aPasteIsNeverCompleted() {
        var field = Typist()
        field.paste("goo")
        #expect(field.text == "goo")
        #expect(field.caret == 3)
        #expect(field.draft.ending.isEmpty)
    }

    @Test func aPasteOverTheCompletionReplacesIt() {
        var field = Typist()
        field.type("go")
        field.paste("od")
        #expect(field.text == "good")
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.match == nil)
    }

    @Test func typingAfterAPasteCompletes() {
        var field = Typist()
        field.paste("goo")
        field.type("g")
        #expect(field.text == "google.com")
        #expect(field.selected == "le.com")
    }

    // MARK: - the caret

    @Test func movingTheCaretKeepsTheCompletionAsText() {
        var field = Typist()
        field.type("go")
        field.tap(at: 1)
        #expect(field.text == "google.com")
        #expect(field.caret == 1)
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.typed == "google.com")
        // Still the place it spells, so Return still goes there.
        #expect(field.draft.match?.key == "google.com")
    }

    @Test func typingInTheMiddleDoesNotComplete() {
        var field = Typist()
        field.type("go")
        field.tap(at: 1)
        field.type("x")
        #expect(field.text == "gxoogle.com")
        #expect(field.caret == 2)
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.match == nil)
    }

    @Test func movingTheCaretToTheEndAndTypingCompletesAgain() {
        var field = Typist()
        field.type("gi")
        field.tap(at: 10)
        field.type("/")
        #expect(field.text == "github.com/field")
        #expect(field.selected == "field")
    }

    @Test func theFieldsOwnSelectionOfTheEndingChangesNothing() {
        var field = Typist()
        field.type("go")
        let before = field.draft
        field.draft.selected(before.selection)
        #expect(field.draft == before)
    }

    // MARK: - marked text

    @Test func textBeingComposedIsNeverCompleted() {
        var field = Typist()
        field.compose("go")
        #expect(field.text == "go")
        #expect(field.caret == 2)
        #expect(field.draft.ending.isEmpty)
    }

    @Test func composingOverTheCompletionDropsIt() {
        var field = Typist()
        field.type("go")
        field.compose("k")
        #expect(field.text == "gok")
        #expect(field.caret == 3)
        #expect(field.draft.ending.isEmpty)
        #expect(field.draft.match == nil)
    }

    @Test func aFinishedCompositionCompletesLikeTyping() {
        var field = Typist()
        field.compose("go")
        field.commit()
        #expect(field.text == "google.com")
        #expect(field.selected == "ogle.com")
    }

    // MARK: - opening

    @Test func anOpenedFieldStartsWithEverythingSelected() {
        let draft = Draft(text: "example.com/page")
        #expect(draft.text == "example.com/page")
        #expect(draft.selection == 0..<16)
        #expect(draft.ending.isEmpty)
    }

    @Test func typingOverTheOpenedAddressStartsAgain() {
        var field = Typist(draft: Draft(text: "example.com/page"))
        field.type("go")
        #expect(field.text == "google.com")
        #expect(field.selected == "ogle.com")
    }

    @Test func anEmptyDraftHasACaretAndNothingElse() {
        let draft = Draft()
        #expect(draft.text.isEmpty)
        #expect(draft.selection == 0..<0)
    }

    // MARK: - counting as UIKit counts

    @Test func theSelectionIsInUTF16LikeUIKits() {
        var field = Typist()
        field.type("🙂.")
        #expect(field.text == "🙂.ws")
        #expect(field.draft.selection == 3..<5)
        #expect(field.selected == "ws")
    }
}

/// A text field as UIKit edits one, with the draft doing what the coordinator
/// does after each edit.
private struct Typist {
    var draft = Draft()
    var marked = false

    static let places = [
        place("google.com", "https://google.com/"),
        place("github.com", "https://github.com/"),
        place("github.com/field", "https://github.com/field"),
        place("🙂.ws", "https://xn--938h.ws/"),
    ]

    static func place(_ key: String, _ url: String) -> Suggestion {
        Suggestion(key: key, title: "", url: URL(string: url)!, kind: .visited)
    }

    var text: String { draft.text }
    var caret: Int? { draft.selection.isEmpty ? draft.selection.lowerBound : nil }
    var selected: String { (text as NSString).substring(with: NSRange(draft.selection)) }

    /// One letter at a time, over whatever is selected.
    mutating func type(_ letters: String) {
        for letter in letters {
            replaceSelection(with: String(letter), cause: .typed)
        }
    }

    mutating func paste(_ words: String) {
        replaceSelection(with: words, cause: .pasted)
    }

    /// Marked text, as a Japanese or Chinese keyboard leaves it mid-word.
    mutating func compose(_ letters: String) {
        marked = true
        replaceSelection(with: letters, cause: .typed)
    }

    /// The composition is accepted: the same text, no longer marked.
    mutating func commit() {
        marked = false
        edited(text, selection: draft.selection, cause: .typed)
    }

    mutating func backspace() {
        let selection = NSRange(draft.selection)
        guard selection.length == 0 else { return replace(selection, with: "", cause: .deleted) }
        guard selection.location > 0 else { return }
        let letter = (text as NSString).rangeOfComposedCharacterSequence(at: selection.location - 1)
        replace(letter, with: "", cause: .deleted)
    }

    mutating func deleteForward() {
        let selection = NSRange(draft.selection)
        guard selection.length == 0 else { return replace(selection, with: "", cause: .deleted) }
        guard selection.location < (text as NSString).length else { return }
        let letter = (text as NSString).rangeOfComposedCharacterSequence(at: selection.location)
        replace(letter, with: "", cause: .deleted)
    }

    mutating func tap(at offset: Int) {
        draft.selected(offset..<offset)
    }

    private mutating func replaceSelection(with words: String, cause: Draft.Cause) {
        replace(NSRange(draft.selection), with: words, cause: cause)
    }

    private mutating func replace(_ range: NSRange, with words: String, cause: Draft.Cause) {
        let after = (text as NSString).replacingCharacters(in: range, with: words)
        let caret = range.location + (words as NSString).length
        edited(after, selection: caret..<caret, cause: cause)
    }

    private mutating func edited(_ text: String, selection: Range<Int>, cause: Draft.Cause) {
        draft.edited(to: text, selection: selection, marked: marked, cause: cause) { typed in
            History().completion(for: typed, among: Self.places)
        }
    }
}
