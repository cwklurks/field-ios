import Foundation
import UIKit
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

/// The address's press: dimmed while a finger is on it, and whole again
/// however the finger leaves, a tap included. A tap on the pill brings the
/// whole bar back, and its address mustn't stay dimmed (bar-polish B-01).
@MainActor struct BarPressTests {
    @Test func aFingerDownDimsTheAddress() {
        let bar = BarContent()
        bar.address.sendActions(for: .touchDown)
        #expect(bar.address.alpha == 0.5)
    }

    @Test func everyWayTheFingerLeavesBringsItBack() {
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
            let bar = BarContent()
            bar.address.sendActions(for: .touchDown)
            #expect(bar.address.alpha == 0.5)
            bar.address.sendActions(for: event)
            #expect(bar.address.alpha == 1, "after \(event)")
        }
    }
}
