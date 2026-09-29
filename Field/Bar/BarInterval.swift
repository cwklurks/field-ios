import CoreGraphics

/// Which of `bar.collapse` and `bar.expand` is open. One opens when the bar
/// starts moving toward that state and closes when it settles there: when
/// the last spring toward it finishes, or at the lift if a finger already
/// took it all the way. A spring a finger interrupts no longer counts, and
/// turning back closes one and opens the other.
struct BarInterval {
    enum Name { case collapse, expand }
    enum Event: Equatable { case begin(Name), end(Name) }

    private(set) var open: Name?
    /// The spring in flight, 0 for none.
    private var spring = 0
    private var springs = 0

    /// A finger moved the bar straight from one amount to another.
    mutating func moved(from old: CGFloat, to new: CGFloat) -> [Event] {
        spring = 0
        return head(from: old, to: new)
    }

    /// The bar is to spring from where it's drawn to `new`. Returns the
    /// spring's number, to hand back to `finished`, or nil when there's
    /// nothing to animate.
    mutating func spring(from old: CGFloat, to new: CGFloat) -> (events: [Event], spring: Int?) {
        guard old == new else {
            let events = head(from: old, to: new)
            springs += 1
            spring = springs
            return (events, spring)
        }
        // Already there. A spring still on its way finishes the interval;
        // with none, the bar has settled now.
        guard spring == 0, let name = open else { return ([], nil) }
        open = nil
        return ([.end(name)], nil)
    }

    mutating func finished(_ number: Int) -> [Event] {
        guard number == spring, let name = open else { return [] }
        spring = 0
        open = nil
        return [.end(name)]
    }

    private mutating func head(from old: CGFloat, to new: CGFloat) -> [Event] {
        guard old != new else { return [] }
        let name: Name = new > old ? .collapse : .expand
        guard name != open else { return [] }
        defer { open = name }
        return open.map { [.end($0), .begin(name)] } ?? [.begin(name)]
    }
}
