import XCTest

/// Settings must keep its place when "What Private can't do" is dismissed
/// (P6-10): the list opens over Settings scrolled down to Private, and the
/// "When you leave" label must not move when the list goes.
final class SettingsScrollTests: XCTestCase {
    @MainActor func testSettingsKeepsItsPlaceAfterLimits() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", "8"]
        app.launch()
        _ = try app.required("page", timeout: 15)
        try await Task.sleep(for: .seconds(1.5))
        app.element("bar.tabs").tap()
        let gear = try app.required("tabs.settings")
        try await Task.sleep(for: .seconds(1.2))
        gear.tap()
        XCTAssertTrue(app.element("settings").waitForExistence(timeout: 3))
        try await Task.sleep(for: .seconds(1))
        let label = app.staticTexts["When you leave"]
        app.element("settings").swipeUp()
        app.element("settings").swipeUp()
        try await Task.sleep(for: .seconds(1))
        let before = label.frame.minY
        app.buttons["What Private can't do"].tap()
        let limits = app.element("private.limits")
        XCTAssertTrue(limits.waitForExistence(timeout: 3), "the list didn't open")
        try await Task.sleep(for: .seconds(1))
        limits.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(limits.waitForNonExistence(timeout: 3), "the list didn't close")
        try await Task.sleep(for: .seconds(1))
        let after = label.frame.minY
        XCTAssertEqual(before, after, accuracy: 2, "scroll moved")
    }
}
