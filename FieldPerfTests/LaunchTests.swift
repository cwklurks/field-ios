import XCTest

/// Budgets: the first frame within 400 ms, and the field accepting typing
/// within 500 ms. XCTest's "responsive" launch (first frame, then the main
/// thread takes input) stands in for the second; Instruments' App Launch
/// template shows the exact time to the `launch.fieldReady` signpost.
///
/// XCTest terminates the app between iterations, so each launch starts a new
/// process. That is what Apple calls a warm launch: the system's caches stay
/// warm, which only a reboot resets.
final class LaunchTests: XCTestCase {
    @MainActor func testColdLaunch() {
        let app = Harness.app()
        measure(metrics: [XCTApplicationLaunchMetric(), XCTApplicationLaunchMetric(waitUntilResponsive: true)],
                options: Harness.options()) {
            app.launch()
        }
    }
}
