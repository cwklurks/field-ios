import Foundation

/// What a navigation may do, until M3's guard takes over.
enum Opening {
    enum Decision: Equatable {
        /// Load it where it asked to go.
        case allow
        /// A link that asked for a new window. One tab until M2, so here.
        case sameTab
        /// A window a script opened: a popup.
        case block
        /// A scheme Field doesn't open (mail, phone, the App Store) yet.
        case ignore
    }

    static let schemes: Set<String> = ["http", "https", "about", "data", "blob"]

    static func decide(_ url: URL?, newWindow: Bool, byLink: Bool) -> Decision {
        guard let scheme = url?.scheme?.lowercased(), schemes.contains(scheme) else { return .ignore }
        guard newWindow else { return .allow }
        return byLink ? .sameTab : .block
    }
}
