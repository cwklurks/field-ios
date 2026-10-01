import XCTest

/// Not a measurement: Private and Capture wired into the browser
/// (docs/integration/private.md and capture.md), one test each, at a pace a
/// recording can follow, with touch marks on. Run one at a time with a
/// recording going. Face ID has to be enrolled on the simulator first; a
/// test prints "FACE ID NOW" when it wants a match.
final class PrivateTour: XCTestCase {
    private var server: CriticServer!

    override func setUp() async throws {
        server = try await CriticServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
    }

    @MainActor private func launch(_ extra: [String] = [], open path: String = "/article") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-bar.look", "glass", "-look", "light", "-FieldTouchMarks", "YES",
                               "-FieldSeedTabs", "2", "-FieldOpen", server.url(path).absoluteString] + extra
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// From the page into the grid, and the switch.
    @MainActor private func toggle(_ app: XCUIApplication, fromPage: Bool = true) async throws {
        if fromPage {
            app.element("bar.tabs").tap()
            try await pause(1.5)
        }
        let toggle = app.element("private.switch")
        XCTAssert(toggle.waitForExistence(timeout: 3), "no Private switch in the grid")
        toggle.tap()
    }

    /// In, from a new session: the blank dark page with the field; a page
    /// opened in it.
    @MainActor private func enterAndOpen(_ app: XCUIApplication) async throws {
        try await toggle(app)
        try await pause(2.5)
        app.typeText(server.url("/article").absoluteString + "\n")
        try await pause(3)
    }

    @MainActor private func unlock(_ app: XCUIApplication) async throws {
        let unlock = app.element("private.unlock")
        XCTAssert(unlock.waitForExistence(timeout: 3), "Private isn't locked")
        unlock.tap()
        try await pause(1)
        print("FACE ID NOW")
        try await pause(4)
    }

    /// 1: in and out from the grid, twice: a new session, then back to it,
    /// locked, and unlocked with Face ID.
    @MainActor func testEnterLeave() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await enterAndOpen(app)
        try await toggle(app)
        try await pause(2)
        try await toggle(app, fromPage: false)
        try await pause(1.5)
        try await unlock(app)
        app.element("tabs.done").tap()
        try await pause(2)
        try await toggle(app)
        try await pause(2)
    }

    /// 1b: the grid's row dragged sideways: both grids follow the finger,
    /// and let go past halfway, the other side lands. Out, then back in.
    @MainActor func testDrag() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await enterAndOpen(app)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        let row = { (x: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.935)) }
        row(0.3).press(forDuration: 0.1, thenDragTo: row(0.95), withVelocity: 250, thenHoldForDuration: 0.4)
        try await pause(2.5)
        row(0.9).press(forDuration: 0.1, thenDragTo: row(0.2), withVelocity: 250, thenHoldForDuration: 0.4)
        try await pause(2)
        try await unlock(app)
    }

    /// 1c: a new private tab: one tap on "What Private can't do", under the
    /// field's dim, opens the list.
    @MainActor func testWelcomeLink() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await toggle(app)
        try await pause(2.5)
        app.element("private.limits.open").tap()
        XCTAssert(app.element("private.limits").waitForExistence(timeout: 3), "one tap didn't open the list")
        try await pause(2)
    }

    /// 2: in Private with the keyboard up, to the home screen and the app
    /// switcher, then back: the cover, then the lock.
    @MainActor func testSwitcher() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await enterAndOpen(app)
        app.element("bar.address").tap()
        try await pause(1.5)
        XCUIDevice.shared.press(.home)
        try await pause(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)),
                   withVelocity: 300, thenHoldForDuration: 1.5)
        try await pause(3)
        app.activate()
        try await pause(2)
        try await unlock(app)
        try await pause(1)
    }

    /// 3: "When you leave: Wipe": out of Private and back in to an empty session.
    @MainActor func testWipe() async throws {
        let app = launch(["-private.away", "wipe"])
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await enterAndOpen(app)
        try await toggle(app)
        try await pause(2.5)
        try await toggle(app, fromPage: false)
        try await pause(3)
    }

    /// 4: Capture Page, PDF then Image, through the share sheet, on an
    /// everyday page and then a private one.
    @MainActor func testCapture() async throws {
        let app = launch()
        _ = app.element("page").waitForExistence(timeout: 10)
        try await pause(3)
        try await captures(app)
        try await enterAndOpen(app)
        try await captures(app)
    }

    @MainActor private func captures(_ app: XCUIApplication) async throws {
        for kind in ["PDF", "Image"] {
            app.element("bar.address").press(forDuration: 0.8)
            try await pause(1.2)
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Capture Page")).firstMatch
            XCTAssert(menu.waitForExistence(timeout: 3), "no Capture Page in the address's menu")
            menu.tap()
            try await pause(1)
            app.buttons[kind].firstMatch.tap()
            try await pause(4)
            // The share sheet, closed.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            try await pause(2)
        }
    }

    /// 5: the restored tab's first page, decided before the lists are looked
    /// up: its ad script is blocked all the same.
    @MainActor func testFirstPageBlocked() async throws {
        let app = launch(open: "/ads")
        let blocked = app.staticTexts["Ad script blocked"]
        XCTAssert(blocked.waitForExistence(timeout: 10), "the first page's ad script wasn't blocked")
        try await pause(2)
    }
}
