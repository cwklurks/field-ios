import Foundation

/// Links from other apps, held until the browser can take them: the session
/// restored and the first-run welcome done. A link at a cold launch waits
/// for both, so it never races the restore or lands on the tab being put
/// back; several open in the order they came.
public struct LinkInbox: Equatable, Sendable {
    public private(set) var waiting: [URL] = []
    private var isRestored = false
    private var welcoming = false

    public init() {}

    private var ready: Bool { isRestored && !welcoming }

    /// A link has come. What to open now: it, or nothing yet.
    public mutating func received(_ url: URL) -> [URL] {
        waiting.append(url)
        return release()
    }

    /// The session is back and the browser has started.
    public mutating func restored() -> [URL] {
        isRestored = true
        return release()
    }

    /// The first-run welcome came up, or went. What to open now.
    @discardableResult
    public mutating func welcome(showing: Bool) -> [URL] {
        welcoming = showing
        return release()
    }

    private mutating func release() -> [URL] {
        guard ready else { return [] }
        defer { waiting = [] }
        return waiting
    }
}

/// Where a link from another app opens: always a tab of your own, never
/// Private's, whatever is on screen when it comes
/// (docs/research/switching-and-supporter.md, "Does Field qualify?").
public struct LinkRoute: Equatable, Sendable {
    /// What's on screen when it comes.
    public enum Side: Sendable {
        case everyday
        /// Private, with nothing over it.
        case privateShown
        /// Private under its shade: locked, the switcher's cover, or hidden
        /// from a recording.
        case privateCovered
    }

    public enum Leave: Sendable {
        /// Already on your tabs.
        case stay
        /// Private's switch, sliding back.
        case slide
        /// Your tabs put in place under the shade, which then fades: nothing
        /// private shows, and the lock stays as it was.
        case underShade
    }

    public enum Into: Sendable {
        /// The blank tab on screen: nothing there to lose.
        case blankTab
        case newTab
    }

    public enum Grid: Sendable {
        case none
        /// The grid gives way to the new tab, as when a card is chosen.
        case close
        /// Off screen, so at once, before your tabs come into view.
        case closeAtOnce
    }

    public let leave: Leave
    public let into: Into
    /// The field closes as Cancel closes it; its page is untouched.
    public let closeField: Bool
    public let grid: Grid

    public init(leave: Leave, into: Into, closeField: Bool, grid: Grid) {
        self.leave = leave
        self.into = into
        self.closeField = closeField
        self.grid = grid
    }

    /// `gridShown` and `currentBlank` are about your tabs, wherever you are.
    public init(side: Side, fieldOpen: Bool, gridShown: Bool, currentBlank: Bool) {
        leave = switch side {
        case .everyday: .stay
        case .privateShown: .slide
        case .privateCovered: .underShade
        }
        into = currentBlank ? .blankTab : .newTab
        closeField = fieldOpen
        grid = !gridShown ? .none : side == .everyday ? .close : .closeAtOnce
    }
}
