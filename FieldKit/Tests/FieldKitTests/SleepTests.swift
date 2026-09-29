import Foundation
import Testing
@testable import FieldKit

/// Which tabs keep their web view: the one on screen and the few used most
/// recently. The rest sleep, the one left longest first, and a memory warning
/// puts all but the one on screen to sleep.
struct SleepTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let ids = (0..<8).map { _ in UUID() }

    /// Tab i, awake, last seen i minutes ago.
    func tab(_ i: Int, awake: Bool = true, held: Bool = false) -> Sleep.Tab {
        Sleep.Tab(id: ids[i], seen: now.addingTimeInterval(-Double(i) * 60), awake: awake, held: held)
    }

    @Test func theActiveTabAndTheMostRecentStayAwake() {
        let tabs = (0..<6).map { tab($0) }
        let asleep = Sleep.toSleep(tabs, active: ids[0], pressure: .normal)
        // The active one plus the next Sleep.recent.
        #expect(Sleep.recent == 2)
        #expect(asleep == [ids[5], ids[4], ids[3]])
    }

    /// Recency is when a tab was last seen, not where it sits in the list.
    @Test func theActiveTabNeverSleepsEvenIfItWasSeenLongestAgo() {
        let tabs = (0..<5).map { tab($0) }
        let asleep = Sleep.toSleep(tabs, active: ids[4], pressure: .normal)
        #expect(!asleep.contains(ids[4]))
        #expect(asleep == [ids[3], ids[2]])
    }

    @Test func aMemoryWarningLeavesOnlyTheActiveTab() {
        let tabs = (0..<4).map { tab($0) }
        let asleep = Sleep.toSleep(tabs, active: ids[1], pressure: .warning)
        #expect(asleep == [ids[3], ids[2], ids[0]])
    }

    /// A tab playing sound or on a call can't be woken back into doing it, so
    /// it stays awake, and doesn't take one of the recent places either.
    @Test func aHeldTabStaysAwakeOutsideTheCount() {
        let tabs = [tab(0), tab(1), tab(2), tab(3, held: true), tab(4)]
        let asleep = Sleep.toSleep(tabs, active: ids[0], pressure: .normal)
        #expect(asleep == [ids[4]])
        let warned = Sleep.toSleep(tabs, active: ids[0], pressure: .warning)
        #expect(warned == [ids[4], ids[2], ids[1]])
    }

    @Test func tabsAlreadyAsleepAreLeftAlone() {
        // Sleeping tabs neither sleep again nor take a recent place.
        let tabs = [tab(0), tab(1, awake: false), tab(2), tab(3), tab(4, awake: false), tab(5)]
        let asleep = Sleep.toSleep(tabs, active: ids[0], pressure: .normal)
        #expect(asleep == [ids[5]])
    }

    @Test func fewTabsMeansNoSleep() {
        #expect(Sleep.toSleep([tab(0), tab(1)], active: ids[0], pressure: .normal).isEmpty)
        #expect(Sleep.toSleep([], active: ids[0], pressure: .warning).isEmpty)
    }
}
