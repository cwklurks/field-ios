import Foundation
import Testing
@testable import FieldKit

/// session.json: what was open last time, and which one you were looking at.
/// The Mac's format, plus each tab's id (its snapshot's name in Caches) and
/// its `interactionState`, the back and forward list WebKit hands back.
@Suite(.serialized)
struct SessionTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SessionTests-\(UUID().uuidString)", isDirectory: true)
    var file: URL { directory.appendingPathComponent("session.json") }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    @Test func roundTrips() throws {
        defer { clean() }
        let state = Data([1, 2, 3, 250])
        let shape = Session.Shape(tabs: [
            Session.Entry(url: "https://example.com/a", title: "A", interactionState: state),
            Session.Entry(url: "", title: ""),
        ], active: 1)
        try shape.save(to: file)
        let read = try Session.Shape.load(from: file)
        #expect(read == shape)
        #expect(read.tabs[0].interactionState == state)
    }

    @Test func noFileIsAnEmptySession() throws {
        defer { clean() }
        #expect(try Session.Shape.load(from: file) == Session.Shape())
    }

    /// Something wrote it, so it's set aside for a person to look at rather
    /// than overwritten by the next save.
    @Test func aFileThatIsNotASessionIsSetAside() throws {
        defer { clean() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(try Session.Shape.load(from: file) == Session.Shape())
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(left.count == 1)
        #expect(left.first?.hasPrefix("session.unreadable-") == true)
    }

    /// The Mac's own file: no ids and no interaction state, and a pin and a
    /// name Field has no use for. Each tab is given an id of its own.
    @Test func readsTheMacFormat() throws {
        let mac = """
        {"tabs":[{"url":"https://a.com/","title":"A","pin":"x"},{"url":"https://b.com/","title":"B","name":"Mine"}],"active":1}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(mac.utf8))
        #expect(shape.tabs.map(\.url) == ["https://a.com/", "https://b.com/"])
        #expect(shape.tabs.map(\.title) == ["A", "B"])
        #expect(shape.tabs.allSatisfy { $0.interactionState == nil })
        #expect(Set(shape.tabs.map(\.id)).count == 2)
        #expect(shape.active == 1)
    }

    /// An active index that points nowhere lands on the nearest tab.
    @Test func activeIsKeptInRange() throws {
        let json = """
        {"tabs":[{"url":"https://a.com/","title":"A"},{"url":"https://b.com/","title":"B"}],"active":7}
        """
        let shape = try JSONDecoder().decode(Session.Shape.self, from: Data(json.utf8))
        #expect(shape.active == 1)
        let negative = try JSONDecoder().decode(Session.Shape.self, from: Data(#"{"tabs":[],"active":-3}"#.utf8))
        #expect(negative.active == 0)
    }

    /// The same tab keeps its id from one launch to the next, so its snapshot
    /// is found again.
    @Test func idsSurviveARoundTrip() throws {
        let entry = Session.Entry(url: "https://a.com/", title: "A")
        let data = try JSONEncoder().encode(Session.Shape(tabs: [entry], active: 0))
        let read = try JSONDecoder().decode(Session.Shape.self, from: data)
        #expect(read.tabs.first?.id == entry.id)
    }
}
