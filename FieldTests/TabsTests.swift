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

    /// At launch, a page whose picture is late holds the bar back with it,
    /// even a bar made after the hold began, and lets it go with the page.
    @Test func aHeldBarWaitsWithThePage() {
        let t = tabs()
        t.barHeld = true
        let bar = UIView()
        t.chrome = bar
        #expect(bar.alpha == 0)
        t.barHeld = false
        #expect(bar.alpha == 1)
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
        // But for when the tab on screen was last seen: now.
        #expect(restored.shape.tabs[1].viewed != nil)
        var seen = restored.shape
        seen.tabs = seen.tabs.map { entry in
            var unseen = entry
            unseen.viewed = nil
            return unseen
        }
        #expect(seen == shape)
    }

    @Test func aNewTabGoesAtTheEndAndIsCurrent() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 0))
        let new = t.newTab()
        #expect(t.all.last === new)
        #expect(t.current === new)
        #expect(t.shape.active == 2)
    }

    /// A popup let through opens next to its page, not at the end, and is
    /// the one shown.
    @Test func aPopupOpensBesideItsPage() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 0))
        t.openBeside(URL(string: "https://popup.example/")!)
        #expect(urls(t) == ["https://a.com/", "https://popup.example/", "https://b.com/"])
        #expect(t.current.url?.absoluteString == "https://popup.example/")
    }

    /// Groups come back from the session, and go back into it, with each
    /// tab's group and when it was last seen.
    @Test func groupsRoundTripThroughTheSession() {
        let group = Session.Group(name: "Trip")
        var first = entry("https://a.com/")
        first.group = group.id
        first.viewed = Date(timeIntervalSince1970: 1_000)
        let t = tabs(Session.Shape(tabs: [first, entry("https://b.com/")], active: 1, groups: [group]))
        #expect(t.groups == [group])
        #expect(t.all[0].group == group.id)
        #expect(t.shape.tabs[0].viewed == Date(timeIntervalSince1970: 1_000))
        #expect(t.shape.groups == [group])
        // Shown, a tab's clock starts again.
        #expect(t.shape.tabs[1].viewed != nil)
    }

    /// Tidy's Apply and Undo: the grouping as a whole, and a group left with
    /// no tabs goes.
    @Test func regroupSetsEveryTabsGroup() {
        let t = tabs(Session.Shape(tabs: [entry("https://a.com/"), entry("https://b.com/")], active: 0))
        let trip = Session.Group(name: "Trip")
        t.regroup(Session.Grouping(groups: [trip, Session.Group(name: "Empty")], membership: [t.all[1].id: trip.id]))
        #expect(t.groups == [trip])
        #expect(t.all.map(\.group) == [nil, trip.id])
        t.regroup(Session.Grouping())
        #expect(t.groups.isEmpty)
        #expect(t.all.allSatisfy { $0.group == nil })
    }

    /// Stale tabs closed together come back together, however many: more
    /// than Recently Closed holds, in their places, the one on screen kept.
    @Test func aBulkCloseUndoesWhole() {
        let many = (0..<30).map { entry("https://\($0).com/") }
        let t = tabs(Session.Shape(tabs: many + [entry("https://keep.com/")], active: 30))
        let before = urls(t)
        let undo = t.close(all: Array(t.all.prefix(30)))
        #expect(urls(t) == ["https://keep.com/"])
        undo()
        #expect(urls(t) == before)
        #expect(t.current.url?.absoluteString == "https://keep.com/")
        #expect(t.closed.items.isEmpty)
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
