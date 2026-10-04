import XCTest

/// Not a measurement: Tidy wired into the grid (docs/integration/tidy.md),
/// at a pace a recording can follow, with touch marks on. On the simulator
/// the model can't run, so what's seen is the rules' grouping.
final class TidyTour: XCTestCase {
    private var server: CriticServer!

    override func setUp() async throws {
        server = try await CriticServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-bar.look", "glass", "-look", "light", "-FieldTouchMarks", "YES",
                               "-FieldSeedTidy", "YES", "-FieldOpen", server.url("/article").absoluteString]
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// 1: the grid with the stale banner; Tidy, its groups streaming in,
    /// Apply; the cards moving into sections; Undo from the toast.
    @MainActor func testTidy() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(2)
        XCTAssert(app.element("stale.line").waitForExistence(timeout: 3), "no stale banner")
        let tidy = app.element("tabs.tidy")
        XCTAssert(tidy.waitForExistence(timeout: 3), "no Tidy button")
        tidy.tap()
        let apply = app.element("tidy.apply")
        XCTAssert(apply.waitForExistence(timeout: 5), "no Tidy sheet")
        try await pause(4)
        apply.tap()
        try await pause(1)
        let undo = app.element("toast.offer")
        XCTAssert(undo.waitForExistence(timeout: 3), "no Undo")
        undo.tap()
        try await pause(2.5)
    }

    /// 2: the stale banner's Review, its sheet's Close, then Undo.
    @MainActor func testStale() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(2)
        let review = app.element("stale.review")
        XCTAssert(review.waitForExistence(timeout: 3), "no stale banner")
        review.tap()
        let close = app.element("stale.sheet.close")
        XCTAssert(close.waitForExistence(timeout: 3), "no stale sheet")
        try await pause(2)
        close.tap()
        try await pause(1)
        let undo = app.element("toast.offer")
        XCTAssert(undo.waitForExistence(timeout: 3), "no Undo")
        undo.tap()
        try await pause(2.5)
    }

    /// 3: Tidy applied, then a group's header held: Rename.
    @MainActor func testSections() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        // To the top, where the stale banner is.
        for _ in 0..<3 { app.element("tabs.grid").swipeDown(velocity: .fast) }
        try await pause(2)
        app.element("tabs.tidy").tap()
        let apply = app.element("tidy.apply")
        XCTAssert(apply.waitForExistence(timeout: 5), "no Tidy sheet")
        try await pause(3)
        apply.tap()
        try await pause(3)
        let header = app.element("tabs.group")
        XCTAssert(header.waitForExistence(timeout: 3), "no group header")
        header.press(forDuration: 0.8)
        try await pause(1.2)
        app.buttons["Rename"].firstMatch.tap()
        try await pause(1)
        let name = app.alerts["Rename Group"].textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Trip")
        XCTAssertEqual(name.value as? String, "Trip", "typing must replace the selected group name")
        let selection = XCTAttachment(screenshot: app.screenshot())
        selection.name = "Rename replacement"
        selection.lifetime = .keepAlways
        add(selection)
        app.alerts["Rename Group"].buttons["Rename"].tap()
        try await pause(2)
        header.press(forDuration: 0.8)
        app.buttons["Add Similar Tabs"].firstMatch.tap()
        XCTAssertFalse(app.element("tidy").exists, "an empty lookup must leave the grid showing")
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "No similar tabs"
        empty.lifetime = .keepAlways
        add(empty)
        app.element("tabs.done").tap()
        try await pause(2)
    }
}
