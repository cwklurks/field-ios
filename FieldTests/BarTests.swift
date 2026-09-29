import Foundation
import Testing
@testable import Field

/// What the bar says about the page: its host, and nothing nobody reads.
struct BarTests {
    @Test func theHostWithoutWWW() {
        #expect(Bar.host(of: URL(string: "https://www.example.com/a/b?c=d")) == "example.com")
        #expect(Bar.host(of: URL(string: "https://news.ycombinator.com/")) == "news.ycombinator.com")
        #expect(Bar.host(of: URL(string: "http://localhost:8080/")) == "localhost")
    }

    /// A blank tab has no host, so the bar asks for one instead.
    @Test func nothingForABlankTab() {
        #expect(Bar.host(of: nil) == nil)
        #expect(Bar.host(of: URL(string: "about:blank")) == nil)
    }
}

/// What the bar's address says: the placeholder only for a blank tab, and
/// for a page with no host (a `data:` page), its scheme, as the Mac does.
@MainActor struct BarAddressTests {
    @Test func noPageIsTheBlankTabsPlaceholder() {
        let bar = BarContent()
        bar.say(nil)
        #expect(bar.label.text == Bar.placeholder)
        #expect(bar.blank)
    }

    @Test func aPageWithNoHostSaysItsScheme() {
        let bar = BarContent()
        bar.say(URL(string: "data:text/html,hi"))
        #expect(bar.label.text == "data:")
        #expect(!bar.blank)
    }
}
