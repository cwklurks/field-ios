import XCTest

/// How the perf tests launch Field and find what they measure. The launch
/// arguments, identifiers and signpost names are the contract in
/// docs/perf.md, "Launch arguments and identifiers".
///
/// Two things about the metrics shape every test here:
/// - XCTOSSignpostMetric reports only the first matching interval in each
///   iteration, so a test does one of each interaction per iteration.
/// - A signpost the app never emits isn't an error: the metric is simply
///   missing from the results, and scripts/perf/run.sh flags it.
enum Harness {
    /// Field/Perf/Signpost.swift logs here, in the points-of-interest category.
    static func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "com.connork.field", category: "PointsOfInterest", name: name)
    }

    /// Field past the welcome screen with a known bar look, optionally opening `url`.
    @MainActor static func app(look: String = "glass", open url: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-bar.look", look]
        if let url {
            app.launchArguments += ["-FieldOpen", url.absoluteString]
        } else {
            // One blank tab, never the simulator's saved session: a restore would change what launch measures.
            app.launchArguments += ["-FieldSeedTabs", "0"]
        }
        return app
    }

    /// Iterations after the discarded warm-up; XCTest's default is 5.
    static func options(_ iterations: Int = 5, _ invocation: XCTMeasureOptions.InvocationOptions = []) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        options.invocationOptions = invocation
        return options
    }
}

extension XCUIApplication {
    /// The element with this accessibility identifier, whatever its type.
    @MainActor func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The element with this identifier, or a skip while the app doesn't have it yet.
    @MainActor func required(_ id: String, timeout: TimeInterval = 5) throws -> XCUIElement {
        let element = element(id)
        guard element.waitForExistence(timeout: timeout) else {
            throw XCTSkip("No \"\(id)\" element yet (docs/perf.md, launch arguments and identifiers).")
        }
        return element
    }

    /// Taps the address and waits for the field and the keyboard.
    @MainActor func openField() -> XCUIElement {
        element("bar.address").tap()
        let field = element("field")
        _ = field.waitForExistence(timeout: 3)
        _ = keyboards.firstMatch.waitForExistence(timeout: 2)
        return field
    }

    /// Closes the field: its cancel control if it has one, else a tap on the
    /// scrim near the top of the screen. False if the field is still there.
    @MainActor func closeField() -> Bool {
        let cancel = element("field.cancel")
        if cancel.exists {
            cancel.tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        return element("field").waitForNonExistence(timeout: 3)
    }
}
