import CoreGraphics
import Testing
@testable import Field

/// The grid's bottom row: Settings and a new tab at the leading end, how
/// many tabs there are in the middle, and Done at the trailing end.
struct GridRowTests {
    let row = GridRow(width: 402)

    @Test func settingsThenNewTabAtTheLeadingEnd() {
        #expect(row.settings.minX == GridRow.margin)
        #expect(row.new.minX >= row.settings.maxX)
    }

    @Test func doneAtTheTrailingEnd() {
        #expect(row.done.maxX == 402 - GridRow.margin)
    }

    @Test func theCountIsCentredBetweenThem() {
        #expect(row.count.midX == 201)
        #expect(row.count.minX >= row.new.maxX)
        #expect(row.count.maxX <= row.done.minX)
    }

    @Test func everyButtonIsAFingerWide() {
        for frame in [row.settings, row.new, row.done] {
            #expect(frame.width >= 44)
            #expect(frame.height >= 44)
        }
    }
}
