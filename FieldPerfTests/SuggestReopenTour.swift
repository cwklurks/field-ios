import XCTest

/// Real-network smoke coverage of the bar-motion/search-suggestions merge.
/// Pair with SuggestReopenTests: the network's timing is not deterministic here.
final class SuggestReopenTour: XCTestCase {
    @MainActor func testReopenDropsThePreviousQuery() async throws {
        let server = try await CriticServer.start()
        defer { server.stop() }
        let app = Harness.app(open: server.url("/article"))
        app.launchArguments += ["-FieldTouchMarks", "YES", "-suggest", "YES", "-engine", "google"]
        app.launch()
        let address = try app.required("bar.address", timeout: 10)
        XCTAssertTrue(app.staticTexts[Article.headline].waitForExistence(timeout: 10))
        let home = CGPoint(x: address.frame.midX, y: address.frame.midY)
        let outside = CGPoint(x: app.frame.midX, y: app.frame.height * 0.12)
        let field = app.openField()
        app.typeText("zebra")
        guard app.element("suggestion.0").waitForExistence(timeout: 5) else {
            throw XCTSkip("The live engine did not answer the probe query")
        }
        let settled = field.frame
        // Change the request, then bypass XCTest's animation-idle wait for
        // both touches, just as BarTour/testReopenMidClose does.
        app.typeText(" fish")
        try await Task.sleep(for: .milliseconds(125))
        print("REOPEN home=\(home), outside=\(outside), settled=\(settled)")
        try await Path.drag([(outside, 0), (outside, 0.03)])
        try await Path.drag([(home, 0), (home, 0.03)])
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(field.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse((field.value as? String ?? "").contains("zebra"))
        XCTAssertEqual(field.frame.minY, settled.minY, accuracy: 1)
        for _ in 0..<10 {
            XCTAssertFalse(app.element("suggestion.0").exists, "An outgoing query's rows returned")
            XCTAssertEqual(app.buttons.matching(identifier: "suggestion.fill").count, 0)
            try await Task.sleep(for: .milliseconds(200))
        }
        app.typeText("otter")
        XCTAssertTrue((field.value as? String ?? "").hasPrefix("otter"))
    }
}
