// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI
import UIKit

// One spring for anything that moves between two places, one for anything that
// arrives or leaves, and one ease for a change of state. Using the same three
// everywhere is most of why a thing feels like a single piece of software
// rather than a pile of views.
enum Motion {
    static let glide = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.14)

    /// Glide, picking up where a finger left off at the speed it was going.
    static func glide(velocity: Double) -> Animation {
        .interpolatingSpring(Spring(response: 0.34, dampingRatio: 0.82), initialVelocity: velocity)
    }

    /// With Reduce Motion on, every spring becomes the quick fade.
    static func calm(_ animation: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled ? quick : animation
    }
}
