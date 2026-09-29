import CoreGraphics
import Testing
@testable import Field

/// A finger taking the keyboard down turns the field into the bar as far as
/// the keyboard has gone: none of the way with it up, all of it with it gone.
struct KeyboardDragTests {
    /// The iPhone 17: a 301-point keyboard over a 34-point home indicator.
    @Test func theWayGoneFollowsTheKeyboard() {
        #expect(KeyboardDrag.gone(height: 301, full: 301, rest: 34) == 0)
        #expect(KeyboardDrag.gone(height: 34, full: 301, rest: 34) == 1)
        #expect(abs(KeyboardDrag.gone(height: 167.5, full: 301, rest: 34) - 0.5) < 0.001)
    }

    /// Past either end (a rubber band, or the guide settling) it stays put.
    @Test func itStopsAtTheEnds() {
        #expect(KeyboardDrag.gone(height: 320, full: 301, rest: 34) == 0)
        #expect(KeyboardDrag.gone(height: 0, full: 301, rest: 34) == 1)
    }

    /// Before the keyboard's height is known there's nothing to follow.
    @Test func noKeyboardIsNoWay() {
        #expect(KeyboardDrag.gone(height: 34, full: 0, rest: 34) == 0)
        #expect(KeyboardDrag.gone(height: 34, full: 34, rest: 34) == 0)
    }
}
