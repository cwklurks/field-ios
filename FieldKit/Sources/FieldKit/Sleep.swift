// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

// Tabs you aren't using, put to sleep.
//
// A page keeps its whole content process, a hundred megabytes or more, for as
// long as its web view exists, and iOS kills the app long before a Mac would
// start to swap. So only the tab on screen and the couple used just before it
// keep theirs. The others keep what it takes to come back where they were
// (their interaction state and a picture), and give the rest back.
//
// A tab that's doing something waking couldn't give back (playing sound, on
// a call) is held awake, whatever the count says.

public enum Sleep {
    /// Awake besides the one on screen, when memory isn't short.
    public static let recent = 2

    public enum Pressure: Sendable {
        case normal
        /// iOS said memory is short: only the tab on screen stays.
        case warning
    }

    public struct Tab: Sendable {
        public var id: UUID
        /// When it was last on screen.
        public var seen: Date
        /// Has a web view.
        public var awake: Bool
        /// Can't sleep now, whatever the count says.
        public var held: Bool

        public init(id: UUID, seen: Date, awake: Bool, held: Bool = false) {
            self.id = id
            self.seen = seen
            self.awake = awake
            self.held = held
        }
    }

    /// The tabs to put to sleep, the one left longest first.
    public static func toSleep(_ tabs: [Tab], active: UUID, pressure: Pressure) -> [UUID] {
        let keep = pressure == .warning ? 0 : recent
        let candidates = tabs
            .filter { $0.awake && !$0.held && $0.id != active }
            .sorted { $0.seen > $1.seen }
        return candidates.dropFirst(keep).reversed().map(\.id)
    }
}
