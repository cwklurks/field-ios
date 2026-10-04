import Network
import XCTest

/// Not a measurement: the polish review's interactions (docs/review/), one
/// test each, at a pace a recording can follow, with touch marks on. Run one
/// at a time with a recording going. CRITIC_LOOK picks the bar's look and
/// CRITIC_MODE the app's (light, dark or system).
final class CriticTour: XCTestCase {
    private var server: CriticServer!

    override func setUp() async throws {
        server = try await CriticServer.start()
    }

    override func tearDown() async throws {
        server?.stop()
    }

    private var look: String { ProcessInfo.processInfo.environment["CRITIC_LOOK"] ?? "glass" }
    private var mode: String { ProcessInfo.processInfo.environment["CRITIC_MODE"] ?? "light" }

    /// White, then a dark "photo", then white again, then a mid grey: what's
    /// under the bar changes as it scrolls, though the page's own background
    /// stays white.
    static let tonePage: String = {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{margin:0;background:#fff;color:#111;font:17px/1.5 -apple-system}
        p{margin:0 24px 16px}h1{margin:0;padding:80px 24px 16px;font-size:32px}
        .white{min-height:100vh}
        .hero{height:70vh;background:radial-gradient(circle at 30% 40%,#3a4a6a 0,#141a28 45%,#05070c 100%);color:#fff;
        display:flex;align-items:flex-end;padding:24px;box-sizing:border-box;font-size:28px;font-weight:600}
        .grey{height:60vh;background:#808080}</style></head><body>\(CriticTour.heartbeat)
        <div class="white"><h1>White section</h1><p>The bar starts over white. Scroll and a dark photo comes under it.</p>
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        <p>Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p></div>
        <div class="hero">Dark hero image</div>
        <div class="white"><p style="padding-top:24px">White again, with text running under the bar. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.</p>
        <p>Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p></div>
        <div class="grey"></div><div class="white"></div></body></html>
        """
        return html
    }()

    /// Page N: its own title and colour, so cards in the grid tell apart.
    static func page(_ n: Int) -> String {
        let names = ["Zero", "Sourdough starter", "Lisbon in October", "Night trains", "Bike fitting", "Fermented hot sauce",
                     "Swift concurrency", "Reading glasses", "Tide tables"]
        let hue = (n * 47) % 360
        return "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><title>\(names[n % names.count])</title>"
            + "<body style='margin:0;font:19px/1.5 -apple-system;color:#111'>\(heartbeat)<div style='height:42vh;background:hsl(\(hue),45%,62%)'></div>"
            + "<h1 style='margin:24px'>\(names[n % names.count])</h1>"
            + String(repeating: "<p style='margin:0 24px 16px'>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>", count: 14)
    }

    /// A short page of our own, with the heartbeat.
    static func small(_ body: String) -> String {
        "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><title>Field test</title>"
            + "<body style='font:20px -apple-system;padding:120px 24px'>\(heartbeat)\(body)"
    }

    /// A 2-point square at the left edge that never stops changing, so the
    /// simulator's recorder never goes idle and drops the first frames of
    /// a motion. Masked out of the analysis.
    static let heartbeat = "<style>@keyframes hb{50%{opacity:0}}</style><div style='position:fixed;left:0;top:40%;width:2px;height:2px;background:#f0f;animation:hb .1s steps(1) infinite;z-index:9'></div>"

    /// `welcomed` nil leaves the setting alone: a fresh install shows the welcome.
    @MainActor private func launch(_ extra: [String], open url: URL? = nil, welcomed: Bool? = true, looks: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FieldTouchMarks", "YES", "-FieldSeedHistory", "2000"]
        if let welcomed { app.launchArguments += ["-welcomed", welcomed ? "YES" : "NO"] }
        // Settings can't change what the arguments pin, so its test leaves them out.
        if looks { app.launchArguments += ["-bar.look", look, "-look", mode] }
        if let url { app.launchArguments += ["-FieldOpen", url.absoluteString] }
        app.launchArguments += extra
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// 1: tap, type "wea" a key at a time, Go.
    @MainActor func testField() async throws {
        let app = launch([], open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        address.tap()
        try await pause(1.5)
        for key in ["w", "e", "a"] {
            app.typeText(key)
            try await pause(0.5)
        }
        try await pause(1)
        app.typeText("\n")
        try await pause(3)
    }

    /// 2: tap, then a tap outside; then again with text typed.
    @MainActor func testCancelTap() async throws {
        let app = launch([], open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        address.tap()
        try await pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(1.5)
        address.tap()
        try await pause(1.2)
        app.typeText("wea")
        try await pause(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    /// 3: tap, then a slow drag of the keyboard all the way down; then a drag
    /// halfway, held, and let go (the keyboard should come back up).
    @MainActor func testCancelSwipe() async throws {
        let app = launch([], open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        address.tap()
        try await pause(1.5)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: 250, thenHoldForDuration: 0.3)
        try await pause(2)
        address.tap()
        try await pause(1.5)
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        top.press(forDuration: 0.1, thenDragTo: middle, withVelocity: 200, thenHoldForDuration: 0.8)
        try await pause(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    /// 3b: a drag into the keyboard that turns back up before the lift,
    /// which UIKit answers by bringing the keyboard back; then a tap outside.
    @MainActor func testCancelSwipeBack() async throws {
        let app = launch([], open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        address.tap()
        try await pause(1.5)
        let size = app.frame.size
        let x = size.width / 2
        try await Path.drag([
            (CGPoint(x: x, y: size.height * 0.35), 0),
            (CGPoint(x: x, y: size.height * 0.80), 1.2),
            (CGPoint(x: x, y: size.height * 0.80), 1.5),
            (CGPoint(x: x, y: size.height * 0.45), 2.0),
        ])
        try await pause(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    /// 3c: not Field. The same half drag and release in Messages, as the
    /// system's own reference for what the keyboard does on the lift.
    @MainActor func testReferenceMessages() async throws {
        let app = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        app.activate()
        try await pause(1.5)
        // The conversation opens with its field focused.
        app.cells.firstMatch.tap()
        try await pause(2)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        top.press(forDuration: 0.1, thenDragTo: middle, withVelocity: 200, thenHoldForDuration: 0.8)
        try await pause(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        try await pause(1.5)
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.1, thenDragTo: bottom, withVelocity: 250, thenHoldForDuration: 0.3)
        try await pause(2)
    }

    /// 3d: a flick down the keyboard; then a short drag let go while still
    /// moving; then one let go just as it reaches the keyboard.
    @MainActor func testFlickDown() async throws {
        let app = launch([], open: server.url("/article"))
        let address = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        address.tap()
        try await pause(1.5)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: 1500, thenHoldForDuration: 0)
        try await pause(2)
        address.tap()
        try await pause(1.5)
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)), withVelocity: 600, thenHoldForDuration: 0)
        try await pause(2)
        address.tap()
        try await pause(1.5)
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.63)), withVelocity: 800, thenHoldForDuration: 0)
        try await pause(2)
    }

    /// 4: a slow drag up and down, then flicks.
    @MainActor func testScroll() async throws {
        let app = launch([], open: server.url("/article"))
        _ = try app.required("bar.address", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 150, thenHoldForDuration: 0.5)
        try await pause(1.2)
        high.press(forDuration: 0.05, thenDragTo: low, withVelocity: 150, thenHoldForDuration: 0.5)
        try await pause(1.2)
        let page = app.element("page")
        page.swipeUp(velocity: .fast)
        try await pause(2)
        page.swipeDown(velocity: .fast)
        try await pause(2)
        page.swipeUp(velocity: 600)
        try await pause(1.5)
        page.swipeDown(velocity: 600)
        try await pause(2)
    }

    /// 5 and 6: the grid, a card chosen, a card thrown away, one closed with
    /// its button, then + for a new tab.
    @MainActor func testTabs() async throws {
        let app = launch(["-FieldSeedTabs", "8"], open: server.url("/article"))
        _ = try app.required("page", timeout: 15)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 15)
        try await pause(3)
        app.element("bar.tabs").tap()
        _ = try app.required("tabs.grid")
        try await pause(1.5)
        app.element("tabs.card.6").tap()
        try await pause(2)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        app.element("tabs.card.4").swipeLeft(velocity: .default)
        try await pause(1.5)
        app.element("tabs.close.2").tap()
        try await pause(1.5)
        app.element("tabs.new").tap()
        try await pause(2.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    /// 7: sideways on the bar, a slow drag, then a throw each way.
    @MainActor func testBarSwipe() async throws {
        let app = launch(["-FieldSeedTabs", "8"])
        let bar = try app.required("bar", timeout: 10)
        try await pause(3)
        let from = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let to = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 200, thenHoldForDuration: 0.3)
        try await pause(1.5)
        bar.swipeRight(velocity: .default)
        try await pause(1.5)
        bar.swipeLeft(velocity: .fast)
        try await pause(2)
    }

    /// 7b: up on the bar opens the grid, Done closes it; then a slower drag up.
    @MainActor func testBarSwipeUp() async throws {
        let app = launch(["-FieldSeedTabs", "8"], open: server.url("/article"))
        let bar = try app.required("bar", timeout: 10)
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(3)
        bar.swipeUp(velocity: .default)
        _ = try app.required("tabs.grid")
        try await pause(1.5)
        app.element("tabs.done").tap()
        try await pause(1.5)
        let from = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)), withVelocity: 300, thenHoldForDuration: 0.2)
        try await pause(1.5)
        app.element("tabs.done").tap()
        try await pause(1.5)
    }

    /// 8: a cold launch on a blank tab, through to the keyboard.
    @MainActor func testColdBlank() async throws {
        let app = launch(["-FieldSeedTabs", "0"])
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        try await pause(2)
        app.typeText("wea")
        try await pause(2)
    }

    /// 9: eight tabs come back.
    @MainActor func testRestore() async throws {
        let app = launch(["-FieldSeedTabs", "8"])
        _ = try app.required("bar", timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(2)
        app.element("tabs.done").tap()
        try await pause(2)
    }

    /// 10: the welcome, both looks tried, Continue.
    @MainActor func testWelcome() async throws {
        let app = launch(["-FieldSeedTabs", "0"], welcomed: false)
        let glass = try app.required("welcome.glass", timeout: 10)
        try await pause(2)
        glass.tap()
        try await pause(1.2)
        app.element("welcome.solid").tap()
        try await pause(1.2)
        glass.tap()
        try await pause(1.2)
        app.buttons["Continue"].tap()
        try await pause(3)
    }

    /// 10b: the welcome on a fresh install (uninstall first), no -welcomed
    /// argument, so Continue runs exactly as a first launch does.
    @MainActor func testWelcomeFresh() async throws {
        let app = launch(["-FieldSeedTabs", "0"], welcomed: nil, looks: false)
        let glass = try app.required("welcome.glass", timeout: 10)
        try await pause(2)
        glass.tap()
        try await pause(1.2)
        app.buttons["Continue"].tap()
        try await pause(4)
    }

    /// 11: Settings from the grid's gear, the look changed, Done; then
    /// again, closed with a swipe down.
    @MainActor func testSettings() async throws {
        let app = launch([], open: server.url("/tone"), looks: false)
        let tabs = try app.required("bar.tabs", timeout: 10)
        try await pause(2.5)
        tabs.tap()
        let gear = try app.required("tabs.settings")
        try await pause(1.2)
        gear.tap()
        _ = try app.required("settings")
        try await pause(1.5)
        app.buttons["Solid"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Dark"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Glass"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Light"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["settings.done"].tap()
        try await pause(2)
        // Closing Settings left the grid up.
        _ = gear.waitForExistence(timeout: 2)
        try await pause(0.6)
        gear.tap()
        try await pause(1.5)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: 800, thenHoldForDuration: 0)
        try await pause(2)
    }

    /// 12: the glass over white, a dark photo, white and grey, held on each.
    @MainActor func testTone() async throws {
        let app = launch([], open: server.url("/tone"))
        _ = try app.required("bar", timeout: 10)
        try await pause(3)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        for _ in 0..<7 {
            low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 300, thenHoldForDuration: 0.6)
            try await pause(1.2)
        }
        app.element("bar.address").tap()
        try await pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    // MARK: Round 5: M3 and M4

    /// The address's long press, then one of its items (by the start of its title).
    @MainActor private func addressMenu(_ app: XCUIApplication, choose item: String?) async throws {
        try app.required("bar.address", timeout: 10).press(forDuration: 0.8)
        try await pause(1.2)
        guard let item else { return }
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item)).firstMatch
        XCTAssert(button.waitForExistence(timeout: 3), "no \(item) in the address's menu")
        button.tap()
    }

    /// 13: the long press, dismissed by a tap outside; Share, dismissed;
    /// Copy; then a plain tap still opens the field.
    @MainActor func testAddressMenu() async throws {
        let app = launch([], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(2.5)
        try await addressMenu(app, choose: nil)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(1.5)
        try await addressMenu(app, choose: "Share")
        try await pause(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        try await pause(1.5)
        try await addressMenu(app, choose: "Copy")
        try await pause(1.5)
        app.element("bar.address").tap()
        try await pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(2)
    }

    /// 14: Save from the long press, the sheet with its suggested folder;
    /// star, another folder, Done. Then Edit Saved Page, closed by a swipe.
    @MainActor func testSaveSheet() async throws {
        let app = launch(["-FieldSeedSaved", "60"], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(4)
        try await addressMenu(app, choose: "Save")
        try await pause(2)
        try app.required("savesheet.star").tap()
        try await pause(1.2)
        app.element("savesheet.folder.none").tap()
        try await pause(1.2)
        app.element("savesheet.done").tap()
        try await pause(1.8)
        try await addressMenu(app, choose: "Edit Saved Page")
        try await pause(2)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                  withVelocity: 600, thenHoldForDuration: 0)
        try await pause(2)
    }

    /// 15: a cold blank tab with starred pages: the shelf rises with the
    /// keyboard; a half drag held and let go; a key and back; all the way down.
    @MainActor func testStarredCold() async throws {
        let app = launch(["-FieldSeedTabs", "0", "-FieldSeedSaved", "60"])
        _ = app.element("starred").waitForExistence(timeout: 10)
        try await pause(2.5)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)),
                  withVelocity: 200, thenHoldForDuration: 0.8)
        try await pause(2)
        if !app.keyboards.firstMatch.exists { app.element("bar.address").tap() }
        try await pause(1.5)
        app.typeText("w")
        try await pause(1.2)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        try await pause(1.5)
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                  withVelocity: 250, thenHoldForDuration: 0.3)
        try await pause(2)
    }

    /// 16: + in the grid with starred pages: the shelf on the new tab; a
    /// starred page opened from it.
    @MainActor func testStarredNewTab() async throws {
        let app = launch(["-FieldSeedTabs", "4", "-FieldSeedSaved", "60"], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        try app.required("tabs.new").tap()
        try await pause(2.5)
        try app.required("starred.tile.0").tap()
        try await pause(3)
    }

    /// 17: Saved from the grid: search, filters, a folder, rows swiped each
    /// way, a flick, and a page opened as the sheet goes.
    @MainActor func testSavedList() async throws {
        let app = launch(["-FieldSeedTabs", "4", "-FieldSeedSaved", "60"], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        try app.required("tabs.saved").tap()
        try await pause(1.8)
        try app.required("saved.search").tap()
        try await pause(1.2)
        for key in ["p", "a", "s"] {
            app.typeText(key)
            try await pause(0.5)
        }
        try await pause(1)
        app.buttons["Clear"].firstMatch.tap()
        try await pause(1.2)
        try app.required("saved.filter.later").tap()
        try await pause(1.5)
        app.element("saved.filter.all").tap()
        try await pause(1.5)
        try app.required("saved.folder.Work").tap()
        try await pause(1.5)
        app.element("saved.filter.all").tap()
        try await pause(1.5)
        let list = app.element("saved.list")
        list.swipeUp(velocity: .fast)
        try await pause(2)
        list.swipeDown(velocity: .fast)
        try await pause(2)
        try app.required("saved.row.1").swipeLeft()
        try await pause(1.5)
        app.element("saved.row.1").swipeRight()
        try await pause(1.2)
        app.element("saved.row.2").swipeRight(velocity: .slow)
        try await pause(1.5)
        try app.required("saved.row.3").tap()
        try await pause(3.5)
    }

    /// 18: a script's popup: the toast and its Open.
    @MainActor func testPopupToast() async throws {
        let app = launch([], open: server.url("/popup"))
        _ = try app.required("page", timeout: 10)
        try await pause(3)
        app.webViews.buttons.firstMatch.tap()
        try await pause(1.2)
        let open = app.element("toast.offer")
        XCTAssert(open.waitForExistence(timeout: 2), "no popup toast")
        open.tap()
        try await pause(3)
    }

    /// 19: a page that script-jumps to the App Store: the toast, twice.
    @MainActor func testAppStoreToast() async throws {
        let app = launch([], open: server.url("/jump"))
        _ = try app.required("page", timeout: 10)
        try await pause(8)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// 20: the shield off for the page's site and back on, each a reload.
    @MainActor func testShieldToggle() async throws {
        let app = launch([], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(3)
        try await addressMenu(app, choose: "Turn Off Blocking")
        try await pause(3)
        try await addressMenu(app, choose: "Turn On Blocking")
        try await pause(3)
    }

    /// 21: an address the lists stop outright, then "Load anyway".
    @MainActor func testLoadAnyway() async throws {
        let app = launch([], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        // Time for the lists to compile on a first launch.
        try await pause(10)
        app.element("bar.address").tap()
        try await pause(1.2)
        app.typeText("https://pagead2.googlesyndication.com/pagead/show_ads.js\n")
        let button = app.buttons["Load anyway"]
        XCTAssert(button.waitForExistence(timeout: 8), "not stopped by the blocker")
        try await pause(2)
        button.tap()
        try await pause(5)
    }

    /// 22: a real page with display ads (CRITIC_URL), scrolled, to see
    /// the lists at work. Run again with the shield off to compare.
    @MainActor func testAds() async throws {
        let url = URL(string: ProcessInfo.processInfo.environment["CRITIC_URL"] ?? "https://www.cnn.com/")!
        let app = launch([], open: url)
        _ = try app.required("page", timeout: 15)
        try await pause(12)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        for _ in 0..<6 {
            low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 400, thenHoldForDuration: 0.4)
            try await pause(2.5)
        }
    }

    // MARK: Round 6: the Release 1 candidate

    /// 23: a first launch on a fresh install (uninstall first): the welcome,
    /// Continue, then a real site typed as a friend would (CRITIC_URL's host).
    @MainActor func testFirstRun() async throws {
        let app = launch([], welcomed: nil, looks: false)
        let glass = try app.required("welcome.glass", timeout: 15)
        try await pause(2.5)
        glass.tap()
        try await pause(1.2)
        app.buttons["Continue"].tap()
        try await pause(3)
        let host = URL(string: ProcessInfo.processInfo.environment["CRITIC_URL"] ?? "https://www.theverge.com/")?.host() ?? "theverge.com"
        if !app.keyboards.firstMatch.exists { app.element("bar.address").tap() }
        try await pause(1.5)
        app.typeText(host.replacingOccurrences(of: "www.", with: ""))
        try await pause(1)
        app.typeText("\n")
        try await pause(10)
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        for _ in 0..<3 {
            low.press(forDuration: 0.05, thenDragTo: high, withVelocity: 400, thenHoldForDuration: 0.4)
            try await pause(2)
        }
    }

    /// 24: wrapped links tapped on a page: each opens at the real address,
    /// shown in full by opening the field, then back.
    @MainActor func testCleanLinks() async throws {
        let app = launch([], open: server.url("/links"))
        _ = try app.required("page", timeout: 10)
        try await pause(3)
        for name in ["Google result", "Facebook link", "Reddit link", "AMP link"] {
            let link = app.webViews.links[name].firstMatch
            XCTAssert(link.waitForExistence(timeout: 5), "no \(name)")
            link.tap()
            try await pause(5)
            app.element("bar.address").tap()
            try await pause(2)
            _ = app.closeField()
            try await pause(1)
            app.element("bar.back").tap()
            try await pause(3)
        }
    }

    /// 25: as a friend would: eight tabs opened by hand from the grid's +,
    /// one swiped away, then home, force-quit and open again: they're back.
    @MainActor func testTabsByHand() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FieldTouchMarks", "YES", "-welcomed", "YES", "-bar.look", look, "-look", mode]
        app.launch()
        try await pause(3)
        if !app.keyboards.firstMatch.exists { app.element("bar.address").tap() }
        try await pause(1)
        app.typeText(server.url("/page/1").absoluteString + "\n")
        try await pause(2.5)
        for n in 2...8 {
            app.element("bar.tabs").tap()
            try await pause(1.2)
            app.element("tabs.new").tap()
            try await pause(1.5)
            app.typeText(server.url("/page/\(n)").absoluteString + "\n")
            try await pause(2.5)
        }
        app.element("bar.tabs").tap()
        try await pause(1.5)
        app.element("tabs.card.3").swipeLeft(velocity: .default)
        try await pause(1.5)
        app.element("tabs.card.1").tap()
        try await pause(2)
        XCUIDevice.shared.press(.home)
        try await pause(2)
        app.terminate()
        try await pause(1.5)
        app.launch()
        try await pause(4)
        app.element("bar.tabs").tap()
        try await pause(2)
        print("CARDS AFTER RESTORE: \(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tabs.card.'")).count)")
        app.element("tabs.done").tap()
        try await pause(2)
    }

    /// 26: Save with a new folder and the star; then Saved from the grid,
    /// on Read later.
    @MainActor func testSaveFolder() async throws {
        let app = launch(["-FieldSeedTabs", "2"], open: server.url("/page/3"))
        _ = try app.required("page", timeout: 10)
        try await pause(3)
        try await addressMenu(app, choose: "Save")
        try await pause(2)
        try app.required("savesheet.folder.new").tap()
        try await pause(1.2)
        app.typeText("Recipes\n")
        try await pause(1.5)
        app.element("savesheet.star").tap()
        try await pause(1.2)
        app.element("savesheet.done").tap()
        try await pause(1.8)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        try app.required("tabs.saved").tap()
        try await pause(1.8)
        try app.required("saved.filter.later").tap()
        try await pause(1.5)
        app.element("saved.filter.Recipes").tap()
        try await pause(1.5)
        app.element("saved.done").tap()
        try await pause(1.5)
        // Back on the grid: + shows the shelf with the starred page.
        app.element("tabs.new").tap()
        try await pause(3)
    }

    /// 27: Settings' new rows: Tabs untouched for, Private's When you leave
    /// and Wipe when away, and the limits from there.
    @MainActor func testSettingsNew() async throws {
        let app = launch(["-FieldSeedTabs", "2"], open: server.url("/article"))
        try app.required("bar.tabs", timeout: 10).tap()
        try await pause(1.5)
        try app.required("tabs.settings").tap()
        let settings = try app.required("settings")
        try await pause(1.5)
        settings.swipeUp(velocity: .slow)
        try await pause(1.5)
        app.buttons["1 week"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["2 weeks"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Wipe"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Lock"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["15 min"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["Never"].firstMatch.tap()
        try await pause(1.2)
        app.buttons["What Private can't do"].firstMatch.tap()
        try await pause(2)
        app.element("private.limits").swipeUp(velocity: .slow)
        try await pause(1.5)
        app.buttons["Done"].firstMatch.tap()
        try await pause(1.5)
        app.buttons["settings.done"].tap()
        try await pause(2)
    }

    /// 28: Private's own core loop, dark: in, the limits from its page, a
    /// page typed, scrolled, the field and cancel, the grid and back.
    @MainActor func testPrivateLoop() async throws {
        let app = launch(["-FieldSeedTabs", "2"], open: server.url("/article"))
        _ = app.staticTexts[Article.headline].waitForExistence(timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        try app.required("private.switch").tap()
        try await pause(2.5)
        // The first tap on "What Private can't do" closes the field (as a
        // friend would find it); a second opens the list.
        let limits = app.element("private.limits.open")
        if limits.exists {
            limits.tap()
            try await pause(2)
            if !app.element("private.limits").exists { limits.tap() }
            try await pause(2.5)
            app.element("private.limits").buttons["Done"].firstMatch.tap()
            try await pause(2)
        }
        if !app.keyboards.firstMatch.exists { app.element("bar.address").tap() }
        try await pause(1.2)
        app.typeText(server.url("/article").absoluteString + "\n")
        try await pause(3)
        let page = app.element("page")
        page.swipeUp(velocity: 600)
        try await pause(1.5)
        page.swipeDown(velocity: 600)
        try await pause(1.5)
        app.element("bar.address").tap()
        try await pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(1.5)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        app.element("tabs.card.0").tap()
        try await pause(2)
    }

    /// 29: a Tidy group's header: Add Similar Tabs, then Ungroup; then the
    /// stale banner's own Close and its Undo.
    @MainActor func testGroupMenu() async throws {
        let app = launch(["-FieldSeedTidy", "YES"], open: server.url("/article"))
        _ = try app.required("page", timeout: 10)
        try await pause(3)
        app.element("bar.tabs").tap()
        try await pause(1.5)
        for _ in 0..<3 { app.element("tabs.grid").swipeDown(velocity: .fast) }
        try await pause(1.5)
        app.element("tabs.tidy").tap()
        let apply = try app.required("tidy.apply")
        try await pause(3)
        apply.tap()
        try await pause(2.5)
        let header = try app.required("tabs.group")
        header.press(forDuration: 0.8)
        try await pause(1.2)
        app.buttons["Add Similar Tabs"].firstMatch.tap()
        try await pause(3)
        if app.element("tidy.apply").isEnabled { app.element("tidy.apply").tap() } else { app.element("tidy.cancel").tap() }
        try await pause(2.5)
        header.press(forDuration: 0.8)
        try await pause(1.2)
        app.buttons["Ungroup"].firstMatch.tap()
        try await pause(2.5)
        for _ in 0..<3 { app.element("tabs.grid").swipeDown(velocity: .fast) }
        try await pause(1.5)
        if app.element("stale.close").exists {
            app.element("stale.close").tap()
            try await pause(1.2)
            app.element("toast.offer").tap()
            try await pause(2.5)
        }
    }
}

/// A one-finger drag through several points, which XCUICoordinate can't
/// do: XCTest's own event records, reached by name. For the recordings only.
@MainActor enum Path {
    /// Points in the screen's points, each with its time from the touch.
    static func drag(_ points: [(CGPoint, Double)]) async throws {
        guard let first = points.first,
              let pathType = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
              let recordType = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type else {
            throw XCTSkip("no event records")
        }
        typealias Start = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
        typealias Move = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
        typealias Lift = @convention(c) (AnyObject, Selector, Double) -> Void
        typealias Named = @convention(c) (AnyObject, Selector, NSString, Int64) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        func imp<T>(_ type: AnyClass, _ name: String, as: T.Type) -> (T, Selector) {
            let selector = NSSelectorFromString(name)
            return (unsafeBitCast(class_getMethodImplementation(type, selector), to: T.self), selector)
        }
        func alloc(_ type: AnyClass) -> AnyObject {
            (type as AnyObject).perform(NSSelectorFromString("alloc")).takeRetainedValue()
        }
        let (start, startSel) = imp(pathType, "initForTouchAtPoint:offset:", as: Start.self)
        let (move, moveSel) = imp(pathType, "moveToPoint:atOffset:", as: Move.self)
        let (lift, liftSel) = imp(pathType, "liftUpAtOffset:", as: Lift.self)
        let path = start(alloc(pathType), startSel, first.0, first.1)
        for (point, time) in points.dropFirst() { move(path, moveSel, point, time) }
        lift(path, liftSel, points.last!.1 + 0.02)
        let (named, namedSel) = imp(recordType, "initWithName:interfaceOrientation:", as: Named.self)
        let (add, addSel) = imp(recordType, "addPointerEventPath:", as: Add.self)
        let record = named(alloc(recordType), namedSel, "drag" as NSString, 1)
        add(record, addSel, path)
        guard let synthesizer = XCUIDevice.shared.perform(NSSelectorFromString("eventSynthesizer"))?.takeUnretainedValue() else {
            throw XCTSkip("no synthesizer")
        }
        typealias Done = @convention(block) @Sendable (Bool, NSError?) -> Void
        typealias Synthesize = @convention(c) (AnyObject, Selector, AnyObject, @escaping Done) -> Void
        let (synthesize, synthesizeSel) = imp(type(of: synthesizer), "synthesizeEvent:completion:", as: Synthesize.self)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            synthesize(synthesizer, synthesizeSel, record, { @Sendable _, _ in done.resume() })
        }
    }
}

/// The perf tests' article and the tone page over loopback (as Fixture does),
/// each with the heartbeat, so the bar shows a host as it would for a real page.
final class CriticServer: @unchecked Sendable {
    private let listener: NWListener
    private let port: UInt16
    private static let queue = DispatchQueue(label: "com.connork.field.perftests.critic")

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    func stop() { listener.cancel() }

    static func start() async throws -> CriticServer {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var done = false
            listener.stateUpdateHandler = { state in
                guard !done else { return }
                switch state {
                case .ready: done = true; continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): done = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return CriticServer(listener: listener, port: port)
    }

    private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let path = head.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
                respond(on: connection, path: path)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private static func respond(on connection: NWConnection, path: String) {
        // `/slow/<path>`: the same page, 1.5 s late, so the bar's ring has time to show.
        if path.hasPrefix("/slow/") {
            queue.asyncAfter(deadline: .now() + 1.5) { respond(on: connection, path: String(path.dropFirst(5))) }
            return
        }
        let (status, type, body): (String, String, Data) = switch path {
        case "/article":
            ("200 OK", "text/html; charset=utf-8", Data(Article.html.replacingOccurrences(of: "<body>", with: "<body>" + CriticTour.heartbeat).utf8))
        case "/tone": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.tonePage.utf8))
        case "/popup": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.small(
            "<button style='font-size:22px;padding:14px 20px' onclick=\"window.open('https://example.org/')\">Open a window</button>").utf8))
        case "/jump": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.small(
            "<p>Jumping to the App Store in a moment.</p><script>"
            + "setTimeout(function(){location.href='https://apps.apple.com/us/app/id284882215'},1500);"
            + "setTimeout(function(){location.href='itms-apps://apps.apple.com/app/id284882215'},4500)</script>").utf8))
        case "/ads": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.small(
            "<p id=ad>Waiting for the ad script</p><script src='https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'"
            + " onload=\"ad.textContent='Ad script loaded'\" onerror=\"ad.textContent='Ad script blocked'\"></script>").utf8))
        case "/links": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.small(
            ["Google result": "https://www.google.com/url?q=https://en.wikipedia.org/wiki/Swift_(programming_language)%3Futm_source%3Dgoogle&sa=D&source=web&usg=AOvVaw0abc",
             "Facebook link": "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2F%3Ffbclid%3DIwZXh0bgNhZW0CMTEAAR2&h=AT0xyzABC",
             "Reddit link": "https://out.reddit.com/t3_1fq2abc?url=https%3A%2F%2Fgithub.com%2Fswiftlang%2Fswift%3Futm_source%3Dreddit&token=AQAAq8b5&app_name=web2x",
             "AMP link": "https://www.google.com/amp/s/www.theguardian.com/world/2026/sep/28/example?amp_js_v=0.1&usqp=mq331AQIUAKwASCAAgM%3D"]
                .sorted { $0.key > $1.key }
                .map { "<p><a style='font-size:24px' href='\($0.value)'>\($0.key)</a></p>" }.joined()).utf8))
        case let path where path.hasPrefix("/page/"):
            ("200 OK", "text/html; charset=utf-8", Data(CriticTour.page(Int(path.dropFirst(6)) ?? 0).utf8))
        case let path where path.hasPrefix("/figure/"):
            ("200 OK", "image/svg+xml", Data(Article.svg(Int(path.dropFirst(8).prefix { $0.isNumber }) ?? 0).utf8))
        default: ("404 Not Found", "text/plain", Data("Not found".utf8))
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
