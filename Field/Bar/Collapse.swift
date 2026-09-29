import CoreGraphics

/// How far the bar has shrunk toward its host-only pill: 0 is the whole bar,
/// 1 the pill. It follows the page point for point while a finger drags it,
/// and when the finger lifts it settles on one or the other at the speed the
/// page was going.
struct Collapse: Equatable {
    /// Points of scrolling that take the bar from whole to pill.
    static let distance: CGFloat = 60
    /// Faster than this, in points a second, a lift settles the way the page
    /// was going rather than on the nearer end.
    static let flick: CGFloat = 300

    var amount: CGFloat = 0

    /// The page moved between two offsets, 0 being its top and `limit` its
    /// last. Past either end is the rubber band, which isn't scrolling, so it
    /// counts as the end itself. At the top the bar is whole.
    mutating func scrolled(from old: CGFloat, to new: CGFloat, limit: CGFloat) {
        guard new > 0 else {
            amount = 0
            return
        }
        let end = max(limit, 0)
        let moved = min(new, end) - min(max(old, 0), end)
        amount = min(max(amount + moved / Self.distance, 0), 1)
    }

    /// Where it settles when the finger lifts: `velocity` is the page's, in
    /// points a second down the page, and `landing` where it will come to rest.
    func target(velocity: CGFloat, landing: CGFloat) -> CGFloat {
        if landing <= 0 { return 0 }
        if velocity > Self.flick { return 1 }
        if velocity < -Self.flick { return 0 }
        return amount >= 0.5 ? 1 : 0
    }

    /// The page's speed as the spring's starting speed, in what SwiftUI's
    /// springs take: the share of the remaining way covered per second. Held
    /// to a few times the way, so a flick near the end can't fling it past.
    func springVelocity(_ velocity: CGFloat, toward target: CGFloat) -> Double {
        let remaining = target - amount
        guard abs(remaining) > 0.001 else { return 0 }
        return Double(min(max(velocity / Self.distance / remaining, -8), 8))
    }
}
