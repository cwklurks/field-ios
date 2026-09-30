import Foundation
import Testing
@testable import FieldKit

/// Pages you keep: one list, an optional folder each, a star for the new
/// tab, and "Read later" for the ones not opened since.
struct SavedTests {
    func url(_ text: String) -> URL { URL(string: text)! }
    let day: TimeInterval = 86_400
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func savesAPageNewestFirst() {
        var saved = Saved()
        saved.save(url("https://example.com/a"), title: "A", now: now)
        saved.save(url("https://example.org/b"), title: "B", now: now + 1)
        #expect(saved.pages.map(\.title) == ["B", "A"])
        #expect(saved.pages[0].added == now + 1)
        #expect(saved.pages[0].folder == nil)
        #expect(!saved.pages[0].starred)
        #expect(saved.pages[0].lastOpened == nil)
    }

    /// The same page twice is one page: the first save stands, and the
    /// second hands it back.
    @Test func savingAgainIsTheSamePage() {
        var saved = Saved()
        let first = saved.save(url("https://example.com/a"), title: "A", now: now)
        let again = saved.save(url("https://www.example.com/a#section"), title: "Another", now: now + 5)
        #expect(saved.pages.count == 1)
        #expect(again == first)
        #expect(saved.contains(url("http://EXAMPLE.com/a/")))
        #expect(!saved.contains(url("https://example.com/b")))
    }

    /// A save made again (the app replays one made before its file was
    /// read) is the same page, id and all.
    @Test func keepsTheIDItIsGiven() {
        var saved = Saved()
        let id = UUID()
        #expect(saved.save(url("https://example.com/a"), title: "A", id: id, now: now)?.id == id)
    }

    @Test func onlyWebPagesAreSavedAndNeverAPassword() {
        var saved = Saved()
        #expect(saved.save(url("about:blank"), title: "", now: now) == nil)
        #expect(saved.save(url("file:///etc/hosts"), title: "", now: now) == nil)
        let page = saved.save(url("https://me:secret@example.com/a"), title: "A", now: now)
        #expect(page?.url.absoluteString == "https://example.com/a")
    }

    @Test func aPageWithoutATitleIsCalledByItsAddress() {
        var saved = Saved()
        saved.save(url("https://www.example.com/notes/one"), title: "  ", now: now)
        #expect(saved.pages[0].title == "example.com/notes/one")
        #expect(saved.pages[0].host == "example.com")
    }

    @Test func unsavesByAddressOrByID() {
        var saved = Saved()
        saved.save(url("https://example.com/a"), title: "A", now: now)
        let b = saved.save(url("https://example.com/b"), title: "B", now: now)!
        saved.unsave(url("https://www.example.com/a"))
        #expect(saved.pages.map(\.title) == ["B"])
        saved.remove(b.id)
        #expect(saved.pages.isEmpty)
    }

    @Test func starsAndUnstars() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        let b = saved.save(url("https://example.com/b"), title: "B", now: now + 1)!
        saved.save(url("https://example.com/c"), title: "C", now: now + 2)
        saved.star(b.id)
        saved.star(a.id)
        // The grid keeps its places: oldest saved first, so a new star
        // arrives at the end rather than pushing the others along.
        #expect(saved.starred.map(\.title) == ["A", "B"])
        saved.star(a.id, false)
        #expect(saved.starred.map(\.title) == ["B"])
    }

    @Test func retitles() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        saved.retitle(a.id, "  Better  ")
        #expect(saved.pages[0].title == "Better")
        // An empty title is the address again, never blank.
        saved.retitle(a.id, "")
        #expect(saved.pages[0].title == "example.com/a")
    }

    // MARK: - folders

    @Test func movingToAFolderMakesIt() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        saved.move(a.id, to: " Work ")
        #expect(saved.folders == ["Work"])
        #expect(saved.pages[0].folder == "Work")
        #expect(saved.pages(in: "Work").map(\.title) == ["A"])
        saved.move(a.id, to: nil)
        #expect(saved.pages[0].folder == nil)
        // A folder stays when it empties; it goes when you delete it.
        #expect(saved.folders == ["Work"])
    }

    /// "work" is the Work folder that's already there, not a second one.
    @Test func aFolderNameIsMatchedWithoutCase() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        let b = saved.save(url("https://example.com/b"), title: "B", now: now)!
        saved.move(a.id, to: "Work")
        saved.move(b.id, to: "work")
        #expect(saved.folders == ["Work"])
        #expect(saved.count(in: "Work") == 2)
        #expect(saved.addFolder("WORK") == "Work")
        #expect(saved.addFolder("   ") == nil)
        #expect(saved.addFolder("Home") == "Home")
        #expect(saved.folders == ["Work", "Home"])
    }

    /// Folders are one level: a slash is only a character.
    @Test func saveCanFileAndStarAtOnce() {
        var saved = Saved()
        let page = saved.save(url("https://example.com/a"), title: "A", folder: "Trips/Lisbon", starred: true, now: now)
        #expect(page?.folder == "Trips/Lisbon")
        #expect(page?.starred == true)
        #expect(saved.folders == ["Trips/Lisbon"])
    }

    @Test func renamesAFolderAndItsPages() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        saved.move(a.id, to: "Wrok")
        saved.addFolder("Home")
        saved.renameFolder("Wrok", to: "Work")
        #expect(saved.folders == ["Work", "Home"])
        #expect(saved.pages[0].folder == "Work")
    }

    /// Renaming onto a folder that exists merges the two.
    @Test func renamingOntoAnotherFolderMerges() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        let b = saved.save(url("https://example.com/b"), title: "B", now: now)!
        saved.move(a.id, to: "Work")
        saved.move(b.id, to: "Jobs")
        saved.renameFolder("Jobs", to: "work")
        #expect(saved.folders == ["Work"])
        #expect(saved.count(in: "Work") == 2)
        // Nothing to rename to, or nothing to rename: nothing happens.
        saved.renameFolder("Work", to: " ")
        saved.renameFolder("Nowhere", to: "Else")
        #expect(saved.folders == ["Work"])
    }

    /// Deleting a folder never deletes what's in it: the pages stay saved,
    /// in no folder.
    @Test func deletingAFolderKeepsItsPages() {
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", now: now)!
        saved.move(a.id, to: "Work")
        saved.deleteFolder("work")
        #expect(saved.folders.isEmpty)
        #expect(saved.pages.count == 1)
        #expect(saved.pages[0].folder == nil)
    }

    // MARK: - read later

    /// Saved and not opened since: a page saved and never looked at again.
    @Test func readLaterIsWhatYouHaveNotOpenedSinceSaving() {
        var saved = Saved()
        saved.save(url("https://example.com/a"), title: "A", now: now)
        saved.save(url("https://example.com/b"), title: "B", now: now + 1)
        #expect(saved.readLater.map(\.title) == ["B", "A"])
        saved.opened(url("https://www.example.com/a#top"), now: now + day)
        #expect(saved.readLater.map(\.title) == ["B"])
        #expect(saved.pages.first { $0.title == "A" }?.lastOpened == now + day)
        // Opening a page nobody saved changes nothing.
        let before = saved
        saved.opened(url("https://example.com/z"), now: now + day)
        #expect(saved == before)
    }

    // MARK: - search

    @Test func searchesTitlesAndHosts() {
        var saved = Saved()
        saved.save(url("https://www.seriouseats.com/cookies"), title: "The Best Chocolate Chip Cookies", now: now)
        saved.save(url("https://swift.org/documentation"), title: "Swift Documentation", now: now + 1)
        saved.save(url("https://example.com/crème"), title: "Crème brûlée", now: now + 2)
        #expect(saved.search("cookie").map(\.host) == ["seriouseats.com"])
        #expect(saved.search("SERIOUSEATS").count == 1)
        #expect(saved.search("swift docs").isEmpty)
        #expect(saved.search("swift documentation").count == 1)
        // Every word has to be there, in any order and either place.
        #expect(saved.search("documentation swift.org").count == 1)
        // Accents are optional.
        #expect(saved.search("creme brulee").count == 1)
        // Nothing typed is everything, newest first.
        #expect(saved.search("  ").count == 3)
        // Only the host, never the rest of the address.
        #expect(saved.search("documentation").count == 1)
        #expect(saved.search("cookies").count == 1)
    }

    // MARK: - the file

    @Test func roundTripsThroughAFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedTests-\(UUID().uuidString)/saved.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var saved = Saved()
        let a = saved.save(url("https://example.com/a"), title: "A", folder: "Work", starred: true, now: now)!
        saved.save(url("https://example.com/b"), title: "B", now: now + 1)
        saved.addFolder("Empty")
        saved.opened(a.url, now: now + day)
        try saved.save(to: file)
        #expect(try Saved.load(from: file) == saved)
    }

    @Test func noFileIsNothingSaved() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SavedTests-none-\(UUID().uuidString).json")
        #expect(try Saved.load(from: file) == Saved())
    }

    /// A file that isn't one is set aside and read as empty, as history is.
    @Test func aFileThatIsNotOneIsSetAside() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SavedTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("saved.json")
        try Data("not json".utf8).write(to: file)
        #expect(try Saved.load(from: file) == Saved())
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left.count == 1)
        #expect(left[0].hasPrefix("saved.unreadable-"))
    }

    /// Whatever a file says, what's read keeps the rules: one page per
    /// address, and every page's folder in the list of folders.
    @Test func aFileIsMadeToKeepTheRules() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedTests-\(UUID().uuidString)/saved.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let json = """
        {"folders": ["Work", "work"], "pages": [
          {"id": "\(UUID())", "url": "https://example.com/a", "title": "A", "added": 0, "folder": "Home", "starred": false},
          {"id": "\(UUID())", "url": "https://www.example.com/a", "title": "A again", "added": 0, "starred": true}
        ]}
        """
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
        let saved = try Saved.load(from: file)
        #expect(saved.pages.map(\.title) == ["A"])
        #expect(saved.folders == ["Work", "Home"])
    }

    @Test func aSampleIsTheSameEveryTime() {
        let one = Saved.sample(500, now: now)
        let two = Saved.sample(500, now: now)
        #expect(one.pages.count == 500)
        #expect(one.pages.map(\.url) == two.pages.map(\.url))
        #expect(!one.folders.isEmpty)
        #expect(!one.starred.isEmpty)
        #expect(!one.readLater.isEmpty)
        #expect(one.readLater.count < 500)
    }
}
