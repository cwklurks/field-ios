import XCTest

/// Not a measurement: the tab interactions one after another at a person's
/// pace, for recording on video and checking frame by frame against
/// docs/motion.md ("The video loop"). Open the grid, choose
/// another tab, open it again, throw a card away, reopen it, swipe between
/// tabs on the bar, swipe up on it for the grid.
final class TabsTour: XCTestCase {
    @MainActor func testTour() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", "8", "-FieldTouchMarks", "YES"]
        app.launch()
        _ = try app.required("page", timeout: 15)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 15)
        let pause: Duration = .seconds(1.2)
        let tabs = app.element("bar.tabs")
        let count = Int(tabs.value as? String ?? "")
        XCTAssertNotNil(count, "The tabs button doesn't say how many tabs there are.")

        // Open the grid: the page shrinks into its card.
        app.element("bar.tabs").tap()
        let grid = try app.required("tabs.grid")
        try await Task.sleep(for: pause)

        // Choose another tab: its card grows into the page, which wakes.
        app.element("tabs.card.6").tap()
        XCTAssertTrue(grid.waitForNonExistence(timeout: 3))
        try await Task.sleep(for: pause)

        // Back to the grid, and throw a card away sideways.
        app.element("bar.tabs").tap()
        try await Task.sleep(for: pause)
        let card = app.element("tabs.card.4")
        card.swipeLeft(velocity: .default)
        try await Task.sleep(for: pause)

        // Close one with its button.
        app.element("tabs.close.2").tap()
        try await Task.sleep(for: pause)

        // Reopen the last closed from the + button's menu.
        app.element("tabs.new").press(forDuration: 0.8)
        let reopen = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Seeded tab'")).firstMatch
        if reopen.waitForExistence(timeout: 2) { reopen.tap() }
        try await Task.sleep(for: pause)

        // Done: the current card grows back into the page.
        app.element("tabs.done").tap()
        try await Task.sleep(for: pause)

        // One thrown away, one closed, one reopened.
        if let count { XCTAssertEqual(tabs.value as? String, "\(count - 1)") }

        // Sideways on the bar, both ways: the tab before, and back.
        let heading = app.staticTexts.matching(NSPredicate(format: "label MATCHES 'Tab [0-9]+'")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        let here = heading.label
        let bar = app.element("bar")
        bar.swipeRight(velocity: .slow)
        XCTAssertTrue(app.staticTexts[here].waitForNonExistence(timeout: 3), "Swiping right on the bar stayed on \(here).")
        try await Task.sleep(for: pause)
        bar.swipeLeft(velocity: .default)
        XCTAssertTrue(app.staticTexts[here].waitForExistence(timeout: 3), "Swiping left on the bar didn't come back to \(here).")
        try await Task.sleep(for: pause)

        // Up on the bar: the grid.
        bar.swipeUp(velocity: .default)
        XCTAssertTrue(app.element("tabs.grid").waitForExistence(timeout: 3), "Swiping up on the bar didn't open the grid.")
        try await Task.sleep(for: pause)
    }

    /// Settings from the grid's row: the sheet comes up at once, with no
    /// menu to close first, and goes back to the grid.
    @MainActor func testSettingsFromGrid() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", "8", "-FieldTouchMarks", "YES"]
        app.launch()
        _ = try app.required("page", timeout: 15)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 15)
        try await Task.sleep(for: .seconds(1.5))
        app.element("bar.tabs").tap()
        let gear = try app.required("tabs.settings")
        try await Task.sleep(for: .seconds(1.2))
        gear.tap()
        XCTAssertTrue(app.element("settings").waitForExistence(timeout: 2), "The grid's Settings button didn't bring up Settings.")
        try await Task.sleep(for: .seconds(1.5))
        app.buttons["Done"].firstMatch.tap()
        try await Task.sleep(for: .seconds(1.5))
        XCTAssertTrue(app.element("tabs.grid").exists, "Closing Settings left the grid.")
    }

    /// The grid opened and closed eight times at a person's pace, for
    /// counting frames from the finger lifting off the tabs button to the
    /// page starting to shrink (docs/motion.md: it must be the next one).
    @MainActor func testOpenResponse() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", "8", "-FieldTouchMarks", "YES"]
        app.launch()
        _ = try app.required("page", timeout: 15)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 15)
        try await Task.sleep(for: .seconds(2.5))
        for _ in 0..<8 {
            app.element("bar.tabs").tap()
            _ = try app.required("tabs.done")
            try await Task.sleep(for: .seconds(1.2))
            app.element("tabs.done").tap()
            XCTAssertTrue(app.element("tabs.grid").waitForNonExistence(timeout: 3))
            try await Task.sleep(for: .seconds(1.2))
        }
    }
}
