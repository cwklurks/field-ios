import Foundation
import Testing
@testable import Field

/// What a launch on a blank tab does, and what it leaves for later: the
/// first frame is already the field, which takes focus the turn after, and
/// no web view exists until something is loaded.
@MainActor struct BrowserLaunchTests {
    @Test func theFirstFrameIsTheFieldNotYetFocused() {
        let browser = Browser(restoring: false)
        #expect(browser.opensInField)
        #expect(!browser.fieldOpen)
        #expect(browser.tab.web == nil)
    }

    @Test func startingABlankTabOpensTheFieldAndBuildsNoWebView() {
        let browser = Browser(restoring: false)
        browser.start()
        #expect(browser.fieldOpen)
        #expect(!browser.opensInField)
        #expect(browser.tab.web == nil)
    }

    @Test func goingSomewhereBuildsTheWebView() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: URL(string: "about:blank")!)
        #expect(browser.tab.web != nil)
        #expect(!browser.fieldOpen)
    }
}
