import Foundation
import Testing
@testable import FieldKit

// When links from other apps open, and where (docs/research/switching-and-supporter.md,
// "Does Field qualify?"): never before the session is back and the welcome
// is done, always in order, and always in a tab of your own.
struct LinkInboxTests {
    static let a = URL(string: "https://a.example/")!
    static let b = URL(string: "https://b.example/")!
    static let c = URL(string: "https://c.example/")!

    // MARK: - When

    @Test func aLinkAtLaunchWaitsForTheRestore() {
        var inbox = LinkInbox()
        #expect(inbox.received(Self.a) == [])
        #expect(inbox.waiting == [Self.a])
        #expect(inbox.restored() == [Self.a])
        #expect(inbox.waiting == [])
    }

    @Test func linksAtLaunchOpenInTheOrderTheyCame() {
        var inbox = LinkInbox()
        _ = inbox.received(Self.a)
        _ = inbox.received(Self.b)
        _ = inbox.received(Self.c)
        #expect(inbox.restored() == [Self.a, Self.b, Self.c])
    }

    @Test func theFirstRunWelcomeHoldsThemUntilItIsDone() {
        var inbox = LinkInbox()
        inbox.welcome(showing: true)
        _ = inbox.received(Self.a)
        #expect(inbox.restored() == [])
        _ = inbox.received(Self.b)
        #expect(inbox.welcome(showing: false) == [Self.a, Self.b])
    }

    @Test func aWelcomeDoneBeforeTheRestoreStillWaitsForIt() {
        var inbox = LinkInbox()
        inbox.welcome(showing: true)
        _ = inbox.received(Self.a)
        #expect(inbox.welcome(showing: false) == [])
        #expect(inbox.restored() == [Self.a])
    }

    @Test func onceReadyEachOpensAsItComes() {
        var inbox = LinkInbox()
        #expect(inbox.restored() == [])
        #expect(inbox.received(Self.a) == [Self.a])
        #expect(inbox.received(Self.b) == [Self.b])
        #expect(inbox.waiting == [])
    }

    @Test func aSecondRestoreReleasesNothingTwice() {
        var inbox = LinkInbox()
        _ = inbox.received(Self.a)
        #expect(inbox.restored() == [Self.a])
        #expect(inbox.restored() == [])
    }

    // MARK: - Where

    @Test func onYourTabsANewTabOpens() {
        let route = LinkRoute(side: .everyday, fieldOpen: false, gridShown: false, currentBlank: false)
        #expect(route == LinkRoute(leave: .stay, into: .newTab, closeField: false, grid: .none))
    }

    /// A blank tab has nothing to lose, so the link takes it rather than
    /// leaving an empty tab behind, as Go would from its field.
    @Test func aBlankTabIsUsedRatherThanLeftEmpty() {
        let route = LinkRoute(side: .everyday, fieldOpen: true, gridShown: false, currentBlank: true)
        #expect(route.into == .blankTab)
        #expect(route.closeField)
    }

    /// The field closes as Cancel closes it; the tab under it keeps its page.
    @Test func anOpenFieldClosesOverAPage() {
        let route = LinkRoute(side: .everyday, fieldOpen: true, gridShown: false, currentBlank: false)
        #expect(route.into == .newTab)
        #expect(route.closeField)
    }

    @Test func theGridGivesWayToTheNewTab() {
        let route = LinkRoute(side: .everyday, fieldOpen: false, gridShown: true, currentBlank: false)
        #expect(route.grid == .close)
    }

    /// Private in view, nothing over it: back to your tabs with the switch's
    /// own slide, your side made ready first while it's off screen.
    @Test func fromAnOpenPrivateItSlidesBack() {
        let route = LinkRoute(side: .privateShown, fieldOpen: true, gridShown: true, currentBlank: false)
        #expect(route.leave == .slide)
        #expect(route.into == .newTab)
        #expect(route.closeField)
        #expect(route.grid == .closeAtOnce)
    }

    /// Locked (or covered): the private tabs never show. Your side is put in
    /// place under the shade, which then fades.
    @Test func fromALockedPrivateItChangesUnderTheShade() {
        let route = LinkRoute(side: .privateCovered, fieldOpen: false, gridShown: true, currentBlank: true)
        #expect(route.leave == .underShade)
        #expect(route.into == .blankTab)
        #expect(route.grid == .closeAtOnce)
    }

    @Test func noRouteEverStaysInPrivate() {
        for side in [LinkRoute.Side.privateShown, .privateCovered] {
            for field in [false, true] {
                for grid in [false, true] {
                    for blank in [false, true] {
                        let route = LinkRoute(side: side, fieldOpen: field, gridShown: grid, currentBlank: blank)
                        #expect(route.leave != .stay)
                    }
                }
            }
        }
    }
}
