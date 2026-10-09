import XCTest
import notify

/// Not a measurement: links from other apps, handed to Field two ways.
///
/// - Cold: `XCUIApplication.open(_:)`, which ends a running Field and
///   launches it with the link, as a tap in Mail does when Field isn't
///   running. Works in any build.
/// - Warm: the Debug build's `field-test://open?url=` scheme, opened by the
///   system (`XCUIDevice.shared.system.open`), which reaches the running app
///   through the same `onOpenURL`. iOS sends http itself to the default
///   browser, which Field isn't here. Run these with `-configuration Debug`;
///   in Release they skip.
///
/// Tabs opened while the test runs are never saved (`-FieldOpen`), so a tab
/// count past what the launch made shows the app wasn't relaunched.
final class IncomingLinksTests: XCTestCase {
    private var server: CriticServer!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try await CriticServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
    }

    /// The pages' headings (CriticTour.page).
    private static let titles = ["Zero", "Sourdough starter", "Lisbon in October", "Night trains", "Bike fitting",
                                 "Fermented hot sauce", "Swift concurrency"]

    @MainActor private func launch(welcomed: Bool = true, open page: Int? = 1, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", welcomed ? "YES" : "NO", "-bar.look", "glass", "-look", "light", "-FieldSeedTabs", "0"]
            + (page.map { ["-FieldOpen", server.url("/page/\($0)").absoluteString] } ?? [])
            + extra
        app.launch()
        if let page { XCTAssert(shows(app, page), "the launch page never showed") }
        return app
    }

    @MainActor private func shows(_ app: XCUIApplication, _ page: Int, timeout: TimeInterval = 10) -> Bool {
        app.webViews.staticTexts[Self.titles[page]].waitForExistence(timeout: timeout)
    }

    @MainActor private func tabCount(_ app: XCUIApplication) -> String? {
        app.element("bar.tabs").value as? String
    }

    /// Hands the running app `url`, as another app would.
    private func warm(_ url: URL) throws {
        #if DEBUG
        var parts = URLComponents(string: "field-test://open")!
        parts.queryItems = [.init(name: "url", value: url.absoluteString)]
        XCUIDevice.shared.system.open(parts.url!)
        #else
        throw XCTSkip("A warm link needs the Debug build's field-test scheme: run with -configuration Debug.")
        #endif
    }

    private func warm(_ text: String) throws {
        try warm(URL(string: text)!)
    }

    /// Backgrounded, as from Mail: a tab of your own each time, shown; the
    /// pages before stay. The third tab shows nothing was relaunched.
    @MainActor func testWarm() throws {
        let app = launch()
        try warm(server.url("/page/2"))
        XCTAssert(shows(app, 2), "the link's page didn't show")
        XCTAssertEqual(tabCount(app), "2")
        XCUIDevice.shared.press(.home)
        XCTAssert(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        try warm(server.url("/page/3"))
        XCTAssert(shows(app, 3), "the link's page didn't show from the background")
        XCTAssertEqual(tabCount(app), "3", "the app was relaunched, or a tab was overwritten")
    }

    /// One after another from the background: one tab each, in order, the
    /// last on screen.
    @MainActor func testSeveral() throws {
        let app = launch()
        XCUIDevice.shared.press(.home)
        XCTAssert(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        for page in 2...4 { try warm(server.url("/page/\(page)")) }
        XCTAssert(shows(app, 4))
        XCTAssertEqual(tabCount(app), "4")
    }

    /// Not running: the link waits for the session and opens after it, in a
    /// tab of its own. `open(_:)` launches with the first launch's
    /// arguments, so the session is page 1 again.
    @MainActor func testCold() throws {
        let app = launch()
        app.terminate()
        app.open(server.url("/page/3"))
        XCTAssert(shows(app, 3), "the link's page didn't show after a cold launch")
        XCTAssertEqual(tabCount(app), "2", "the link took the session's tab")
    }

    /// Not running, the session a blank tab: the link takes it, rather than
    /// the field the blank tab was about to open, and the bar comes back.
    @MainActor func testColdOnABlankTab() throws {
        let app = launch(open: nil)
        app.terminate()
        app.open(server.url("/page/3"))
        XCTAssert(shows(app, 3), "the link's page didn't show after a cold launch")
        XCTAssertEqual(tabCount(app), "1")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the field opened over the link")
    }

    /// First run, not running: the link waits under the welcome, and opens
    /// after Continue, in the blank tab that was waiting for the field.
    @MainActor func testColdUnderTheWelcome() throws {
        let app = launch(welcomed: false, open: nil)
        app.terminate()
        app.open(server.url("/page/3"))
        XCTAssert(app.buttons["Continue"].waitForExistence(timeout: 5), "no welcome")
        XCTAssertFalse(shows(app, 3, timeout: 2), "the link opened under the welcome")
        continueFromWelcome(app)
        XCTAssert(shows(app, 3), "the link didn't open after Continue")
        XCTAssertEqual(tabCount(app), "1")
    }

    /// First run, running: the same, the link coming while the welcome is up.
    @MainActor func testWarmUnderTheWelcome() throws {
        let app = launch(welcomed: false, open: nil)
        XCTAssert(app.buttons["Continue"].waitForExistence(timeout: 5), "no welcome")
        try warm(server.url("/page/3"))
        XCTAssertFalse(shows(app, 3, timeout: 2), "the link opened under the welcome")
        XCTAssert(app.buttons["Continue"].exists, "the link took the welcome away")
        continueFromWelcome(app)
        XCTAssert(shows(app, 3), "the link didn't open after Continue")
        XCTAssertEqual(tabCount(app), "1")
    }

    // MARK: - where

    /// Private open, its blank tab and field up: back to your tabs, and
    /// Private's tab is where it was, without the link.
    @MainActor func testPrivateOpen() throws {
        let app = launch()
        try enterPrivate(app)
        try warm(server.url("/page/3"))
        XCTAssert(shows(app, 3))
        XCTAssertEqual(tabCount(app), "2")
        app.element("bar.tabs").tap()
        app.element("private.switch").tap()
        XCTAssert(app.element("private.limits.open").waitForExistence(timeout: 3), "Private's blank tab is gone")
        XCTAssertFalse(app.webViews.staticTexts[Self.titles[3]].isHittable)
    }

    /// Private locked behind Face ID: the link opens in your tabs, the lock
    /// never shows over it, and Private is still locked after.
    @MainActor func testPrivateLocked() async throws {
        Self.enrollFaceID()
        let app = launch()
        try enterPrivate(app)
        app.typeText(server.url("/page/2").absoluteString + "\n")
        XCTAssert(shows(app, 2))
        XCUIDevice.shared.press(.home)
        XCTAssert(app.wait(for: .runningBackground, timeout: 5) || app.wait(for: .runningBackgroundSuspended, timeout: 5))
        try warm(server.url("/page/3"))
        XCTAssert(shows(app, 3))
        XCTAssert(app.element("private.shade").waitForNonExistence(timeout: 2), "the lock stayed over your tabs")
        XCTAssertFalse(app.webViews.staticTexts[Self.titles[2]].exists, "Private's page showed")
        XCTAssertEqual(tabCount(app), "2")
        app.element("bar.tabs").tap()
        app.element("private.switch").tap()
        XCTAssert(app.element("private.unlock").waitForExistence(timeout: 3), "Private isn't locked any more")
    }

    // MARK: - what

    /// A Google redirect lands where it was going, cold and warm.
    @MainActor func testCleanedRedirect() throws {
        let app = launch()
        var parts = URLComponents(string: "https://www.google.com/url")!
        parts.queryItems = [.init(name: "q", value: server.url("/page/4").absoluteString), .init(name: "sa", value: "D")]
        app.terminate()
        app.open(parts.url!)
        XCTAssert(shows(app, 4), "the redirect wasn't unwrapped")
        XCTAssertEqual(app.element("bar.address").label, "127.0.0.1")
        parts.queryItems = [.init(name: "q", value: server.url("/page/5").absoluteString), .init(name: "sa", value: "D")]
        try warm(parts.url!)
        XCTAssert(shows(app, 5), "the redirect wasn't unwrapped")
        XCTAssertEqual(app.element("bar.address").label, "127.0.0.1")
    }

    /// A password in the link: said, and nothing opens.
    @MainActor func testRejectedCredentials() throws {
        let app = launch()
        var parts = URLComponents(url: server.url("/page/3"), resolvingAgainstBaseURL: false)!
        parts.user = "me"
        parts.password = "secret"
        try warm(parts.url!)
        XCTAssert(app.staticTexts["Didn't open a link with a password in it."].waitForExistence(timeout: 5))
        XCTAssertFalse(shows(app, 3, timeout: 1))
        XCTAssertEqual(tabCount(app), "1")
    }

    /// A scheme a web link can't have: said, and nothing opens.
    @MainActor func testRejectedScheme() throws {
        let app = launch()
        try warm("javascript:alert(document.cookie)")
        XCTAssert(app.staticTexts["Field opens only web links."].waitForExistence(timeout: 5))
        XCTAssertEqual(tabCount(app), "1")
    }

    // MARK: -

    /// A look chosen, which Continue waits for, then Continue.
    @MainActor private func continueFromWelcome(_ app: XCUIApplication) {
        app.element("welcome.glass").tap()
        let go = app.buttons["Continue"]
        XCTAssert(go.wait(for: \.isEnabled, toEqual: true, timeout: 3), "Continue never came on")
        go.tap()
    }

    /// From the page into the grid and through the switch: a new private
    /// session, its blank tab with the field.
    @MainActor private func enterPrivate(_ app: XCUIApplication) throws {
        app.element("bar.tabs").tap()
        let toggle = app.element("private.switch")
        XCTAssert(toggle.waitForExistence(timeout: 3), "no Private switch in the grid")
        toggle.tap()
        XCTAssert(app.element("private.limits.open").waitForExistence(timeout: 3), "not in Private")
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
    }

    /// A face enrolled, so Private locks rather than wipes (PrivateLock.canLock).
    private static func enrollFaceID() {
        var token: Int32 = 0
        notify_register_check("com.apple.BiometricKit.enrollmentChanged", &token)
        notify_set_state(token, 1)
        notify_post("com.apple.BiometricKit.enrollmentChanged")
        notify_cancel(token)
    }
}
