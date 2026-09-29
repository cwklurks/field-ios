import XCTest

/// The control for LaunchTests and InputTests: `-FieldBaseline YES` shows only
/// a bare text field with the field's keyboard, focused on launch, and emits
/// the same `launch.fieldReady` and `field.keystroke` signposts. Side by side
/// with the real ones, it shows how much of each number is the system
/// keyboard's own.
final class BaselineTests: XCTestCase {
    @MainActor func testColdLaunch() {
        let app = baseline()
        measure(metrics: [XCTApplicationLaunchMetric(), XCTApplicationLaunchMetric(waitUntilResponsive: true)],
                options: Harness.options()) {
            app.launch()
        }
    }

    /// Typed as InputTests.testKeystroke types: one letter per iteration, the
    /// first discarded as XCTest's warm-up.
    @MainActor func testKeystroke() throws {
        let word = Array("weather")
        let app = baseline()
        app.launch()
        _ = try app.required("field", timeout: 10)
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("No keyboard came up for the baseline field.")
        }

        var next = 0
        measure(metrics: [Harness.signpost("field.keystroke")], options: Harness.options(word.count - 1)) {
            app.typeText(String(word[next]))
            next += 1
        }
    }

    @MainActor private func baseline() -> XCUIApplication {
        let app = Harness.app()
        app.launchArguments += ["-FieldBaseline", "YES"]
        return app
    }
}
