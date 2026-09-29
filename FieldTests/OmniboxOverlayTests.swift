import Foundation
import Testing
import UIKit
@testable import Field

// The field's ending drawn after the text instead of written into it, in a
// real field in a window, typed into the way the keyboard types. Whatever the
// field draws, the draft is the same as when the ending was written: these
// check both.
@MainActor struct OmniboxOverlayTests {
    let history: HistoryStore

    init() {
        let defaults = UserDefaults(suiteName: "OmniboxOverlayTests.\(UUID().uuidString)")!
        history = HistoryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: defaults,
            seed: 0
        )
        history.visited(URL(string: "https://google.com/")!, title: "Google")
    }

    @Test func typingDrawsTheEndingWithoutWritingIt() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("go", into: field)

        #expect(field.text == "go")
        #expect(field.ending == "ogle.com")
        #expect(coordinator.omnibox.draft.text == "google.com")
        #expect(coordinator.omnibox.draft.selection == 2..<10)
        #expect(selection(in: field) == 2..<2)
    }

    @Test func typingOverTheDrawnEndingCarriesOnMatching() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("goo", into: field)

        #expect(field.text == "goo")
        #expect(field.ending == "gle.com")
        #expect(coordinator.omnibox.draft.typed == "goo")
    }

    @Test func backspaceTakesOnlyTheDrawnEnding() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("goo", into: field)
        backspace(field)

        #expect(field.text == "goo")
        #expect(field.ending == nil)
        #expect(coordinator.omnibox.draft.text == "goo")
        #expect(coordinator.omnibox.draft.match == nil)
        #expect(selection(in: field) == 3..<3)

        // The next one takes a letter, and still finishes nothing.
        backspace(field)
        #expect(field.text == "go")
        #expect(field.ending == nil)
    }

    @Test func aTouchWritesTheEndingInSelected() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("go", into: field)
        coordinator.unfold(field)

        #expect(field.text == "google.com")
        #expect(field.ending == nil)
        #expect(selection(in: field) == 2..<10)
        #expect(coordinator.omnibox.draft.selection == 2..<10)

        // Typing on replaces it as before, and draws what's left.
        type("o", into: field)
        #expect(coordinator.omnibox.draft.typed == "goo")
        #expect(coordinator.omnibox.draft.text == "google.com")
        #expect(!field.wearsPaint || field.ending == nil)
        type("g", into: field)
        #expect(field.text == "goog")
        #expect(field.ending == "le.com")
    }

    @Test func movingTheCaretKeepsTheEndingAsText() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("go", into: field)
        let caret = try #require(field.position(from: field.beginningOfDocument, offset: 1))
        field.selectedTextRange = field.textRange(from: caret, to: caret)

        #expect(field.text == "google.com")
        #expect(field.ending == nil)
        #expect(coordinator.omnibox.draft.typed == "google.com")
        #expect(coordinator.omnibox.draft.ending.isEmpty)
        #expect(selection(in: field) == 1..<1)
    }

    @Test func anEndingWithNoRoomIsWrittenInSelected() throws {
        let (field, coordinator, window) = try focus(width: 30)
        defer { window.isHidden = true }

        type("go", into: field)

        #expect(field.ending == nil)
        #expect(field.text == "google.com")
        #expect(selection(in: field) == 2..<10)
        #expect(coordinator.omnibox.draft.selection == 2..<10)
    }

    @Test func textBeingComposedDrawsNoEnding() throws {
        let (field, coordinator, window) = try focus()
        defer { window.isHidden = true }

        type("g", into: field)
        field.setMarkedText("o", selectedRange: NSRange(location: 1, length: 0))

        #expect(field.ending == nil)
        #expect(coordinator.omnibox.draft.ending.isEmpty)
    }

    // MARK: -

    /// One letter at a time, as the keyboard types them: it asks the
    /// delegate first, which calling the field directly doesn't.
    private func type(_ letters: String, into field: AddressField.Input) {
        for letter in letters where allowed(field, String(letter)) {
            field.insertText(String(letter))
        }
    }

    private func backspace(_ field: AddressField.Input) {
        if allowed(field, "") { field.deleteBackward() }
    }

    private func allowed(_ field: AddressField.Input, _ string: String) -> Bool {
        guard let delegate = field.delegate, let range = selection(in: field) else { return false }
        let replaced = range.isEmpty && string.isEmpty ? max(0, range.lowerBound - 1)..<range.lowerBound : range
        return delegate.textField?(field, shouldChangeCharactersInRanges: [NSValue(range: NSRange(replaced))], replacementString: string) ?? true
    }

    private func focus(width: CGFloat = 300) throws -> (AddressField.Input, AddressField.Coordinator, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
        let coordinator = AddressField.Coordinator(omnibox: Omnibox(initial: nil, history: history))
        let field = AddressField.Input()
        field.font = .systemFont(ofSize: 17)
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(AddressField.Coordinator.changed(_:)), for: .editingChanged)
        coordinator.field = field
        window.addSubview(field)
        field.frame = CGRect(x: 0, y: 100, width: width, height: 44)
        coordinator.open(field)
        return (field, coordinator, window)
    }

    private func selection(in field: UITextField) -> Range<Int>? {
        guard let range = field.selectedTextRange else { return nil }
        return field.offset(from: field.beginningOfDocument, to: range.start)
            ..< field.offset(from: field.beginningOfDocument, to: range.end)
    }
}
