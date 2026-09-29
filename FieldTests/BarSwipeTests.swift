import CoreGraphics
import Testing
@testable import Field

/// What a drag on the bar is for, judged from the finger's velocity as it
/// starts: only a clearly sideways one moves the pages, only a clearly
/// upward one opens the grid.
struct BarSwipeTests {
    @Test func sidewaysMovesThePages() {
        #expect(BarSwipe(velocity: CGPoint(x: 600, y: 40)) == .sideways)
        #expect(BarSwipe(velocity: CGPoint(x: -600, y: -40)) == .sideways)
    }

    @Test func upOpensTheGrid() {
        #expect(BarSwipe(velocity: CGPoint(x: 30, y: -700)) == .up)
    }

    /// A diagonal is neither, and down is nothing on the bar: the touch is
    /// left to the buttons.
    @Test func anythingLessClearIsLeftAlone() {
        #expect(BarSwipe(velocity: CGPoint(x: 400, y: 300)) == nil)
        #expect(BarSwipe(velocity: CGPoint(x: -300, y: -400)) == nil)
        #expect(BarSwipe(velocity: CGPoint(x: 20, y: 700)) == nil)
        #expect(BarSwipe(velocity: .zero) == nil)
    }

    /// Recognised only after the finger has gone some way: the page starts
    /// moving then, neither jumping to the finger nor staying behind it.
    @Test func theSlopIsTakenUpGradually() {
        let first = BarSwipe.shown(travel: 24, slop: 24, step: 0)
        #expect(first > 0 && first < 24)
        // A finger held still: each frame takes up less than the one before.
        let offsets = (0..<BarSwipe.catchUp).map { BarSwipe.shown(travel: 24, slop: 24, step: $0) }
        let steps = zip(offsets.dropFirst(), offsets).map { $0 - $1 }
        #expect(steps.allSatisfy { $0 > 0 })
        #expect(zip(steps.dropFirst(), steps).allSatisfy { $0 < $1 })
    }

    @Test func thenThePageIsExactlyUnderTheFinger() {
        for step in (BarSwipe.catchUp - 1)...(BarSwipe.catchUp + 5) {
            #expect(BarSwipe.shown(travel: 140, slop: 24, step: step) == 140)
            #expect(BarSwipe.shown(travel: -140, slop: -30, step: step) == -140)
        }
    }

    @Test func noSlopIsOneToOneFromTheStart() {
        #expect(BarSwipe.shown(travel: 12, slop: 0, step: 0) == 12)
    }
}
