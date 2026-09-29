import XCTest

/// From the tap on a look to it having taken effect. Budget: under 2 ms/s of
/// hitch time. Iterations alternate between the two looks. The welcome stays
/// up after the choice (Continue dismisses it), so each iteration relaunches
/// to measure a first choice, not a change of mind.
final class WelcomeTests: XCTestCase {
    @MainActor func testChoose() throws {
        let app = XCUIApplication()
        // No -bar.look: the choice has to be what the app then reads.
        app.launchArguments = ["-welcomed", "NO"]
        app.launch()
        _ = try app.required("welcome.glass")
        _ = try app.required("welcome.solid", timeout: 1)

        var iteration = 0
        measure(metrics: [Harness.signpost("welcome.choose"), XCTHitchMetric(application: app)],
                options: Harness.options(5, [.manuallyStart, .manuallyStop])) {
            app.launch()
            let choice = app.element(iteration % 2 == 0 ? "welcome.glass" : "welcome.solid")
            iteration += 1
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            startMeasuring()
            choice.tap()
            XCTAssertTrue(choice.wait(for: \.isSelected, toEqual: true, timeout: 3), "The look wasn't chosen after the tap.")
            stopMeasuring()
        }
    }
}
