import CoreGraphics
import Testing
@testable import Field

/// The bar's size at each shrink. It's worked out from the room the bar is
/// given and the address's own width, neither of which the shrink changes,
/// so measuring them can't feed back into what they measure.
struct BarGeometryTests {
    private let room: CGFloat = 370
    private let amounts: [CGFloat] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]

    /// The loop guard: the address is laid out at one width at every shrink,
    /// so a measurement of it never moves with the shrink.
    @Test func theAddressKeepsItsWidthAtEveryShrink() {
        let slots = amounts.map { BarGeometry(room: room, address: 140, amount: $0).slot }
        #expect(Set(slots).count == 1)
        #expect(slots[0] == 140)
    }

    @Test func wholeFillsTheRoom() {
        let g = BarGeometry(room: room, address: 140, amount: 0)
        #expect(g.width == room)
        #expect(g.height == Bar.height)
        #expect(g.scale == 1)
        #expect(g.drop == 0)
    }

    /// The pill holds the shrunk address and a little either side of it.
    @Test func thePillHoldsTheAddress() {
        let g = BarGeometry(room: room, address: 140, amount: 1)
        #expect(g.height == Bar.pillHeight)
        #expect(g.scale == Bar.pillScale)
        #expect(g.width == 140 * Bar.pillScale + 12)
    }

    @Test func narrowsSteadily() {
        let widths = amounts.map { BarGeometry(room: room, address: 140, amount: $0).width }
        #expect(widths == widths.sorted(by: >))
    }

    /// A long host is cut in the middle to leave room for back and tabs.
    @Test func aLongAddressLeavesRoomForTheButtons() {
        let g = BarGeometry(room: room, address: 900, amount: 0)
        #expect(g.slot == room - 120)
    }

    /// Before the bar knows its room, and past either end of the shrink,
    /// nothing comes out negative or bigger than the room.
    @Test func staysInsideTheRoom() {
        #expect(BarGeometry(room: 0, address: 140, amount: 1).width == 0)
        #expect(BarGeometry(room: room, address: 140, amount: 2) == BarGeometry(room: room, address: 140, amount: 1))
        #expect(BarGeometry(room: room, address: 140, amount: -1) == BarGeometry(room: room, address: 140, amount: 0))
    }
}
