import Foundation
import Testing
import UIKit
import SwiftUI
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
        #expect(!browser.gate.lock.inside)
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

    /// Debug's field-test://open?url=…, for the UI tests: the link inside
    /// goes through the same door, checks and all.
    @Test func theTestSchemeHandsOverTheLinkInside() async throws {
        let arrivals = Arrivals()
        var opened: [URL] = []
        var said: [String] = []
        arrivals.open = { opened.append($0) }
        arrivals.announce = { said.append($0) }
        arrivals.restored()
        var parts = URLComponents(string: "field-test://open")!
        for inner in ["https://example.org/a?utm_source=mail", "javascript:alert(1)"] {
            parts.queryItems = [.init(name: "url", value: inner)]
            arrivals.received(parts.url!)
        }
        arrivals.received(URL(string: "field-test://open")!)
        for _ in 0..<50 where said.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(opened == [URL(string: "https://example.org/a")!])
        #expect(said == ["Field opens only web links.", "Field opens only web links."])
    }
    @Test func aRedirectUsesTheDestinationsShield() async throws {
        let blocker = ContentBlocking.shared
        defer {
            blocker.setShield(true, for: "destination.example")
            blocker.setShield(true, for: "www.google.com")
        }
        let arrivals = Arrivals()
        var opened: [URL] = []
        arrivals.open = { opened.append($0) }
        arrivals.restored()
        let redirect = URL(string: "https://www.google.com/url?q=https%3A%2F%2Fdestination.example%2Fa%3Futm_source%3Dmail")!
        blocker.setShield(false, for: "destination.example")
        arrivals.received(redirect)
        for _ in 0..<50 where opened.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(opened == [URL(string: "https://destination.example/a?utm_source=mail")!])
        blocker.setShield(true, for: "destination.example")
        blocker.setShield(false, for: "www.google.com")
        arrivals.received(redirect)
        for _ in 0..<50 where opened.count < 2 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(opened.last == URL(string: "https://destination.example/a")!)
    }

    @Test func aCoveredPartialDragCutsBeforeTheShadeGoes() {
        let browser = Browser(restoring: false)
        browser.start()
        browser.enterPrivate()
        browser.go(to: page)
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: nil)
        defer { NotificationCenter.default.post(name: UIScene.didActivateNotification, object: nil) }
        let strip = PrivateStrip(everyday: UIView())
        strip.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        strip.hold(UIView())
        strip.track(-100)
        let coordinator = StageView.Coordinator()
        coordinator.dragging = true
        browser.open(incoming: link)
        StageView(browser: browser, openSettings: {}).update(strip, coordinator: coordinator)
        #expect(strip.progress == 0)
        #expect(!coordinator.dragging)
        #expect(!browser.privately)
    }

    @Test func aLinkDuringWipeOnlyTouchesEverydayTabs() async {
        let browser = Browser(restoring: false)
        browser.start()
        browser.enterPrivate()
        browser.go(to: page)
        browser.privateSpace.stepped = { step in
            if step == .webViews { browser.open(incoming: link) }
        }
        await browser.privateSpace.wipe()
        #expect(!browser.privately)
        #expect(browser.privateSpace.tabs == nil)
        #expect(browser.everyday.current.url == link)
    }

    @Test func severalLinksWhileTheGridClosesShowTheLastPage() async throws {
        let browser = Browser(restoring: false)
        browser.start()
        browser.go(to: page)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: BrowserView(browser: browser))
        window.isHidden = false
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(300))
        browser.showTabs()
        try await Task.sleep(for: .milliseconds(400))
        let links = (1...3).map { URL(string: "about:blank#incoming\($0)")! }
        links.forEach(browser.open(incoming:))
        try await Task.sleep(for: .seconds(1))
        #expect(browser.everyday.current.url == links.last)
        let web = try #require(browser.everyday.current.web)
        #expect(web.superview != nil)
    }

}
