import Foundation
import Testing
@testable import FieldKit

/// Private's lock: shut the moment you leave the app or the space, covered
/// whenever the app isn't in front, open again only through Face ID, and
/// never caught in a loop by the Face ID prompt's own coming and going.
struct PrivateLockTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Inside Private, with a page open, the app in front.
    func inside(_ away: PrivateLock.Away = .lock, wipeAfter: TimeInterval? = nil, canLock: Bool = true) -> PrivateLock {
        var lock = PrivateLock(away: away, wipeAfter: wipeAfter, canLock: canLock)
        lock.holding = true
        #expect(lock.handle(.entered, now: now) == nil)
        return lock
    }

    func later(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }

    @Test func openInsideShowsThePage() {
        let lock = inside()
        #expect(lock.state == .open)
        #expect(lock.shade == .none)
    }

    /// The app switcher's live card: covered, not locked, and back as it was.
    @Test func theSwitcherCoversWithoutLocking() {
        var lock = inside()
        #expect(lock.handle(.resigned, now: now) == nil)
        #expect(lock.shade == .cover)
        #expect(lock.state == .open)
        #expect(lock.handle(.activated, now: later(2)) == nil)
        #expect(lock.shade == .none)
    }

    @Test func leavingTheAppLocksAtOnce() {
        var lock = inside()
        _ = lock.handle(.resigned, now: now)
        #expect(lock.handle(.backgrounded, now: now) == nil)
        #expect(lock.state == .locked)
        #expect(lock.shade == .locked)
        #expect(lock.handle(.activated, now: later(1)) == nil)
        #expect(lock.shade == .locked)
    }

    @Test func leavingTheSpaceLocksItToo() {
        var lock = inside()
        #expect(lock.handle(.left, now: now) == nil)
        #expect(lock.state == .locked)
        // Nothing covers the everyday tabs.
        #expect(lock.shade == .none)
        #expect(lock.handle(.entered, now: later(5)) == nil)
        #expect(lock.shade == .locked)
    }

    /// An empty space has nothing to hide: no lock, no wipe.
    @Test func nothingOpenNothingLocked() {
        var lock = inside()
        lock.holding = false
        #expect(lock.handle(.backgrounded, now: now) == nil)
        #expect(lock.state == .open)
    }

    @Test func unlockingTakesFaceID() {
        var lock = inside()
        _ = lock.handle(.backgrounded, now: now)
        _ = lock.handle(.activated, now: later(1))
        #expect(lock.handle(.unlockTapped, now: later(2)) == .authenticate)
        #expect(lock.state == .unlocking)
        #expect(lock.handle(.unlocked(true), now: later(3)) == nil)
        #expect(lock.state == .open)
        #expect(lock.shade == .none)
    }

    /// The Face ID prompt resigns the app and hands it back. Neither may
    /// cover, lock or ask again, whichever order the answer comes in.
    @Test func theFaceIDPromptNeverLoops() {
        for answerFirst in [true, false] {
            var lock = inside()
            _ = lock.handle(.backgrounded, now: now)
            _ = lock.handle(.activated, now: later(1))
            var actions = [lock.handle(.unlockTapped, now: later(2))]
            actions.append(lock.handle(.resigned, now: later(2)))
            #expect(lock.shade == .locked)
            if answerFirst {
                actions.append(lock.handle(.unlocked(true), now: later(3)))
                actions.append(lock.handle(.activated, now: later(3)))
            } else {
                actions.append(lock.handle(.activated, now: later(3)))
                #expect(lock.state == .unlocking)
                actions.append(lock.handle(.unlocked(true), now: later(3)))
            }
            #expect(actions.compactMap { $0 } == [.authenticate])
            #expect(lock.state == .open)
            #expect(lock.shade == .none)
        }
    }

    @Test func aFailedUnlockStaysLockedAndAsksOnlyWhenTapped() {
        var lock = inside()
        _ = lock.handle(.backgrounded, now: now)
        _ = lock.handle(.activated, now: later(1))
        _ = lock.handle(.unlockTapped, now: later(2))
        _ = lock.handle(.resigned, now: later(2))
        #expect(lock.handle(.unlocked(false), now: later(3)) == nil)
        #expect(lock.handle(.activated, now: later(3)) == nil)
        #expect(lock.state == .locked)
        #expect(lock.handle(.unlockTapped, now: later(4)) == .authenticate)
    }

    /// Going home with the prompt up cancels it; a late yes doesn't open.
    @Test func leavingMidPromptStaysLocked() {
        var lock = inside()
        _ = lock.handle(.backgrounded, now: now)
        _ = lock.handle(.activated, now: later(1))
        _ = lock.handle(.unlockTapped, now: later(2))
        _ = lock.handle(.backgrounded, now: later(3))
        #expect(lock.state == .locked)
        #expect(lock.handle(.unlocked(true), now: later(4)) == nil)
        #expect(lock.state == .locked)
    }

    @Test func wipeInsteadOfLock() {
        var lock = inside(.wipe)
        #expect(lock.handle(.backgrounded, now: now) == .wipe)
        _ = lock.handle(.wiped, now: now)
        #expect(lock.state == .open)
        #expect(!lock.holding)

        var leaving = inside(.wipe)
        #expect(leaving.handle(.left, now: now) == .wipe)
    }

    /// No passcode on the phone, so nothing could unlock it: wiped instead.
    @Test func withoutAPasscodeItWipes() {
        var lock = inside(canLock: false)
        #expect(lock.handle(.backgrounded, now: now) == .wipe)
    }

    @Test func wipedAfterMinutesAway() {
        var lock = inside(wipeAfter: 300)
        _ = lock.handle(.backgrounded, now: now)
        #expect(lock.handle(.activated, now: later(299)) == nil)
        _ = lock.handle(.backgrounded, now: later(300))
        #expect(lock.handle(.activated, now: later(300 + 301)) == .wipe)
    }

    /// Away counts from leaving the space, even with the app in front.
    @Test func wipedAfterMinutesInTheEverydayTabs() {
        var lock = inside(wipeAfter: 60)
        _ = lock.handle(.left, now: now)
        #expect(lock.handle(.entered, now: later(30)) == nil)
        _ = lock.handle(.left, now: later(30))
        #expect(lock.handle(.entered, now: later(30 + 61)) == .wipe)
        #expect(lock.handle(.activated, now: later(200)) == nil)
    }

    @Test func unlockingResetsTheClock() {
        var lock = inside(wipeAfter: 60)
        _ = lock.handle(.backgrounded, now: now)
        _ = lock.handle(.activated, now: later(10))
        _ = lock.handle(.unlockTapped, now: later(10))
        _ = lock.handle(.unlocked(true), now: later(11))
        _ = lock.handle(.resigned, now: later(100))
        #expect(lock.handle(.activated, now: later(100)) == nil)
    }

    /// Recording or mirroring blanks an open space; a lock or cover wins.
    @Test func captureBlanksOnlyInside() {
        var lock = inside()
        _ = lock.handle(.captured(true), now: now)
        #expect(lock.shade == .captured)
        _ = lock.handle(.resigned, now: now)
        #expect(lock.shade == .cover)
        _ = lock.handle(.activated, now: now)
        _ = lock.handle(.left, now: now)
        #expect(lock.shade == .none)
        _ = lock.handle(.captured(false), now: now)
        _ = lock.handle(.entered, now: now)
        #expect(lock.shade == .locked)
    }

    /// Only a locked space asks.
    @Test func unlockTappedWhenOpenDoesNothing() {
        var lock = inside()
        #expect(lock.handle(.unlockTapped, now: now) == nil)
        #expect(lock.state == .open)
    }

    @Test func leavingDuringAuthenticationIgnoresItsLateSuccess() {
        var lock = inside()
        _ = lock.handle(.backgrounded, now: now)
        _ = lock.handle(.activated, now: later(1))
        _ = lock.handle(.unlockTapped, now: later(2))
        _ = lock.handle(.left, now: later(3))
        _ = lock.handle(.unlocked(true), now: later(4))
        #expect(lock.state == .locked)
        _ = lock.handle(.entered, now: later(5))
        #expect(lock.shade == .locked)
    }
    @Test func anUnlockTapAfterLeavingCannotStartAuthentication() {
        var lock = inside()
        _ = lock.handle(.left, now: now)
        #expect(lock.handle(.unlockTapped, now: later(1)) == nil)
        #expect(lock.state == .locked)
    }

}

/// The wipe's order: nothing may still hold the store when its data goes,
/// and the files go last, once nothing can write another.
struct PrivateWipeTests {
    @Test func order() {
        #expect(PrivateWipe.order == [.webViews, .websiteData, .store, .tabs, .files])
        #expect(Set(PrivateWipe.order).count == PrivateWipe.Step.allCases.count)
    }
}
