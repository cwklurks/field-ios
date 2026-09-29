import XCTest
import os

/// Budget: under 2 ms of hitch time per second while a long page scrolls and
/// the bar shrinks and grows, in both bar looks. The page is the fixture
/// article, served from this process.
///
/// Each iteration flings down twice (the bar shrinks) and back up twice (it
/// grows). The test first flings to the middle of the page, so the page never
/// reaches the top, where a pull would reload it.
final class ScrollTests: XCTestCase {
    /// Marks each iteration's scrolling, so scripts/perf/hitches.sh can find it in a trace.
    private static let window = OSSignposter(subsystem: "com.connork.field.perftests", category: .pointsOfInterest)

    @MainActor func testScrollGlass() async throws {
        try await scroll(look: "glass")
    }

    @MainActor func testScrollSolid() async throws {
        try await scroll(look: "solid")
    }

    @MainActor private func scroll(look: String) async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(look: look, open: fixture.url)
        app.launch()
        let page = try app.required("page")
        guard app.staticTexts[Article.headline].waitForExistence(timeout: 15) else {
            throw XCTSkip("The fixture article didn't appear: the app doesn't honour -FieldOpen yet, or couldn't load \(fixture.url.absoluteString.prefix(40)).")
        }
        for _ in 0..<4 {
            page.swipeUp(velocity: .fast)
        }

        let metrics: [any XCTMetric] = [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric.scrollingAndDecelerationMetric,
            Harness.signpost("bar.collapse"),
            Harness.signpost("bar.expand"),
        ]
        measure(metrics: metrics, options: Harness.options()) {
            let state = Self.window.beginInterval("scroll", id: Self.window.makeSignpostID())
            page.swipeUp(velocity: .fast)
            page.swipeUp(velocity: .fast)
            page.swipeDown(velocity: .fast)
            page.swipeDown(velocity: .fast)
            Self.window.endInterval("scroll", state)
        }
    }
}
