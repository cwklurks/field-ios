import Foundation

/// When a blank tab's first web view may be built: once the field has gone
/// `quiet` with no keystroke, counting from when it took focus. Building one
/// holds the main thread for 100 ms or more, which between two keystrokes is
/// a stall; a Return builds it anyway, where the network's wait hides it.
struct WarmUp {
    static let quiet: Duration = .seconds(1.5)

    private(set) var due: ContinuousClock.Instant?

    mutating func focused(at now: ContinuousClock.Instant) {
        due = now + Self.quiet
    }

    mutating func typed(at now: ContinuousClock.Instant) {
        guard due != nil else { return }
        due = now + Self.quiet
    }

    func isDue(at now: ContinuousClock.Instant) -> Bool {
        guard let due else { return false }
        return now >= due
    }
}
