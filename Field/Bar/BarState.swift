import SwiftUI
import os

/// The bar's shrink, which the page's scrolling moves every frame. It lives
/// apart from everything else and is drawn by the surface alone, straight from
/// here, so a scroll redraws that one small view and nothing else.
@MainActor final class BarState {
    /// Where the bar is, before any animation catches up.
    var amount: CGFloat { collapse.amount }

    /// Draws the bar at an amount: at once (nil), or springing there on the
    /// glide at a speed, calling back when it lands or is taken over by a
    /// newer move. The surface sets this.
    var draw: (_ amount: CGFloat, _ spring: CGFloat?, _ done: @escaping () -> Void) -> Void = { _, _, done in done() }

    private var collapse = Collapse()
    private var interval = BarInterval()
    private var signpost: OSSignpostIntervalState?
    /// What's drawn, or on its way there.
    private var drawn: CGFloat = 0

    /// The page moved under a finger; see Collapse.scrolled.
    func track(from old: CGFloat, to new: CGFloat, limit: CGFloat) {
        let before = collapse.amount
        collapse.scrolled(from: old, to: new, limit: limit)
        let after = collapse.amount
        guard after != before else { return }
        if abs(after - before) > 0.2 {
            // Reaching the top whole all at once: glide there instead of jumping.
            settle(to: after)
        } else {
            signal(interval.moved(from: drawn, to: after))
            drawn = after
            draw(after, nil) {}
        }
    }

    /// The finger lifted, with the page going `velocity` points a second down
    /// it, to come to rest at `landing`.
    func release(velocity: CGFloat, landing: CGFloat) {
        settle(to: collapse.target(velocity: velocity, landing: landing), velocity: velocity)
    }

    /// Back to the whole bar: a tap on the pill, a new page, the top.
    func expand() {
        guard collapse.amount != 0 || drawn != 0 else { return }
        settle(to: 0)
    }

    private func settle(to target: CGFloat, velocity: CGFloat = 0) {
        let speed = collapse.springVelocity(velocity, toward: target)
        collapse.amount = target
        let (events, spring) = interval.spring(from: drawn, to: target)
        signal(events)
        guard let spring else { return }
        drawn = target
        // A spring a finger or a newer spring takes over finishes early;
        // BarInterval knows it no longer counts.
        draw(target, CGFloat(speed)) { [weak self] in
            guard let self else { return }
            signal(interval.finished(spring))
        }
    }

    /// `bar.collapse` and `bar.expand`, as BarInterval opens and closes them.
    private func signal(_ events: [BarInterval.Event]) {
        for event in events {
            switch event {
            case .begin(let name):
                signpost = Signpost.log.beginAnimationInterval(Self.signpost(name))
            case .end(let name):
                guard let state = signpost else { continue }
                Signpost.log.endInterval(Self.signpost(name), state)
                signpost = nil
            }
        }
    }

    private static func signpost(_ name: BarInterval.Name) -> StaticString {
        switch name {
        case .collapse: return Signpost.barCollapse
        case .expand: return Signpost.barExpand
        }
    }
}
