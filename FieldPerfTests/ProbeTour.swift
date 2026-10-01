import XCTest

final class ProbeTour: XCTestCase {
    @MainActor func testIdle() async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-FieldSeedTabs", ProcessInfo.processInfo.environment["PROBE_SEEDS"] ?? "50"]
        app.launch()
        _ = app.element("page").waitForExistence(timeout: 15)
        let start = Date()
        app.element("bar.tabs").tap()
        print("PROBE tap took \(Date().timeIntervalSince(start))")
    }
}
