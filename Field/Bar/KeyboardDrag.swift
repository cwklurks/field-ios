import CoreGraphics

/// A finger taking the keyboard down: how far the field has turned into the
/// bar, which is how far the keyboard has gone.
enum KeyboardDrag {
    /// 0 with the keyboard all the way up, 1 with it gone. `height` is the
    /// keyboard guide's now, `full` with the keyboard up, `rest` with it
    /// down (the home indicator's).
    static func gone(height: CGFloat, full: CGFloat, rest: CGFloat) -> CGFloat {
        guard full > rest else { return 0 }
        return min(max(1 - (height - rest) / (full - rest), 0), 1)
    }
}
