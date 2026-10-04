import CoreGraphics
import Testing
@testable import Field

/// The rows above the field, in less room than they want: the nearest stay,
/// the farthest (the engine's) go first.
@Suite struct SuggestionsFitTests {
    @Test func everyRowWhenThereIsRoom() {
        #expect(NearestFirst.kept([44, 44, 44], room: 200) == 3)
    }

    @Test func theFarthestGoFirst() {
        #expect(NearestFirst.kept([44, 44, 44, 44], room: 100) == 2)
    }

    @Test func aTallRowCountsItsHeight() {
        #expect(NearestFirst.kept([44, 44, 60], room: 100) == 1)
        #expect(NearestFirst.kept([60, 44, 44], room: 100) == 2)
    }

    @Test func theNearestStaysWithNoRoomAtAll() {
        #expect(NearestFirst.kept([44, 44], room: 10) == 1)
        #expect(NearestFirst.kept([], room: 10) == 0)
    }
}
