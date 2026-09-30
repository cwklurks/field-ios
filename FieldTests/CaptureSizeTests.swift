import CoreGraphics
import Testing
@testable import Field

/// How big the tall image is: the screen's sharpness while it fits, and
/// smaller, never cut, when the page is too long for one image iOS can hold.
struct CaptureSizeTests {
    @Test func aShortPageKeepsItsScale() throws {
        let size = try #require(TallImage.pixels(for: CGSize(width: 390, height: 2000), scale: 2))
        #expect(size.width == 780)
        #expect(size.height == 4000)
        #expect(size.scale == 2)
    }

    /// The longest side is the cap; the width shrinks with it.
    @Test func aLongPageIsScaledToTheCap() throws {
        let size = try #require(TallImage.pixels(for: CGSize(width: 390, height: 20000), scale: 2))
        #expect(size.height == TallImage.maxSide)
        #expect(size.width == 319)
        #expect(abs(size.scale - 0.8192) < 0.0001)
    }

    /// A wide desktop page runs out of pixels before it runs out of height.
    @Test func aWideLongPageIsScaledToThePixelBudget() throws {
        let size = try #require(TallImage.pixels(for: CGSize(width: 1200, height: 12000), scale: 2))
        #expect(size.height < TallImage.maxSide)
        #expect(size.width * size.height <= TallImage.maxPixels)
        #expect(size.width * size.height > TallImage.maxPixels * 99 / 100)
        #expect(abs(Double(size.width) / Double(size.height) - 0.1) < 0.001)
    }

    @Test func neverOverEitherCap() throws {
        for width in [320.0, 390, 1024, 1920, 4000] {
            for height in [1.0, 800, 5000, 40_000, 400_000] {
                let size = try #require(TallImage.pixels(for: CGSize(width: width, height: height), scale: 3))
                #expect(size.width <= TallImage.maxSide && size.height <= TallImage.maxSide)
                #expect(size.width * size.height <= TallImage.maxPixels)
                #expect(size.width >= 1 && size.height >= 1)
                #expect(size.scale <= 3)
            }
        }
    }

    @Test func nothingToDraw() {
        #expect(TallImage.pixels(for: .zero, scale: 2) == nil)
        #expect(TallImage.pixels(for: CGSize(width: 390, height: 0), scale: 2) == nil)
        #expect(TallImage.pixels(for: CGSize(width: -1, height: 100), scale: 2) == nil)
        #expect(TallImage.pixels(for: CGSize(width: 390, height: 100), scale: 0) == nil)
    }

    /// Several PDF pages make one image, one under the other.
    @Test func pagesStack() {
        let size = TallImage.stacked([CGSize(width: 390, height: 3000), CGSize(width: 390, height: 1200)])
        #expect(size == CGSize(width: 390, height: 4200))
        #expect(TallImage.stacked([]) == .zero)
    }
}
