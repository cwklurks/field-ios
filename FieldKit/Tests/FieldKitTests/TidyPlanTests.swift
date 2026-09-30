import Foundation
import Testing
@testable import FieldKit

/// What sits between the language model and the tab grid: the prompt's list
/// of tabs, the check on what the model hands back (it may name tabs that
/// don't exist, or one tab twice), the batches a small context window needs,
/// and joining one batch's groups to the last's.
struct TidyPlanTests {
    static let id = TidyTests.id

    func tab(_ n: Int, _ title: String, _ url: String) -> TabInfo {
        TabInfo(id: Self.id(n), title: title, url: URL(string: url)!)
    }

    var batch: [TabInfo] {
        [
            tab(1, "Flights to Lisbon", "https://www.google.com/flights"),
            tab(2, "Hotels in Alfama", "https://booking.com/alfama"),
            tab(3, "Sourdough starter", "https://kingarthurbaking.com/starter"),
            tab(4, "No-knead bread", "https://nytimes.com/bread"),
        ]
    }

    // MARK: - the prompt

    /// Numbered from 1, so the model spends a token or two per tab rather
    /// than a UUID's dozens; host without www.; titles cut short.
    @Test func rendersNumberedLines() {
        let long = String(repeating: "x", count: 200)
        let lines = Tidy.render([batch[0], tab(9, long, "https://a.com/")]).split(separator: "\n")
        #expect(lines[0] == "1 | google.com | Flights to Lisbon")
        #expect(lines[1] == "2 | a.com | " + String(repeating: "x", count: Tidy.titleLimit))
    }

    /// A tab with no title is described by its address.
    @Test func anUntitledTabShowsItsPath() {
        #expect(Tidy.render([tab(1, "", "https://a.com/docs/intro")]) == "1 | a.com | /docs/intro")
    }

    // MARK: - validation

    @Test func mapsNumbersToTabs() {
        let groups = Tidy.validate([.init(name: "Lisbon trip", ids: [1, 2]), .init(name: "Baking", ids: [3, 4])], batch: batch)
        #expect(groups == [
            TidyGroup(name: "Lisbon trip", ids: [Self.id(1), Self.id(2)]),
            TidyGroup(name: "Baking", ids: [Self.id(3), Self.id(4)]),
        ])
    }

    /// Guided generation makes the shape right, never the numbers.
    @Test func dropsInventedIDs() {
        let groups = Tidy.validate([.init(name: "Trip", ids: [0, 1, 2, 7, -3])], batch: batch)
        #expect(groups == [TidyGroup(name: "Trip", ids: [Self.id(1), Self.id(2)])])
    }

    /// A tab goes where the model put it first; a later mention, in the same
    /// group or another, is dropped.
    @Test func dropsDuplicateIDs() {
        let groups = Tidy.validate([
            .init(name: "Trip", ids: [1, 1, 2]),
            .init(name: "Baking", ids: [2, 3, 4]),
        ], batch: batch)
        #expect(groups == [
            TidyGroup(name: "Trip", ids: [Self.id(1), Self.id(2)]),
            TidyGroup(name: "Baking", ids: [Self.id(3), Self.id(4)]),
        ])
    }

    /// A group of one isn't a group: the tab stays loose.
    @Test func dropsGroupsLeftWithOneTab() {
        let groups = Tidy.validate([
            .init(name: "Trip", ids: [1, 9]),
            .init(name: "Baking", ids: [3, 4]),
        ], batch: batch)
        #expect(groups.map(\.name) == ["Baking"])
    }

    /// Between batches a group of one is kept, since its partner may be in
    /// the next batch; only what's shown needs two.
    @Test func keepsSinglesWhenAsked() {
        let groups = Tidy.validate([.init(name: "Trip", ids: [1]), .init(name: "New", ids: [3])], batch: batch, minimum: 1)
        #expect(groups == [TidyGroup(name: "Trip", ids: [Self.id(1)]), TidyGroup(name: "New", ids: [Self.id(3)])])
        let joined = Tidy.merge(groups, [TidyGroup(name: "trip", ids: [Self.id(2)])], minimum: 1)
        #expect(joined[0] == TidyGroup(name: "Trip", ids: [Self.id(1), Self.id(2)]))
    }

    /// Two groups the model named alike are one.
    @Test func joinsGroupsNamedAlike() {
        let groups = Tidy.validate([
            .init(name: "Baking", ids: [3]),
            .init(name: "baking ", ids: [4]),
        ], batch: batch)
        #expect(groups == [TidyGroup(name: "Baking", ids: [Self.id(3), Self.id(4)])])
    }

    /// A name that says nothing, or nothing at all, is swapped for the
    /// rule's own name for those tabs.
    @Test func replacesEmptyAndGenericNames() {
        let groups = Tidy.validate([.init(name: "Other", ids: [3, 4]), .init(name: "  ", ids: [1, 2])], batch: batch)
        #expect(groups.count == 2)
        #expect(!groups.map(\.name).contains("Other"))
        #expect(groups.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: - names

    @Test func namesLoseEmojiAndKeepThreeWords() {
        #expect(Tidy.clean(name: "✈️ Lisbon trip") == "Lisbon trip")
        #expect(Tidy.clean(name: "Lisbon 🇵🇹") == "Lisbon")
        #expect(Tidy.clean(name: "Planning the big summer trip") == "Planning the big")
        #expect(Tidy.clean(name: "\"Baking\".") == "Baking")
        #expect(Tidy.clean(name: "C++ tips") == "C++ tips")
        #expect(Tidy.clean(name: "Misc") == nil)
        #expect(Tidy.clean(name: "🍞") == nil)
        #expect((Tidy.clean(name: "Supercalifragilisticexpialidocious words") ?? "").count <= Tidy.nameLimit)
    }

    // MARK: - batches

    /// A fake counter: one token per character, so the tests can say
    /// exactly where the budget falls.
    static let characters: @Sendable (String) async throws -> Int = { $0.count }

    @Test func oneBatchWhenItFits() async throws {
        let batches = try await Tidy.batches(batch, budget: 10_000, count: Self.characters)
        #expect(batches == [batch])
    }

    /// Halved until each half fits, and in the order the tabs were given.
    @Test func splitsToFitTheBudget() async throws {
        let tabs = (1...8).map { tab($0, "Page \($0)", "https://site\($0).com/") }
        let one = Tidy.render([tabs[0]]).count
        let batches = try await Tidy.batches(tabs, budget: one * 2 + 1, count: Self.characters)
        #expect(batches.count == 4)
        #expect(batches.flatMap { $0 } == tabs)
        for b in batches { #expect(Tidy.render(b).count <= one * 2 + 1) }
    }

    /// A tab too long for any budget still goes, on its own: the model's
    /// own error then sends it to the fallback.
    @Test func aTabTooLongGoesAlone() async throws {
        let tabs = [tab(1, "a", "https://a.com/"), tab(2, "b", "https://b.com/")]
        let batches = try await Tidy.batches(tabs, budget: 1, count: Self.characters)
        #expect(batches == [[tabs[0]], [tabs[1]]])
    }

    @Test func noTabsNoBatches() async throws {
        #expect(try await Tidy.batches([], budget: 100, count: Self.characters).isEmpty)
    }

    /// The counter is asked about the whole list once, not about each tab.
    @Test func countsSparingly() async throws {
        let tabs = (1...40).map { tab($0, "Page \($0)", "https://site\($0).com/") }
        let calls = Counter()
        _ = try await Tidy.batches(tabs, budget: 100_000) { text in
            await calls.bump()
            return text.count
        }
        #expect(await calls.value == 1)
    }

    actor Counter {
        var value = 0
        func bump() { value += 1 }
    }

    // MARK: - merging batches

    @Test func laterBatchesJoinGroupsOfTheSameName() {
        let first = [TidyGroup(name: "Lisbon trip", ids: [Self.id(1), Self.id(2)])]
        let second = [
            TidyGroup(name: "lisbon trip", ids: [Self.id(5), Self.id(6)]),
            TidyGroup(name: "Baking", ids: [Self.id(7), Self.id(8)]),
        ]
        #expect(Tidy.merge(first, second) == [
            TidyGroup(name: "Lisbon trip", ids: [Self.id(1), Self.id(2), Self.id(5), Self.id(6)]),
            TidyGroup(name: "Baking", ids: [Self.id(7), Self.id(8)]),
        ])
    }

    /// A tab already placed stays where it is.
    @Test func mergeNeverPlacesATabTwice() {
        let first = [TidyGroup(name: "A", ids: [Self.id(1), Self.id(2)])]
        let second = [TidyGroup(name: "B", ids: [Self.id(2), Self.id(3), Self.id(4)])]
        #expect(Tidy.merge(first, second) == [
            TidyGroup(name: "A", ids: [Self.id(1), Self.id(2)]),
            TidyGroup(name: "B", ids: [Self.id(3), Self.id(4)]),
        ])
    }
}
