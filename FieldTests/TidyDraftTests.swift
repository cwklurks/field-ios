import Foundation
import Testing
@testable import FieldKit
@testable import Field

/// The preview sheet's state: groups stream in, can be renamed, unchecked
/// and moved, and nothing moves in the grid until Apply. Apply sets the
/// grouping at once and offers Undo, which puts the old one back.
@MainActor
struct TidyDraftTests {
    static let id = TidyEngineTests.id
    static let tabs = TidyEngineTests.tabs

    func suggestion(done: Bool = true) -> TidySuggestion {
        TidySuggestion(groups: [
            TidyGroup(name: "Lisbon trip", ids: [Self.id(1), Self.id(2), Self.id(5)]),
            TidyGroup(name: "Baking", ids: [Self.id(3), Self.id(4), Self.id(6)]),
        ], engine: .model, done: done)
    }

    // MARK: - the draft

    @Test func startsThinkingAndCannotApply() {
        let draft = TidyDraft(tabs: Self.tabs)
        #expect(draft.thinking)
        #expect(draft.sections.isEmpty)
        #expect(!draft.canApply)
    }

    /// Groups show as they come; Apply waits for the answer to be whole.
    @Test func streamsThenSettles() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(TidySuggestion(groups: [suggestion().groups[0]], engine: .model, done: false))
        #expect(draft.sections.map(\.name) == ["Lisbon trip"])
        #expect(!draft.canApply)
        let first = draft.sections[0].id
        draft.receive(suggestion())
        #expect(draft.sections.map(\.name) == ["Lisbon trip", "Baking"])
        // The same group keeps its identity as it grows, so it doesn't redraw.
        #expect(draft.sections[0].id == first)
        #expect(!draft.thinking)
        #expect(draft.engine == .model)
        #expect(draft.canApply)
    }

    @Test func renames() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        draft.rename(draft.sections[1].id, to: "Bread")
        #expect(draft.chosen.map(\.name) == ["Lisbon trip", "Bread"])
    }

    /// A name cleared keeps the suggested one rather than making a group
    /// with no name.
    @Test func anEmptyNameKeepsTheSuggestion() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        draft.rename(draft.sections[1].id, to: "   ")
        #expect(draft.chosen.map(\.name) == ["Lisbon trip", "Baking"])
    }

    @Test func uncheckedTabsStayWhereTheyAre() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        draft.toggle(Self.id(2))
        #expect(!draft.isChecked(Self.id(2)))
        #expect(draft.chosen[0].ids == [Self.id(1), Self.id(5)])
        #expect(draft.chosenCount == 5)
        draft.toggle(Self.id(2))
        #expect(draft.chosenCount == 6)
    }

    /// Moved to another group: it goes last there, checked.
    @Test func movesBetweenGroups() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        draft.toggle(Self.id(5))
        draft.move(Self.id(5), to: draft.sections[1].id)
        #expect(draft.sections[0].tabs == [Self.id(1), Self.id(2)])
        #expect(draft.sections[1].tabs == [Self.id(3), Self.id(4), Self.id(6), Self.id(5)])
        #expect(draft.isChecked(Self.id(5)))
    }

    /// A group with every tab unchecked or moved away isn't made.
    @Test func anEmptiedGroupIsNotMade() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        for n in [3, 4, 6] { draft.toggle(Self.id(n)) }
        #expect(draft.chosen.map(\.name) == ["Lisbon trip"])
    }

    @Test func nothingFoundSaysSo() {
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(TidySuggestion(groups: [], engine: .rules, done: true))
        #expect(!draft.thinking)
        #expect(draft.sections.isEmpty)
        #expect(!draft.canApply)
    }

    // MARK: - apply and undo

    /// A grouping held where Tabs will hold it, and the toasts it was asked for.
    final class Board {
        var grouping = Session.Grouping()
        var toasts: [(String, Toaster.Offer)] = []
    }

    func flow(_ board: Board) -> TidyFlow {
        TidyFlow(grouping: { board.grouping }, regroup: { board.grouping = $0 },
                 toast: { board.toasts.append(($0, $1)) })
    }

    @Test func applySetsTheGroupsAndOffersUndo() {
        let board = Board()
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        draft.toggle(Self.id(6))
        flow(board).apply(draft)
        #expect(board.grouping.groups.map(\.name) == ["Lisbon trip", "Baking"])
        #expect(board.grouping.membership.count == 5)
        #expect(board.grouping.membership[Self.id(6)] == nil)
        #expect(board.toasts.map(\.0) == ["Grouped 5 tabs"])
        #expect(board.toasts.first?.1.title == "Undo")
    }

    @Test func undoPutsTheOldGroupingBack() {
        let board = Board()
        board.grouping = Session.Grouping(groups: [Session.Group(id: Self.id(900), name: "Old")],
                                          membership: [Self.id(1): Self.id(900)])
        let before = board.grouping
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(suggestion())
        flow(board).apply(draft)
        #expect(board.grouping != before)
        board.toasts.last?.1.perform()
        #expect(board.grouping == before)
    }

    /// Nothing chosen, nothing changes and nothing is said.
    @Test func applyingNothingDoesNothing() {
        let board = Board()
        let draft = TidyDraft(tabs: Self.tabs)
        draft.receive(TidySuggestion(groups: [], engine: .rules, done: true))
        flow(board).apply(draft)
        #expect(board.grouping == Session.Grouping())
        #expect(board.toasts.isEmpty)
    }

    // MARK: - add similar tabs

    @Test func similarAddsToTheGroup() {
        let board = Board()
        let lisbon = Self.id(900)
        board.grouping = Session.Grouping(groups: [Session.Group(id: lisbon, name: "Lisbon trip")],
                                          membership: [Self.id(1): lisbon, Self.id(2): lisbon])
        let draft = TidyDraft(tabs: Self.tabs, mode: .similar(group: lisbon, name: "Lisbon trip"))
        draft.receiveSimilar([Self.id(5), Self.id(3)])
        #expect(draft.sections.map(\.name) == ["Lisbon trip"])
        draft.toggle(Self.id(3))
        flow(board).apply(draft)
        #expect(board.grouping.membership[Self.id(5)] == lisbon)
        #expect(board.grouping.membership[Self.id(3)] == nil)
        #expect(board.toasts.map(\.0) == ["Added 1 tab to Lisbon trip"])
    }
}
