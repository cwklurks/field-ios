import UIKit

/// The three curves of Motion, for the UIKit surface, plus the keyboard's own
/// for whatever rides on it. UIKit hands these to Core Animation, which runs
/// them in the render server: they keep moving while the main thread is held,
/// as it is for a moment when the field takes focus.
enum SurfaceMotion {
    enum Curve {
        /// Something moving between two places, picking up a finger's speed
        /// as a share of the way per second.
        case glide(velocity: CGFloat)
        case settle
        case quick
        /// The keyboard's, from its notification.
        case keyboard(duration: TimeInterval, curve: Int)

        static let glide = Curve.glide(velocity: 0)

        /// From a keyboard notification, or nil if it has no animation.
        init?(keyboard note: Notification) {
            let info = note.userInfo ?? [:]
            guard let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval, duration > 0 else { return nil }
            let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int ?? UIView.AnimationCurve.easeInOut.rawValue
            self = .keyboard(duration: duration, curve: curve)
        }
    }

    static func animate(
        _ curve: Curve,
        _ changes: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        let options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        // With Reduce Motion, every spring becomes the quick fade; the
        // keyboard keeps its own, since the surface rides it either way.
        let calm = UIAccessibility.isReduceMotionEnabled
        switch curve {
        case .glide(let velocity) where !calm:
            UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: velocity,
                           options: options, animations: changes, completion: completion)
        case .settle where !calm:
            UIView.animate(springDuration: 0.30, bounce: 0.14,
                           options: options, animations: changes, completion: completion)
        case .keyboard(let duration, let raw):
            UIView.animate(withDuration: duration, delay: 0,
                           options: options.union(UIView.AnimationOptions(rawValue: UInt(raw) << 16)),
                           animations: changes, completion: completion)
        default:
            UIView.animate(withDuration: 0.14, delay: 0, options: options.union(.curveEaseOut),
                           animations: changes, completion: completion)
        }
    }
}

/// Runs something once this turn's Core Animation commit is done: whatever
/// the turn set moving is with the render server and moving, and the main
/// thread is free to be held. From inside UIKit's handling of a touch or a
/// key, `CATransaction.flush()` can't do this: the commit waits for the turn
/// to end, and anything that holds the thread first (a focus, a resign, a
/// page load) holds the motion's start with it.
enum AfterCommit {
    static func run(_ body: @escaping () -> Void) {
        // Last before the main thread sleeps, after Core Animation's own
        // observer has committed.
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
        ) { _, _ in
            MainActor.assumeIsolated {
                body()
                // Nothing else commits before the thread sleeps.
                CATransaction.flush()
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
