import UIKit
import UniformTypeIdentifiers

/// Field's own copies from Private: this phone only (never Universal
/// Clipboard to your other devices), gone after a couple of minutes, and
/// gone with the wipe unless something else was copied since. What the
/// page's own Copy puts there is iOS's, and the limits screen says so.
@MainActor enum PrivatePasteboard {
    static let lifetime: TimeInterval = 120
    /// The pasteboard's count when Private last copied, to know it's still ours.
    private static var ours: Int?

    static func options(now: Date = .now) -> [UIPasteboard.OptionsKey: Any] {
        [.localOnly: true, .expirationDate: now.addingTimeInterval(lifetime)]
    }

    /// A page's address, stripped of tracking as an everyday copy is.
    static func copy(_ url: URL) {
        let clean = Guarded.stripped(url)
        let board = UIPasteboard.general
        board.setItems([[UTType.url.identifier: clean, UTType.utf8PlainText.identifier: clean.absoluteString]], options: options())
        ours = board.changeCount
    }

    static func forget() {
        let board = UIPasteboard.general
        defer { ours = nil }
        guard let ours, board.changeCount == ours else { return }
        board.setItems([])
    }
}

/// What Field hands the phone about a page. For a private one, nothing:
/// no Handoff, Spotlight, Siri suggestions or widgets, and notifications
/// that don't say what they're about.
enum Hygiene {
    /// Nil for a private page. An everyday page's is Handoff only.
    static func activity(for url: URL, title: String, isPrivate: Bool) -> NSUserActivity? {
        guard !isPrivate else { return nil }
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = false
        return activity
    }

    static func notificationText(_ text: String, isPrivate: Bool) -> String {
        isPrivate ? "Field has something for you." : text
    }
}
