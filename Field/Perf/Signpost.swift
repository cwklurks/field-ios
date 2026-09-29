import os

/// Marks the interactions the "Smooth" budgets cover (docs/PLAN.md), so
/// Instruments and the FieldPerf tests see exactly where the time goes.
/// The names are the contract with FieldPerfTests: change them in both places.
nonisolated enum Signpost {
    static let log = OSSignposter(subsystem: "com.connork.field", category: .pointsOfInterest)

    // Events.
    static let firstFrame: StaticString = "launch.firstFrame"
    static let fieldReady: StaticString = "launch.fieldReady"
    static let firstPaint: StaticString = "page.firstPaint"
    static let launchStart: StaticString = "launch.start"      // the turn after the first frame: the field opens

    // Intervals.
    static let fieldOpen: StaticString = "field.open"          // tap on the address → field focused, keyboard up
    static let keystroke: StaticString = "field.keystroke"     // text changed → suggestions on screen
    static let barCollapse: StaticString = "bar.collapse"
    static let barExpand: StaticString = "bar.expand"
    static let welcomeChoose: StaticString = "welcome.choose"  // tap on a look → it has taken effect
    static let tabBuild: StaticString = "tab.build"            // WKWebView construction; not budgeted, shows where launch goes
    static let tabsOpen: StaticString = "tabs.open"            // grid opening: the page shrinks into its card
    static let tabsClose: StaticString = "tabs.close"          // the chosen card grows into the page
    static let tabSwitch: StaticString = "tab.switch"          // carousel settle after release, or switchTab
    static let cardClose: StaticString = "card.close"          // a card thrown away in the grid
    static let tabWake: StaticString = "tab.wake"              // a sleeping tab's build → first paint
    static let memoryWarning: StaticString = "tabs.memoryWarning"  // event
}
