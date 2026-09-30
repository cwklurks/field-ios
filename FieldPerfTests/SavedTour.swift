import XCTest

/// Not a measurement: M4 wired into the browser (docs/integration/saved.md,
/// "After wiring, on video"), one test each, at a pace a recording can
/// follow, with touch marks on. Run one at a time with a recording going.
final class SavedTour: XCTestCase {
    @MainActor private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-bar.look", "glass", "-FieldTouchMarks", "YES"] + extra
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// 1: long press, Save: the sheet with its folder; star it, Done. The
    /// long press again says it's saved.
    @MainActor func testSave() async throws {
        // A page no earlier run saved.
        let app = launch(["-FieldOpen", "https://example.org/?tour=\(Int(Date.now.timeIntervalSince1970))"])
        let address = try app.required("bar.address", timeout: 10)
        try await pause(4)
        address.press(forDuration: 0.8)
        try await pause(1)
        app.buttons["Save"].tap()
        try await pause(2)
        let star = app.element("savesheet.star")
        if !star.waitForExistence(timeout: 3) { print("SavedTour tree:\n\(app.debugDescription)") }
        XCTAssert(star.exists, "no Save sheet")
        star.tap()
        try await pause(1)
        app.element("savesheet.done").tap()
        try await pause(1.5)
        address.press(forDuration: 0.8)
        try await pause(1)
        XCTAssert(app.buttons["Edit Saved Page"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        try await pause(1)
    }

    /// 2: a new tab: the starred shelf rises with the keyboard, rides it
    /// down under a finger and back, and gives way to the first suggestions.
    @MainActor func testStarredShelf() async throws {
        let app = launch(["-FieldSeedTabs", "0", "-FieldSeedSaved", "60", "-FieldSeedHistory", "2000"])
        XCTAssert(app.element("starred").waitForExistence(timeout: 10), "no shelf")
        try await pause(2)
        // Part way down and let go: the keyboard comes back, the shelf with it.
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64)),
                  withVelocity: 200, thenHoldForDuration: 0.8)
        try await pause(1.5)
        // UIKit may have taken the keyboard all the way: the field again.
        if !app.keyboards.firstMatch.exists { app.element("bar.address").tap() }
        try await pause(1.5)
        app.typeText("w")
        try await pause(1)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        try await pause(1.5)
        // All the way down: the field goes home as the bar, the shelf gone.
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                  withVelocity: 250, thenHoldForDuration: 0.3)
        try await pause(1.5)
    }

    /// 3: the grid's Saved: a row swiped each way, then a page opened, the
    /// sheet going as its card grows into the page.
    @MainActor func testGridSaved() async throws {
        let app = launch(["-FieldOpen", "https://example.org/", "-FieldSeedSaved", "60"])
        try app.required("bar.tabs", timeout: 10).tap()
        try await pause(1.5)
        try app.required("tabs.saved").tap()
        try await pause(1.5)
        let row = try app.required("saved.row.1")
        row.swipeLeft()
        try await pause(1.5)
        row.swipeRight()
        try await pause(1)
        try app.required("saved.row.2").swipeRight()
        try await pause(1.5)
        try app.required("saved.row.3").tap()
        try await pause(4)
    }

    /// Settings' look: the lift slides under the other names.
    @MainActor func testSegmented() async throws {
        let app = launch(["-FieldOpen", "https://example.org/"])
        try app.required("bar.tabs", timeout: 10).tap()
        try await pause(1.5)
        try app.required("tabs.settings").tap()
        try await pause(1.5)
        for title in ["Dark", "Light", "System"] {
            app.buttons[title].firstMatch.tap()
            try await pause(1.2)
        }
    }
}
