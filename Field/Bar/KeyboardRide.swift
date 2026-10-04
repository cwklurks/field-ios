import Foundation
import UIKit

/// The bar going down with the keyboard after a tap outside or Go. The rider
/// stands on the keyboard's layout guide, which stops at the home indicator,
/// and UIKit moves it there on the keyboard's own spring. But the keyboard's
/// top goes further, to the bottom of the screen, on the same spring, so it
/// pulled away from the bar, and the bar landed after the keyboard had gone.
/// This is how far below the rider the bar goes instead: the field's gap
/// above the keyboard's top, all the way down, until it's in its place.
struct KeyboardRide {
    /// How far the rider goes down, from the keyboard's top to `rest`.
    let travel: CGFloat
    /// Where the rider stops, above the bottom of the screen: the home
    /// indicator's height.
    let rest: CGFloat
    /// Between the bar's foot and the keyboard's top on the way down.
    let gap: CGFloat

    /// Points below the rider, when the keyboard is `progress` of its way
    /// down (0 to 1). The keyboard's top is `(travel + rest) * (1 - x)` above
    /// the bottom, the rider's foot `rest + travel * (1 - x)`; the bar's foot
    /// is the gap (growing in from none) above the keyboard's top, or at
    /// rest, whichever is higher. Never above the rider, and none at the ends.
    func offset(at progress: Double) -> CGFloat {
        let x = CGFloat(progress)
        return max(0, min((rest - gap) * x, travel * (1 - x)))
    }

    /// A Core Animation spring's progress from 0 to 1, as CASpringAnimation
    /// draws it: the keyboard's, read off the rider's animation.
    struct Spring: Equatable {
        let mass: Double
        let stiffness: Double
        let damping: Double
        /// In the whole way per second, as CASpringAnimation takes it.
        let velocity: Double

        func progress(at t: Double) -> Double {
            guard t > 0 else { return 0 }
            let w0 = (stiffness / mass).squareRoot()
            let zeta = damping / (2 * (stiffness * mass).squareRoot())
            // What's left of the way, from 1, leaving at `velocity`.
            let left: Double
            if abs(zeta - 1) < 0.001 {
                left = exp(-w0 * t) * (1 + (w0 - velocity) * t)
            } else if zeta < 1 {
                let wd = w0 * (1 - zeta * zeta).squareRoot()
                left = exp(-zeta * w0 * t) * (cos(wd * t) + (zeta * w0 - velocity) / wd * sin(wd * t))
            } else {
                let root = (zeta * zeta - 1).squareRoot()
                let r1 = -w0 * (zeta - root), r2 = -w0 * (zeta + root)
                let a = (-velocity - r2) / (r1 - r2)
                left = a * exp(r1 * t) + (1 - a) * exp(r2 * t)
            }
            return 1 - left
        }
    }
}

extension KeyboardRide {
    /// The keep for the rider's ride, if it's the keyboard's spring taking
    /// it down: what the bar adds to it, as an animation timed as the ride
    /// itself, and the same as a function of the time since it began.
    static func keep(along ride: CAAnimation?, rest: CGFloat, gap: CGFloat)
        -> (animation: CAKeyframeAnimation, offset: (CFTimeInterval) -> CGFloat)? {
        guard let ride = ride as? CASpringAnimation, ride.isAdditive,
              let from = (ride.fromValue as? NSValue)?.cgPointValue, from.y < 0 else { return nil }
        let spring = Spring(mass: ride.mass, stiffness: ride.stiffness, damping: ride.damping, velocity: ride.initialVelocity)
        let path = KeyboardRide(travel: -from.y, rest: rest, gap: gap)
        let duration = ride.duration
        let steps = 48
        let keep = CAKeyframeAnimation(keyPath: "transform.translation.y")
        keep.values = (0...steps).map { path.offset(at: spring.progress(at: duration * Double($0) / Double(steps))) }
        keep.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        keep.beginTime = ride.beginTime
        keep.duration = duration
        keep.isAdditive = true
        return (keep, { path.offset(at: spring.progress(at: min($0, duration))) })
    }
}
