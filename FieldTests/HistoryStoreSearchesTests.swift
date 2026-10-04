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

    @Test func aSeededHistoryNeverTouchesTheFile() async throws {
        defer { clean() }
        let history = store(seed: 10)
        await history.load()
        history.searched("swift concurrency")
        await history.flush()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
