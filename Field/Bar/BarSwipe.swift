import CoreGraphics

/// What a drag on the bar is for, judged as it starts: sideways moves the
/// pages under it (Stage's carousel), up opens the tab grid. Anything less
/// clear-cut is left alone, for the buttons and the pill.
enum BarSwipe: Equatable {
    case sideways
    case up

    /// How many times faster one way than the other a drag has to be going.
    static let dominance: CGFloat = 2

    /// From the finger's velocity as the drag starts; nil for neither.
    init?(velocity v: CGPoint) {
        if abs(v.x) > Self.dominance * abs(v.y) {
            self = .sideways
        } else if -v.y > Self.dominance * abs(v.x) {
            self = .up
        } else {
            return nil
        }
    }

    /// Frames, from the one the drag is recognised on, until the page is
    /// exactly under the finger.
    static let catchUp = 4

    /// Where the page is drawn for a finger `travel` from where it came
    /// down, `step` frames after the drag was recognised (0 on that frame).
    /// It's recognised only once the finger has gone `slop`: the page takes
    /// that up over the first few frames on an ease out, as `quick` does,
    /// so it neither jumps to the finger nor trails behind it.
    static func shown(travel: CGFloat, slop: CGFloat, step: Int) -> CGFloat {
        let done = min(CGFloat(step + 1) / CGFloat(catchUp), 1)
        let remaining = (1 - done) * (1 - done)
        return travel - slop * remaining
    }
}
