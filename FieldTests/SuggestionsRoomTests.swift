import Foundation
import SwiftUI
import Testing
import FieldKit
@testable import Field

/// Eight rows at the largest text the chrome takes, over an iPhone SE's
/// keyboard: the panel stands no taller than the room above the field, and
/// the rows nearest the field are the ones it keeps. With
/// TEST_RUNNER_SUGGEST_SNAPSHOTS set to a folder, the panel is drawn there,
/// with room and without.
@MainActor @Suite(.serialized) struct SuggestionsRoomTests {
    actor Network: SuggestFetching {
        func data(for url: URL) async throws -> Data {
            let words = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            return Data(#"["\#(words)",["\#(words)ui","\#(words) package manager","\#(words) evolution"]]"#.utf8)
        }
    }

    /// An SE's: from the field's top (667 - 260 keyboard - 8 gap - 50 field)
    /// up to 8 short of the 20-point status bar.
    static let seRoom: CGFloat = 667 - 260 - 8 - 50 - 20 - 8
    static let width: CGFloat = 375 - 2 * 4

    @Test func eightRowsKeepToTheRoomAboveAnSEField() async throws {
        let box = try await eightRows()
        let open = height(box)
        #expect(open > Self.seRoom, "Eight rows should want more than an SE has: \(open)")

        box.room = Self.seRoom
        let kept = height(box)
        #expect(kept <= Self.seRoom)
        #expect(kept >= Self.seRoom - 60)
        save(box, "room-se-xxxl.png")
        box.room = .infinity
        save(box, "room-none-xxxl.png")
        box.ended()
    }

    private func eightRows() async throws -> Omnibox {
        let defaults = UserDefaults(suiteName: "SuggestionsRoomTests.\(UUID().uuidString)")!
        let history = HistoryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            defaults: defaults, seed: 0
        )
        for host in ["docs.swift.org", "hackingwithswift.com", "theswiftdev.com"] {
            history.visited(URL(string: "https://\(host)/")!, title: host)
        }
        for words in ["swift concurrency", "swift charts", "swift testing"] { history.searched(words) }
        let box = Omnibox(initial: nil, history: history, defaults: defaults, privately: { false },
                          suggester: Suggester(fetch: Network(), wait: .zero))
        _ = box.edited(to: "swift", selection: 5..<5, marked: false, cause: .typed)
        try await Task.sleep(for: .milliseconds(150))
        #expect(box.offers.count == Offers.allLimit)
        return box
    }

    private func panel(_ box: Omnibox) -> some View {
        SuggestionRows(omnibox: box, onGo: { _ in })
            .environment(\.dynamicTypeSize, Ramp.cap)
            .frame(width: Self.width)
    }

    private func height(_ box: Omnibox) -> CGFloat {
        let host = UIHostingController(rootView: panel(box))
        host.sizingOptions = []
        return host.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
    }

    private func save(_ box: Omnibox, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SUGGEST_SNAPSHOTS"] else { return }
        let renderer = ImageRenderer(content: panel(box).background(Color(white: 0.96)))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return }
        try? data.write(to: URL(filePath: folder).appending(path: name))
    }
}
