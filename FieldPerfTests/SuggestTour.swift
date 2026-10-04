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

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
