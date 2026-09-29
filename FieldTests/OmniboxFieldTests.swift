import Foundation
import Testing
import UIKit
@testable import Field

// The field itself, in a window, focused the way the omnibox focuses it:
// what UIKit does on its own as a field takes focus mustn't undo the draft.
@MainActor struct OmniboxFieldTests {
    @Test func anOpenedFieldHasTheWholeAddressSelected() throws {
        let (field, coordinator, window) = try focus(URL(string: "https://example.com/article")!)
        defer { window.isHidden = true }

        coordinator.open(field)

        #expect(field.isFirstResponder)
        #expect(field.text == "example.com/article")
        #expect(selection(in: field) == 0..<19)
        #expect(coordinator.omnibox.draft.selection == 0..<19)
    }

    @Test func theFirstLetterReplacesTheOpenedAddress() throws {
        let (field, coordinator, window) = try focus(URL(string: "https://example.com/article")!)
        defer { window.isHidden = true }

        coordinator.open(field)
        field.insertText("w")

        #expect(field.text?.hasPrefix("w") == true)
        #expect(coordinator.omnibox.draft.typed == "w")
    }

    private func focus(_ initial: URL) throws -> (AddressField.Input, AddressField.Coordinator, UIWindow) {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
        let history = HistoryStore(directory: FileManager.default.temporaryDirectory, seed: 0)
        let coordinator = AddressField.Coordinator(omnibox: Omnibox(initial: initial, history: history))
        let field = AddressField.Input()
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(AddressField.Coordinator.changed(_:)), for: .editingChanged)
        field.text = coordinator.omnibox.draft.text
        coordinator.field = field
        window.addSubview(field)
        field.frame = CGRect(x: 0, y: 100, width: 300, height: 44)
        return (field, coordinator, window)
    }

    private func selection(in field: UITextField) -> Range<Int>? {
        guard let range = field.selectedTextRange else { return nil }
        return field.offset(from: field.beginningOfDocument, to: range.start)
            ..< field.offset(from: field.beginningOfDocument, to: range.end)
    }
}
