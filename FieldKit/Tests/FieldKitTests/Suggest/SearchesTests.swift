import Foundation
import Testing
@testable import FieldKit

// The searches made from the field, kept on the phone so the field can offer
// them again. Scored like history: count × e^(−days/30), on top of where the
// match falls.
struct SearchesTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let google = Engine.google.template(custom: "")

    func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func keys(_ list: [Suggestion]) -> [String] { list.map(\.key) }

    @Test func aSearchIsOfferedAgainFromItsFirstLetters() {
        var searches = Searches()
        searches.record("swift concurrency", now: now)
        let list = searches.suggestions(for: "swi", template: google, now: now)
        #expect(keys(list) == ["swift concurrency"])
        #expect(list.first?.kind == .searched)
        #expect(list.first?.url.absoluteString == "https://www.google.com/search?q=swift%20concurrency")
    }

    @Test func theURLFollowsTheEngineChosenNow() {
        var searches = Searches()
        searches.record("swift concurrency", now: now)
        let list = searches.suggestions(for: "swi", template: Engine.duckduckgo.template(custom: ""), now: now)
        #expect(list.first?.url.absoluteString == "https://duckduckgo.com/?q=swift%20concurrency")
    }

    @Test func caseAndSpacingDoNotMakeANewSearch() {
        var searches = Searches()
        searches.record("Swift  Concurrency", now: ago(days: 1))
        searches.record(" swift concurrency ", now: now)
        let list = searches.suggestions(for: "s", template: google, now: now)
        #expect(list.count == 1)
        // Shown as last typed.
        #expect(list.first?.key == "swift concurrency")
    }

    @Test func aLaterWordAlsoMatchesFromTwoLetters() {
        var searches = Searches()
        searches.record("swift concurrency", now: now)
        #expect(keys(searches.suggestions(for: "conc", template: google, now: now)) == ["swift concurrency"])
        #expect(searches.suggestions(for: "c", template: google, now: now).isEmpty)
        // Never from the middle of a word.
        #expect(searches.suggestions(for: "oncu", template: google, now: now).isEmpty)
    }

    @Test func theStartBeatsALaterWord() {
        var searches = Searches()
        for _ in 0..<5 { searches.record("learn swift", now: now) }
        searches.record("swift concurrency", now: ago(days: 60))
        #expect(keys(searches.suggestions(for: "swift", template: google, now: now))
            == ["swift concurrency", "learn swift"])
    }

    @Test func oftenAndLatelyComeFirst() {
        var searches = Searches()
        searches.record("swift testing", now: ago(days: 90))
        searches.record("swift concurrency", now: now)
        searches.record("swift charts", now: ago(days: 2))
        searches.record("swift charts", now: ago(days: 1))
        #expect(keys(searches.suggestions(for: "swift", template: google, now: now))
            == ["swift charts", "swift concurrency", "swift testing"])
    }

    @Test func exactlyWhatWasTypedIsNotOfferedBack() {
        var searches = Searches()
        searches.record("swift", now: now)
        #expect(searches.suggestions(for: "Swift", template: google, now: now).isEmpty)
    }

    @Test func aLimit() {
        var searches = Searches()
        for word in ["swift a", "swift b", "swift c", "swift d", "swift e"] { searches.record(word, now: now) }
        #expect(searches.suggestions(for: "swift", template: google, limit: 3, now: now).count == 3)
    }

    @Test func nothingForAnEmptyField() {
        var searches = Searches()
        searches.record("swift", now: now)
        #expect(searches.suggestions(for: "  ", template: google, now: now).isEmpty)
    }

    @Test func aSecretOrAnAddressIsNeverRemembered() {
        var searches = Searches()
        searches.record("ghp_16C7e42F292c6912E7710c838347Ae178B4a", now: now)
        searches.record("4111 1111 1111 1111", now: now)
        searches.record("github.com", now: now)
        searches.record("   ", now: now)
        #expect(searches.isEmpty)
    }

    @Test func forgetting() {
        var searches = Searches()
        searches.record("swift concurrency", now: now)
        searches.record("swift charts", now: now)
        searches.forget("Swift Charts")
        #expect(keys(searches.suggestions(for: "swift", template: google, now: now)) == ["swift concurrency"])
        searches.forget()
        #expect(searches.isEmpty)
    }

    @Test func roundTripsThroughAFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("searches.json")
        var searches = Searches()
        searches.record("swift concurrency", now: now)
        searches.record("swift concurrency", now: now)
        searches.record("café crème", now: ago(days: 3))
        try searches.save(to: file, now: now)
        let read = try Searches.load(from: file)
        #expect(read == searches)
    }

    @Test func noFileIsNoSearches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        #expect(try Searches.load(from: file).isEmpty)
    }

    @Test func aFileThatIsNotOneIsSetAside() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("searches.json")
        try Data("not json".utf8).write(to: file)
        #expect(try Searches.load(from: file).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theFileIsCapped() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("searches.json")
        var searches = Searches()
        for i in 0..<(Searches.cap + 20) { searches.record("query \(i)", now: ago(days: Double(i))) }
        try searches.save(to: file, now: now)
        let read = try Searches.load(from: file)
        #expect(read.count == Searches.cap)
        // What goes is the oldest: 500 to 519 are gone, 490 to 499 stay.
        #expect(read.suggestions(for: "query 51", template: google, limit: 20, now: now).isEmpty)
        #expect(read.suggestions(for: "query 49", template: google, limit: 20, now: now).count == 10)
    }
}
