import XCTest

/// Settings › About lists the licences, and each opens in full.
final class LicencesTests: XCTestCase {
    @MainActor func testALicenceOpensInFullInLight() async throws {
        try await openLicence(look: "light")
    }

    @MainActor func testALicenceOpensInFullInDark() async throws {
        try await openLicence(look: "dark")
    }

    @MainActor private func openLicence(look: String) async throws {
        let fixture = await Fixture.start()
        defer { fixture.stop() }
        let app = Harness.app(open: fixture.url)
        app.launchArguments += ["-look", look]
        app.launch()
        _ = try app.required("page", timeout: 15)
        try await Task.sleep(for: .seconds(1.5))
        app.element("bar.tabs").tap()
        let gear = try app.required("tabs.settings")
        try await Task.sleep(for: .seconds(1.2))
        gear.tap()
        let settings = app.element("settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        let row = app.element("about.licence.gpl")
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            settings.swipeUp()
        }
        // Let the scroll come to rest before the picture.
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(row.isHittable, "the licences aren't in About")
        for licence in ["mpl", "gpl", "ccBySA", "apache"] {
            XCTAssertTrue(app.element("about.licence.\(licence)").exists, "no \(licence) row")
        }
        attach(app, "About's licences in \(look)")

        row.tap()
        let sheet = app.element("licence.gpl")
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "the licence didn't open")
        let text = sheet.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "GNU GENERAL PUBLIC LICENSE")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 3), "the licence's text didn't load")
        try await Task.sleep(for: .seconds(0.6))
        attach(app, "GPL in full in \(look)")
        app.element("licence.gpl.done").tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "the licence didn't close")
        XCTAssertTrue(settings.exists)
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
