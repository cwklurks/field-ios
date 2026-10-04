import FieldKit
import Testing
import UIKit
@testable import Field

@MainActor
struct TidySheetsTests {
    @Test func similarPresentsOnlyCompletedMatches() async throws {
        let windows = UIApplication.shared.connectedScenes.compactMap {
            ($0 as? UIWindowScene)?.keyWindow
        }
        let window = try #require(windows.first)
        let root = try #require(window.rootViewController)
        #expect(root.presentedViewController == nil)
        let previous = TidySheets.shownDraft
        var lines: [String] = []
        let flow = TidyFlow(grouping: { .init() }, regroup: { _ in }, toast: { _, _ in },
                            announce: { lines.append($0) })
        TidySheets.showSimilar(to: .init(id: UUID(), name: "Trip"), members: [], among: [],
                              flow: flow, engine: TidyEngine(model: { nil }))
        #expect(TidySheets.shownDraft === previous)
        #expect(root.presentedViewController == nil)
        for _ in 0..<100 where !lines.contains("No other tabs look like these.") {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(lines.first == "Looking for similar tabs…")
        #expect(lines.last == "No other tabs look like these.")
        #expect(TidySheets.shownDraft === previous)
        #expect(root.presentedViewController == nil)

        TidySheets.showSimilar(to: .init(id: UUID(), name: "Cancelled"), members: [], among: [],
                              flow: flow, engine: TidyEngine(model: { nil }))
        TidySheets.cancelReading()
        try await Task.sleep(for: .milliseconds(50))
        #expect(lines.last == "Looking for similar tabs…")
        #expect(TidySheets.shownDraft === previous)

        let member = TabInfo(id: UUID(), title: "Trip", url: URL(string: "https://trip.example/one")!)
        let candidate = TabInfo(id: UUID(), title: "Trip", url: URL(string: "https://trip.example/two")!)
        TidySheets.showSimilar(to: .init(id: UUID(), name: "Trip"), members: [member], among: [candidate],
                              flow: flow, engine: TidyEngine(model: { nil }, embed: { _ in [1, 0] }))
        #expect(root.presentedViewController == nil)
        for _ in 0..<100 where TidySheets.shownDraft === previous {
            try await Task.sleep(for: .milliseconds(10))
        }
        let draft = try #require(TidySheets.shownDraft)
        #expect(draft.canApply)
        #expect(draft.chosen.flatMap(\.ids) == [candidate.id])
        #expect(root.presentedViewController === TidySheets.shownHost)
        try await Task.sleep(for: .milliseconds(500))
        root.dismiss(animated: false)
    }
}
