import CoreGraphics

/// Where a sideways throw lands: the pages under the bar, or a card in the
/// grid being thrown away. Each follows the finger 1:1 and, on release, goes
/// where the finger was throwing it, judged from where it would have coasted
/// to rather than where it let go.
enum Swipe {
    /// Seconds of coasting a release is judged by.
    static let projection: CGFloat = 0.2
    /// Between two pages side by side.
    static let pageGap: CGFloat = 16

    /// -1 for the tab before, 1 for the one after, 0 to stay. A negative
    /// offset is the page moved left, toward the next tab.
    static func step(offset: CGFloat, velocity: CGFloat, width: CGFloat, previous: Bool, next: Bool) -> Int {
        let landing = offset + velocity * projection
        if landing < -width / 2, next { return 1 }
        if landing > width / 2, previous { return -1 }
        return 0
    }

    /// How far the page moves for a finger `offset` past an end: less and
    /// less, as UIScrollView's edges do.
    static func rubber(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let moved = (1 - 1 / (abs(offset) * 0.55 / limit + 1)) * limit
        return offset < 0 ? -moved : moved
    }

    /// A card thrown far or fast enough to be closed.
    static func dismisses(offset: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        let landing = offset + velocity * projection
        return abs(landing) > width / 2 && (landing < 0) == (offset < 0)
    }

    /// A finger's speed in points a second, as UIKit's springs want it: a
    /// fraction of the distance still to go, each second.
    static func relative(velocity: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let distance = to - from
        guard abs(distance) > 0.5 else { return 0 }
        return velocity / distance
    }
}
