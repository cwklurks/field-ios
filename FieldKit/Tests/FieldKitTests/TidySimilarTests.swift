import Foundation
import Testing
@testable import FieldKit

/// "Add similar tabs": given a group the person made or kept, which loose
/// tabs belong with it. Firefox found this beats grouping from nothing.
struct TidySimilarTests {
    static let id = TidyTests.id

    func tab(_ n: Int, _ title: String, _ url: String) -> TabInfo {
        TabInfo(id: Self.id(n), title: title, url: URL(string: url)!)
    }

    func similar(_ members: [TabInfo], _ candidates: [TabInfo]) -> [UUID] {
        Tidy.similar(to: members, among: candidates, embed: TidyTests.embed, site: TidyTests.site)
    }

    @Test func findsTabsAboutTheSameThing() {
        let group = [tab(1, "Flights to Lisbon", "https://a.com/"), tab(2, "Lisbon hotel", "https://b.com/")]
        let loose = [
            tab(3, "Sourdough recipe", "https://c.com/"),
            tab(4, "Lisbon trip ideas", "https://d.com/"),
            tab(5, "Swift testing", "https://e.com/"),
        ]
        #expect(similar(group, loose) == [Self.id(4)])
    }

    /// A site most of the group is on counts, whatever the title says.
    @Test func findsTheGroupsSite() {
        let group = [tab(1, "Swift repo", "https://github.com/a"), tab(2, "Swift issues", "https://github.com/b")]
        let loose = [tab(3, "Pull request", "https://github.com/c"), tab(4, "Lisbon weather", "https://weather.com/")]
        #expect(similar(group, loose) == [Self.id(3)])
    }

    /// One tab of three on a site doesn't make the site the group's.
    @Test func aStraySiteDoesNotCount() {
        let group = [
            tab(1, "Lisbon flights", "https://google.com/flights"),
            tab(2, "Lisbon hotel", "https://a.com/"),
            tab(3, "Lisbon trip", "https://b.com/"),
        ]
        let loose = [tab(4, "Weather", "https://google.com/weather")]
        #expect(similar(group, loose).isEmpty)
    }

    @Test func neverOffersAMember() {
        let group = [tab(1, "Lisbon flights", "https://a.com/"), tab(2, "Lisbon hotel", "https://b.com/")]
        #expect(similar(group, group + [tab(3, "Lisbon trip", "https://c.com/")]) == [Self.id(3)])
    }

    @Test func anEmptyGroupFindsNothing() {
        #expect(similar([], [tab(1, "Lisbon", "https://a.com/")]).isEmpty)
    }
}
