import Foundation
import Testing
@testable import FieldKit

struct GuardRulesTests {
    /// The snapshot in Guard/Rules, at least as big as when it was taken
    /// (scripts/guard/update.sh).
    @Test func theBundledTablesAreAllThere() {
        let counts = GuardRules.bundled.counts
        #expect(counts["brave-query-filter.json"] ?? 0 >= 70)
        #expect(counts["ddg-tracking-parameters.json"] ?? 0 >= 25)
        #expect(counts["brave-debounce.json"] ?? 0 >= 180)
        #expect(counts["shims.json"] ?? 0 >= 8)
        #expect(counts["amp.json"] ?? 0 >= 2)
        #expect(counts["public-suffix-list.json"] ?? 0 >= 10_000)
    }

    @Test func aFolderWithoutTablesIsAnError() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("no-guard-rules-\(UUID())")
        #expect(throws: (any Error).self) { try GuardRules.load(from: empty) }
    }

    @Test(arguments: [
        ("example.com", "example.com"),
        ("www.example.com", "example.com"),
        ("a.b.c.example.com", "example.com"),
        ("WWW.Example.COM", "example.com"),
        ("www.example.com.", "example.com"),
        ("www.bbc.co.uk", "bbc.co.uk"),
        ("co.uk", "co.uk"),
        ("uk", "uk"),
        // The private section: each of these is its own site.
        ("alice.github.io", "alice.github.io"),
        ("www.alice.github.io", "alice.github.io"),
        ("myblog.blogspot.com", "myblog.blogspot.com"),
        // A wildcard and its exception.
        ("foo.bar.ck", "foo.bar.ck"),
        ("www.ck", "www.ck"),
        ("a.www.ck", "www.ck"),
        ("x.city.kawasaki.jp", "city.kawasaki.jp"),
        // Internationalised, in the form URL hands over.
        ("www.xn--80ak6aa92e.xn--p1ai", "xn--80ak6aa92e.xn--p1ai"),
        // Unknown suffixes fall back to the last label.
        ("a.b.notatld", "b.notatld"),
        // Addresses are their own site.
        ("192.168.1.1", "192.168.1.1"),
        ("[2001:db8::1]", "[2001:db8::1]"),
        ("localhost", "localhost"),
    ])
    func registrableDomain(host: String, site: String) {
        #expect(GuardRules.bundled.site(of: host) == site)
    }

    @Test func loadingIsQuickEnoughForABackgroundTask() throws {
        let folder = try #require(GuardRules.bundledFolder)
        let clock = ContinuousClock()
        let time = try clock.measure { _ = try GuardRules.load(from: folder) }
        print("GuardRules.load: \(time)")
        #expect(time < .milliseconds(500))
    }
}
