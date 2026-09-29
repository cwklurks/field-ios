import Foundation
import Testing
@testable import FieldKit

/// Tabs you closed, newest first, so the last one comes back first and to
/// the place it was.
struct RecentlyClosedTests {
    @Test func reopensTheLastClosedFirst() {
        var closed = RecentlyClosed<String>()
        closed.push("a", at: 0)
        closed.push("b", at: 3)
        let b = closed.pop()
        let a = closed.pop()
        let none = closed.pop()
        #expect(b?.item == "b")
        #expect(a?.item == "a")
        #expect(a?.index == 0)
        #expect(none == nil)
        #expect(closed.isEmpty)
    }

    /// Past the cap the oldest goes, and is handed back so what it kept on
    /// disk (its snapshot) can go too.
    @Test func dropsTheOldestPastTheCap() {
        var closed = RecentlyClosed<Int>(cap: 3)
        let first = closed.push(1, at: 0)
        closed.push(2, at: 0)
        closed.push(3, at: 0)
        let dropped = closed.push(4, at: 0)
        #expect(first == nil)
        #expect(dropped == 1)
        #expect(closed.items == [4, 3, 2])
    }

    @Test func theNewestIsFirst() {
        var closed = RecentlyClosed<String>()
        closed.push("a", at: 0)
        closed.push("b", at: 0)
        #expect(closed.items == ["b", "a"])
        #expect(closed.count == 2)
    }

    /// Reopening one from the middle of the list.
    @Test func removesByPosition() {
        var closed = RecentlyClosed<String>()
        closed.push("a", at: 0)
        closed.push("b", at: 1)
        closed.push("c", at: 2)
        let b = closed.remove(at: 1)
        #expect(b.item == "b")
        #expect(b.index == 1)
        #expect(closed.items == ["c", "a"])
    }
}
