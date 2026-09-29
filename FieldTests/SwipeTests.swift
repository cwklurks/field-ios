import CoreGraphics
import Testing
@testable import Field

/// Where a sideways swipe lands: the page follows the finger, and on release
/// goes where the finger was throwing it.
struct SwipeTests {
    let width: CGFloat = 402

    @Test func aSlowDragPastHalfwayChangesTab() {
        #expect(Swipe.step(offset: -210, velocity: 0, width: width, previous: true, next: true) == 1)
        #expect(Swipe.step(offset: 210, velocity: 0, width: width, previous: true, next: true) == -1)
        #expect(Swipe.step(offset: -150, velocity: 0, width: width, previous: true, next: true) == 0)
    }

    /// A flick counts from where it would coast to, not where it let go.
    @Test func aFlickChangesTabFromAShortDrag() {
        #expect(Swipe.step(offset: -40, velocity: -900, width: width, previous: true, next: true) == 1)
        // Thrown back the other way: stays.
        #expect(Swipe.step(offset: -250, velocity: 900, width: width, previous: true, next: true) == 0)
    }

    @Test func thereIsNothingPastTheEnds() {
        #expect(Swipe.step(offset: -300, velocity: -2000, width: width, previous: true, next: false) == 0)
        #expect(Swipe.step(offset: 300, velocity: 2000, width: width, previous: false, next: true) == 0)
    }

    /// Past the end the page still moves, but less and less.
    @Test func theEndsResist() {
        let a = Swipe.rubber(100, limit: width)
        let b = Swipe.rubber(200, limit: width)
        #expect(a > 0 && a < 100)
        #expect(b > a && b - a < a)
        #expect(Swipe.rubber(-100, limit: width) == -a)
        #expect(Swipe.rubber(0, limit: width) == 0)
    }

    /// A card thrown sideways far or fast enough is closed.
    @Test func aCardThrownAwayCloses() {
        #expect(Swipe.dismisses(offset: -120, velocity: -800, width: 180))
        #expect(Swipe.dismisses(offset: 110, velocity: 0, width: 180))
        #expect(!Swipe.dismisses(offset: 40, velocity: 0, width: 180))
        #expect(!Swipe.dismisses(offset: 120, velocity: -900, width: 180))
    }

    /// UIKit wants a spring's starting speed relative to the distance left.
    @Test func velocityIsRelativeToTheDistanceLeft() {
        // Moving toward where it's going: positive.
        #expect(abs(Swipe.relative(velocity: -800, from: -200, to: -402) - 800.0 / 202) < 0.0001)
        #expect(Swipe.relative(velocity: 800, from: -200, to: -402) < 0)
        #expect(Swipe.relative(velocity: 500, from: 10, to: 10) == 0)
    }
}
