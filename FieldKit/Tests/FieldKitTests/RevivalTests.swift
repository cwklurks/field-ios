import Testing
@testable import FieldKit

/// What a tab does when iOS kills its page's process: on screen it reloads
/// at once, off screen it waits to be shown, and after three deaths in a row
/// with no paint between them its web view is built again from scratch.
///
/// Each call is made outside #expect, which under xcodebuild won't take a
/// mutating one.
struct RevivalTests {
    /// What each death in turn asks for.
    func deaths(_ r: inout Revival, _ visible: [Bool]) -> [Revival.Action?] {
        visible.map { r.terminated(visible: $0) }
    }

    @Test func aVisibleTabReloads() {
        var r = Revival()
        let actions = deaths(&r, [true])
        #expect(actions == [.reload])
    }

    @Test func aHiddenTabWaitsUntilItIsShown() {
        var r = Revival()
        let died = deaths(&r, [false])
        #expect(died == [nil])
        #expect(r.pending)
        let first = r.shown()
        let again = r.shown()
        #expect(first == .reload)
        #expect(again == nil)
        #expect(!r.pending)
    }

    @Test func theThirdFailureInARowRebuilds() {
        var r = Revival()
        // The fourth is a new web view's first.
        let actions = deaths(&r, [true, true, true, true])
        #expect(actions == [.reload, .reload, .rebuild, .reload])
    }

    @Test func aPaintInBetweenStartsTheCountAgain() {
        var r = Revival()
        _ = deaths(&r, [true, true])
        r.painted()
        let actions = deaths(&r, [true, true, true])
        #expect(actions == [.reload, .reload, .rebuild])
    }

    /// Dying again while hidden still counts, and showing it then rebuilds.
    @Test func hiddenFailuresCountToo() {
        var r = Revival()
        let died = deaths(&r, [true, true, false])
        let shown = r.shown()
        #expect(died == [.reload, .reload, nil])
        #expect(shown == .rebuild)
    }
}
