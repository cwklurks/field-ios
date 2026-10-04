import Foundation
@testable import FieldKit
import Testing
@testable import Field

/// Past searches on disk, beside the history and by its rules: saved a
/// moment after a change, kept through a search made before the load, and
/// never saved over a file that couldn't be read.
@Suite(.serialized)
struct HistoryStoreSearchesTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HistoryStoreSearchesTests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("searches.json") }
    let google = Engine.google.template(custom: "")

    func store(seed: Int = 0) -> HistoryStore {
        let defaults = UserDefaults(suiteName: "HistoryStoreSearchesTests-\(UUID().uuidString)")!
        return HistoryStore(directory: directory, defaults: defaults, wait: .seconds(60), seed: seed)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test func aSearchIsSavedAndReadBack() async throws {
        defer { clean() }
        let history = store()
        await history.load()
        history.searched("swift concurrency")
        await history.flush()
        #expect(try Searches.load(from: file).count == 1)

        let again = store()
        await again.load()
        #expect(again.searchSuggestions(for: "swi", template: google).map(\.key) == ["swift concurrency"])
    }

    @Test func aSearchBeforeTheLoadFinishesIsKept() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift charts", now: .now)
        try before.save(to: file)
        let history = store()
        history.searched("swift concurrency")
        await history.load()
        #expect(history.searches.count == 2)
    }

    @Test func aFileThatCannotBeReadIsNeverSavedOver() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift charts", now: .now)
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let history = store()
        await history.load()
        history.searched("swift concurrency")
        await history.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func aFailedSearchReadCanRetryWithoutLosingNewSearches() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift charts")
        try before.save(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        let history = store()
        history.searched("swift before")
        await history.load()
        history.searched("swift after")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        await history.load()
        await history.flush()
        #expect(history.searches.count == 3)
        #expect(try Searches.load(from: file).count == 3)
    }

    @Test func aSeededHistoryNeverTouchesTheFile() async throws {
        defer { clean() }
        let history = store(seed: 10)
        await history.load()
        history.searched("swift concurrency")
        await history.flush()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func clearingForgetsEverySearchAndSavesTheEmptyList() async throws {
        defer { clean() }
        let history = store()
        await history.load()
        history.visited(URL(string: "https://swift.org")!, title: "Swift")
        history.searched("swift concurrency")
        history.searched("swift charts")
        await history.flush()
        #expect(try Searches.load(from: file).count == 2)

        history.forgetSearches()
        #expect(history.searches.isEmpty)
        #expect(history.searchSuggestions(for: "swi", template: google).isEmpty)
        await history.flush()
        #expect(try Searches.load(from: file).isEmpty)
        // Places stay: only what was asked goes.
        #expect(!history.suggestions(for: "swift").isEmpty)
    }

    @Test func clearingBeforeTheLoadClearsWhatItReads() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift charts", now: .now)
        try before.save(to: file)
        let history = store()
        history.forgetSearches()
        history.searched("swift after")
        await history.load()
        #expect(history.searches.count == 1)
        await history.flush()
        #expect(try Searches.load(from: file).count == 1)
    }

    @Test func clearingNeverWritesOverAFileThatCannotBeRead() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift charts", now: .now)
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let history = store()
        await history.load()
        history.forgetSearches()
        await history.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
        // Read at last, it is cleared then.
        await history.load()
        #expect(history.searches.isEmpty)
    }
    @Test func clearingWithAScheduledSaveDoesNotRestoreTheOldSearches() async throws {
        defer { clean() }
        let history = HistoryStore(directory: directory, wait: .milliseconds(30), seed: 0)
        await history.load()
        history.searched("swift before")
        history.forgetSearches()
        history.searched("swift after")
        try await Task.sleep(for: .milliseconds(150))
        #expect(try Searches.load(from: file).suggestions(for: "swift", template: google).map(\.key) == ["swift after"])
    }

    @Test func anOldSaveArrivingAfterClearCannotRestoreSearches() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift before")
        let disk = SearchesFile(url: file)
        try await disk.write(Searches(), generation: 2, now: .now)
        try await disk.write(before, generation: 1, now: .now)
        #expect(try Searches.load(from: file).isEmpty)
    }

    @Test func clearingDuringALoadKeepsOnlySearchesMadeAfterClear() async throws {
        defer { clean() }
        var before = Searches()
        before.record("swift before")
        try before.save(to: file)
        let history = store()
        let loading = Task { await history.load() }
        await Task.yield()
        history.forgetSearches()
        history.searched("swift after")
        await loading.value
        await history.flush()
        #expect(try Searches.load(from: file).suggestions(for: "swift", template: google).map(\.key) == ["swift after"])
    }

}
