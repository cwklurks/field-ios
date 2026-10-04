import SwiftUI
import FieldKit

/// A deterministic panel for the UI accessibility test, without touching
/// the simulator's history or asking a live engine.
struct SuggestionFixture: View {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-FieldSuggestionFixture") }
    @State private var box: Omnibox = {
        let history = HistoryStore(directory: FileManager.default.temporaryDirectory, seed: 1)
        for word in ["swift charts", "swift concurrency", "swift testing"] { history.searched(word) }
        let defaults = UserDefaults(suiteName: "SuggestionFixture")!
        defaults.register(defaults: ["engine": "google", "suggest": true])
        let box = Omnibox(initial: nil, history: history, defaults: defaults, privately: { false },
                          suggester: Suggester(fetch: Silent(), wait: .zero), patience: .seconds(60))
        box.room = 110
        _ = box.edited(to: "swift", selection: 5..<5, marked: false, cause: .typed)
        return box
    }()

    var body: some View {
        VStack {
            Button("Expand") { box.room = 500 }
            Button("Cap") { box.room = 110 }
            Button("Change query") {
                _ = box.edited(to: "rust", selection: 4..<4, marked: false, cause: .typed)
            }
            Spacer()
            SuggestionRows(omnibox: box, onGo: { _ in })
                .frame(width: 360)
        }
        .padding()
    }

    private actor Silent: SuggestFetching {
        func data(for url: URL) async throws -> Data {
            try await Task.sleep(for: .seconds(60))
            return Data()
        }
    }
}
