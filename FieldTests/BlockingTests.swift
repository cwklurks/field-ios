import FieldKit
import Foundation
import Testing
import WebKit
@testable import Field

/// The per-site shield: on unless someone turned it off, remembered across
/// launches, and keyed by the site rather than the exact host, so turning it
/// off on www.example.co.uk also covers shop.example.co.uk.
struct BlockingShieldTests {
    private let suite = "BlockingShieldTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func onUntilTurnedOff() {
        defer { defaults.removePersistentDomain(forName: suite) }
        var shields = Shields(defaults: defaults)
        #expect(shields.isOn(for: "example.com"))
        #expect(shields.isOn(for: nil))
        shields.set(false, for: "example.com")
        #expect(!shields.isOn(for: "example.com"))
        #expect(shields.isOn(for: "other.com"))
        #expect(shields.isOn(for: nil))
    }

    @Test func rememberedAcrossLaunches() {
        defer { defaults.removePersistentDomain(forName: suite) }
        var shields = Shields(defaults: defaults)
        shields.set(false, for: "news.example.com")
        #expect(!Shields(defaults: defaults).isOn(for: "example.com"))
        shields.set(true, for: "example.com")
        #expect(Shields(defaults: defaults).isOn(for: "news.example.com"))
        #expect(defaults.stringArray(forKey: Shields.key) == [])
    }

    @Test func keyedBySite() {
        defer { defaults.removePersistentDomain(forName: suite) }
        var shields = Shields(defaults: defaults)
        shields.set(false, for: "www.example.co.uk")
        #expect(!shields.isOn(for: "shop.example.co.uk"))
        #expect(!shields.isOn(for: "EXAMPLE.CO.UK"))
        #expect(shields.isOn(for: "other.co.uk"))
        #expect(defaults.stringArray(forKey: Shields.key) == ["example.co.uk"])
    }

    @Test func theSiteOfAHost() {
        let site = Shields.registrableDomain
        #expect(site("www.example.com") == "example.com")
        #expect(site("a.b.example.com.") == "example.com")
        #expect(site("example.com") == "example.com")
        #expect(site("bbc.co.uk") == "bbc.co.uk")
        #expect(site("www.bbc.co.uk") == "bbc.co.uk")
        #expect(site("www.abc.net.au") == "abc.net.au")
        #expect(site("localhost") == "localhost")
        #expect(site("192.168.1.10") == "192.168.1.10")
        #expect(site("[::1]") == "[::1]")
    }

    /// Given a proper public-suffix lookup, the shield keys by that instead.
    @Test func takesAnotherLookup() {
        defer { defaults.removePersistentDomain(forName: suite) }
        var shields = Shields(defaults: defaults, domain: { $0.hasSuffix("github.io") ? $0 : "same" })
        shields.set(false, for: "me.github.io")
        #expect(!shields.isOn(for: "me.github.io"))
        #expect(shields.isOn(for: "you.github.io"))
    }

    /// The guard's public-suffix lookup loads off the main thread after
    /// launch, so the blocker takes it once it's there.
    @MainActor @Test func takesTheGuardsSitesOnceLoaded() {
        defer { defaults.removePersistentDomain(forName: suite) }
        let blocking = ContentBlocking(manifest: nil, defaults: defaults)
        blocking.site = GuardRules.bundled.site(of:)
        blocking.setShield(false, for: "me.github.io")
        #expect(!blocking.isShieldOn(for: "me.github.io"))
        #expect(!blocking.isShieldOn(for: "ME.github.io."))
        #expect(blocking.isShieldOn(for: "you.github.io"))
        #expect(defaults.stringArray(forKey: Shields.key) == ["me.github.io"])
    }
}

/// What ships: EasyList, EasyPrivacy and the domain lists, each under
/// WebKit's 150,000 rules, each compiled
/// under a name that changes when its contents do.
struct BlockingManifestTests {
    private func manifest(_ lists: (String, String)...) -> BlockingManifest {
        BlockingManifest(lists: lists.map { BlockingManifest.List(name: $0.0, file: "\($0.0).json.gz", rules: 1, sha256: $0.1) })
    }

    @Test func theBundledLists() throws {
        let manifest = try #require(BlockingManifest.bundled())
        #expect(manifest.lists.map(\.name).prefix(2) == ["easylist", "easyprivacy"])
        #expect(manifest.lists.dropFirst(2).map(\.name) == (1...manifest.lists.count - 2).map { "domains-\($0)" })
        #expect(manifest.lists.count >= 4)
        for list in manifest.lists {
            #expect(list.rules > 10_000 && list.rules < 150_000)
            #expect(FileManager.default.fileExists(atPath: manifest.directory!.appendingPathComponent(list.file).path))
        }
    }

    @Test func aNewVersionIsANewIdentifier() {
        let old = manifest(("easylist", "aaaaaaaaaaaaaaaa1111"), ("easyprivacy", "bbbbbbbbbbbbbbbb2222"))
        let new = manifest(("easylist", "cccccccccccccccc1111"), ("easyprivacy", "bbbbbbbbbbbbbbbb2222"))
        #expect(old.identifiers[0] != new.identifiers[0])
        #expect(old.identifiers[1] == new.identifiers[1])
        #expect(new.identifiers[0].hasPrefix(BlockingManifest.prefix))
        #expect(new.identifiers[0].contains("easylist"))
    }

    /// Everything Field compiled that this build doesn't ship goes; lists
    /// under anyone else's names are left alone.
    @Test func staleIdentifiers() {
        let current = manifest(("easylist", "cccccccccccccccc"), ("easyprivacy", "dddddddddddddddd"))
        let older = manifest(("easylist", "aaaaaaaaaaaaaaaa"), ("easyprivacy", "dddddddddddddddd"))
        let stored = current.identifiers + [older.identifiers[0], "somebody.else"]
        #expect(current.stale(among: stored) == [older.identifiers[0]])
        #expect(current.stale(among: current.identifiers).isEmpty)
    }
}

struct BlockingGzipTests {
    @Test func inflates() throws {
        let data = try #require(Data(base64Encoded: "H4sIAAAAAAACA8tIzcnJ5wIAIDA6NgYAAAA="))
        #expect(try Gzip.inflate(data) == Data("hello\n".utf8))
    }

    @Test func refusesWhatIsNotGzip() {
        #expect(throws: Gzip.Failure.self) { try Gzip.inflate(Data("hello".utf8)) }
        #expect(throws: Gzip.Failure.self) { try Gzip.inflate(Data()) }
    }

    /// The whole shipped list comes back as WebKit JSON with every rule.
    @Test func theBundledListInflates() throws {
        let manifest = try #require(BlockingManifest.bundled())
        let list = manifest.lists[0]
        let data = try Gzip.inflate(Data(contentsOf: manifest.directory!.appendingPathComponent(list.file)))
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(rules.count == list.rules)
    }
}

/// WebKit's "blocked by content blocker" (104) is what a page the lists
/// stopped outright looks like; it gets "Load anyway", nothing else does.
struct BlockingErrorTests {
    @Test func blockedByTheLists() {
        let url = URL(string: "https://ads.example.com/")!
        let blocked = NSError(domain: "WebKitErrorDomain", code: 104, userInfo: [NSURLErrorFailingURLErrorKey: url])
        #expect(ContentBlocking.blockedURL(from: blocked) == url)
        #expect(ContentBlocking.blockedURL(from: NSError(domain: "WebKitErrorDomain", code: 102)) == nil)
        #expect(ContentBlocking.blockedURL(from: NSError(domain: NSURLErrorDomain, code: 104, userInfo: [NSURLErrorFailingURLErrorKey: url])) == nil)
    }
}

/// The per-site switch as a menu item, for the address's long-press: it
/// names the site, flips the shield for all of it, and reloads the page.
@MainActor struct BlockingShieldActionTests {
    private let suite = "BlockingShieldActionTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func turnsTheSiteOffThenOnAgain() throws {
        defer { defaults.removePersistentDomain(forName: suite) }
        let blocking = ContentBlocking(manifest: nil, defaults: defaults)
        let page = URL(string: "https://www.example.com/a")
        var reloads = 0

        let off = try #require(blocking.shieldAction(for: page) { reloads += 1 })
        #expect(off.title == "Turn Off Blocking on example.com")
        off.performWithSender(nil, target: nil)
        #expect(!blocking.isShieldOn(for: "shop.example.com"))
        #expect(reloads == 1)

        let on = try #require(blocking.shieldAction(for: page) { reloads += 1 })
        #expect(on.title == "Turn On Blocking on example.com")
        on.performWithSender(nil, target: nil)
        #expect(blocking.isShieldOn(for: "example.com"))
        #expect(reloads == 2)
    }

    /// A blank tab, or a page with no host, has no site to switch.
    @Test func nothingWithoutASite() {
        let blocking = ContentBlocking(manifest: nil, defaults: defaults)
        #expect(blocking.shieldAction(for: nil) {} == nil)
        #expect(blocking.shieldAction(for: URL(string: "data:text/plain,hi")) {} == nil)
        #expect(blocking.shieldAction(for: URL(string: "about:blank")) {} == nil)
    }
}

/// When a list may be compiled: WebKit parses it on the main thread first,
/// which holds it for tens of milliseconds, so that waits for a stretch of
/// quiet: timer ticks on time, with nothing (the keyboard, the app leaving)
/// in the way.
struct BlockingLullTests {
    private let start = ContinuousClock.now

    /// Ticks 250 ms apart from `from`, each quiet or not, until one says it's time.
    private func ticks(_ lull: inout Lull, from: Int = 0, _ quiet: [Bool]) -> Int? {
        for (i, quiet) in quiet.enumerated() {
            let ms = from + i * 250
            if lull.tick(at: start + .milliseconds(ms), quiet: quiet) { return ms }
        }
        return nil
    }

    @Test func quietForLongEnough() {
        var lull = Lull(needed: .seconds(1), interval: .milliseconds(250))
        #expect(ticks(&lull, Array(repeating: true, count: 8)) == 1000)
    }

    /// The keyboard coming up, say, starts the wait again.
    @Test func interruptedStartsOver() {
        var lull = Lull(needed: .seconds(1), interval: .milliseconds(250))
        #expect(ticks(&lull, [true, true, true, false] + Array(repeating: true, count: 8)) == 2000)
    }

    /// A late tick means the main thread was busy, or a finger was on a
    /// scroll view (the timer doesn't fire while it tracks): the quiet
    /// starts from that tick.
    @Test func aLateTickStartsOver() {
        var lull = Lull(needed: .seconds(1), interval: .milliseconds(250))
        #expect(ticks(&lull, [true, true, true]) == nil)
        #expect(ticks(&lull, from: 1500, Array(repeating: true, count: 8)) == 2500)
    }

    @Test func noWaitNeeded() {
        var lull = Lull(needed: .zero, interval: .milliseconds(250))
        #expect(ticks(&lull, [true]) == 0)
    }

    /// Once one lull has come, the app was quiet a moment ago, so each list
    /// after the first needs only a short one.
    @Test func laterListsNeedLess() {
        var lull = Lull(needed: .seconds(1), interval: .milliseconds(250), then: .milliseconds(500), deadline: .seconds(60))
        #expect(ticks(&lull, Array(repeating: true, count: 8)) == 1000)
        // The list compiled for a while; the next wait starts with a late tick.
        #expect(ticks(&lull, from: 3000, Array(repeating: true, count: 8)) == 3500)
    }

    /// Someone who keeps busy doesn't stay unprotected: past the deadline,
    /// the short quiet will do.
    @Test func pastTheDeadlineAShortQuietWillDo() {
        var lull = Lull(needed: .seconds(1), interval: .milliseconds(250), then: .milliseconds(500), deadline: .seconds(3))
        let busy = Array(repeating: [true, true, false], count: 4).flatMap { $0 }
        #expect(ticks(&lull, busy) == nil)
        #expect(!lull.isPastDeadline(at: start + .milliseconds(2750)))
        #expect(lull.isPastDeadline(at: start + .seconds(3)))
        #expect(ticks(&lull, from: 3000, [true, true, true]) == 3500)
    }

    /// What counts as quiet: the app in front, and before the deadline no
    /// keyboard. After it, the keyboard may be up as long as nothing's
    /// been typed (or the keyboard moved) for a while.
    @Test func whatCountsAsQuiet() {
        let now = start + .seconds(10)
        let long = now - .seconds(5), just = now - .milliseconds(100)
        #expect(Lull.isQuiet(active: true, keyboardUp: false, lastInput: nil, pastDeadline: false, at: now, calm: .seconds(2)))
        #expect(!Lull.isQuiet(active: false, keyboardUp: false, lastInput: nil, pastDeadline: true, at: now, calm: .seconds(2)))
        #expect(!Lull.isQuiet(active: true, keyboardUp: true, lastInput: long, pastDeadline: false, at: now, calm: .seconds(2)))
        #expect(Lull.isQuiet(active: true, keyboardUp: true, lastInput: long, pastDeadline: true, at: now, calm: .seconds(2)))
        #expect(!Lull.isQuiet(active: true, keyboardUp: true, lastInput: just, pastDeadline: true, at: now, calm: .seconds(2)))
        #expect(!Lull.isQuiet(active: true, keyboardUp: false, lastInput: just, pastDeadline: true, at: now, calm: .seconds(2)))
    }
}
