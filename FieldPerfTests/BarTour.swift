import XCTest

/// Not a measurement: the bar's own interactions, one test each, at a pace a
/// recording can follow, with touch marks on (docs/motion.md, "How to check it").
/// Opening and closing the field, and the bar sitting on a page: the shrink,
/// the ring, the pill. CRITIC_LOOK and CRITIC_MODE pick the looks, as for
/// CriticTour.
final class BarTour: XCTestCase {
    private var server: CriticServer!

    override func setUp() async throws {
        server = try await CriticServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
    }

    private var look: String { ProcessInfo.processInfo.environment["CRITIC_LOOK"] ?? "glass" }
    private var mode: String { ProcessInfo.processInfo.environment["CRITIC_MODE"] ?? "light" }

    @MainActor private func launch(_ extra: [String] = [], open url: URL?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FieldTouchMarks", "YES", "-FieldSeedHistory", "2000", "-welcomed", "YES",
                               "-bar.look", look, "-look", mode]
        if let url { app.launchArguments += ["-FieldOpen", url.absoluteString] }
        app.launchArguments += extra
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Open and close, each way: a tap outside, a slow swipe down the
    /// keyboard, and Go to a page that takes a moment, so the ring shows.
    @MainActor func testOpenClose() async throws {
        let app = launch(open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)

        address.tap()
        try await pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(1.5)

        address.tap()
        try await pause(1.5)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: 250, thenHoldForDuration: 0.3)
        try await pause(2)

        address.tap()
        try await pause(1.5)
        app.typeText(server.url("/slow/page/3").absoluteString + "\n")
        try await pause(4)
    }

    /// A close taken over: a tap outside, then the address tapped again while
    /// the bar is still on its way down. Synthesized, since XCUITest waits
    /// for animations to end before each tap; the second lands where the bar
    /// is going, which is where UIKit hit-tests it.
    @MainActor func testReopenMidClose() async throws {
        let app = launch(open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        let home = CGPoint(x: address.frame.midX, y: address.frame.midY)
        let outside = CGPoint(x: app.frame.midX, y: app.frame.height * 0.12)
        for delay in [0, 0.06] {
            address.tap()
            try await pause(1.5)
            try await Path.drag([(outside, 0), (outside, 0.03)])
            if delay > 0 { try await pause(delay) }
            try await Path.drag([(home, 0), (home, 0.03)])
            try await pause(1.5)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
            try await pause(1.5)
        }
    }

    /// The bar on a page: a slow drag down the page and back, flicks each
    /// way, then a tap on the pill.
    @MainActor func testOnPage() async throws {
        let app = launch(open: server.url("/article"))
        _ = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 120, thenHoldForDuration: 0.5)
        try await pause(1.2)
        high.press(forDuration: 0.05, thenDragTo: low, withVelocity: 120, thenHoldForDuration: 0.5)
        try await pause(1.2)
        let page = app.element("page")
        page.swipeUp(velocity: 600)
        try await pause(1.5)
        page.swipeDown(velocity: 600)
        try await pause(1.5)
        page.swipeUp(velocity: 600)
        try await pause(1.5)
        app.element("bar").tap()
        try await pause(2)
    }

    /// The pill, shrunk over a page, swiped sideways to the next tab and
    /// back; then the whole bar swiped.
    @MainActor func testPillSwipe() async throws {
        let app = launch(["-FieldSeedTabs", "4"], open: server.url("/article"))
        let bar = try app.required("bar", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        app.element("page").swipeUp(velocity: 600)
        try await pause(1.5)
        bar.swipeRight(velocity: .default)
        try await pause(2)
        bar.swipeLeft(velocity: .default)
        try await pause(2)
    }
}
