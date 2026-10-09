import Foundation

// Private's lock, as a pure state machine the app feeds with what happens
// (the scene coming and going, the person entering and leaving the space,
// Face ID's answer) and asks two things of: what should cover the screen,
// and whether to wipe or ask for Face ID now.
//
// It locks the moment you leave: the app, or the space for your everyday
// tabs. The app switcher's live card is covered as soon as the app stops
// being in front, but that alone doesn't lock, so a glance at Control
// Center costs nothing. The lock only hides what's in memory; "wipe
// instead" throws it away, and so does a phone with no passcode, where
// nothing could unlock it again.
//
// The Face ID prompt resigns the app while it's up and hands it back when
// it goes, in either order with its answer. While unlocking, neither counts
// as leaving, so the prompt can never lock the space again or ask twice.

public struct PrivateLock: Equatable, Sendable {
    /// What leaving does to a space with pages in it.
    public enum Away: String, CaseIterable, Sendable {
        case lock, wipe
    }

    public enum State: Equatable, Sendable {
        case open
        case locked
        /// Face ID is asking.
        case unlocking
    }

    /// What lies over Private, when the person is in it.
    public enum Shade: Equatable, Sendable {
        case none
        /// The app isn't in front: the switcher's card and its snapshot.
        case cover
        /// Unlock to see it.
        case locked
        /// The screen is being recorded, mirrored or AirPlayed.
        case captured
    }

    public enum Event: Equatable, Sendable {
        /// Into Private, from the everyday tabs.
        case entered
        /// Back to the everyday tabs.
        case left
        /// The scene will stop being active: the switcher, Control Center,
        /// a call, or Face ID's own prompt.
        case resigned
        case backgrounded
        case activated
        case captured(Bool)
        case unlockTapped
        /// Face ID's answer.
        case unlocked(Bool)
        /// The app has wiped the space.
        case wiped
    }

    public enum Action: Equatable, Sendable {
        case wipe
        case authenticate
    }

    public var away: Away
    /// Seconds away from the space before it's wiped; nil for never.
    public var wipeAfter: TimeInterval?
    /// The phone has a passcode, so Face ID or the passcode can unlock.
    public var canLock: Bool
    /// The space has a page in it, worth hiding. Kept up to date by the app.
    public var holding = false

    public private(set) var state = State.open
    public private(set) var inside = false
    public private(set) var active = true
    public private(set) var capturing = false
    /// When the space was last left open, in memory only.
    private var leftAt: Date?

    public init(away: Away = .lock, wipeAfter: TimeInterval? = nil, canLock: Bool = true) {
        self.away = away
        self.wipeAfter = wipeAfter
        self.canLock = canLock
    }

    public var shade: Shade {
        guard inside else { return .none }
        if state != .open { return .locked }
        if !active { return .cover }
        return capturing ? .captured : .none
    }

    public mutating func handle(_ event: Event, now: Date) -> Action? {
        switch event {
        case .entered:
            inside = true
            return overdue(now)
        case .left:
            inside = false
            // Leaving mid-prompt revokes that attempt, just like backgrounding.
            if state == .unlocking { state = .locked }
            return leave(now)
        case .resigned:
            active = false
            return nil
        case .backgrounded:
            active = false
            // Face ID's prompt is cancelled on the way out.
            if state == .unlocking { state = .locked }
            return inside ? leave(now) : nil
        case .activated:
            active = true
            // The prompt going away; its answer settles it.
            if state == .unlocking { return nil }
            return overdue(now)
        case .captured(let on):
            capturing = on
            return nil
        case .unlockTapped:
            guard inside, state == .locked else { return nil }
            state = .unlocking
            return .authenticate
        case .unlocked(let yes):
            // A late answer, after leaving mid-prompt, opens nothing.
            guard state == .unlocking else { return nil }
            state = yes ? .open : .locked
            if yes { leftAt = nil }
            return nil
        case .wiped:
            state = .open
            holding = false
            leftAt = nil
            return nil
        }
    }

    /// The person has gone, from the app or the space.
    private mutating func leave(_ now: Date) -> Action? {
        guard holding, state == .open else { return nil }
        leftAt = now
        if away == .wipe || !canLock { return .wipe }
        state = .locked
        return nil
    }

    /// Away longer than the person allows: gone, whether they're back in
    /// Private or only back in the app.
    private mutating func overdue(_ now: Date) -> Action? {
        guard holding, let wipeAfter, let leftAt, now.timeIntervalSince(leftAt) >= wipeAfter else { return nil }
        self.leftAt = nil
        return .wipe
    }
}

/// How a private space is thrown away, in this order: nothing may still
/// hold the store when its data goes, and the files go last, once nothing
/// is left that could write another.
public enum PrivateWipe {
    public enum Step: CaseIterable, Sendable {
        /// Every private web view closed and released.
        case webViews
        /// `removeData` for every type, from the beginning of time.
        case websiteData
        /// The data store itself let go.
        case store
        /// The tab list, its pictures and its closed tabs.
        case tabs
        /// Uploads and downloads in tmp.
        case files
    }

    public static let order: [Step] = [.webViews, .websiteData, .store, .tabs, .files]
}
