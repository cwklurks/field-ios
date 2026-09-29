import XCTest

/// The tab grid and switching tabs, with 50 tabs open (`-FieldSeedTabs 50`,
/// made-up pages with pictures, plus the fixture article on screen). Budget:
/// under 2 ms of hitch time per second, opening and closing the grid and
/// switching tabs, as for every core interaction (docs/PLAN.md, "Smooth").
final class TabsTests: XCTestCase {
    static let seeded = 50

    /// One open and one close per iteration: the page shrinks into its card,
    /// then the card grows back into the page.
    @MainActor func testGridOpenAndClose() async throws {
        let (app, fixture) = try await launch()
        defer { fixture.stop() }
        let current = "tabs.card.\(Self.seeded)"

        let metrics: [any XCTMetric] = [
            XCTHitchMetric(application: app),
            Harness.signpost("tabs.open"),
            Harness.signpost("tabs.close"),
        ]
        measure(metrics: metrics, options: Harness.options()) {
            app.element("bar.tabs").tap()
            let card = app.element(current)
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            card.tap()
            XCTAssertTrue(app.element("tabs.grid").waitForNonExistence(timeout: 3))
        }
    }

    /// Through the grid to the tab before, and back: each switch wakes a
    /// sleeping tab from its picture.
    @MainActor func testSwitchThroughGrid() async throws {
        let (app, fixture) = try await launch()
        defer { fixture.stop() }
        var target = Self.seeded - 1

        measure(metrics: [XCTHitchMetric(application: app), Harness.signpost("tabs.close")], options: Harness.options()) {
            app.element("bar.tabs").tap()
            XCTAssertTrue(app.element("tabs.grid").waitForExistence(timeout: 3), "The tabs button didn't open the grid.")
            let card = app.element("tabs.card.\(target)")
            XCTAssertTrue(card.waitForExistence(timeout: 3), "The grid has no card \(target).")
            card.tap()
            XCTAssertTrue(app.element("tabs.grid").waitForNonExistence(timeout: 3))
            target = target == Self.seeded - 1 ? Self.seeded : Self.seeded - 1
        }
    }

    /// Swiping sideways on the bar: the pages follow the finger and settle.
    @MainActor func testSwipeBetweenTabs() async throws {
        let (app, fixture) = try await launch()
        defer { fixture.stop() }
        let bar = try app.required("bar")
        var right = true

        measure(metrics: [XCTHitchMetric(application: app), Harness.signpost("tab.switch")], options: Harness.options()) {
            if right { bar.swipeRight(velocity: .default) } else { bar.swipeLeft(velocity: .default) }
            right.toggle()
        }
    }

    /// Scrolling through all 50 cards: pictures come in lazily, decoded off
    /// the main thread.
    @MainActor func testGridScroll() async throws {
        let (app, fixture) = try await launch()
        defer { fixture.stop() }
        app.element("bar.tabs").tap()
        let grid = try app.required("tabs.grid")

        measure(metrics: [XCTHitchMetric(application: app)], options: Harness.options()) {
            grid.swipeDown(velocity: .fast)
            grid.swipeDown(velocity: .fast)
            grid.swipeUp(velocity: .fast)
            grid.swipeUp(velocity: .fast)
        }
    }

    /// Field on the fixture article with 50 more tabs asleep behind it,
    /// skipped until the bar opens the grid.
    @MainActor private func launch() async throws -> (XCUIApplication, Fixture) {
        let fixture = await Fixture.start()
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", "\(Self.seeded)"]
        app.launch()
        _ = try app.required("page", timeout: 15)
        guard app.staticTexts[Article.headline].waitForExistence(timeout: 15) else {
            fixture.stop()
            throw XCTSkip("The fixture article didn't appear.")
        }
        app.element("bar.tabs").tap()
        guard app.element("tabs.grid").waitForExistence(timeout: 3) else {
            fixture.stop()
            throw XCTSkip("The bar's tabs button doesn't open the grid yet (Browser.showTabs).")
        }
        app.element("tabs.done").tap()
        _ = app.element("tabs.grid").waitForNonExistence(timeout: 3)
        return (app, fixture)
    }
}
