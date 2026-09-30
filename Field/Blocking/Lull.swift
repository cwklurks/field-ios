/// A stretch of quiet long enough to hold the main thread in: WebKit parses a
/// list there before compiling it on its own queue, about 40 ms per list on
/// an M-series simulator. Fed by a timer on the main run loop's default mode,
/// which doesn't fire while a finger is on a scroll view or the page coasts,
/// so a tick that comes late means something was going on.
nonisolated struct Lull {
    let needed: Duration
    let interval: Duration
    private var since: ContinuousClock.Instant?
    private var last: ContinuousClock.Instant?

    init(needed: Duration, interval: Duration) {
        self.needed = needed
        self.interval = interval
    }

    /// One tick of the timer, `quiet` when nothing else is in the way (no
    /// keyboard, the app in front): whether the quiet has now lasted long enough.
    mutating func tick(at now: ContinuousClock.Instant, quiet: Bool) -> Bool {
        defer { last = now }
        guard quiet else {
            since = nil
            return false
        }
        if let last, now - last > interval * 2 { since = now }
        let start = since ?? now
        since = start
        return now - start >= needed
    }
}
