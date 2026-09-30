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
        let (status, type, body): (String, String, Data) = switch path {
        case "/article":
            ("200 OK", "text/html; charset=utf-8", Data(Article.html.replacingOccurrences(of: "<body>", with: "<body>" + CriticTour.heartbeat).utf8))
        case "/tone": ("200 OK", "text/html; charset=utf-8", Data(CriticTour.tonePage.utf8))
        case let path where path.hasPrefix("/figure/"):
            ("200 OK", "image/svg+xml", Data(Article.svg(Int(path.dropFirst(8).prefix { $0.isNumber }) ?? 0).utf8))
        default: ("404 Not Found", "text/plain", Data("Not found".utf8))
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
