import Foundation
import Testing
import UIKit
import WebKit
@testable import Field

/// What leaves Private through the phone itself: copies stay on this phone
/// and expire, and nothing is handed to Handoff, Spotlight or Siri.
@Suite(.serialized)
@MainActor struct PrivateHygieneTests {
    @Test func copiesStayOnThisPhoneAndExpire() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let options = PrivatePasteboard.options(now: now)
        #expect(options[.localOnly] as? Bool == true)
        #expect(options[.expirationDate] as? Date == now.addingTimeInterval(PrivatePasteboard.lifetime))
        #expect(PrivatePasteboard.lifetime <= 180)
    }

    /// Forgotten with the space, unless something else has been copied since.
    @Test func aWipeForgetsTheCopy() {
        let url = URL(string: "https://private.example/page")!
        PrivatePasteboard.copy(url)
        #expect(UIPasteboard.general.hasURLs)
        PrivatePasteboard.forget()
        #expect(!UIPasteboard.general.hasURLs)

        PrivatePasteboard.copy(url)
        UIPasteboard.general.string = "copied since"
        PrivatePasteboard.forget()
        #expect(UIPasteboard.general.string == "copied since")
    }

    @Test func noActivityForPrivatePages() {
        let url = URL(string: "https://example.com/")!
        #expect(Hygiene.activity(for: url, title: "Example", isPrivate: true) == nil)
        let everyday = Hygiene.activity(for: url, title: "Example", isPrivate: false)
        #expect(everyday?.webpageURL == url)
        #expect(everyday?.isEligibleForSearch == false)
        #expect(everyday?.isEligibleForPrediction == false)
    }

    /// Nothing on the private path makes one: its web views carry none.
    @Test func privateWebViewsCarryNoActivity() {
        let config = WKWebViewConfiguration()
        PrivateSpace().configure(config)
        let web = WKWebView(frame: .zero, configuration: config)
        #expect(web.userActivity == nil)
    }

    @Test func notificationsSayNothing() {
        #expect(Hygiene.notificationText("Your download of secret.pdf finished", isPrivate: true) == "Field has something for you.")
        #expect(Hygiene.notificationText("Done", isPrivate: false) == "Done")
    }
}
