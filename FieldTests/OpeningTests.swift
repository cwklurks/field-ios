import Foundation
import Testing
@testable import Field

/// What a navigation is allowed to do, until M3's guard.
struct OpeningTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test(arguments: ["https://example.com", "http://example.com", "about:blank",
                      "data:text/html,hi", "blob:https://example.com/1234"])
    func webSchemesLoad(_ address: String) {
        #expect(Opening.decide(url(address), newWindow: false, byLink: true) == .allow)
    }

    @Test(arguments: ["mailto:a@example.com", "tel:123", "itms-apps://apps.apple.com/app/id1",
                      "file:///etc/hosts", "javascript:alert(1)", "sms:123"])
    func otherSchemesAreIgnored(_ address: String) {
        #expect(Opening.decide(url(address), newWindow: false, byLink: true) == .ignore)
        #expect(Opening.decide(url(address), newWindow: true, byLink: true) == .ignore)
    }

    /// One tab until M2: a link that asks for a new window opens here.
    @Test func newWindowLinksOpenHere() {
        #expect(Opening.decide(url("https://example.com"), newWindow: true, byLink: true) == .sameTab)
    }

    /// A window a script opens is a popup, and stays shut.
    @Test func scriptWindowsAreBlocked() {
        #expect(Opening.decide(url("https://ads.example"), newWindow: true, byLink: false) == .block)
    }

    @Test func noAddressIsIgnored() {
        #expect(Opening.decide(nil, newWindow: false, byLink: false) == .ignore)
    }
}
