import Foundation
import UIKit
@testable import FieldKit
import Testing
@testable import Field

/// The list of tabs, without web views: what opening, closing, reopening
/// and restoring do to it, and what it tells the session.
@Suite(.serialized)
struct TabsTests {
    let history = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("TabsTests-\(UUID().uuidString)"))

    func tabs(_ shape: Session.Shape = Session.Shape()) -> Tabs {
        Tabs(history: history, restoring: shape, store: SessionStore(directory: nil), snapshots: Snapshots(directory: nil))
    }

    func entry(_ url: String) -> Session.Entry {
        Session.Entry(url: url, title: url, interactionState: Data(url.utf8))
    }

    func urls(_ tabs: Tabs) -> [String] { tabs.all.map { $0.url?.absoluteString ?? "" } }

    @Test func anEmptySessionIsOneBlankTab() {
        let t = tabs()
        #expect(t.all.count == 1)
        #expect(t.current.url == nil)
        #expect(!t.current.asleep)
    }

    /// Every tab comes back asleep, the active one included: it's the one
    /// woken first, after the first frame.
    @Test func restoresEveryTabAsleepWithItsId() {
        let entries = [entry("https://a.com/"), entry("https://b.com/"), entry("https://c.com/")]
        let t = tabs(Session.Shape(tabs: entries, active: 1))
        #expect(t.all.map(\.id) == entries.map(\.id))
        #expect(t.current.id == entries[1].id)
        #expect(t.all.allSatisfy { $0.asleep })
        #expect(t.all.map(\.title) == ["https://a.com/", "https://b.com/", "https://c.com/"])
    }

    @Test func theShapeIsWhatWasRestored() {
        let entries = [entry("https://a.com/"), entry("https://b.com/")]
        let shape = Session.Shape(tabs: entries, active: 1)
        let restored = tabs(shape)
        #expect(restored.shape == shape)
    }

    @Test func aNewTabGoesAtTheEndAndIsCurrent() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 0))
        let new = t.newTab()
        #expect(t.all.last === new)
        #expect(t.current === new)
        #expect(t.shape.active == 2)
    }

    /// As in Safari: closing the one you're on shows the next, or the one
    /// before when it was last.
    @Test func closingTheCurrentTabShowsItsNeighbour() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/"), entry("https://c.com/")], active: 1))
        t.close(t.current)
        #expect(urls(t) == ["https://a.com/", "https://c.com/"])
        #expect(t.current.url?.absoluteString == "https://c.com/")
        t.close(t.current)
        #expect(t.current.url?.absoluteString == "https://a.com/")
    }

    @Test func closingTheLastTabLeavesABlankOne() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/")], active: 0))
        t.close(t.current)
        #expect(t.all.count == 1)
        #expect(t.current.url == nil)
    }

    @Test func closingAnotherTabKeepsTheCurrentOne() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 1))
        let b = t.current
        t.close(t.all[0])
        #expect(t.current === b)
    }

    /// Back where it was, with its back and forward list and its id (and so
    /// its picture).
    @Test func reopenPutsTheLastClosedBackInItsPlace() throws {
        let entries = [entry("https://a.com/"), entry("https://b.com/"), entry("https://c.com/")]
        let t = tabs(Session.Shape(tabs: entries, active: 2))
        t.close(t.all[1])
        #expect(t.closed.count == 1)
        let back = try #require(t.reopen())
        #expect(back.id == entries[1].id)
        #expect(t.all.firstIndex { $0 === back } == 1)
        #expect(t.current === back)
        #expect(back.entry.interactionState == entries[1].interactionState)
        #expect(t.closed.isEmpty)
        #expect(t.reopen() == nil)
    }

    /// A blank tab has nothing to reopen.
    @Test func aBlankTabIsNotRemembered() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/")], active: 0))
        let blank = t.newTab()
        t.close(blank)
        #expect(t.closed.isEmpty)
    }

    @Test func switchingByAStepStopsAtTheEnds() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 0))
        #expect(t.neighbour(by: -1) == nil)
        #expect(t.neighbour(by: 1) === t.all[1])
        t.select(t.all[1])
        #expect(t.neighbour(by: 1) == nil)
        #expect(t.neighbour(by: -1) === t.all[0])
    }

    /// `-FieldSeedTabs 50`: made-up tabs that open without a network.
    @Test func seedsAreDistinctPagesThatNeedNoNetwork() {
        let seed = Tabs.seed(50)
        #expect(seed.count == 50)
        #expect(Set(seed.map(\.id)).count == 50)
        #expect(seed.allSatisfy { $0.url.hasPrefix("data:text/html") && URL(string: $0.url) != nil })
        #expect(Set(seed.map(\.title)).count == 50)
    }
}

/// The sleep policy with real web views: the one on screen and the two used
/// just before it keep theirs, and a memory warning leaves only the one on
/// screen. Each keeps its address and state asleep.
@Suite(.serialized)
struct TabsSleepTests {
    let history = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("TabsSleepTests-\(UUID().uuidString)"))

    func awake(_ tabs: Tabs, within: Duration = .seconds(3), until done: (Int) -> Bool) async -> Int {
        let clock = ContinuousClock()
        let end = clock.now + within
        var count = tabs.all.filter { $0.web != nil }.count
        while !done(count), clock.now < end {
            try? await Task.sleep(for: .milliseconds(50))
            count = tabs.all.filter { $0.web != nil }.count
        }
        return count
    }

    @Test func onlyTheCurrentAndTwoRecentStayAwake() async {
        let entries = (0..<5).map { Session.Entry(url: "about:blank#\($0)", title: "\($0)") }
        let tabs = Tabs(history: history, restoring: Session.Shape(tabs: entries, active: 0),
                        store: SessionStore(directory: nil), snapshots: Snapshots(directory: nil))
        for tab in tabs.all {
            tabs.select(tab)
            tab.build()
        }
        let settled = await awake(tabs) { $0 == 1 + Sleep.recent }
        #expect(settled == 1 + Sleep.recent)
        #expect(tabs.current.web != nil)
        #expect(tabs.all.suffix(3).allSatisfy { $0.web != nil })
        #expect(tabs.all.prefix(2).allSatisfy { $0.asleep && $0.url != nil })

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        let warned = await awake(tabs) { $0 == 1 }
        #expect(warned == 1)
        #expect(tabs.current.web != nil)
    }
}
