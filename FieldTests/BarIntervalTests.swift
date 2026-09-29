import CoreGraphics
import Testing
@testable import Field

/// `bar.collapse` and `bar.expand` span the bar's movement toward that state,
/// from its first move until it settles there.
struct BarIntervalTests {
    /// The bug perf saw: a lift on a bar already whole or already a pill
    /// moves nothing, so it mustn't open (and at once close) an interval.
    @Test func settlingWhereItAlreadyIsIsNotAMovement() {
        var i = BarInterval()
        let (events, spring) = i.spring(from: 1, to: 1)
        #expect(events.isEmpty)
        #expect(spring == nil)
        #expect(i.open == nil)
    }

    @Test func aDragBeginsItOnceAndTheSpringEndsIt() {
        var i = BarInterval()
        #expect(i.moved(from: 0, to: 0.3) == [.begin(.collapse)])
        #expect(i.moved(from: 0.3, to: 0.5).isEmpty)
        let (events, spring) = i.spring(from: 0.5, to: 1)
        #expect(events.isEmpty)
        #expect(spring != nil)
        #expect(i.finished(spring!) == [.end(.collapse)])
        #expect(i.open == nil)
    }

    /// A drag that took the bar all the way leaves nothing to spring: it has
    /// settled when the finger lifts.
    @Test func aDragAllTheWayEndsAtTheLift() {
        var i = BarInterval()
        #expect(i.moved(from: 1, to: 0) == [.begin(.expand)])
        let (events, spring) = i.spring(from: 0, to: 0)
        #expect(events == [.end(.expand)])
        #expect(spring == nil)
    }

    /// A finger catching a spring: the spring's own finish no longer counts,
    /// and turning back is the other interval.
    @Test func anInterruptedSpringEndsWithTheOneThatSettles() {
        var i = BarInterval()
        let (begun, first) = i.spring(from: 0, to: 1)
        #expect(begun == [.begin(.collapse)])
        #expect(i.moved(from: 1, to: 0.8) == [.end(.collapse), .begin(.expand)])
        #expect(i.finished(first!).isEmpty)
        let (events, second) = i.spring(from: 0.8, to: 0)
        #expect(events.isEmpty)
        #expect(i.finished(second!) == [.end(.expand)])
    }

    /// Settling again on the target a spring is already heading for leaves
    /// that spring to finish, and to end the interval.
    @Test func aSecondSettleOnTheSameTargetWaitsForTheFirst() {
        var i = BarInterval()
        let (_, first) = i.spring(from: 0, to: 1)
        let (events, second) = i.spring(from: 1, to: 1)
        #expect(events.isEmpty)
        #expect(second == nil)
        #expect(i.finished(first!) == [.end(.collapse)])
    }

    @Test func aSpringSentBackTheOtherWay() {
        var i = BarInterval()
        let (_, first) = i.spring(from: 0, to: 1)
        let (events, second) = i.spring(from: 1, to: 0)
        #expect(events == [.end(.collapse), .begin(.expand)])
        #expect(i.finished(first!).isEmpty)
        #expect(i.finished(second!) == [.end(.expand)])
    }
}
