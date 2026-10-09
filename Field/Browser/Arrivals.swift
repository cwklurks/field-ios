import FieldKit
import Foundation
import os

/// Links other apps hand Field (Mail, Messages, Notes), from `onOpenURL`.
/// FieldKit's LinkInbox holds them until the browser has started and the
/// welcome is done; then each is checked and cleaned (IncomingLink) and
/// opened in a tab of your own, one at a time, in the order they came.
/// One that can't be opened says so, quietly.
@MainActor final class Arrivals {
    var open: (URL) -> Void = { _ in }
    var announce: (String) -> Void = { _ in }

    private var inbox = LinkInbox()
    /// Released by the inbox, waiting their turn.
    private var due: [URL] = []
    private var opening: Task<Void, Never>?

    /// Under `arrivals` in the log. Addresses are private.
    nonisolated static let log = Logger(subsystem: "com.connork.field", category: "arrivals")

    func received(_ url: URL) {
        #if DEBUG
        // field-test://open?url=<link>, declared only in Debug (Info.plist):
        // the UI tests' way to hand a running Field a link, since iOS sends
        // http to the default browser and XCUIApplication.open relaunches.
        if url.scheme == "field-test",
           let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
           let link = URL(string: inner) {
            return received(link)
        }
        #endif
        let now = inbox.received(url)
        Self.log.notice("received \(url), \(now.isEmpty ? "waiting" : "opening", privacy: .public)")
        take(now)
    }

    /// `-FieldIncoming <url>`: for the UI tests, what no app can send (a
    /// javascript: link), through the same door as onOpenURL.
    func receiveFromLaunchArguments() {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard let raw = arguments["FieldIncoming"] as? String, let url = URL(string: raw) else { return }
        received(url)
    }

    /// Browser.start: the session is back.
    func restored() { take(inbox.restored()) }

    func welcome(showing: Bool) { take(inbox.welcome(showing: showing)) }

    private func take(_ urls: [URL]) {
        due += urls
        guard opening == nil, !due.isEmpty else { return }
        opening = Task { await openDue() }
    }

    /// Links that come meanwhile join the end.
    private func openDue() async {
        // At launch the rules are a few milliseconds behind the first frame.
        let cleaning = await Guarded.loaded()
        while !due.isEmpty {
            let url = due.removeFirst()
            let shield = ContentBlocking.shared.isShieldOn(for: url.host())
            switch IncomingLink.accept(url, cleaning: cleaning, shieldOn: shield) {
            case .success(let clean): open(clean)
            case .failure(let rejection): announce(Self.sentence(rejection))
            }
        }
        opening = nil
    }

    static func sentence(_ rejection: IncomingLink.Rejection) -> String {
        switch rejection {
        case .notWeb: "Field opens only web links."
        case .credentials: "Didn't open a link with a password in it."
        case .malformed: "That link has no address to open."
        }
    }
}
