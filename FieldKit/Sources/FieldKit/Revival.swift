/// What a tab does when iOS kills its page's web process, which leaves the
/// web view blank. On screen, it reloads straight away; off screen, it waits
/// until it's shown. A reload doesn't always bring a dead view back, so after
/// three deaths in a row, with no paint between them, the web view is built
/// again from scratch (as Firefox does).
public struct Revival: Sendable {
    public enum Action: Equatable, Sendable {
        case reload
        case rebuild
    }

    public static let limit = 3

    private var failures = 0
    /// Died while hidden; acts when shown.
    public private(set) var pending = false

    public init() {}

    /// The process died. Nil means nothing to do until `shown`.
    public mutating func terminated(visible: Bool) -> Action? {
        failures += 1
        guard visible else {
            pending = true
            return nil
        }
        return act()
    }

    /// The tab came on screen.
    public mutating func shown() -> Action? {
        guard pending else { return nil }
        return act()
    }

    /// The page drew: whatever was wrong has passed.
    public mutating func painted() {
        failures = 0
    }

    private mutating func act() -> Action {
        pending = false
        guard failures >= Revival.limit else { return .reload }
        failures = 0
        return .rebuild
    }
}
