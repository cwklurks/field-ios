import XCTest

/// Search suggestions in the real app, over the real network: a search made,
/// then offered again from its first letters, with the engine's suggestions
/// landing beyond it. Not a measurement. It fails if the engine's rows,
/// arriving late, move the row nearest the field, and it paces itself for a
/// recording (docs/motion.md's video loop). Needs the network; skips without.
final class SuggestTour: XCTestCase {
    @MainActor func testEngineRowsLandWithoutMovingTheFieldsOwn() async throws {
        let app = Harness.app()
        app.launchArguments += ["-FieldTouchMarks", "YES", "-suggest", "YES", "-engine", "google"]
        app.launch()
        let field = try app.required("field", timeout: 10)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        try await pause(1)

        // A search, so there is one to offer again.
        app.typeText("swift concurrency\n")
        _ = try app.required("bar.address", timeout: 10)
        try await pause(2)

        // From its first letters: the past search, nearest the field, at once.
        _ = app.openField()
        try await pause(1)
        for letter in "swift c" {
            app.typeText(String(letter))
            try await pause(0.25)
        }
        let nearest = app.element("suggestion.0")
        XCTAssertTrue(nearest.waitForExistence(timeout: 2))
        let before = nearest.frame
        XCTAssertEqual(nearest.label.hasPrefix("swift concurrency"), true, nearest.label)

        // Then the engine's, above it.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'suggestion.'"))
        let deadline = Date.now.addingTimeInterval(4)
        while rows.count <= 2, Date.now < deadline { try await pause(0.1) }
        guard rows.count > 2 else { throw XCTSkip("No suggestions came back from the engine: offline?") }
        XCTAssertEqual(nearest.frame, before, "The engine's rows moved the row nearest the field")
        try await pause(1.5)

        // Fill: the top suggestion's words into the field, without going.
        let fill = app.descendants(matching: .any).matching(identifier: "suggestion.fill").firstMatch
        XCTAssertTrue(fill.exists)
        fill.tap()
        try await pause(1.5)
        let filled = field.value as? String ?? ""
        XCTAssertTrue(filled.hasPrefix("swift c") && filled.count > "swift c".count, filled)
        XCTAssertTrue(app.element("field").exists)

        // Then go with the row nearest the field.
        try await pause(1)
        app.element("suggestion.0").tap()
        _ = try app.required("bar.address", timeout: 10)
        try await pause(2)
    }

    /// Words nothing on the phone knows, so every row is the engine's, and
    /// each letter changes them all. Between answers the panel holds its
    /// height, the old rows faded and out of reach, rather than folding
    /// away and growing back. The video shows it; this fails only if the
    /// panel is gone just after a letter.
    @MainActor func testARemoteOnlyQueryChangingHoldsThePanel() async throws {
        let app = Harness.app()
        app.launchArguments += ["-FieldTouchMarks", "YES", "-suggest", "YES", "-engine", "google"]
        app.launch()
        _ = try app.required("field", timeout: 10)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        try await pause(1)

        for letter in "zebra" {
            app.typeText(String(letter))
            try await pause(0.3)
        }
        let panel = app.element("suggestions")
        guard panel.waitForExistence(timeout: 4) else {
            throw XCTSkip("No suggestions came back from the engine: offline?")
        }
        try await pause(1)

        for letter in " fish" {
            app.typeText(String(letter))
            XCTAssertTrue(panel.exists, "The panel folded away between answers")
            try await pause(0.6)
        }
        try await pause(1.5)
    }

    /// Settings' Clear Past Searches: a search made, cleared after the
    /// confirmation, and no longer offered. With TEST_RUNNER_SUGGEST_SHOTS
    /// set to a folder, the screen is saved there at each step.
    @MainActor func testClearingPastSearches() async throws {
        let app = Harness.app()
        app.launchArguments += ["-FieldTouchMarks", "YES", "-suggest", "YES", "-engine", "google"]
        app.launch()
        _ = try app.required("field", timeout: 10)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        app.typeText("goat cheese tart\n")
        _ = try app.required("bar.address", timeout: 10)
        try await pause(2)

        try app.required("bar.tabs").tap()
        try await pause(1.5)
        try app.required("tabs.settings").tap()
        let settings = try app.required("settings")
        let clear = app.buttons["settings.clearSearches"]
        for _ in 0..<4 where !clear.isHittable {
            settings.swipeUp(velocity: .slow)
            try await pause(0.8)
        }
        XCTAssertTrue(clear.isEnabled)
        shoot("settings-clear")
        clear.tap()
        try await pause(1)
        shoot("settings-confirm")
        app.sheets.buttons["Clear Past Searches"].firstMatch.tap()
        try await pause(1)
        XCTAssertFalse(clear.isEnabled, "Cleared, there is nothing left to clear")
        shoot("settings-cleared")
        app.buttons["settings.done"].tap()
        // Past the save's wait, then from a fresh launch: cleared on disk too.
        try await pause(2.5)
        app.terminate()
        app.launch()
        _ = try app.required("field", timeout: 10)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        try await pause(1)
        app.typeText("goat chee")
        try await pause(2)
        let searched = app.descendants(matching: .any).matching(NSPredicate(format: "value == 'Searched before'"))
        XCTAssertEqual(searched.count, 0, "A cleared search was offered again")
        shoot("cleared-field")
    }

    /// The rows at the largest text the chrome takes. On the iPhone Air all
    /// of them fit; FieldTests/SuggestionsRoomTests draws an SE's.
    @MainActor func testLargestText() async throws {
        let app = Harness.app()
        app.launchArguments += ["-suggest", "YES", "-engine", "google",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        _ = try app.required("field", timeout: 10)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        app.typeText("swift c")
        try await pause(2.5)
        shoot("largest-text-air")
    }

    @MainActor func testCappedRowsAreAbsentFromAccessibility() throws {
        let app = Harness.app()
        app.launchArguments += ["-FieldSuggestionFixture"]
        app.launch()
        XCTAssertTrue(app.element("suggestion.0").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("suggestion.1").exists)
        XCTAssertFalse(app.element("suggestion.2").exists)
        XCTAssertEqual(app.buttons.matching(identifier: "suggestion.fill").count, 2)
        app.buttons["Expand"].tap()
        XCTAssertTrue(app.element("suggestion.2").waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(identifier: "suggestion.fill").count, 3)
        app.buttons["Cap"].tap()
        XCTAssertTrue(app.element("suggestion.2").waitForNonExistence(timeout: 2))
        XCTAssertEqual(app.buttons.matching(identifier: "suggestion.fill").count, 2)
        app.buttons["Change query"].tap()
        // Old rows still occupy the panel, but expose no actions.
        XCTAssertTrue(app.element("suggestions").exists)
        XCTAssertTrue(app.element("suggestion.0").waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.element("suggestion.1").exists)
        XCTAssertEqual(app.buttons.matching(identifier: "suggestion.fill").count, 0)
    }

    private func shoot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["SUGGEST_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(filePath: folder).appending(path: "\(name).png"))
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
