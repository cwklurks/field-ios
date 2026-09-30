/// A stretch of quiet long enough to hold the main thread in: WebKit parses a
/// list there before compiling it on its own queue, about 40 ms per list on
/// an M-series simulator. Fed by a timer on the main run loop's default mode,
/// which doesn't fire while a finger is on a scroll view or the page coasts,
/// so a tick that comes late means something was going on.
///
/// The first list waits for `needed`. Each after it, and any once `deadline`
/// has passed since the first tick, waits only for `then`: the app was quiet
/// a moment ago, and someone who never stops using it still gets the lists.
nonisolated struct Lull {
    let needed: Duration
    let interval: Duration
    let then: Duration
    let deadline: Duration
    private var since: ContinuousClock.Instant?
    private var last: ContinuousClock.Instant?
    private var began: ContinuousClock.Instant?
    private var came = false

    init(needed: Duration, interval: Duration, then: Duration? = nil, deadline: Duration = .seconds(Int64.max)) {
        self.needed = needed
        self.interval = interval
        self.then = then ?? needed
        self.deadline = deadline
    }

    /// One tick of the timer, `quiet` when nothing else is in the way (see
    /// `isQuiet`): whether the quiet has now lasted long enough.
    mutating func tick(at now: ContinuousClock.Instant, quiet: Bool) -> Bool {
        if began == nil { began = now }
        defer { last = now }
        guard quiet else {
            since = nil
            return false
        }
        if let last, now - last > interval * 2 { since = now }
        let start = since ?? now
        since = start
        guard now - start >= (came || isPastDeadline(at: now) ? then : needed) else { return false }
        came = true
        return true
    }

    func isPastDeadline(at now: ContinuousClock.Instant) -> Bool {
        guard let began else { return false }
        return now - began >= deadline
    }

    /// Nothing in the way of a lull: the app in front, and no keyboard. Past
    /// the deadline the keyboard may be up, as long as nothing's been typed
    /// and it hasn't moved for `calm`. Typing into a page can't be seen from
    /// here, only into the app's own fields.
    static func isQuiet(
        active: Bool, keyboardUp: Bool, lastInput: ContinuousClock.Instant?, pastDeadline: Bool,
        at now: ContinuousClock.Instant, calm: Duration
    ) -> Bool {
        guard active else { return false }
        let calmed = lastInput.map { now - $0 >= calm } ?? true
        return pastDeadline ? calmed : !keyboardUp
    }
}
