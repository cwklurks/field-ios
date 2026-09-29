import Foundation
@testable import FieldKit
import Testing
@testable import Field

/// session.json's life on disk: saved a moment after a change, through one
/// actor so an older session never lands last, flushed when the app leaves,
/// and never saved over a file that couldn't be read.
@Suite(.serialized)
struct SessionStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("session.json") }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    func shape(_ urls: String...) -> Session.Shape {
        Session.Shape(tabs: urls.map { Session.Entry(url: $0, title: "") }, active: 0)
    }

    @Test func theLastChangeIsWhatLands() async throws {
        defer { clean() }
        let store = SessionStore(directory: directory, wait: .milliseconds(50))
        #expect(store.read() == Session.Shape())
        var current = shape("https://a.com/")
        store.changed { current }
        current = shape("https://a.com/", "https://b.com/")
        store.changed { current }
        try await Task.sleep(for: .milliseconds(400))
        #expect(try Session.Shape.load(from: file).tabs.map(\.url) == ["https://a.com/", "https://b.com/"])
        #expect(await store.file?.writes == 1)
    }

    @Test func flushWritesNow() async throws {
        defer { clean() }
        let store = SessionStore(directory: directory, wait: .seconds(60))
        _ = store.read()
        store.changed { shape("https://a.com/") }
        await store.flush()
        #expect(try Session.Shape.load(from: file).tabs.map(\.url) == ["https://a.com/"])
    }

    @Test func aFileThatCannotBeReadIsNeverSavedOver() async throws {
        defer { clean() }
        try shape("https://kept.com/").save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let store = SessionStore(directory: directory, wait: .milliseconds(10))
        #expect(store.read() == nil)
        store.changed { shape("https://lost.com/") }
        await store.flush()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// The perf tests' tabs (`-FieldOpen`, `-FieldSeedTabs`) are nobody's
    /// session: nothing is read and nothing written.
    @Test func aStoreWithoutADirectoryTouchesNothing() async throws {
        defer { clean() }
        try shape("https://kept.com/").save(to: file)
        let store = SessionStore(directory: nil, wait: .milliseconds(10))
        #expect(store.read() == Session.Shape())
        store.changed { shape("https://lost.com/") }
        await store.flush()
        #expect(try Session.Shape.load(from: file).tabs.map(\.url) == ["https://kept.com/"])
    }
}
