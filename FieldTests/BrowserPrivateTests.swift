import Testing
@testable import Field

/// Private wired into the browser (docs/PLAN.md, "Private space"): its tabs
/// are the ones on screen only while inside, and yours are left alone.
@MainActor struct BrowserPrivateTests {
    @Test func privateTabsAreOnScreenOnlyInside() {
        let browser = Browser(restoring: false)
        let everyday = browser.tabs
        browser.enterPrivate()
        #expect(browser.privately)
        #expect(browser.tabs !== everyday)
        #expect(browser.tabs.space === browser.privateSpace)
        #expect(browser.tab.space === browser.privateSpace)
        #expect(everyday.space == nil)
        #expect(browser.capture.isPrivate())
        browser.leavePrivate()
        #expect(!browser.privately)
        #expect(browser.tabs === everyday)
        #expect(!browser.capture.isPrivate())
    }
}
