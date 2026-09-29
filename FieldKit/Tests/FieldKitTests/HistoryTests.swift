import Foundation
import Testing
@testable import FieldKit

// Pinned against the Mac's History.swift. The clock is passed in, so every
// score here can be worked out by hand: count × e^(−days/30), plus 4 for
// having been there, plus 1.5 for a bare domain, plus 6, 3 or 2 for where
// the match falls.
struct HistoryTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    func url(_ text: String) -> URL { URL(string: text)! }

    func keys(_ list: [Suggestion]) -> [String] { list.map(\.key) }

    // MARK: - writing

    @Test func countsEachVisit() {
        var history = History()
        history.record(url("https://example.com/"), title: "Example", now: ago(days: 2))
        history.record(url("https://www.example.com/"), title: "Example", now: now)
        let traces = history.everything()
        #expect(traces.count == 1)
        #expect(traces.first?.key == "example.com")
        #expect(traces.first?.count == 2)
        #expect(traces.first?.last == now)
    }

    @Test func aRevisitKeepsTheTitleUnlessItHasANewOne() {
        var history = History()
        history.record(url("https://example.com/a"), title: "First", now: now)
        history.record(url("https://example.com/a"), title: "", now: now)
        #expect(history.everything().first?.title == "First")
        history.record(url("https://example.com/a"), title: "Second", now: now)
        #expect(history.everything().first?.title == "Second")
    }

    @Test func aDeepPageAlsoCreditsTheFrontPage() {
        var history = History()
        history.record(url("https://www.example.com/a/b"), title: "B", now: ago(days: 1))
        history.record(url("https://example.com/c"), title: "C", now: now)
        let home = history.visits["example.com"]
        #expect(home?.count == 2)
        #expect(home?.url == "https://example.com/")
        #expect(home?.title == "")
        #expect(home?.last == now)
        // The credit has no title of its own, so the list of where you have
        // been leaves it out.
        #expect(history.everything().map(\.key) == ["example.com/c", "example.com/a/b"])
    }

    @Test func keysAreLowercased() {
        var history = History()
        history.record(url("https://GitHub.com/Apple"), title: "Apple", now: now)
        #expect(Set(history.visits.keys) == ["github.com", "github.com/apple"])
    }

    @Test(arguments: ["file:///Users/x/a.html", "about:blank", "data:text/plain,hi", "ftp://example.com/x"])
    func onlyTheWebIsRemembered(address: String) {
        var history = History()
        history.record(url(address), title: "T", now: now)
        #expect(history.visits.isEmpty)
    }

    // Unlike the Mac: a search or an anchor on a front page counts as a visit
    // to the site without taking its place, so the site's suggestion still
    // opens the site rather than the last search.
    @Test func aFrontPageWithAQueryCountsButKeepsItsPlace() {
        var history = History()
        history.record(url("https://duckduckgo.com/"), title: "DuckDuckGo", now: ago(days: 1))
        history.record(url("https://duckduckgo.com/?q=secret"), title: "secret at DuckDuckGo", now: now)
        history.retitle(url("https://duckduckgo.com/?q=secret"), "secret at DuckDuckGo")
        history.record(url("https://duckduckgo.com/#top"), title: "Top", now: now)
        let home = history.visits["duckduckgo.com"]
        #expect(home?.count == 3)
        #expect(home?.last == now)
        #expect(home?.url == "https://duckduckgo.com/")
        #expect(home?.title == "DuckDuckGo")
        #expect(history.suggestions(for: "duck", now: now).first?.url.absoluteString == "https://duckduckgo.com/")

        // A deeper page is still remembered as it was reached, query and all.
        history.record(url("https://duckduckgo.com/settings?kl=fr"), title: "Settings", now: now)
        #expect(history.visits["duckduckgo.com/settings"]?.url == "https://duckduckgo.com/settings?kl=fr")
    }

    @Test func aSearchAsTheFirstVisitStillLeadsToTheFrontPage() {
        var history = History()
        history.record(url("https://www.duckduckgo.com/?q=secret"), title: "secret at DuckDuckGo", now: now)
        history.retitle(url("https://www.duckduckgo.com/?q=secret"), "secret at DuckDuckGo")
        let home = history.visits["duckduckgo.com"]
        #expect(home?.count == 1)
        #expect(home?.url == "https://duckduckgo.com/")
        #expect(home?.title == "")
    }

    // Unlike the Mac: a web app that routes by its fragment is only ever
    // reached that way, so the first title it gives names the front page and
    // keeps it in the list of where you have been.
    @Test func aWebAppRoutedByItsFragmentIsNamed() {
        var history = History()
        history.record(url("https://app.element.io/#/home"), title: "", now: now)
        history.retitle(url("https://app.element.io/#/home"), "Element")
        history.record(url("https://app.element.io/#/room/abc"), title: "Element | Room", now: now)
        history.retitle(url("https://app.element.io/#/room/abc"), "Element | Room")
        let home = history.visits["app.element.io"]
        #expect(home?.title == "Element")
        #expect(home?.url == "https://app.element.io/")
        #expect(home?.count == 2)
        #expect(history.everything().map(\.key) == ["app.element.io"])

        var first = History()
        first.record(url("https://app.example.com/#/home"), title: "Example App", now: now)
        #expect(first.visits["app.example.com"]?.title == "Example App")
    }

    // Unlike the Mac: the port is part of the key, and a front page reached
    // at a local address or on a port of its own keeps the scheme, host and
    // port it was reached on. Anything else still gets https, as before.
    @Test(arguments: [
        ("http://localhost:3000/app", "localhost:3000", "http://localhost:3000/"),
        ("http://dev.localhost/app", "dev.localhost", "http://dev.localhost/"),
        ("http://192.168.1.1/admin", "192.168.1.1", "http://192.168.1.1/"),
        ("http://8.8.8.8:8080/x", "8.8.8.8:8080", "http://8.8.8.8:8080/"),
        ("http://[::1]:8080/p", "[::1]:8080", "http://[::1]:8080/"),
        ("http://printer.local:631/jobs?which=all", "printer.local:631", "http://printer.local:631/"),
        ("https://nas.local/files", "nas.local", "https://nas.local/"),
        ("http://nas.lan:5000/x", "nas.lan:5000", "http://nas.lan:5000/"),
        ("https://www.example.com:8443/page", "example.com:8443", "https://www.example.com:8443/"),
        ("http://example.com/page", "example.com", "https://example.com/"),
        ("https://example.com:443/a", "example.com", "https://example.com/"),
        ("http://10.tv/x", "10.tv", "https://10.tv/"),
        ("http://172.20.0.5/x", "172.20.0.5", "http://172.20.0.5/"),
        ("http://[fe80::1]/x", "[fe80::1]", "http://[fe80::1]/"),
        // A public address on the scheme's own port is not local.
        ("http://8.8.8.8/x", "8.8.8.8", "https://8.8.8.8/"),
        ("http://[2001:db8::1]/x", "[2001:db8::1]", "https://[2001:db8::1]/"),
        ("http://192.168.evil.com/x", "192.168.evil.com", "https://192.168.evil.com/"),
    ])
    func aFrontPageIsReachedTheWayItWas(address: String, root: String, home: String) {
        var history = History()
        history.record(url(address), title: "Page", now: now)
        #expect(history.visits[root]?.url == home)
        #expect(history.visits.count == 2)
    }

    // Unlike the Mac: a name and password typed into an address are never
    // written down, on the page or on its front door.
    @Test(arguments: [
        ("http://user:hunter2@192.168.1.1/admin", ["http://192.168.1.1/", "http://192.168.1.1/admin"]),
        ("https://user:hunter2@example.com/a?b=1", ["https://example.com/", "https://example.com/a?b=1"]),
        ("http://user:hunter2@nas.lan:5000/x", ["http://nas.lan:5000/", "http://nas.lan:5000/x"]),
        ("http://admin@router.local/x#y", ["http://router.local/", "http://router.local/x#y"]),
        ("https://user:hunter2@example.com/", ["https://example.com/"]),
        ("https://user:hunter2@example.com/?q=1", ["https://example.com/"]),
    ])
    func aPasswordIsNeverKept(address: String, kept: [String]) {
        var history = History()
        history.record(url(address), title: "Admin", now: now)
        #expect(history.visits.values.map(\.url).sorted() == kept.sorted())
    }

    @Test func thePortIsPartOfTheKey() {
        var history = History()
        history.record(url("http://localhost:3000/"), title: "App", now: now)
        history.record(url("http://localhost:3000/"), title: "App", now: now)
        history.record(url("http://localhost:8080/"), title: "API", now: now)
        history.retitle(url("http://localhost:8080/"), "API docs")
        #expect(history.visits["localhost:3000"]?.title == "App")
        #expect(history.visits["localhost:8080"]?.title == "API docs")
        #expect(history.visits["localhost"] == nil)
        #expect(keys(history.suggestions(for: "local", now: now)) == ["localhost:3000", "localhost:8080"])
        #expect(keys(history.suggestions(for: "localhost:8", now: now)) == ["localhost:8080"])
    }

    // Unlike the Mac: the scheme's own port is left out, so it is one place
    // with or without it, and an IPv6 host keeps its brackets, so a key reads
    // back as an address.
    @Test func aKeyReadsBackAsAnAddress() throws {
        var history = History()
        history.record(url("https://example.com:443/a"), title: "A", now: now)
        history.record(url("https://example.com/a"), title: "A", now: now)
        history.record(url("http://example.com:80/"), title: "Example", now: now)
        #expect(Set(history.visits.keys) == ["example.com", "example.com/a"])
        #expect(history.visits["example.com/a"]?.count == 2)

        history.record(url("http://[::1]:8080/p"), title: "P", now: now)
        #expect(history.visits["[::1]:8080/p"] != nil)
        let back = try #require(URL(string: "http://[::1]:8080/p"))
        #expect(back.host() == "::1")
        #expect(back.port == 8080)
    }

    @Test func retitle() {
        var history = History()
        history.record(url("https://example.com/a"), title: "", now: now)
        history.retitle(url("https://example.com/a"), "Later")
        #expect(history.everything().first?.title == "Later")
        history.retitle(url("https://example.com/a"), "")
        #expect(history.everything().first?.title == "Later")
        history.retitle(url("https://elsewhere.com/"), "Nowhere")
        #expect(history.visits["elsewhere.com"] == nil)
    }

    @Test func forget() {
        var history = History()
        history.record(url("https://example.com/a"), title: "A", now: now)
        history.record(url("https://example.org/b"), title: "B", now: now)
        history.forget("example.com/a")
        #expect(history.everything().map(\.key) == ["example.org/b"])
        history.forget()
        #expect(history.visits.isEmpty)
    }

    @Test func everythingIsNewestFirstAndFiltered() {
        var history = History()
        history.record(url("https://example.com/old"), title: "An old Page", now: ago(days: 3))
        history.record(url("https://example.org/new"), title: "New", now: now)
        history.record(url("https://example.net/mid"), title: "Middle", now: ago(days: 1))
        #expect(history.everything().map(\.key) == ["example.org/new", "example.net/mid", "example.com/old"])
        #expect(history.everything(matching: "  PAGE ").map(\.key) == ["example.com/old"])
        #expect(history.everything(matching: "example.n").map(\.key) == ["example.net/mid"])
        #expect(history.everything().first?.url.absoluteString == "https://example.org/new")
    }

    // MARK: - suggestions

    @Test(arguments: ["", "   ", "https://", "http://www.", "www."])
    func anEmptyFieldSuggestsNothing(typed: String) {
        var history = History()
        history.record(url("https://example.com/"), title: "Example", now: now)
        #expect(history.suggestions(for: typed, now: now).isEmpty)
    }

    @Test func theStartBeatsAfterTheFirstDotBeatsAnywhere() {
        var history = History()
        for site in ["https://keynote.com/", "https://my.notebook.io/", "https://note.com/"] {
            history.record(url(site), title: "", now: now)
        }
        // 6 + 4 + 1 + 1.5, then 3 + 6.5, then 2 + 6.5.
        #expect(keys(history.suggestions(for: "note", now: now)) == ["note.com", "my.notebook.io", "keynote.com"])
    }

    @Test func oneLetterOnlyMatchesAtTheStartOrAfterTheFirstDot() {
        var history = History()
        history.record(url("https://netflix.com/"), title: "", now: now)
        history.record(url("https://go.xkcd.com/"), title: "", now: now)
        #expect(keys(history.suggestions(for: "x", now: now)) == ["go.xkcd.com", "x.com"])
        // From two letters, anywhere in the host: the visit, then the known
        // sites, all worth 2, shortest first.
        #expect(keys(history.suggestions(for: "fl", now: now)) == [
            "netflix.com", "webflow.com", "cloudflare.com", "stackoverflow.com",
        ])
    }

    @Test func thePathIsOnlyMatchedFromTheStart() {
        var history = History()
        history.record(url("https://example.com/blog/post"), title: "Post", now: now)
        #expect(history.suggestions(for: "blog", now: now).isEmpty)
        #expect(keys(history.suggestions(for: "example.com/bl", now: now)) == ["example.com/blog/post"])
    }

    // No known site has "zz" in it, so only what was visited answers.
    @Test func oftenAndLately() {
        var history = History()
        history.record(url("https://zza.com/"), title: "", now: now)
        for _ in 0..<3 { history.record(url("https://zzb.com/"), title: "", now: ago(days: 60)) }
        // Three visits two months ago are worth 3e^-2 ≈ 0.41, one today is 1.
        #expect(keys(history.suggestions(for: "zz", now: now)) == ["zza.com", "zzb.com"])
        // Twenty days after those three, they are worth 3e^-2/3 ≈ 1.54.
        #expect(keys(history.suggestions(for: "zz", now: ago(days: 40))) == ["zzb.com", "zza.com"])
    }

    @Test func aVisitDatedLaterThanNowCountsAsNow() {
        var history = History()
        history.record(url("https://zzz.com/"), title: "", now: now.addingTimeInterval(86_400))
        history.record(url("https://zz.com/"), title: "", now: now)
        // Both worth exactly 1, so the shorter key wins; unclamped, tomorrow's
        // visit would be worth e^(1/30) and win instead.
        #expect(keys(history.suggestions(for: "zz", now: now)) == ["zz.com", "zzz.com"])
    }

    @Test func theFrontDoorBeforeTheRoom() {
        var history = History()
        history.record(url("https://example.com/page"), title: "Page", now: now)
        history.record(url("https://example.com/page"), title: "Page", now: now)
        // Both counted twice; only the 1.5 for a bare domain tells them apart.
        let list = history.suggestions(for: "exa", now: now)
        #expect(keys(list) == ["example.com", "example.com/page"])
        #expect(list.first?.url.absoluteString == "https://example.com/")
        #expect(list.map(\.kind) == [.visited, .visited])
    }

    @Test func aTieGoesToTheShorterKey() {
        var history = History()
        history.record(url("https://zzzz.com/"), title: "", now: now)
        history.record(url("https://zz.com/"), title: "", now: now)
        #expect(keys(history.suggestions(for: "zz", now: now)) == ["zz.com", "zzzz.com"])
    }

    @Test func aKnownSiteIsOfferedUntilYouHaveBeenThere() {
        var history = History()
        let known = history.suggestions(for: "github", now: now)
        #expect(keys(known) == ["github.com"])
        #expect(known.first?.kind == .known)
        #expect(known.first?.title == "GitHub")
        #expect(known.first?.url.absoluteString == "https://github.com")

        history.record(url("https://github.com/apple/swift"), title: "Swift", now: now)
        let visited = history.suggestions(for: "github", now: now)
        #expect(keys(visited) == ["github.com", "github.com/apple/swift"])
        #expect(visited.map(\.kind) == [.visited, .visited])
        #expect(visited.first?.url.absoluteString == "https://github.com/")
    }

    @Test func aPlaceYouHaveBeenBeatsAPlaceTheAppKnows() {
        var history = History()
        // Long ago, and only matched in the middle: still above the seed.
        history.record(url("https://legit.io/"), title: "", now: ago(days: 365))
        #expect(keys(history.suggestions(for: "git", now: now)) == ["legit.io", "github.com"])
    }

    @Test func theSchemeAndWWWAreNotPartOfWhatIsTyped() {
        let history = History()
        #expect(keys(history.suggestions(for: "  HTTPS://WWW.GitHub", now: now)) == ["github.com"])
    }

    @Test func theLimit() {
        let history = History()
        // google.com and github.com at the start, and four *.google.com.
        #expect(history.suggestions(for: "g", now: now).count == 5)
        #expect(Set(keys(history.suggestions(for: "g", limit: 2, now: now))) == ["google.com", "github.com"])
    }

    // MARK: - completion

    func offers(_ keys: String...) -> [Suggestion] {
        keys.map { Suggestion(key: $0, title: "", url: url("https://" + $0), kind: .visited) }
    }

    @Test func completion() {
        let history = History()
        #expect(history.completion(for: "gi", among: offers("github.com"))?.ending == "thub.com")
        #expect(history.completion(for: "GI", among: offers("github.com"))?.ending == "thub.com")
        #expect(history.completion(for: "g", among: offers("github.com"))?.ending == "ithub.com")
        #expect(history.completion(for: "github.com", among: offers("github.com")) == nil)
        #expect(history.completion(for: "hub", among: offers("github.com")) == nil)
        #expect(history.completion(for: "https://gi", among: offers("github.com")) == nil)
        // The first option that carries on, not necessarily the first option.
        let google = history.completion(for: "go", among: offers("mail.google.com", "google.com"))
        #expect(google?.ending == "ogle.com")
        #expect(google?.suggestion.key == "google.com")
    }

    // Unlike the Mac, which finished the text and read it again as typed, so
    // a place reached over plain http came back as https.
    @Test(arguments: ["http://printer.local:631/", "http://172.16.0.5:3000/", "http://8.8.8.8:8080/", "http://nas.lan:5000/"])
    func aCompletionLeadsWhereThePlaceWasReached(home: String) throws {
        var history = History()
        history.record(url(home + "x"), title: "X", now: now)
        let typed = String(home.dropFirst("http://".count).prefix(3))
        let done = try #require(history.completion(for: typed, among: history.suggestions(for: typed, now: now)))
        #expect(typed + done.ending == done.suggestion.key)
        #expect(done.suggestion.url.absoluteString == home)
    }

    // MARK: - a made-up history

    @Test(arguments: [1, 2, 3, 500, 2_000])
    func aSampleIsTheSizeAskedAndTheSameEveryTime(count: Int) {
        let sample = History.sample(count, now: now)
        #expect(sample.visits.count == count)
        #expect(sample == History.sample(count, now: now))
    }

    @Test func aSampleHasTheWeather() {
        let weather = History.sample(2_000, now: now).suggestions(for: "weather", now: now).map(\.key)
        #expect(Set(weather).isSuperset(of: ["weather.com", "weather.gov", "weather.example/forecast/today"]))
    }

    // MARK: - the file

    func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FieldKitTests-\(UUID().uuidString)")
    }

    @Test func aSavedHistoryLoadsTheSame() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("nested/history.json")

        var history = History()
        history.record(url("https://example.com/a"), title: "A", now: ago(days: 5))
        history.record(url("https://example.org/"), title: "Org", now: now)
        history.record(url("https://example.org/"), title: "", now: now)
        try history.save(to: file, now: now)

        let loaded = try History.load(from: file)
        #expect(loaded == history)
        #expect(loaded.visits.count == 3)
    }

    @Test func theFileIsTheMacsShape() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Written by Search on the Mac: an array of visits, dates in seconds
        // since 2001.
        let mac = #"[{"url":"https:\/\/example.com\/a","key":"example.com\/a","title":"A","count":3,"last":800000000}]"#
        try Data(mac.utf8).write(to: file)
        let history = try History.load(from: file)
        let trace = try #require(history.everything().first)
        #expect(trace.key == "example.com/a")
        #expect(trace.url.absoluteString == "https://example.com/a")
        #expect(trace.count == 3)
        #expect(trace.last == now)

        try history.save(to: file, now: now)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]]
        #expect(written?.count == 1)
        #expect(Set(written?.first?.keys.map { $0 } ?? []) == ["url", "key", "title", "count", "last"])
        #expect(written?.first?["last"] as? Double == 800_000_000)
    }

    // Unlike the Mac, which stopped on a key written twice.
    @Test func aKeyWrittenTwiceKeepsTheBusierVisitThenTheLater() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let twice = """
        [
          {"url":"https://a.com/x","key":"a.com/x","title":"busier","count":5,"last":1000},
          {"url":"https://a.com/x","key":"a.com/x","title":"later","count":2,"last":2000},
          {"url":"https://b.com/y","key":"b.com/y","title":"earlier","count":3,"last":1000},
          {"url":"https://b.com/y","key":"b.com/y","title":"later","count":3,"last":2000}
        ]
        """
        try Data(twice.utf8).write(to: file)
        let history = try History.load(from: file)
        #expect(history.visits.count == 2)
        #expect(history.visits["a.com/x"]?.title == "busier")
        #expect(history.visits["b.com/y"]?.title == "later")
    }

    @Test func noFileIsAnEmptyHistory() throws {
        let dir = folder()
        let history = try History.load(from: dir.appendingPathComponent("history.json"))
        #expect(history == History())
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    // Unlike the Mac, which took any failed read for an empty history and
    // saved over the file the next time. Before first unlock, iOS refuses to
    // read a protected file; that is not the same as there being none.
    @Test func aFileThatCannotBeReadIsNotTakenForEmpty() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")

        var history = History()
        history.record(url("https://example.com/a"), title: "A", now: now)
        try history.save(to: file, now: now)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        #expect(throws: CocoaError.self) { try History.load(from: file) }

        // Left where it was, for a later load to read.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try History.load(from: file) == history)
    }

    @Test func anUnreadableFileIsSetAsideNotOverwritten() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        #expect(try History.load(from: file) == History())
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(aside.count == 1)
        let name = try #require(aside.first)
        #expect(name.hasPrefix("history.unreadable-") && name.hasSuffix(".json"))
        #expect(try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) == "not json")
    }

    @Test func theFileKeepsTheBest2000() throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("history.json")

        var history = History()
        // Each an hour older than the one before, so each is worth less.
        for i in 0...2_000 {
            history.record(url("https://site\(i).com/"), title: "", now: now.addingTimeInterval(Double(-i * 3_600)))
        }
        try history.save(to: file, now: now)
        // What is in hand is not cut, only what is written.
        #expect(history.visits.count == 2_001)

        let loaded = try History.load(from: file)
        #expect(loaded.visits.count == 2_000)
        #expect(loaded.visits["site0.com"] != nil)
        #expect(loaded.visits["site1999.com"] != nil)
        #expect(loaded.visits["site2000.com"] == nil)
    }
}
