import CoreGraphics
import Testing
@testable import Field

/// The bar shrinks with the page point for point, and settles when the finger lifts.
struct CollapseTests {
    private let d = Collapse.distance

    @Test func followsThePageDown() {
        var c = Collapse()
        c.scrolled(from: 100, to: 100 + d / 2, limit: 1000)
        #expect(c.amount == 0.5)
        c.scrolled(from: 100 + d / 2, to: 100 + d, limit: 1000)
        #expect(c.amount == 1)
    }

    @Test func staysBetweenWholeAndPill() {
        var c = Collapse()
        c.scrolled(from: 100, to: 100 + 3 * d, limit: 1000)
        #expect(c.amount == 1)
        c.scrolled(from: 400, to: 400 - 5 * d, limit: 1000)
        #expect(c.amount == 0)
    }

    @Test func growsBackOnTheWayUp() {
        var c = Collapse(amount: 1)
        c.scrolled(from: 500, to: 500 - d / 4, limit: 1000)
        #expect(c.amount == 0.75)
    }

    /// Pulling past the top (pull to reload) is still the top: the whole bar.
    @Test func wholeAtTheTop() {
        var c = Collapse(amount: 1)
        c.scrolled(from: 10, to: -30, limit: 1000)
        #expect(c.amount == 0)
    }

    /// The rubber band at the bottom is not scrolling: it neither shrinks nor grows the bar.
    @Test func bounceAtTheBottomIsIgnored() {
        var c = Collapse(amount: 0.4)
        c.scrolled(from: 1000, to: 1060, limit: 1000)
        #expect(c.amount == 0.4)
        c.scrolled(from: 1060, to: 1000, limit: 1000)
        #expect(c.amount == 0.4)
    }

    /// A page shorter than the screen never scrolls, so never hides the bar.
    @Test func shortPageKeepsTheBar() {
        var c = Collapse()
        c.scrolled(from: 0, to: 40, limit: 0)
        #expect(c.amount == 0)
    }

    @Test func aFlickSettlesItsOwnWay() {
        #expect(Collapse(amount: 0.1).target(velocity: 2 * Collapse.flick, landing: 800) == 1)
        #expect(Collapse(amount: 0.9).target(velocity: -2 * Collapse.flick, landing: 800) == 0)
    }

    @Test func slowLiftsSettleOnTheNearer() {
        #expect(Collapse(amount: 0.6).target(velocity: 0, landing: 800) == 1)
        #expect(Collapse(amount: 0.4).target(velocity: 0, landing: 800) == 0)
    }

    /// Heading for the top of the page, the bar comes back whatever the speed.
    @Test func landingAtTheTopIsWhole() {
        #expect(Collapse(amount: 0.9).target(velocity: 2 * Collapse.flick, landing: 0) == 0)
    }

    /// The spring starts at the page's own speed: points per second become the
    /// share of the remaining way per second that SwiftUI's springs take.
    @Test func springStartsAtThePagesSpeed() {
        let c = Collapse(amount: 0.5)
        // 120 pt/s is two distances a second, over the half still to go.
        #expect(c.springVelocity(2 * d, toward: 1) == 4)
        #expect(c.springVelocity(-2 * d, toward: 0) == 4)
        #expect(Collapse(amount: 1).springVelocity(500, toward: 1) == 0)
    }
}
