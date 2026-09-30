import XCTest

/// Not a measurement: M3's checklist of real pages (docs/PLAN.md, M3), one
/// test each, at a pace a recording can follow, with touch marks on. Run one
/// at a time with a recording going; they need the network.
final class GuardTour: XCTestCase {
    static let news = URL(string: "https://www.cnn.com/")!

    @MainActor private func launch(_ url: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-bar.look", "glass", "-FieldTouchMarks", "YES",
                               "-FieldOpen", url.absoluteString]
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// A page of our own, as a `data:` address.
    private static func page(_ body: String) -> URL {
        let html = "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><body style='font:20px -apple-system;padding:80px 24px'>\(body)"
        return URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
    }

    @MainActor private func scroll(_ app: XCUIApplication, times: Int = 2) {
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        for _ in 0..<times { low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 400, thenHoldForDuration: 0.4) }
    }

    @MainActor private func pullToReload(_ app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)),
                  withVelocity: 600, thenHoldForDuration: 0.2)
    }

    /// The address's long press, then one of its items.
    @MainActor private func addressMenu(_ app: XCUIApplication, choose item: String) async throws {
        try app.required("bar.address", timeout: 10).press(forDuration: 0.8)
        try await pause(1)
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item)).firstMatch
        XCTAssert(button.waitForExistence(timeout: 3), "no \(item) in the address's menu")
        button.tap()
    }

    /// 1: a news site with ads, reloaded once the lists are ready, scrolled.
    @MainActor func testNews() async throws {
        let app = launch(Self.news)
        try await pause(12)
        pullToReload(app)
        try await pause(10)
        scroll(app, times: 3)
        try await pause(2)
    }

    /// 7: the shield off for the same site, reloaded: the ads are back. Then on again.
    @MainActor func testShieldOff() async throws {
        let app = launch(Self.news)
        try await pause(10)
        try await addressMenu(app, choose: "Turn Off Blocking")
        try await pause(10)
        scroll(app, times: 3)
        try await pause(2)
        try await addressMenu(app, choose: "Turn On Blocking")
        try await pause(3)
    }

    /// 2: a Google result, tapped.
    @MainActor func testGoogleResult() async throws {
        let app = launch(URL(string: "https://www.google.com/search?q=swift+programming+language+wikipedia")!)
        try await pause(6)
        let result = app.webViews.links.matching(NSPredicate(format: "label CONTAINS 'Wikipedia'")).firstMatch
        XCTAssert(result.waitForExistence(timeout: 10))
        result.tap()
        try await pause(6)
    }

    /// 2b: a Google result as Google's own redirect links it, tapped from a page.
    @MainActor func testGoogleShim() async throws {
        let shim = "https://www.google.com/url?sa=t&source=web&rct=j&url=https://en.wikipedia.org/wiki/Swift_(programming_language)&ved=2ahUKEwjX9&usg=AOvVaw0abc"
        let app = launch(Self.page("<a href='\(shim)'>google.com/url?…&amp;url=en.wikipedia.org/wiki/Swift…</a>"))
        try await pause(3)
        app.webViews.links.firstMatch.tap()
        try await pause(6)
    }

    /// 3: an address carrying fbclid and utm_source, from a page on another
    /// site; then the address copied from the long press.
    @MainActor func testTrackingParameters() async throws {
        let target = "https://www.apple.com/iphone/?fbclid=IwAR2abcDEF&utm_source=facebook&utm_medium=social"
        let app = launch(Self.page("<a id=go href='\(target)'>apple.com/iphone/?fbclid=…&amp;utm_source=…</a>"))
        try await pause(3)
        app.webViews.links.firstMatch.tap()
        try await pause(6)
        try await addressMenu(app, choose: "Copy")
        try await pause(1)
        try app.required("bar.address").tap()
        try await pause(1)
        app.typeText("x")
        try await pause(0.3)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        try await pause(1)
    }

    /// 4: an AMP link, as Google's viewer serves it.
    @MainActor func testAMP() async throws {
        let app = launch(Self.page("<a href='https://www.google.com/amp/s/www.bbc.com/news'>www.google.com/amp/s/www.bbc.com/news</a>"))
        try await pause(3)
        app.webViews.links.firstMatch.tap()
        try await pause(7)
    }

    /// 5: a script's window.open, from a tap on a button: the chip, then Open.
    @MainActor func testPopup() async throws {
        let app = launch(Self.page("<button style='font-size:22px' onclick=\"window.open('https://example.org/')\">window.open</button>"
                                   + "<p><a href='https://example.org/' target=_blank>A target=_blank link</a>"
                                   + "<script>setTimeout(function(){window.open('https://example.com/')},500)</script>"))
        try await pause(3)
        app.webViews.buttons.firstMatch.tap()
        try await pause(1.5)
        let open = app.element("toast.offer")
        XCTAssert(open.waitForExistence(timeout: 2), "no popup chip")
        open.tap()
        try await pause(4)
    }

    /// 5b: a target=_blank link still opens.
    @MainActor func testBlankTarget() async throws {
        let app = launch(Self.page("<a href='https://example.org/' target=_blank>A target=_blank link</a>"))
        try await pause(3)
        app.webViews.links.firstMatch.tap()
        try await pause(4)
    }

    /// 6: a page that script-jumps to the App Store, both ways.
    @MainActor func testAppStoreJump() async throws {
        let app = launch(Self.page("<p>Jumping to the App Store in a moment.</p><script>"
                                   + "setTimeout(function(){location.href='https://apps.apple.com/us/app/id284882215'},1500);"
                                   + "setTimeout(function(){location.href='itms-apps://apps.apple.com/app/id284882215'},4000)</script>"))
        try await pause(7)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// 8b: from a page, a link the blocker stops, then "Load anyway": the
    /// message stays until the stopped page commits.
    @MainActor func testLoadAnywayFromAPage() async throws {
        let app = launch(Self.page("<h1>A page before</h1><a href='https://pagead2.googlesyndication.com/pagead/show_ads.js'>An ad server link</a>"))
        try await pause(3)
        app.webViews.links.firstMatch.tap()
        let button = app.buttons["Load anyway"]
        XCTAssert(button.waitForExistence(timeout: 8), "not stopped by the blocker")
        try await pause(1.5)
        button.tap()
        try await pause(5)
    }

    /// 8: a page the blocker stops outright, then "Load anyway".
    @MainActor func testLoadAnyway() async throws {
        let app = launch(URL(string: "https://pagead2.googlesyndication.com/pagead/show_ads.js")!)
        try await pause(8)
        pullToReload(app)
        try await pause(4)
        let button = app.buttons["Load anyway"]
        XCTAssert(button.waitForExistence(timeout: 5), "not stopped by the blocker")
        button.tap()
        try await pause(5)
    }
}
