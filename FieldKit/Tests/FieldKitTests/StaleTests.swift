import Foundation
import Testing
@testable import FieldKit

/// Stale tabs, by rule and never by a model: tabs not looked at for two
/// weeks (or however long the setting says), and second copies of an
/// address. The grid offers them in a quiet banner; nothing closes itself.
struct StaleTests {
    static let id = TidyTests.id
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func tab(_ n: Int, _ url: String, title: String = "", daysAgo: Double?) -> Stale.Tab {
        Stale.Tab(id: Self.id(n), url: url, title: title, viewed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) })
    }

    func find(_ tabs: [Stale.Tab], current: Int? = nil, days: Int = 14) -> Stale.Found {
        Stale.find(tabs, current: current.map(Self.id), now: now, days: days)
    }

    // MARK: - untouched

    @Test func untouchedForTheWholeSpan() {
        let found = find([
            tab(1, "https://a.com/", daysAgo: 20),
            tab(2, "https://b.com/", daysAgo: 14),
            tab(3, "https://c.com/", daysAgo: 13.9),
        ])
        #expect(found.untouched == [Self.id(1), Self.id(2)])
        #expect(found.duplicates.isEmpty)
    }

    @Test func theSpanIsASetting() {
        let found = find([tab(1, "https://a.com/", daysAgo: 8), tab(2, "https://b.com/", daysAgo: 6)], days: 7)
        #expect(found.untouched == [Self.id(1)])
    }

    /// The one on screen is being looked at, however old its date.
    @Test func theCurrentTabIsNeverStale() {
        let found = find([tab(1, "https://a.com/", daysAgo: 30), tab(2, "https://a.com/", daysAgo: 1)], current: 1)
        #expect(found.untouched.isEmpty)
        #expect(found.duplicates == [Self.id(2)])
    }

    /// A tab from before Field kept dates hasn't been timed yet: not stale.
    @Test func noDateIsNotStale() {
        #expect(find([tab(1, "https://a.com/", daysAgo: nil)]).isEmpty)
    }

    // MARK: - duplicates

    /// The copy looked at last stays; the others are offered.
    @Test func duplicatesKeepTheLatestCopy() {
        let found = find([
            tab(1, "https://a.com/x", daysAgo: 3),
            tab(2, "https://a.com/x", daysAgo: 1),
            tab(3, "https://a.com/x", daysAgo: 2),
            tab(4, "https://a.com/y", daysAgo: 1),
        ])
        #expect(found.duplicates == [Self.id(1), Self.id(3)])
    }

    /// Only the fragment differs: the same page.
    @Test func aFragmentIsTheSamePage() {
        let found = find([tab(1, "https://a.com/x#top", daysAgo: 2), tab(2, "https://a.com/x", daysAgo: 1)])
        #expect(found.duplicates == [Self.id(1)])
    }

    /// On a hash-routed app the fragment is the page.
    @Test func routedFragmentsAreDifferentPages() {
        let mail = find([
            tab(1, "https://mail.google.com/mail/u/0/#inbox", title: "Inbox", daysAgo: 2),
            tab(2, "https://mail.google.com/mail/u/0/#drafts", title: "Drafts", daysAgo: 1),
        ])
        #expect(mail.duplicates.isEmpty)
        let app = find([
            tab(1, "https://a.com/app#/settings", daysAgo: 2),
            tab(2, "https://a.com/app#/profile", daysAgo: 1),
            tab(3, "https://a.com/app#!/x", daysAgo: 1),
            tab(4, "https://a.com/app", daysAgo: 1),
        ])
        #expect(app.duplicates.isEmpty)
        let same = find([tab(1, "https://a.com/app#/inbox", daysAgo: 2), tab(2, "https://a.com/app#/inbox", daysAgo: 1)])
        #expect(same.duplicates == [Self.id(1)])
    }

    /// Anchors within one page, under one title, are the one page.
    @Test func anchorsUnderOneTitleAreTheSamePage() {
        let found = find([
            tab(1, "https://a.com/docs#intro", title: "Docs", daysAgo: 2),
            tab(2, "https://a.com/docs#usage", title: "Docs", daysAgo: 1),
        ])
        #expect(found.duplicates == [Self.id(1)])
    }

    @Test func anchorsUnderDifferentTitlesAreDifferentPages() {
        let found = find([
            tab(1, "https://a.com/docs#intro", title: "Intro", daysAgo: 2),
            tab(2, "https://a.com/docs#usage", title: "Usage", daysAgo: 1),
            tab(3, "https://a.com/docs", title: "Docs", daysAgo: 1),
        ])
        #expect(found.duplicates.isEmpty)
    }

    /// A page whose title changed is still the one address.
    @Test func theSameAddressIsADuplicateWhateverTheTitle() {
        let found = find([tab(1, "https://a.com/x", title: "Loading", daysAgo: 2), tab(2, "https://a.com/x", title: "X", daysAgo: 1)])
        #expect(found.duplicates == [Self.id(1)])
    }

    @Test func schemeHostAndDefaultPortAreNormalised() {
        let found = find([
            tab(1, "HTTPS://Example.com:443/", daysAgo: 2),
            tab(2, "https://example.com", daysAgo: 1),
            tab(3, "http://example.com:80/x", daysAgo: 2),
            tab(4, "http://EXAMPLE.com/x", daysAgo: 1),
            tab(5, "https://example.com:8443/", daysAgo: 1),
        ])
        #expect(found.duplicates == [Self.id(1), Self.id(3)])
    }

    @Test func trackingParametersAreIgnored() {
        let found = find([
            tab(1, "https://a.com/x?id=7&utm_source=news", daysAgo: 2),
            tab(2, "https://a.com/x?id=7", daysAgo: 1),
            tab(3, "https://a.com/x?id=8", daysAgo: 1),
        ])
        #expect(found.duplicates == [Self.id(1)])
    }

    @Test func blankTabsAreNotDuplicates() {
        #expect(find([tab(1, "", daysAgo: 1), tab(2, "", daysAgo: 1)]).isEmpty)
    }

    /// A tab both old and a copy is counted once.
    @Test func allCountsEachTabOnce() {
        let found = find([tab(1, "https://a.com/", daysAgo: 30), tab(2, "https://a.com/", daysAgo: 1)])
        #expect(found.untouched == [Self.id(1)])
        #expect(found.duplicates == [Self.id(1)])
        #expect(found.all == [Self.id(1)])
    }

    // MARK: - the banner's line

    @Test func lines() {
        let untouched = Stale.Found(untouched: (1...12).map(Self.id), duplicates: [])
        #expect(Stale.line(untouched, days: 14) == "12 tabs untouched for 2 weeks")
        #expect(Stale.line(Stale.Found(untouched: [Self.id(1)], duplicates: []), days: 7) == "1 tab untouched for a week")
        #expect(Stale.line(Stale.Found(untouched: [Self.id(1), Self.id(2)], duplicates: []), days: 10) == "2 tabs untouched for 10 days")
        #expect(Stale.line(Stale.Found(untouched: [], duplicates: [Self.id(1)]), days: 14) == "1 duplicate tab")
        #expect(Stale.line(Stale.Found(untouched: [], duplicates: [Self.id(1), Self.id(2)]), days: 14) == "2 duplicate tabs")
        let both = Stale.Found(untouched: (1...12).map(Self.id), duplicates: [Self.id(20), Self.id(21), Self.id(22)])
        #expect(Stale.line(both, days: 14) == "12 tabs untouched for 2 weeks, 3 duplicates")
        #expect(Stale.line(Stale.Found(untouched: [], duplicates: []), days: 14) == nil)
    }
}
