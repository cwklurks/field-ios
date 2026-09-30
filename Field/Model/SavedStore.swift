import Foundation
import FieldKit
import Observation

/// The pages you keep: FieldKit's Saved, read and written off the main
/// thread, and saved a moment after a change rather than on each one. Kept
/// as HistoryStore keeps history.
@MainActor @Observable final class SavedStore {
    /// False until a load succeeds, and until then nothing is saved: a file
    /// that couldn't be read (a protected one, before first unlock) is not an
    /// empty list, and writing one over it would lose everything.
    private(set) var isLoaded = false

    private(set) var saved = Saved()

    @ObservationIgnored let file: SavedFile
    @ObservationIgnored private let wait: Duration
    /// Pages made up for the perf tests and the harness; while there are
    /// any, the file is never read or written.
    @ObservationIgnored private let seed: Int
    @ObservationIgnored private var loading = false
    /// Changes made before the load finished, played again over what it read.
    @ObservationIgnored private var early: [(inout Saved) -> Void] = []
    /// How many changes there have been. A write carries it, so the file can
    /// tell an older snapshot arriving late from a newer one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// `wait` is how long a save waits for more changes, there for the
    /// tests; `seed` is how many pages to make up.
    init(directory: URL, wait: Duration = .seconds(1.5), seed: Int = SavedStore.launchSeed) {
        file = SavedFile(url: directory.appendingPathComponent("saved.json"))
        self.wait = wait
        self.seed = max(0, seed)
    }

    /// `-FieldSeedSaved 500`: a made-up library, taken from the launch
    /// arguments only, so no setting left behind can ever stand in for
    /// somebody's real one.
    nonisolated static var launchSeed: Int {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["FieldSeedSaved"] != nil else { return 0 }
        return UserDefaults.standard.integer(forKey: "FieldSeedSaved")
    }

    /// No file is nothing saved yet. Any other failure leaves `isLoaded`
    /// false, and a later call can try again. With a seed, the pages are
    /// made up instead, off the main thread like a read.
    func load() async {
        guard !isLoaded, !loading else { return }
        loading = true
        defer { loading = false }
        var loaded: Saved
        if seed > 0 {
            loaded = await Task.detached(priority: .userInitiated) { [seed] in Saved.sample(seed, now: .now) }.value
        } else {
            guard let read = try? await file.read() else { return }
            loaded = read
        }
        for change in early { change(&loaded) }
        let replayed = !early.isEmpty
        early = []
        saved = loaded
        isLoaded = true
        if replayed { scheduleSave() }
    }

    // MARK: - reading

    func contains(_ url: URL) -> Bool { saved.contains(url) }

    func page(for url: URL) -> SavedPage? { saved.page(for: url) }

    // MARK: - changing

    /// The page saved now, or the one already saved there. Nil for anything
    /// that isn't a web page.
    @discardableResult
    func save(_ url: URL, title: String, folder: String? = nil, starred: Bool = false) -> SavedPage? {
        if let kept = saved.page(for: url) { return kept }
        let id = UUID()
        let now = Date.now
        change { $0.save(url, title: title, folder: folder, starred: starred, id: id, now: now) }
        return saved.pages.first { $0.id == id }
    }

    func unsave(_ url: URL) { change { $0.unsave(url) } }

    func remove(_ id: UUID) { change { $0.remove(id) } }

    func star(_ id: UUID, _ on: Bool = true) { change { $0.star(id, on) } }

    func retitle(_ id: UUID, _ title: String) { change { $0.retitle(id, title) } }

    func move(_ id: UUID, to folder: String?) { change { $0.move(id, to: folder) } }

    @discardableResult
    func addFolder(_ name: String) -> String? {
        var made: String?
        change { made = $0.addFolder(name) }
        return made
    }

    func renameFolder(_ name: String, to new: String) { change { $0.renameFolder(name, to: new) } }

    func deleteFolder(_ name: String) { change { $0.deleteFolder(name) } }

    /// Call on every page that finishes loading; only a saved one changes.
    func opened(_ url: URL) {
        guard !isLoaded || saved.contains(url) else { return }
        let now = Date.now
        change { $0.opened(url, now: now) }
    }

    /// Writes now, for when the app goes to the background.
    func flush() async {
        pending?.cancel()
        await save()
    }

    private func change(_ apply: @escaping (inout Saved) -> Void) {
        apply(&saved)
        generation += 1
        if isLoaded { scheduleSave() } else { early.append(apply) }
    }

    /// A moment after a change: whatever else changes in the meantime goes
    /// in the same write.
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
        try? await file.write(saved, generation: generation)
    }
}

/// saved.json, read and written one thing at a time and never on the main
/// thread. Each write carries the count of changes it holds, so one that
/// arrives after a newer one is dropped rather than landing last.
actor SavedFile {
    let url: URL
    private var written = 0
    private(set) var writes = 0

    init(url: URL) { self.url = url }

    func read() throws -> Saved {
        try Saved.load(from: url)
    }

    func write(_ saved: Saved, generation: Int) throws {
        guard generation > written else { return }
        try saved.save(to: url)
        written = generation
        writes += 1
    }
}
