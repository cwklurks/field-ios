import FieldKit
import Foundation
import Testing
import WebKit
@testable import Field

/// The guard as a tab asks it: what each navigation counts as, and what a
/// page trying to leave, or to throw you somewhere, gets.
@Suite(.serialized)
struct GuardWiringTests {
    /// The app's own loads, and their redirects, are typed; anything else
    /// WebKit calls "other" is a page's own doing.
    @Test func kinds() {
        #expect(Tab.kind(of: .linkActivated, asked: false) == .link)
        #expect(Tab.kind(of: .formSubmitted, asked: false) == .formSubmit)
        #expect(Tab.kind(of: .formResubmitted, asked: true) == .formSubmit)
        #expect(Tab.kind(of: .backForward, asked: true) == .backForward)
        #expect(Tab.kind(of: .reload, asked: false) == .reload)
        #expect(Tab.kind(of: .other, asked: true) == .typed)
        #expect(Tab.kind(of: .other, asked: false) == .other)
    }

    @Test func whereALinkGoes() {
        #expect(Tab.leaving(to: URL(string: "mailto:a@example.com")!) == "This link opens Mail.")
        #expect(Tab.leaving(to: URL(string: "tel:123")!) == "This link opens Phone.")
        #expect(Tab.leaving(to: URL(string: "itms-apps://apps.apple.com/app/id1")!) == "This link opens the App Store.")
        #expect(Tab.leaving(to: URL(string: "spotify:track:1")!) == "This link opens another app.")
    }

    @Test func anOfferIsTakenOnce() {
        let toaster = Toaster()
        var taken = 0
        toaster.show("Popup blocked", offering: Toaster.Offer(title: "Open") { taken += 1 })
        #expect(toaster.offer?.title == "Open")
        toaster.take()
        toaster.take()
        #expect(taken == 1)
        #expect(toaster.text == nil)
    }

    /// A page's script heading for the App Store is stopped, and says so.
    @Test func aScriptCantJumpToTheAppStore() async throws {
        let (tab, said) = try await Self.guardedTab()
        tab.load(Self.page("location = 'itms-apps://apps.apple.com/app/id1'"))
        #expect(await Self.eventually { said.value.contains("Stopped a jump to the App Store.") })
    }

    /// A shim a page sends you through is unwrapped before it leaves.
    @Test func aShimIsUnwrappedOnTheWay() async throws {
        let (tab, _) = try await Self.guardedTab()
        tab.load(Self.page("location = 'https://www.google.com/url?q=https://example.org/landing%3Futm_source%3Dx'"))
        #expect(await Self.eventually { tab.url?.absoluteString == "https://example.org/landing" })
    }

    // MARK: -

    final class Said { var value: [String] = [] }

    private static func guardedTab() async throws -> (Tab, Said) {
        if Guarded.current == nil {
            Guarded.current = Guard(rules: await Task.detached { GuardRules.bundled }.value)
        }
        let history = HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("GuardWiringTests-\(UUID().uuidString)"))
        let tab = Tab(history: history)
        let said = Said()
        tab.announce = { said.value.append($0) }
        tab.build()
        return (tab, said)
    }

    private static func page(_ script: String) -> URL {
        let html = "<!doctype html><script>\(script)</script>"
        return URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
    }

    private static func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
