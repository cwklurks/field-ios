import Foundation
import Testing
import UIKit
@testable import Field

/// Links from other apps, in the browser: a tab of your own every time,
/// never Private's, and nothing loaded is overwritten.
@Suite(.serialized)
@MainActor struct IncomingTests {
    let link = URL(string: "https://example.com/from-mail")!
    let page = URL(string: "about:blank#page")!

    @Test func aBlankTabTakesTheLink() {
        let browser = Browser(restoring: false)
        browser.start()
        #expect(browser.fieldOpen)
        browser.open(incoming: link)
        #expect(browser.everyday.all.count == 1)
        #expect(browser.tab.url == link)
        #expect(browser.tab.web != nil)
        #expect(!browser.fieldOpen)
    }

    @Test func aPageIsNeverOverwritten() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: page)
        browser.open(incoming: link)
        #expect(browser.everyday.all.map(\.url) == [page, link])
        #expect(browser.tab.url == link)
    }

    @Test func severalOpenOneTabEachInOrder() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: page)
        let links = (1...3).map { URL(string: "https://example.com/\($0)")! }
        links.forEach(browser.open(incoming:))
        #expect(browser.everyday.all.map(\.url) == [page] + links)
        #expect(browser.tab.url == links.last)
    }

    @Test func anOpenFieldClosesOverAPage() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: page)
        browser.openField()
        browser.open(incoming: link)
        #expect(!browser.fieldOpen)
        #expect(browser.everyday.all.first?.url == page)
    }

    @Test func fromPrivateItGoesToYourTabs() throws {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: page)
        browser.enterPrivate()
        let secret = URL(string: "about:blank#secret")!
        browser.go(to: secret)
        browser.open(incoming: link)
        #expect(!browser.privately)
        #expect(browser.tab.url == link)
        #expect(browser.everyday.all.map(\.url) == [page, link])
        let inside = try #require(browser.privateSpace.tabs)
        #expect(!inside.all.contains { $0.url == link })
        #expect(!browser.cutToEveryday)
    }

    /// Covered (here by the switcher's cover; locked works the same), the
    /// strip cuts under the shade rather than sliding the private page out.
    @Test func underPrivatesShadeItCuts() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.enterPrivate()
        browser.go(to: URL(string: "about:blank#secret")!)
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: nil)
        defer { NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil) }
        #expect(browser.gate.shadeShown)
        browser.open(incoming: link)
        #expect(!browser.privately)
        #expect(browser.cutToEveryday)
        #expect(browser.tab.url == link)
        // The shade goes only once the cut is on its way to the screen.
        #expect(browser.gate.shadeShown)
    }

    @Test func arrivalsWaitForTheStartThenOpenInOrder() async throws {
        let arrivals = Arrivals()
        var opened: [URL] = []
        var said: [String] = []
        arrivals.open = { opened.append($0) }
        arrivals.announce = { said.append($0) }
        let b = URL(string: "https://www.google.com/url?q=https://example.org/b&sa=D")!
        arrivals.received(link)
        arrivals.received(URL(string: "javascript:alert(1)")!)
        arrivals.received(b)
        try await Task.sleep(for: .milliseconds(100))
        #expect(opened.isEmpty)
        arrivals.restored()
        for _ in 0..<50 where opened.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(opened == [link, URL(string: "https://example.org/b")!])
        #expect(said == ["Field opens only web links."])
    }
}
