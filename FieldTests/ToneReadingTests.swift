import SwiftUI
import Testing
@testable import Field

/// The glass bar's tone, from what's under it: decided at once the first
/// time, then only changed by a reading clearly on the other side.
@MainActor struct ToneReadingTests {
    @Test func theFirstReadingDecidesAtTheMiddle() {
        let dark = Reader()
        #expect(dark.read(0.45))
        #expect(dark.tone == .dark)

        let light = Reader()
        #expect(light.read(0.55))
        #expect(light.tone == .light)
    }

    /// A boundary sitting under the bar reads near the middle, one way and
    /// then the other. The tone holds.
    @Test func readingsNearTheMiddleDoNotFlipIt() {
        let reader = Reader()
        reader.read(0.9)
        for luma in [0.48, 0.52, 0.45, 0.55, 0.41] {
            #expect(!reader.read(luma))
        }
        #expect(reader.tone == .light)
    }

    @Test func aClearlyDifferentReadingFlipsIt() {
        let reader = Reader()
        reader.read(0.95)
        #expect(reader.read(0.2))
        #expect(reader.tone == .dark)
        #expect(!reader.read(0.58))
        #expect(reader.read(0.7))
        #expect(reader.tone == .light)
    }

    @Test func nothingToReadKeepsTheTone() {
        let reader = Reader()
        #expect(!reader.read(nil))
        #expect(reader.tone == nil)
        reader.read(0.1)
        #expect(!reader.read(nil))
        #expect(reader.tone == .dark)
    }

    /// White text on black is still dark, however crisp the text.
    @Test func lumaAveragesWhatIsSeen() {
        let white: [UInt8] = [255, 255, 255, 255]
        let black: [UInt8] = [0, 0, 0, 255]
        let clear: [UInt8] = [255, 255, 255, 0]
        #expect(near(ToneReading.luma(rgba: white), 1))
        #expect(near(ToneReading.luma(rgba: black), 0))
        #expect(near(ToneReading.luma(rgba: white + black + black + black), 0.25))
        #expect(near(ToneReading.luma(rgba: black + clear), 0))
        #expect(ToneReading.luma(rgba: clear) == nil)
        #expect(ToneReading.luma(rgba: []) == nil)
    }

    private func near(_ value: Double?, _ expected: Double) -> Bool {
        value.map { abs($0 - expected) < 1e-9 } ?? false
    }

    /// One reading, fed one luma after another.
    private final class Reader {
        private var reading = ToneReading()
        var tone: ColorScheme? { reading.tone }

        @discardableResult
        func read(_ luma: Double?) -> Bool {
            reading.read(luma)
        }
    }
}
