import XCTest

/// Not a measurement: the script docs/motion.md's video loop records. It drives
/// the field's core interactions at a pace a camera can follow (tap, type,
/// cancel, tap, Go, swipe down) with touch marks on, so each frame strip shows
/// where the finger was and when it lifted. Run it alone, with a recording
/// going (scripts/motion/record.sh).
final class MotionScript: XCTestCase {
    /// A white page on a black one: its background colour says dark, and
    /// what sits under the bar is white, until a black band scrolls under it.
    static let page: URL = {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{margin:0;background:#000;font:17px -apple-system}
        .hero{height:58vh;color:#fff;display:flex;align-items:center;justify-content:center;font-size:34px;font-weight:600}
        .sheet{background:#fff;color:#111;padding:24px;min-height:60vh}
        .band{height:45vh;background:#111}</style></head>
        <body><div class="hero">Dark band</div><div class="sheet"><h2>White sheet</h2><p>Under the bar is white here,
        though the page's own background is black.</p></div><div class="band"></div><div class="sheet"></div>
        <div class="band"></div><div class="sheet"></div></body></html>
        """
        return URL(string: "data:text/html;base64,\(Data(html.utf8).base64EncodedString())")!
    }()

    @MainActor func testChoreography() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(look: ProcessInfo.processInfo.environment["MOTION_LOOK"] ?? "glass", open: Self.page)
        app.launchArguments += ["-FieldSeedHistory", "2000", "-FieldTouchMarks", "YES"]
        app.launch()
        let address = try app.required("bar.address", timeout: 10)
        try await pause(2.5)

        // Scroll a black band under the bar and back: the bar shrinks, turns
        // dark over the band and light again, and grows back at the top.
        let page = app.element("page")
        page.swipeUp(velocity: 400)
        try await pause(1.5)
        page.swipeDown(velocity: 400)
        try await pause(1.5)

        // Open, type, cancel with a tap outside.
        address.tap()
        try await pause(1.4)
        app.typeText("wea")
        try await pause(1.2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        try await pause(1.6)

        // Open and Go somewhere.
        address.tap()
        try await pause(1.4)
        app.typeText(fixture.url.absoluteString + "\n")
        try await pause(2.5)

        // Open, then swipe the keyboard away.
        address.tap()
        try await pause(1.4)
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: 1500, thenHoldForDuration: 0.05)
        try await pause(3)
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
