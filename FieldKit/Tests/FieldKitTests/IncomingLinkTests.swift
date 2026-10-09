import Foundation
import Testing
@testable import FieldKit

// Links other apps hand Field (Mail, Messages, Notes): external input, so
// only a web address with a host gets through, and it lands clean, as a
// tapped link would.
struct IncomingLinkTests {
    static let field = Guard(rules: .bundled)

    static func accept(_ text: String, cleaning: Guard? = field, shieldOn: Bool = true) throws -> Result<URL, IncomingLink.Rejection> {
        IncomingLink.accept(try #require(URL(string: text)), cleaning: cleaning, shieldOn: shieldOn)
    }

    static let web = [
        "https://example.com",
        "http://example.com/path?q=1#part",
        "HTTPS://Example.com/Caps",
        "https://xn--r8jz45g.jp/",
        "http://192.168.1.1/",
        "http://router.local:8080/admin",
        "https://[::1]:8443/",
    ]

    @Test(arguments: web)
    func webAddressesAreAccepted(_ text: String) throws {
        #expect(try Self.accept(text) == .success(try #require(URL(string: text))))
    }

    static let notWeb = [
        "javascript:alert(document.cookie)",
        "JavaScript://example.com/%0Aalert(1)",
        "data:text/html,<script>alert(1)</script>",
        "file:///etc/passwd",
        "mailto:someone@example.com",
        "ftp://example.com/file",
        "about:blank",
        "blob:https://example.com/7d1c",
        "field://open",
    ]

    @Test(arguments: notWeb)
    func otherSchemesAreRejected(_ text: String) throws {
        #expect(try Self.accept(text) == .failure(.notWeb))
    }

    static let credentials = [
        "https://user:secret@example.com/",
        "https://user@example.com/",
        "http://user@example.com:8080/",
        "https://%75ser@example.com/",
        "https://@example.com/",
        "http://:secret@example.com/",
        // The old trick: the "host" a person reads is the user name.
        "https://www.apple.com@evil.example/",
    ]

    @Test(arguments: credentials)
    func credentialsAreRejected(_ text: String) throws {
        #expect(try Self.accept(text) == .failure(.credentials))
    }

    static let malformed = [
        "https:example.com",
        "https:///path/only",
        "http://",
        "example.com/no-scheme",
        "//example.com/no-scheme",
    ]

    @Test(arguments: malformed)
    func addressesWithoutAHostAreRejected(_ text: String) throws {
        #expect(try Self.accept(text) == .failure(.malformed))
    }

    // MARK: - Cleaned as a tapped link is

    static let cleaned: [(String, String)] = [
        // A Google result forwarded in Mail.
        ("https://www.google.com/url?q=https://developer.apple.com/documentation/webkit&sa=D&source=docs&ust=1727600000000000&usg=AOvVaw1x",
         "https://developer.apple.com/documentation/webkit"),
        // Facebook's outbound link, and the fbclid it adds.
        ("https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.nytimes.com%2F2026%2F09%2F28%2Fworld%2Fexample.html%3Ffbclid%3DIwZXh0bgNhZW0CMTEAAR2&h=AT0xyzABC",
         "https://www.nytimes.com/2026/09/28/world/example.html"),
        // A newsletter's own tracking, with nothing to unwrap.
        ("https://www.theguardian.com/world?utm_source=newsletter&utm_medium=email&id=5",
         "https://www.theguardian.com/world?id=5"),
    ]

    @Test(arguments: cleaned)
    func redirectsAndTrackingAreCleaned(_ pair: (String, String)) throws {
        #expect(try Self.accept(pair.0) == .success(try #require(URL(string: pair.1))))
    }

    @Test func aClearLinkIsLeftAsItIs() throws {
        let text = "https://www.theguardian.com/world?id=5"
        #expect(try Self.accept(text) == .success(try #require(URL(string: text))))
    }

    @Test func theShieldOffLeavesItAsSent() throws {
        let text = "https://www.theguardian.com/world?utm_source=newsletter"
        #expect(try Self.accept(text, shieldOn: false) == .success(try #require(URL(string: text))))
    }

    @Test func beforeTheRulesHaveLoadedItIsOnlyChecked() throws {
        let text = "https://www.theguardian.com/world?utm_source=newsletter"
        #expect(try Self.accept(text, cleaning: nil) == .success(try #require(URL(string: text))))
        #expect(try Self.accept("javascript:alert(1)", cleaning: nil) == .failure(.notWeb))
    }

    /// What a redirect was hiding is checked too, so it can't smuggle in a
    /// password the outer link didn't show.
    @Test func whatARedirectHidCannotCarryCredentials() throws {
        let hidden = "https://www.google.com/url?q=https%3A%2F%2Fwww.apple.com%40evil.example%2F&sa=D"
        #expect(try Self.accept(hidden) == .failure(.credentials))
    }
    @Test(arguments: ["http://example.com:65536/", "https://example.com/%00", "https://example.com/?q=%00", "https://%00.example/", "http://user%40host/", "http://host%2Fother/", "http://host%20name/", "http://host%0Aname/"])
    func malformedWebLinksAreRejected(_ text: String) throws {
        #expect(try Self.accept(text) == .failure(.malformed))
    }

    @Test(arguments: ["javascript:alert(1)", "data:text/html,secret", "file:///tmp/secret", "https://user@evil.example/", "https://example.com:99999/", "https://example.com/%00"])
    func nestedRedirectDestinationsAreChecked(_ destination: String) throws {
        var inner = URLComponents(string: "https://l.facebook.com/l.php")!
        inner.queryItems = [.init(name: "u", value: destination)]
        var outer = URLComponents(string: "https://www.google.com/url")!
        outer.queryItems = [.init(name: "q", value: inner.url!.absoluteString)]
        let rejection: IncomingLink.Rejection = destination.hasPrefix("https://user@") ? .credentials
            : destination.hasPrefix("https:") ? .malformed : .notWeb
        #expect(IncomingLink.accept(outer.url!, cleaning: Self.field, shieldOn: true) == .failure(rejection))
    }

    @Test func uppercaseRedirectDestinationIsCleaned() throws {
        let text = "https://www.google.com/url?q=HTTPS%3A%2F%2Fexample.org%2Fa%3Futm_source%3Dmail"
        #expect(try Self.accept(text) == .success(URL(string: "HTTPS://example.org/a")!))
    }

    @Test func idnsAndLongValidPathsAreAccepted() throws {
        for text in ["https://例え.jp/", "https://xn--r8jz45g.jp/", "https://example.com/" + String(repeating: "a", count: 100_000)] {
            #expect(try Self.accept(text) == .success(URL(string: text)!))
        }
    }

    @Test func redirectChainsBeyondTheGuardsLimitAreRefused() {
        var url = URL(string: "https://user@evil.example/")!
        for index in 0..<5 {
            var parts = URLComponents(string: index % 2 == 0 ? "https://www.google.com/url" : "https://l.facebook.com/l.php")!
            parts.queryItems = [.init(name: index % 2 == 0 ? "q" : "u", value: url.absoluteString)]
            url = parts.url!
        }
        #expect(IncomingLink.accept(url, cleaning: Self.field, shieldOn: true) == .failure(.malformed))
    }

    @Test func theShieldReceivesTheIDNsCanonicalHost() {
        let url = URL(string: "https://例え.jp/?utm_source=mail")!
        var host: String?
        #expect(IncomingLink.accept(url, cleaning: Self.field, shieldOn: { host = $0; return false }) == .success(url))
        #expect(host == "xn--r8jz45g.jp")
    }

}
