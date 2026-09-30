import Foundation
@testable import FieldKit
import Testing
@testable import Field

/// saved.json's life on disk, kept as history's is: loaded off the main
/// thread, saved a moment after a change through one actor, and never saved
/// over a file it couldn't read.
@Suite(.serialized)
struct SavedStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SavedStoreTests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("saved.json") }

    func url(_ text: String) -> URL { URL(string: text)! }

    func onDisk() throws -> Saved { try Saved.load(from: file) }

    func store(wait: Duration = .seconds(60), seed: Int = 0) -> SavedStore {
        SavedStore(directory: directory, wait: wait, seed: seed)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test func aFileThatCannotBeReadIsNeverSavedOver() async throws {
        defer { clean() }
        var before = Saved()
        before.save(url("https://example.com/a"), title: "A")
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let saved = store()
        await saved.load()
        #expect(!saved.isLoaded)
        saved.save(url("https://example.org/b"), title: "B")
        await saved.flush()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// `-FieldSeedSaved 500`: the file is never read (here it can't be) and
    /// never written, whatever happens.
    @Test func aSeededLibraryNeverTouchesTheFile() async throws {
        defer { clean() }
        var before = Saved()
        before.save(url("https://example.com/a"), title: "A")
        try before.save(to: file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        let saved = store(wait: .milliseconds(50), seed: 500)
        await saved.load()
        #expect(saved.isLoaded)
        #expect(saved.saved.pages.count == 500)

        let page = saved.save(url("https://example.org/b"), title: "B")
        saved.star(page!.id)
        try await Task.sleep(for: .milliseconds(300))
        await saved.flush()
        #expect(await saved.file.writes == 0)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// Only a launch argument turns the seed on, never a stored setting.
    @Test func theSeedComesOnlyFromTheLaunchArguments() {
        UserDefaults.standard.set(500, forKey: "FieldSeedSaved")
        defer { UserDefaults.standard.removeObject(forKey: "FieldSeedSaved") }
        #expect(SavedStore.launchSeed == 0)
    }

    @Test func noFileIsNothingSavedYetAndCanBeSaved() async throws {
        defer { clean() }
        let saved = store()
        await saved.load()
        #expect(saved.isLoaded)
        saved.save(url("https://example.com/a"), title: "A", folder: "Work", starred: true)
        await saved.flush()
        let disk = try onDisk()
        #expect(disk.pages.map(\.title) == ["A"])
        #expect(disk.folders == ["Work"])
        #expect(disk.starred.count == 1)
    }

    /// Saved before the file was read: kept, as the same page, so the save
    /// sheet's edits to it land.
    @Test func aSaveBeforeTheLoadFinishesIsKept() async throws {
        defer { clean() }
        var before = Saved()
        before.save(url("https://example.com/a"), title: "A")
        try before.save(to: file)

        let saved = store()
        let page = saved.save(url("https://example.org/b"), title: "B")!
        saved.move(page.id, to: "Later")
        await saved.load()
        #expect(saved.saved.pages.map(\.title) == ["B", "A"])
        #expect(saved.saved.pages[0].id == page.id)
        #expect(saved.saved.pages[0].folder == "Later")
        await saved.flush()
        #expect(try onDisk() == saved.saved)
    }

    @Test func everyChangeReachesTheFile() async throws {
        defer { clean() }
        let saved = store()
        await saved.load()
        let a = saved.save(url("https://example.com/a"), title: "A")!
        let b = saved.save(url("https://example.com/b"), title: "B")!
        saved.save(url("https://example.com/c"), title: "C")
        saved.star(a.id)
        saved.retitle(a.id, "Aye")
        saved.move(b.id, to: "Work")
        saved.addFolder("Home")
        saved.renameFolder("Home", to: "House")
        saved.opened(url("https://example.com/b"))
        saved.unsave(url("https://example.com/c"))
        await saved.flush()
        let disk = try onDisk()
        #expect(disk == saved.saved)
        #expect(disk.pages.map(\.title) == ["B", "Aye"])
        #expect(disk.folders == ["Work", "House"])
        #expect(disk.readLater.map(\.title) == ["Aye"])

        saved.remove(a.id)
        saved.deleteFolder("Work")
        await saved.flush()
        #expect(try onDisk() == saved.saved)
        #expect(saved.contains(url("https://www.example.com/b")))
    }

    @Test func changesAreSavedTogetherAMomentLater() async throws {
        defer { clean() }
        let saved = store(wait: .milliseconds(300))
        await saved.load()
        saved.save(url("https://example.com/a"), title: "A")
        saved.save(url("https://example.com/b"), title: "B")
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: file.path))

        try await Task.sleep(for: .milliseconds(900))
        #expect(try onDisk().pages.count == 2)
        #expect(await saved.file.writes == 1)
    }

    @Test func flushWritesNowAndOnlyWhatIsNew() async throws {
        defer { clean() }
        let saved = store()
        await saved.load()
        saved.save(url("https://example.com/a"), title: "A")
        await saved.flush()
        await saved.flush()
        #expect(await saved.file.writes == 1)
    }

    /// Opening a page that isn't saved is not a change, and writes nothing.
    @Test func openingAnUnsavedPageWritesNothing() async throws {
        defer { clean() }
        let saved = store(wait: .milliseconds(50))
        await saved.load()
        saved.opened(url("https://example.com/a"))
        try await Task.sleep(for: .milliseconds(300))
        await saved.flush()
        #expect(await saved.file.writes == 0)
    }

    @Test func anOlderSnapshotNeverLandsLast() async throws {
        defer { clean() }
        let disk = SavedFile(url: file)
        var snapshots: [Saved] = []
        var saved = Saved()
        for i in 1...20 {
            saved.save(url("https://site\(i).com/"), title: "\(i)")
            snapshots.append(saved)
        }
        await withTaskGroup(of: Void.self) { group in
            for (i, snapshot) in snapshots.enumerated().shuffled() {
                group.addTask { try? await disk.write(snapshot, generation: i + 1) }
            }
        }
        #expect(try onDisk() == snapshots[19])
    }
}
