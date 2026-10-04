import Foundation
import FieldKit
import Observation

/// Where you have been, kept for the field: FieldKit's History, read and
/// written off the main thread, and saved a moment after a visit rather
/// than on every one.
@MainActor @Observable final class HistoryStore {
    /// False until a load succeeds, and until then nothing is saved: a file
    /// that couldn't be read (a protected one, before first unlock) is not an
    /// empty history, and writing one over it would lose everything.
    private(set) var isLoaded = false

    private(set) var history = History()

    /// What was asked from the field (Searches), in searches.json beside
    /// the history, by the same rules. Nobody draws it, so nobody watches it.
    @ObservationIgnored private(set) var searches = Searches()
    /// As `isLoaded`, for searches.json: a file that couldn't be read is
    /// never written over.
    @ObservationIgnored private var searchesLoaded = false

    @ObservationIgnored let file: HistoryFile
    @ObservationIgnored let searchesFile: SearchesFile
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let wait: Duration
    /// Places made up for the perf tests; while there are any, the file is
    /// never read or written.
    @ObservationIgnored private let seed: Int
    @ObservationIgnored private var loading = false
    /// Changes made before the load finished, played again over what it read.
    @ObservationIgnored private var early: [(inout History) -> Void] = []
    @ObservationIgnored private var earlySearches: [(String, Date)] = []
    /// How many changes there have been. A write carries it, so the file can
    /// tell an older snapshot arriving late from a newer one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// `defaults` holds the custom engine; `wait` is how long a save waits
    /// for more changes; `seed` is how many places to make up. The first two
    /// are there for the tests.
    init(directory: URL, defaults: UserDefaults = .standard, wait: Duration = .seconds(1.5),
         seed: Int = HistoryStore.launchSeed) {
        file = HistoryFile(url: directory.appendingPathComponent("history.json"))
        searchesFile = SearchesFile(url: directory.appendingPathComponent("searches.json"))
        self.defaults = defaults
        self.wait = wait
        self.seed = max(0, seed)
    }

    /// `-FieldSeedHistory 2000`: the perf tests' realistic history, taken
    /// from the launch arguments only, so no setting left behind can ever
    /// stand in for somebody's real one.
    nonisolated static var launchSeed: Int {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["FieldSeedHistory"] != nil else { return 0 }
        return UserDefaults.standard.integer(forKey: "FieldSeedHistory")
    }

    /// No file is an empty history. Any other failure leaves `isLoaded`
    /// false, and a later call can try again. With a seed, the places are
    /// made up instead, off the main thread like a read.
    func load() async {
        guard !isLoaded, !loading else { return }
        loading = true
        defer { loading = false }
        var loaded: History
        if seed > 0 {
            loaded = await Task.detached(priority: .userInitiated) { [seed] in History.sample(seed, now: .now) }.value
        } else {
            guard let read = try? await file.read() else { return }
            loaded = read
            if var asked = try? await searchesFile.read() {
                for (words, when) in earlySearches { asked.record(words, now: when) }
                searches = asked
                searchesLoaded = true
            }
        }
        let searchedEarly = !earlySearches.isEmpty
        earlySearches = []
        for change in early { change(&loaded) }
        let replayed = !early.isEmpty || searchedEarly
        early = []
        history = loaded
        isLoaded = true
        if replayed { scheduleSave() }
    }

    func suggestions(for text: String, limit: Int = 5) -> [Suggestion] {
        history.suggestions(for: text, limit: limit)
    }

    func completion(for text: String, among: [Suggestion]) -> (ending: String, suggestion: Suggestion)? {
        history.completion(for: text, among: among)
    }

    func searchSuggestions(for text: String, template: String) -> [Suggestion] {
        searches.suggestions(for: text, template: template)
    }

    /// Words asked of the engine from the field. Private never calls this.
    func searched(_ words: String) {
        let now = Date.now
        searches.record(words, now: now)
        generation += 1
        if isLoaded { scheduleSave() } else { earlySearches.append((words, now)) }
    }

    func visited(_ url: URL, title: String) {
        let now = Date.now
        // The history of places is no record of what was asked: a search
        // counts as a visit to the engine, and no more. The words asked from
        // the field are kept apart, in `searches`.
        if let engine = frontPage(ofResults: url) {
            change { $0.record(engine, title: "", now: now) }
        } else {
            change { $0.record(url, title: title, now: now) }
        }
    }

    func retitled(_ url: URL, _ title: String) {
        guard frontPage(ofResults: url) == nil else { return }
        change { $0.retitle(url, title) }
    }

    /// Writes now, for when the app goes to the background.
    func flush() async {
        pending?.cancel()
        await save()
    }

    private func change(_ apply: @escaping (inout History) -> Void) {
        apply(&history)
        generation += 1
        if isLoaded { scheduleSave() } else { early.append(apply) }
    }

    /// A moment after a change, as on the Mac: whatever else changes in the
    /// meantime goes in the same write.
    private func scheduleSave() {
        guard isLoaded, seed == 0, pending == nil else { return }
        pending = Task { [weak self, wait] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        pending = nil
        guard isLoaded, seed == 0 else { return }
        try? await file.write(history, generation: generation, now: .now)
        if searchesLoaded { try? await searchesFile.write(searches, generation: generation, now: .now) }
    }

    /// The engine's front page, when a page is one of its results: any
    /// preset's, or the custom template's, whichever engine is chosen.
    private func frontPage(ofResults url: URL) -> URL? {
        let custom = defaults.string(forKey: "engine.custom") ?? ""
        guard Engine.allCases.contains(where: { Engine.isResults(url, template: $0.template(custom: custom)) }),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var home = URLComponents()
        home.scheme = parts.scheme
        home.percentEncodedHost = parts.percentEncodedHost
        home.port = parts.port
        home.path = "/"
        return home.url
    }
}

/// history.json, read and written one thing at a time and never on the main
/// thread. Each write carries the count of changes it holds, so one that
/// arrives after a newer one is dropped rather than landing last.
actor HistoryFile {
    let url: URL
    private var written = 0
    private(set) var writes = 0

    init(url: URL) { self.url = url }

    func read() throws -> History {
        try History.load(from: url)
    }

    func write(_ history: History, generation: Int, now: Date) throws {
        guard generation > written else { return }
        try history.save(to: url, now: now)
        written = generation
        writes += 1
    }
}

/// searches.json, as HistoryFile keeps history.json.
actor SearchesFile {
    let url: URL
    private var written = 0

    init(url: URL) { self.url = url }

    func read() throws -> Searches {
        try Searches.load(from: url)
    }

    func write(_ searches: Searches, generation: Int, now: Date) throws {
        guard generation > written else { return }
        try searches.save(to: url, now: now)
        written = generation
    }
}
