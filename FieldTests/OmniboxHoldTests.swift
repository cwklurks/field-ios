import Foundation
import Testing
import FieldKit
@testable import Field

// What the rows do while something is on its way: an answer landing under a
// finger waits for it to lift, and the rows a keystroke left behind keep
// their place, faded and out of reach, until the new answer comes or the
// wait runs out.
@MainActor @Suite(.serialized) struct OmniboxHoldTests {
    actor Network: SuggestFetching {
        let delays: [String: Duration]

        init(delays: [String: Duration] = [:]) { self.delays = delays }

        func data(for url: URL) async throws -> Data {
            let words = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            try await Task.sleep(for: delays[words] ?? .zero)
            return Data(#"["\#(words)",["\#(words)one","\#(words) two","\#(words) three"]]"#.utf8)
        }
    }

    let defaults: UserDefaults
    let history: HistoryStore

    init() {
        defaults = UserDefaults(suiteName: "OmniboxHoldTests.\(UUID().uuidString)")!
        history = HistoryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: defaults,
            seed: 0
        )
    }

    private func omnibox(_ network: Network = Network(), patience: Duration = .seconds(5)) -> Omnibox {
        Omnibox(
            initial: nil, history: history, defaults: defaults, privately: { false },
            suggester: Suggester(fetch: network, wait: .zero), patience: patience
        )
    }

    private func type(_ text: String, into omnibox: Omnibox, cause: Draft.Cause = .typed) {
        let end = text.utf16.count
        _ = omnibox.edited(to: text, selection: end..<end, marked: false, cause: cause)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - a finger on a row

    @Test func anAnswerLandingUnderAFingerWaitsForItToLift() async throws {
        history.searched("goat curry")
        let box = omnibox(Network(delays: ["goat": .milliseconds(60)]))
        var late = 0
        box.onLate = { late += 1 }
        type("goat", into: box)
        let under = box.offers
        #expect(under.map(\.key) == ["goat curry"])

        box.pressed(true)
        try await settle()
        #expect(box.offers == under)
        #expect(late == 0)

        box.pressed(false)
        #expect(box.offers.first == under.first)
        #expect(box.offers.count == 4)
        #expect(late == 1)
    }

    @Test func aCancelledPressAlsoLetsTheAnswerIn() async throws {
        history.searched("goat curry")
        let box = omnibox(Network(delays: ["goat": .milliseconds(30)]))
        type("goat", into: box)
        box.pressed(true)
        box.pressed(true)  // Fill and its row, say.
        try await settle()
        box.pressed(false)
        #expect(box.offers.count == 1)
        box.pressed(false)
        #expect(box.offers.count == 4)
    }

    @Test func aKeystrokeIsNeverHeldByAPress() async throws {
        history.searched("goat curry")
        let box = omnibox(Network(delays: ["goat": .seconds(5)]))
        type("goat", into: box)
        box.pressed(true)
        type("goat cu", into: box)
        #expect(box.offers.map(\.key) == ["goat curry"])
        box.ended()
    }

    // MARK: - rows a keystroke left behind

    @Test func engineRowsHoldTheirPlaceFadedUntilTheNewAnswer() async throws {
        let box = omnibox(Network(delays: ["goat c": .milliseconds(60)]))
        type("goat", into: box)
        try await settle()
        let old = box.offers
        #expect(old.count == 3)
        #expect(box.fading.isEmpty)

        type("goat c", into: box)
        // The same room, but none of it can be taken for the new words.
        #expect(box.offers == old)
        #expect(box.fading == Set(old.map(\.id)))
        #expect(box.listed)

        try await settle()
        #expect(box.offers.map(\.key) == ["goat cone", "goat c two", "goat c three"])
        #expect(box.fading.isEmpty)
    }

    @Test func theHeldRowsNeverMakeThePanelTallerThanItWas() async throws {
        history.searched("goat curry")
        let box = omnibox(Network(delays: ["goat c": .seconds(5)]))
        type("goat", into: box)
        try await settle()
        let before = box.offers.count
        type("goat c", into: box)
        #expect(box.offers.count <= before)
        #expect(box.offers.first?.key == "goat curry")
        #expect(!box.fading.contains(box.offers[0].id))
        box.ended()
    }

    @Test func theHeldRowsGoWhenTheWaitRunsOut() async throws {
        let box = omnibox(Network(delays: ["goat c": .seconds(5)]), patience: .milliseconds(50))
        var late = 0
        box.onLate = { late += 1 }
        type("goat", into: box)
        try await settle()
        #expect(late == 1)
        type("goat c", into: box)
        #expect(!box.offers.isEmpty)
        try await settle()
        #expect(box.offers.isEmpty)
        #expect(!box.listed)
        #expect(late == 2)
        box.ended()
    }

    @Test func nothingIsHeldWhenNothingIsAsked() async throws {
        let box = omnibox()
        type("goat", into: box)
        try await settle()
        #expect(!box.offers.isEmpty)
        type("example.com", into: box, cause: .pasted)
        #expect(box.offers.allSatisfy { $0.kind != .search })
        #expect(box.fading.isEmpty)
    }

    @Test func aFadedRowWaitsBehindAFinger() async throws {
        history.searched("goat curry")
        let box = omnibox(Network(delays: ["goat c": .seconds(5)]), patience: .milliseconds(50))
        type("goat", into: box)
        try await settle()
        type("goat c", into: box)
        let held = box.offers
        box.pressed(true)
        try await settle()
        #expect(box.offers == held)
        box.pressed(false)
        #expect(box.offers.map(\.key) == ["goat curry"])
        box.ended()
    }
}
