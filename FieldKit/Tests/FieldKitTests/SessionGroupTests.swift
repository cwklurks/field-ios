import Foundation
import Testing
@testable import FieldKit

/// Tab groups in session.json: a list of named groups, a `group` on each tab
/// that's in one, and when each tab was last looked at (for stale tabs).
/// Older files have none of it and read as they always did.
struct SessionGroupTests {
    static let id = TidyTests.id

    func entry(_ n: Int, group: Int? = nil) -> Session.Entry {
        Session.Entry(id: Self.id(n), url: "https://s\(n).com/", title: "S\(n)", group: group.map { Self.id(100 + $0) })
    }

    func group(_ n: Int, _ name: String) -> Session.Group {
        Session.Group(id: Self.id(100 + n), name: name)
    }

    // MARK: - the file

    /// Written before groups: no groups, no tab in one, no dates.
    @Test func migratesAFileWithoutGroups() throws {
        let old = """
        {"tabs":[{"id":"\(Self.id(1).uuidString)","url":"https://a.com/","title":"A"}],"active":0}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(old.utf8))
        #expect(shape.groups.isEmpty)
        #expect(shape.tabs[0].group == nil)
        #expect(shape.tabs[0].viewed == nil)
        #expect(shape.tabs[0].id == Self.id(1))
    }

    @Test func groupsAndDatesRoundTrip() throws {
        let viewed = Date(timeIntervalSince1970: 1_800_000_000)
        var tabs = [entry(1, group: 1), entry(2, group: 1), entry(3)]
        tabs[2].viewed = viewed
        let shape = Session.Shape(tabs: tabs, active: 2, groups: [group(1, "Lisbon trip")])
        let read = try JSONDecoder().decode(Session.Shape.self, from: JSONEncoder().encode(shape))
        #expect(read == shape)
        #expect(read.groups.map(\.name) == ["Lisbon trip"])
        #expect(read.tabs.map(\.group) == [Self.id(101), Self.id(101), nil])
        #expect(read.tabs[2].viewed == viewed)
    }

    /// A file an older Field wrote after a newer one: whatever it says, the
    /// tabs aren't lost. A tab pointing at a group that isn't there is loose.
    @Test func aMissingGroupLeavesTheTabLoose() throws {
        let shape = Session.Shape(tabs: [entry(1, group: 9), entry(2, group: 1), entry(3, group: 1)],
                                  active: 0, groups: [group(1, "A")])
        #expect(shape.tabs[0].group == nil)
        #expect(shape.tabs[1].group == Self.id(101))
    }

    /// A group no tab is in is gone; so is a second group with the same id.
    @Test func emptyAndRepeatedGroupsGo() {
        let shape = Session.Shape(tabs: [entry(1, group: 1)], active: 0,
                                  groups: [group(1, "A"), group(2, "Empty"), group(1, "Again")])
        #expect(shape.groups == [group(1, "A")])
    }

    /// The Mac's file has neither, and still reads.
    @Test func theMacFormatStillReads() throws {
        let mac = #"{"tabs":[{"url":"https://a.com/","title":"A","pin":"x"}],"active":0}"#
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(mac.utf8))
        #expect(shape.groups.isEmpty)
        #expect(shape.tabs.count == 1)
    }

    // MARK: - applying Tidy

    /// Tidy's groups become the session's, each with a new id; a tab not
    /// named stays where it was.
    @Test func applyingMakesGroups() {
        let shape = Session.Shape(tabs: [entry(1), entry(2), entry(3)], active: 0)
        let grouping = shape.grouping.applying([TidyGroup(name: "Pair", ids: [Self.id(1), Self.id(2)])])
        #expect(grouping.groups.map(\.name) == ["Pair"])
        let made = grouping.groups[0].id
        #expect(grouping.membership == [Self.id(1): made, Self.id(2): made])
        let after = shape.regrouped(grouping)
        #expect(after.tabs.map(\.group) == [made, made, nil])
    }

    /// A suggestion named like a group already there adds to it.
    @Test func applyingJoinsAGroupOfTheSameName() {
        let shape = Session.Shape(tabs: [entry(1, group: 1), entry(2), entry(3)], active: 0, groups: [group(1, "Lisbon trip")])
        let grouping = shape.grouping.applying([TidyGroup(name: "lisbon trip", ids: [Self.id(2), Self.id(3)])])
        #expect(grouping.groups == [group(1, "Lisbon trip")])
        #expect(Set(grouping.membership.values) == [Self.id(101)])
        #expect(grouping.membership.count == 3)
    }

    /// Moving a group's last tab away leaves nothing behind.
    @Test func applyingDropsGroupsLeftEmpty() {
        let shape = Session.Shape(tabs: [entry(1, group: 1), entry(2)], active: 0, groups: [group(1, "Old")])
        let grouping = shape.grouping.applying([TidyGroup(name: "New", ids: [Self.id(1), Self.id(2)])])
        #expect(grouping.groups.map(\.name) == ["New"])
    }

    /// Undo is the grouping from before, put back.
    @Test func undoPutsTheOldGroupingBack() {
        let shape = Session.Shape(tabs: [entry(1, group: 1), entry(2), entry(3)], active: 0, groups: [group(1, "Old")])
        let before = shape.grouping
        let after = shape.regrouped(before.applying([TidyGroup(name: "New", ids: [Self.id(1), Self.id(3)])]))
        #expect(after.tabs.map(\.group) != shape.tabs.map(\.group))
        #expect(after.regrouped(before) == shape)
    }

    @Test func addingToAGroup() {
        let shape = Session.Shape(tabs: [entry(1, group: 1), entry(2), entry(3)], active: 0, groups: [group(1, "A")])
        let grouping = shape.grouping.adding([Self.id(3)], to: Self.id(101))
        #expect(grouping.membership[Self.id(3)] == Self.id(101))
        #expect(grouping.membership[Self.id(2)] == nil)
        // Not a group there: nothing changes.
        #expect(shape.grouping.adding([Self.id(3)], to: Self.id(999)) == shape.grouping)
    }

    // MARK: - the grid's sections

    /// Groups first, in their order, each with its tabs in tab order; then
    /// the loose tabs, where a new tab lands.
    @Test func sections() {
        let shape = Session.Shape(tabs: [entry(1), entry(2, group: 2), entry(3, group: 1), entry(4), entry(5, group: 2)],
                                  active: 0, groups: [group(2, "B"), group(1, "A")])
        let sections = shape.grouping.sections(shape.tabs, id: \.id)
        #expect(sections.map(\.group?.name) == ["B", "A", nil])
        #expect(sections.map { $0.items.map(\.id) } == [[Self.id(2), Self.id(5)], [Self.id(3)], [Self.id(1), Self.id(4)]])
    }

    /// No groups: one section, no name, as the grid is today.
    @Test func noGroupsIsOneSection() {
        let shape = Session.Shape(tabs: [entry(1), entry(2)], active: 0)
        let sections = shape.grouping.sections(shape.tabs, id: \.id)
        #expect(sections.count == 1)
        #expect(sections[0].group == nil)
    }
}
