import CoreGraphics
import Testing
@testable import Field

/// Where the screenshot editor's "Full Page" opens: the part of the PDF the
/// person was looking at, as UIScreenshotService wants it (a page index,
/// and a rect on that page with its origin at the bottom left).
struct CapturePlaceTests {
    @Test func onOnePage() {
        let place = ScreenshotPlace.locate(
            visible: CGRect(x: 0, y: 1000, width: 390, height: 800),
            contentWidth: 390, pages: [CGSize(width: 390, height: 5000)]
        )
        #expect(place.index == 0)
        #expect(place.rect == CGRect(x: 0, y: 3200, width: 390, height: 800))
    }

    /// Pinch-zoomed in: the scroll view's points are twice the page's.
    @Test func zoomedIn() {
        let place = ScreenshotPlace.locate(
            visible: CGRect(x: 200, y: 2000, width: 390, height: 800),
            contentWidth: 780, pages: [CGSize(width: 390, height: 5000)]
        )
        #expect(place.index == 0)
        #expect(place.rect == CGRect(x: 100, y: 3600, width: 195, height: 400))
    }

    @Test func onALaterPage() {
        let place = ScreenshotPlace.locate(
            visible: CGRect(x: 0, y: 3500, width: 390, height: 800),
            contentWidth: 390, pages: [CGSize(width: 390, height: 3000), CGSize(width: 390, height: 3000)]
        )
        #expect(place.index == 1)
        #expect(place.rect == CGRect(x: 0, y: 1700, width: 390, height: 800))
    }

    /// Across a page break, the page that holds more of it.
    @Test func acrossABreak() {
        let pages = [CGSize(width: 390, height: 3000), CGSize(width: 390, height: 3000)]
        let later = ScreenshotPlace.locate(visible: CGRect(x: 0, y: 2800, width: 390, height: 800), contentWidth: 390, pages: pages)
        #expect(later.index == 1)
        #expect(later.rect == CGRect(x: 0, y: 2400, width: 390, height: 600))
        let earlier = ScreenshotPlace.locate(visible: CGRect(x: 0, y: 2500, width: 390, height: 800), contentWidth: 390, pages: pages)
        #expect(earlier.index == 0)
        #expect(earlier.rect == CGRect(x: 0, y: 0, width: 390, height: 500))
    }

    /// Pulled past the top (the scroll view's offset is negative).
    @Test func overscrolledAtTheTop() {
        let place = ScreenshotPlace.locate(
            visible: CGRect(x: 0, y: -120, width: 390, height: 800),
            contentWidth: 390, pages: [CGSize(width: 390, height: 5000)]
        )
        #expect(place.rect == CGRect(x: 0, y: 4320, width: 390, height: 680))
    }

    @Test func nothingToPlace() {
        let none = ScreenshotPlace.locate(visible: CGRect(x: 0, y: 0, width: 390, height: 800), contentWidth: 390, pages: [])
        #expect(none.index == 0 && none.rect == .zero)
        let flat = ScreenshotPlace.locate(visible: CGRect(x: 0, y: 0, width: 390, height: 800), contentWidth: 0, pages: [CGSize(width: 390, height: 10)])
        #expect(flat.rect == .zero)
    }
}
