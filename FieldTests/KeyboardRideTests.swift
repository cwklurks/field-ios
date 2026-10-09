import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Field

/// The bar going down with the keyboard after a tap outside or Go: it stays
/// a gap above the keyboard's top, as the field did, until it reaches its
/// place, rather than falling behind and landing after the keyboard has gone.
struct KeyboardRideTests {
    /// What UIKit gives the rider on the iPhone 17 simulator, iOS 26.
    static let spring = KeyboardRide.Spring(mass: 1, stiffness: 555.0265, damping: 47.118, velocity: 0)

    /// Critically damped, from rest: 1 - (1 + ωt)e^(-ωt).
    @Test func theSpringsProgressIsCoreAnimations() {
        let s = Self.spring
        #expect(s.progress(at: 0) == 0)
        let w = (555.0265).squareRoot()
        for t in [0.02, 0.1, 0.2, 0.3] {
            let expected = 1 - (1 + w * t) * exp(-w * t)
            #expect(abs(s.progress(at: t) - expected) < 0.002, "at \(t)")
        }
        #expect(s.progress(at: 0.3833) > 0.995)
    }

    @Test func anUnderdampedSpringOvershootsAndSettles() {
        let s = KeyboardRide.Spring(mass: 1, stiffness: 300, damping: 10, velocity: 0)
        let samples = stride(from: 0.0, through: 2, by: 0.01).map(s.progress(at:))
        #expect(samples.max()! > 1)
        #expect(abs(samples.last! - 1) < 0.01)
    }

    /// Nothing at either end, so the bar lands exactly where it would have.
    @Test func itAddsNothingAtTheEnds() {
        let ride = KeyboardRide(travel: 267, rest: 34, gap: 8)
        #expect(ride.offset(at: 0) == 0)
        #expect(abs(ride.offset(at: 1)) < 0.001)
    }

    /// Down from the rider's place, never up; and the bar's foot is the gap
    /// above the keyboard's top until it's home.
    @Test func theBarKeepsItsGapAboveTheKeyboardThenRests() {
        let ride = KeyboardRide(travel: 267, rest: 34, gap: 8)
        for x in stride(from: 0.0, through: 1, by: 0.01) {
            let offset = ride.offset(at: x)
            #expect(offset >= 0)
            let rider = 34 + 267 * (1 - x)
            let keyboard = (267 + 34) * (1 - x)
            let foot = rider - offset
            #expect(foot >= 34 - 0.001, "below its place at \(x)")
            #expect(foot >= keyboard + 8 * x - 0.001, "behind the keyboard at \(x)")
            #expect(foot <= max(keyboard + 8, 34) + 0.001, "left behind at \(x)")
        }
    }

    /// With no home indicator the rider already keeps up: nothing to add.
    @Test func noHomeIndicatorNoOffset() {
        let ride = KeyboardRide(travel: 260, rest: 0, gap: 8)
        for x in stride(from: 0.0, through: 1, by: 0.05) {
            #expect(ride.offset(at: x) == 0)
        }
    }

    /// Read off the rider's ride: only the keyboard's spring taking it down.
    @MainActor @Test func theKeepIsTimedAsTheRide() throws {
        let ride = CASpringAnimation(keyPath: "position")
        ride.mass = 1
        ride.stiffness = 555.0265
        ride.damping = 47.118
        ride.duration = 0.3833
        ride.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: -267))
        ride.toValue = NSValue(cgPoint: .zero)
        ride.isAdditive = true
        let (keep, offset) = try #require(KeyboardRide.keep(along: ride, rest: 34, gap: 8))
        #expect(keep.duration == ride.duration)
        #expect(keep.isAdditive)
        #expect(keep.keyPath == "transform.translation.y")
        let values = keep.values as? [CGFloat] ?? []
        #expect(values.first == 0)
        #expect(abs(values.last ?? 1) < 0.5)
        #expect((values.max() ?? 0) > 20)
        #expect(offset(10) == offset(0.3833))

        let up = ride.copy() as! CASpringAnimation
        up.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: 267))
        #expect(KeyboardRide.keep(along: up, rest: 34, gap: 8) == nil)
        #expect(KeyboardRide.keep(along: CABasicAnimation(keyPath: "position"), rest: 34, gap: 8) == nil)
        #expect(KeyboardRide.keep(along: nil, rest: 34, gap: 8) == nil)
    }
    @MainActor @Test func unfamiliarAnimationsFallBackToTheUnmodifiedRider() {
        let mutations: [(CASpringAnimation) -> Void] = [
            { $0.toValue = NSValue(cgPoint: CGPoint(x: 0, y: 100)) },
            { $0.fromValue = NSValue(cgPoint: CGPoint(x: 10, y: -267)) },
            { $0.speed = 2 },
            { $0.timeOffset = 0.1 },
            { $0.repeatCount = 2 },
            { $0.autoreverses = true },
            { $0.duration = 0.05 },
            { $0.timingFunction = CAMediaTimingFunction(name: .easeIn) },
            { $0.fromValue = NSNumber(value: -267) },
        ]
        for (index, mutate) in mutations.enumerated() {
            let ride = CASpringAnimation(keyPath: "position")
            ride.mass = 1
            ride.stiffness = 555.0265
            ride.damping = 47.118
            ride.duration = 0.3833
            ride.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: -267))
            ride.toValue = NSValue(cgPoint: .zero)
            ride.isAdditive = true
            mutate(ride)
            #expect(KeyboardRide.keep(along: ride, rest: 34, gap: 8) == nil, "variant \(index)")
        }
    }

}
