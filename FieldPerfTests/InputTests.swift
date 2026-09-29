import XCTest

/// Opening the field from a page and typing into it. Budgets: under 2 ms/s of
/// hitch time throughout, and each keystroke's suggestions on screen within
/// one frame (8.3 ms at 120 Hz). The page is the fixture article, so the bar
/// shows its address the way it does in use; a blank tab starts in the field.
final class InputTests: XCTestCase {
    /// From the tap on the address to the field focused with the keyboard up.
    @MainActor func testOpenField() async throws {
        let (app, fixture) = try await launch()
        defer { fixture.stop() }

        measure(metrics: [Harness.signpost("field.open"), XCTHitchMetric(application: app)],
                options: Harness.options(5, .manuallyStop)) {
            XCTAssertTrue(app.openField().exists)
            stopMeasuring()
            XCTAssertTrue(app.closeField())
        }
    }

    /// One keystroke per iteration, since the signpost metric reports only the
    /// first interval in each; run.sh holds the slowest one to the budget.
    /// The first letter, which replaces the selected address, is XCTest's
    /// discarded warm-up.
    @MainActor func testKeystroke() async throws {
        let word = Array("weather")
        let (app, fixture) = try await launch(seedHistory: true)
        defer { fixture.stop() }
        _ = app.openField()

        var next = 0
        measure(metrics: [Harness.signpost("field.keystroke")], options: Harness.options(word.count - 1)) {
            app.typeText(String(word[next]))
            next += 1
        }
    }

    /// A whole word at XCTest's typing speed, for the hitches in between.
    @MainActor func testTypingHitches() async throws {
        let (app, fixture) = try await launch(seedHistory: true)
        defer { fixture.stop() }
        _ = app.openField()

        measure(metrics: [XCTHitchMetric(application: app)], options: Harness.options(5, .manuallyStop)) {
            app.typeText("weather")
            stopMeasuring()
            // Enough for the word and any inline completion after it.
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
    }

    /// Field on the fixture page, having opened and closed the field once: that
    /// skips the test unless the address, the field and a way to close it all
    /// exist, and takes the first, slower keyboard out of the measurement.
    @MainActor private func launch(seedHistory: Bool = false) async throws -> (XCUIApplication, Fixture) {
        let fixture = await Fixture.start()
        let app = Harness.app(open: fixture.url)
        if seedHistory {
            app.launchArguments += ["-FieldSeedHistory", "2000"]
        }
        app.launch()
        do {
            _ = try app.required("bar.address", timeout: 10)
            _ = app.openField()
            _ = try app.required("field", timeout: 1)
            guard app.closeField() else {
                throw XCTSkip("Can't close the field: no \"field.cancel\" element, and a tap on the scrim didn't close it.")
            }
        } catch {
            fixture.stop()
            throw error
        }
        return (app, fixture)
    }
}
