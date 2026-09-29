import Foundation
@testable import FieldKit
import Testing
@testable import Field

/// The history's life on disk: loaded off the main thread, saved a moment
/// after a change through one actor, never saved over a file it couldn't
/// read, and never told what was searched for.
@Suite(.serialized)
struct HistoryStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("history.json") }

    func url(_ text: String) -> URL { URL(string: text)! }

    func onDisk() throws -> History { try History.load(from: file) }

    func store(wait: Duration = .seconds(60), custom: String? = nil, seed: Int = 0) -> HistoryStore {
        let defaults = UserDefaults(suiteName: "HistoryStoreTests-\(UUID().uuidString)")!
        if let custom { defaults.set(custom, forKey: "engine.custom") }
        return HistoryStore(directory: directory, defaults: defaults, wait: wait, seed: seed)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test func aFileThatCannotBeReadIsNeverSavedOver() async throws {
        defer { clean() }
        var before = History()
        before.record(url("https://example.com/a"), title: "A", now: .now)
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let history = store()
        await history.load()
        #expect(!history.isLoaded)
        history.visited(url("https://example.org/b"), title: "B")
        await history.flush()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// `-FieldSeedHistory 2000`, for the perf tests: the file is never read
    /// (here it can't be) and never written, whatever happens.
    @Test func aSeededHistoryNeverTouchesTheFile() async throws {
        defer { clean() }
        var before = History()
        before.record(url("https://example.com/a"), title: "A", now: .now)
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let history = store(wait: .milliseconds(50), seed: 2_000)
        await history.load()
        #expect(history.isLoaded)
        #expect(history.history.visits.count == 2_000)
        #expect(Set(history.suggestions(for: "weather").map(\.key)).isSuperset(of: ["weather.com", "weather.gov"]))

        history.visited(url("https://example.org/b"), title: "B")
        history.retitled(url("https://example.org/b"), "Bee")
        try await Task.sleep(for: .milliseconds(300))
        await history.flush()
        #expect(await history.file.writes == 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// Only a launch argument turns the seed on, never a stored setting.
    @Test func theSeedComesOnlyFromTheLaunchArguments() {
        UserDefaults.standard.set(2_000, forKey: "FieldSeedHistory")
        defer { UserDefaults.standard.removeObject(forKey: "FieldSeedHistory") }
        #expect(HistoryStore.launchSeed == 0)
    }

    @Test func noFileIsAnEmptyHistoryThatCanBeSaved() async throws {
        defer { clean() }
        let history = store()
        await history.load()
        #expect(history.isLoaded)
        history.visited(url("https://example.com/a"), title: "A")
        await history.flush()
        #expect(try onDisk().everything().map(\.key) == ["example.com/a"])
    }

    @Test func aVisitBeforeTheLoadFinishesIsKept() async throws {
        defer { clean() }
        var before = History()
        before.record(url("https://example.com/a"), title: "A", now: .now)
        try before.save(to: file)

        let history = store()
        history.visited(url("https://example.org/b"), title: "B")
        await history.load()
        #expect(Set(history.suggestions(for: "example").map(\.key)) == ["example.com", "example.org", "example.com/a", "example.org/b"])
        await history.flush()
        #expect(Set(try onDisk().everything().map(\.key)) == ["example.com/a", "example.org/b"])
    }

    @Test func visitsAreSavedTogetherAMomentLater() async throws {
        defer { clean() }
        let history = store(wait: .milliseconds(300))
        await history.load()
        history.visited(url("https://example.com/a"), title: "A")
        history.visited(url("https://example.com/b"), title: "B")
        history.visited(url("https://example.com/c"), title: "C")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try await Task.sleep(for: .milliseconds(900))
        #expect(Set(try onDisk().everything().map(\.key)) == ["example.com/a", "example.com/b", "example.com/c"])
        #expect(await history.file.writes == 1)
    }

    @Test func flushWritesNowAndOnlyWhatIsNew() async throws {
        defer { clean() }
        let history = store(wait: .seconds(60))
        await history.load()
        history.visited(url("https://example.com/a"), title: "A")
        await history.flush()
        #expect(try onDisk().everything().map(\.key) == ["example.com/a"])
        await history.flush()
        #expect(await history.file.writes == 1)
    }

    @Test func anOlderSnapshotNeverLandsLast() async throws {
        defer { clean() }
        let disk = HistoryFile(url: file)
        var snapshots: [History] = []
        var history = History()
        for i in 1...20 {
            history.record(url("https://site\(i).com/"), title: "\(i)", now: .now)
            snapshots.append(history)
        }
        // All at once and out of order, as a flush racing a timer can be.
        await withTaskGroup(of: Void.self) { group in
            for (i, snapshot) in snapshots.enumerated().shuffled() {
                group.addTask { try? await disk.write(snapshot, generation: i + 1, now: .now) }
            }
        }
        #expect(try onDisk() == snapshots[19])
    }

    @Test func aSearchCountsOnlyAsAVisitToTheEngine() async throws {
        defer { clean() }
        let history = store(custom: "https://search.example.org/find?q=%s")
        await history.load()
        history.visited(url("https://duckduckgo.com/"), title: "DuckDuckGo")

        // Whichever engine is chosen: a preset, another preset, the custom one.
        let searches = [
            ("https://www.google.com/search?client=safari&q=my+secret+diagnosis", "my secret diagnosis - Google Search"),
            ("https://duckduckgo.com/?q=my+secret+diagnosis&ia=web", "my secret diagnosis at DuckDuckGo"),
            ("https://search.example.org/find?q=my+secret+diagnosis", "my secret diagnosis - Example Search"),
        ]
        for (address, title) in searches {
            history.visited(url(address), title: title)
            history.retitled(url(address), title)
        }
        // A page on an engine's site that isn't an answer is a page.
        history.visited(url("https://www.google.com/preferences"), title: "Search settings")

        // Then Gmail and the other Google sites the field knows, after the dot.
        let google = history.suggestions(for: "google.com")
        #expect(google.prefix(2).map(\.key) == ["google.com", "google.com/preferences"])
        #expect(!google.contains { $0.key.contains("search") })
        #expect(google.first?.url.absoluteString == "https://www.google.com/")
        #expect(google.first?.title == "")
        let duck = history.suggestions(for: "duck").first
        #expect(duck?.url.absoluteString == "https://duckduckgo.com/")
        #expect(duck?.title == "DuckDuckGo")
        #expect(history.suggestions(for: "search.example").map(\.key) == ["search.example.org"])

        await history.flush()
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(!written.contains("secret"))
        #expect(!written.contains("diagnosis"))
    }
}
