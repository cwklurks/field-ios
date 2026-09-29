import CoreGraphics

/// The bar's size at a shrink, worked out from two things the shrink never
/// changes: the room the bar is given and the address's own width. Measuring
/// either of them can't feed back into itself, which a measurement of the
/// laid-out address did, and spun the main thread for good.
struct BarGeometry: Equatable {
    /// Where the address is laid out, the same at every shrink. The pill
    /// shows it scaled rather than narrower, so it's never cut shorter.
    let slot: CGFloat
    /// The surface's.
    let width: CGFloat
    let height: CGFloat
    /// The address's.
    let scale: CGFloat
    /// Toward the home indicator.
    let drop: CGFloat

    /// `address` is the address's ideal width, untruncated.
    init(room: CGFloat, address: CGFloat, amount: CGFloat) {
        let a = min(max(amount, 0), 1)
        let room = max(room, 0)
        slot = min(address, max(room - 120, 60))
        let pill = min(slot * Bar.pillScale + 12, room)
        width = room * (1 - a) + pill * a
        height = Bar.height * (1 - a) + Bar.pillHeight * a
        scale = 1 - a + Bar.pillScale * a
        drop = 8 * a
    }
}
