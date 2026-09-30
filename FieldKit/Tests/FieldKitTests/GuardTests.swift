import Foundation
import Testing
@testable import FieldKit

// The navigation guard against real addresses, one table per step of
// docs/PLAN.md "Navigation guard". Each row is what a page, or a person, asks
// for and what should happen to it.
struct GuardTests {
    static let field = Guard(rules: .bundled)

    static let search = "https://www.google.com/search?q=swift"

    /// Decides for an address, from a page, with the shield on unless told
    /// otherwise.
    static func decide(_ url: String, from source: String? = search, kind: Navigation.Kind = .link,
                       tapped: Bool = true, mainFrame: Bool = true, newWindow: Bool = false,
                       shield: Bool = true) throws -> Verdict {
        let nav = Navigation(url: try #require(URL(string: url)), source: source.flatMap(URL.init(string:)),
                             kind: kind, isMainFrame: mainFrame, opensNewWindow: newWindow, userTapped: tapped)
        return field.decide(nav, shieldOn: shield)
    }

    static func rewrite(_ url: String) throws -> Verdict {
        .rewrite(try #require(URL(string: url)))
    }

    // MARK: - Link shims

    static let shims: [(String, String)] = [
        // A Google web result, as the results page links it.
        ("https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://en.wikipedia.org/wiki/Swift_(programming_language)&ved=2ahUKEwjX9&usg=AOvVaw0abc",
         "https://en.wikipedia.org/wiki/Swift_(programming_language)"),
        // Docs and Gmail use q=.
        ("https://www.google.com/url?q=https://developer.apple.com/documentation/webkit&sa=D&source=docs&ust=1727600000000000&usg=AOvVaw1x",
         "https://developer.apple.com/documentation/webkit"),
        // Another country's Google, with the target encoded.
        ("https://www.google.co.uk/url?q=https%3A%2F%2Fwww.bbc.co.uk%2Fnews%3Fid%3D5&sa=U",
         "https://www.bbc.co.uk/news?id=5"),
        // An ad click, and the gclid on its landing page goes with it.
        ("https://www.googleadservices.com/pagead/aclk?sa=L&ai=DChcSEwi&ohost=www.google.com&cid=CAESVeD2&sig=AOD64_3&adurl=https://www.example-shoes.com/sale%3Fgclid%3DCj0KCQjw",
         "https://www.example-shoes.com/sale"),
        ("https://www.google.com/aclk?sa=l&ai=DChcSEwj&adurl=https%3A%2F%2Fwww.example-shoes.com%2Fboots",
         "https://www.example-shoes.com/boots"),
        // Facebook's outbound link, with the fbclid it adds to the target.
        ("https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.nytimes.com%2F2026%2F09%2F28%2Fworld%2Fexample.html%3Ffbclid%3DIwZXh0bgNhZW0CMTEAAR2&h=AT0xyzABC&__tn__=H-R&c%5B0%5D=AT1abc",
         "https://www.nytimes.com/2026/09/28/world/example.html"),
        ("https://lm.facebook.com/l.php?u=https%3A%2F%2Fwww.theguardian.com%2Fworld&h=AT3",
         "https://www.theguardian.com/world"),
        ("https://l.instagram.com/?u=https%3A%2F%2Fwww.apple.com%2Fiphone%2F&e=AT0",
         "https://www.apple.com/iphone/"),
        ("https://out.reddit.com/t3_1fq2abc?url=https%3A%2F%2Fgithub.com%2Fswiftlang%2Fswift&token=AQAAq8b5ZgAbc&app_name=web2x&web_redirect=true",
         "https://github.com/swiftlang/swift"),
        ("https://www.youtube.com/redirect?event=video_description&redir_token=QUFFLUhqbXc&q=https%3A%2F%2Fwww.patreon.com%2Fexample&v=dQw4w9WgXcQ",
         "https://www.patreon.com/example"),
        ("https://m.youtube.com/redirect?q=https%3A%2F%2Fexample.org%2F&redir_token=abc",
         "https://example.org/"),
        // From Brave's debounce table: a query parameter, a path, base64 and a template.
        ("https://go.skimresources.com/?id=12345X678901&xs=1&url=https%3A%2F%2Fwww.bestbuy.com%2Fsite%2Fapple-airpods%2F6447382.p&xcust=xid%3Afr1727",
         "https://www.bestbuy.com/site/apple-airpods/6447382.p"),
        ("https://click.linksynergy.com/deeplink?id=abcDEF&mid=13867&murl=https%3A%2F%2Fwww.macys.com%2Fshop%2Fmens",
         "https://www.macys.com/shop/mens"),
        ("https://abc123.r.us-east-1.awstrack.me/L0/https:%2F%2Fwww.example.com%2Fwelcome%3Fref=mail/1/0100018c-abc/xyz=345",
         "https://www.example.com/welcome?ref=mail"),
        ("https://example.lt.acemlna.com/Prod/link-tracker?redirectUrl=aHR0cHM6Ly93d3cuZXhhbXBsZS5vcmcvc2FsZQ%3D%3D&sig=abc&iat=1727",
         "https://www.example.org/sale"),
        ("https://y2u.be/dQw4w9WgXcQ", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        // A shim inside a shim.
        ("https://www.google.com/url?q=https%3A%2F%2Fl.facebook.com%2Fl.php%3Fu%3Dhttps%253A%252F%252Fexample.net%252Fpost&sa=D",
         "https://example.net/post"),
        // Written in capitals, and with the root's trailing dot.
        ("HTTPS://WWW.GOOGLE.COM/url?q=https://example.com/", "https://example.com/"),
        ("https://www.google.com./url?q=https://example.com/", "https://example.com/"),
    ]

    @Test(arguments: shims)
    func aShimIsUnwrapped(url: String, target: String) throws {
        #expect(try Self.decide(url) == Self.rewrite(target))
    }

    @Test(arguments: [
        // The target is on the shim's own site.
        "https://www.google.com/url?q=https://maps.google.com/maps&sa=D",
        "https://go.skimresources.com/?url=https%3A%2F%2Fskimresources.com%2Fabout",
        // Nothing to unwrap to.
        "https://www.google.com/url?sa=t&source=web",
        "https://www.google.com/url?q=",
        "https://www.google.com/url?q=/search%3Fq%3Dswift",
        "https://l.facebook.com/l.php?u=javascript%3Aalert(1)",
        "https://out.reddit.com/t3_abc?url=ftp%3A%2F%2Fexample.com%2F",
        // Not a shim.
        "https://www.google.com/search?q=url",
        "https://notgoogle.com/url?q=https://example.org/",
        "https://google.example.com/url?q=https://example.org/",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        // Opaque shorteners can't be unwrapped here.
        "https://t.co/AbCdEf123",
        "https://bit.ly/3xYzAbC",
    ])
    func notEverythingIsAShim(url: String) throws {
        #expect(try Self.decide(url) == .allow)
    }

    // MARK: - Tracking parameters

    static let crossSite: [(String, String, String)] = [
        ("https://www.nytimes.com/2026/09/28/world/example.html?fbclid=IwAR2xyz&smid=fb-share", "https://www.facebook.com/",
         "https://www.nytimes.com/2026/09/28/world/example.html?smid=fb-share"),
        ("https://shop.example.com/p/123?color=red&gclid=Cj0KCQjw", search,
         "https://shop.example.com/p/123?color=red"),
        ("https://blog.example.com/post?utm_source=newsletter&utm_medium=email&utm_campaign=launch&utm_term=swift&utm_content=cta",
         "https://mail.proton.me/u/0/inbox", "https://blog.example.com/post"),
        ("https://example.com/landing?msclkid=abc123&ttclid=E.C.P&twclid=2-xyz&mc_eid=f00&_hsenc=p2AN", "https://www.bing.com/",
         "https://example.com/landing"),
        // Scoped to their own sites.
        ("https://www.instagram.com/p/C8abcDEF/?igshid=MzRlODBiNWFlZA==", "https://x.com/home",
         "https://www.instagram.com/p/C8abcDEF/"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=Hx9abcDEF123", "https://www.reddit.com/",
         "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        ("https://x.com/apple/status/1?ref_src=twsrc%5Etfw", "https://www.apple.com/",
         "https://x.com/apple/status/1"),
        // Order and encoding of the rest stay exactly as they were.
        ("https://example.org/search?b=2&utm_source=x&a=%20%2B%C3%A9&fbclid=y&c&d=", "https://example.net/",
         "https://example.org/search?b=2&a=%20%2B%C3%A9&c&d="),
        ("https://example.org/a?fbclid=x#section-2", "https://example.net/", "https://example.org/a#section-2"),
        ("https://example.org/a?gclid=", "https://example.net/", "https://example.org/a"),
        // Different sites under a shared suffix.
        ("https://bob.github.io/?fbclid=1", "https://alice.github.io/", "https://bob.github.io/"),
        ("https://www.bbc.co.uk/news?fbclid=1", "https://www.itv.co.uk/", "https://www.bbc.co.uk/news"),
        // An address on another site: IPv6.
        ("https://[2001:db8::1]/?fbclid=1", "https://example.net/", "https://[2001:db8::1]/"),
    ]

    @Test(arguments: crossSite)
    func trackingParametersAreStrippedAcrossSites(url: String, source: String, target: String) throws {
        #expect(try Self.decide(url, from: source) == Self.rewrite(target))
    }

    /// Typed, pasted or opened from another app: there is no page to be on
    /// the same site as, so they go, as in Brave.
    @Test(arguments: [
        ("https://youtu.be/dQw4w9WgXcQ?si=Hx9abcDEF123", Navigation.Kind.typed, "https://youtu.be/dQw4w9WgXcQ"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=Hx9abc", .other, "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        ("https://www.instagram.com/reel/C9xyz/?igsh=MWQ1ZGUxMzBkMA%3D%3D", .other, "https://www.instagram.com/reel/C9xyz/"),
    ])
    func withNoPageTheyGoToo(url: String, kind: Navigation.Kind, target: String) throws {
        #expect(try Self.decide(url, from: nil, kind: kind) == Self.rewrite(target))
    }

    @Test func typedIsNeverSameSite() throws {
        #expect(try Self.decide("https://www.nytimes.com/?utm_source=x", from: "https://www.nytimes.com/", kind: .typed)
                    == Self.rewrite("https://www.nytimes.com/"))
    }

    @Test(arguments: [
        // Same site: a site's own utm_source is its business (Brave's rule).
        ("https://www.nytimes.com/section/world?utm_source=homepage", "https://www.nytimes.com/"),
        ("https://www.nytimes.com/section/world?fbclid=1", "https://cooking.nytimes.com/"),
        ("https://news.bbc.co.uk/?fbclid=1", "https://www.bbc.co.uk/"),
        // Scoped parameters stay on other sites.
        ("https://www.example.com/?si=abc&igshid=def&ref_src=ghi", "https://www.youtube.com/"),
        // Near misses.
        ("https://example.org/?fbclid_keep=1&xfbclid=2&UTM_SOURCE=3", "https://example.net/"),
        // A "?" in the fragment isn't a query.
        ("https://example.org/#/route?fbclid=x", "https://example.net/"),
        // DuckDuckGo's exceptions, where stripping breaks the site.
        ("https://www.axs.com/events/123?utm_source=spotify&fbclid=1", "https://open.spotify.com/"),
        ("https://urldefense.com/v3/__https://example.com__;!!abc?utm_source=x", "https://outlook.live.com/"),
        // Nothing to strip.
        ("https://example.org/?q=swift&page=2", "https://example.net/"),
        ("https://example.org/", "https://example.net/"),
    ])
    func somethingsStay(url: String, source: String) throws {
        #expect(try Self.decide(url, from: source) == .allow)
    }

    // MARK: - AMP

    static let amp: [(String, String)] = [
        ("https://www.google.com/amp/s/www.bbc.co.uk/news/amp/world-68000000", "https://www.bbc.co.uk/news/amp/world-68000000"),
        ("https://www.google.de/amp/s/www.spiegel.de/politik/artikel-a-123.amp", "https://www.spiegel.de/politik/artikel-a-123.amp"),
        ("https://www-theverge-com.cdn.ampproject.org/c/s/www.theverge.com/platform/amp/2026/9/28/12345/apple",
         "https://www.theverge.com/platform/amp/2026/9/28/12345/apple"),
        // The viewer's own parameters don't come along.
        ("https://www.google.com/amp/s/example.com/story?amp_js_v=0.1&usqp=mq331AQIUAKwASCAAgM%3D", "https://example.com/story"),
    ]

    @Test(arguments: amp)
    func ampGoesToThePublisher(url: String, target: String) throws {
        #expect(try Self.decide(url) == Self.rewrite(target))
    }

    // MARK: - The app's own load of a rewrite

    /// A rewrite comes back through `decide` as the app's own load, which the
    /// app passes as `.typed`. It has to be let through, or the tab loops.
    @Test(arguments: shims.map(\.1) + crossSite.map(\.2) + amp.map(\.1) + ["https://apps.apple.com/app/id1234567890"])
    func aRewriteIsLetThroughTheSecondTime(target: String) throws {
        #expect(try Self.decide(target, from: nil, kind: .typed, tapped: false) == .allow)
    }

    // MARK: - Other apps and the App Store

    static let sketchy = "https://free-prizes.example/win"

    @Test(arguments: [
        ("https://apps.apple.com/us/app/example/id1234567890", Navigation.Kind.script),
        ("https://apps.apple.com/us/app/example/id1234567890", .other),
        ("https://apps.apple.com/us/app/example/id1234567890", .link),
        ("https://itunes.apple.com/us/app/id1234567890?mt=8", .script),
        // Hidden behind a shim.
        ("https://www.google.com/url?q=https://apps.apple.com/app/id1234567890", .script),
    ])
    func aPageCantThrowYouIntoTheAppStore(url: String, kind: Navigation.Kind) throws {
        #expect(try Self.decide(url, from: Self.sketchy, kind: kind, tapped: false) == .block(.appStore))
    }

    @Test func norCanAPopupItOpened() throws {
        #expect(try Self.decide("https://apps.apple.com/app/id1234567890", from: "about:blank", kind: .other,
                                tapped: false, newWindow: true) == .block(.appStore))
    }

    @Test func butYouCanGoThere() throws {
        let store = "https://apps.apple.com/us/app/example/id1234567890"
        #expect(try Self.decide(store, from: Self.sketchy, kind: .link, tapped: true) == .allow)
        #expect(try Self.decide(store, from: nil, kind: .typed, tapped: false) == .allow)
        #expect(try Self.decide("https://www.google.com/url?q=\(store)", from: Self.search, tapped: true)
                    == Self.rewrite(store))
        // Within the App Store's own pages.
        #expect(try Self.decide("https://apps.apple.com/us/app/other/id99", from: store, kind: .script, tapped: false)
                    == .allow)
    }

    @Test(arguments: [
        ("itms-apps://apps.apple.com/app/id1234567890", Verdict.Reason.appStore),
        ("itms-appss://apps.apple.com/app/id1234567890", .appStore),
        ("fb://profile/4", .otherApp),
        ("instagram://user?username=apple", .otherApp),
        ("mailto:hello@example.com?subject=Hi", .otherApp),
        ("tel:+15555550123", .otherApp),
        ("sms:+15555550123", .otherApp),
        ("javascript:alert(1)", .unsupported),
        ("file:///etc/passwd", .unsupported),
    ])
    func aPageCantOpenAnotherApp(url: String, reason: Verdict.Reason) throws {
        #expect(try Self.decide(url, from: Self.sketchy, kind: .script, tapped: false) == .block(reason))
        #expect(try Self.decide(url, from: Self.sketchy, kind: .other, tapped: false) == .block(reason))
        #expect(try Self.decide(url, from: Self.sketchy, kind: .script, tapped: false, mainFrame: false) == .block(reason))
    }

    @Test(arguments: [
        "itms-apps://apps.apple.com/app/id1234567890",
        "fb://profile/4",
        "mailto:hello@example.com?subject=Hi",
        "tel:+15555550123",
        "maps://?q=Paris",
    ])
    func aTapAsksFirst(url: String) throws {
        let target = try #require(URL(string: url))
        #expect(try Self.decide(url, from: Self.sketchy, tapped: true) == .askToLeave(target))
        #expect(try Self.decide(url, from: Self.sketchy, tapped: true, shield: false) == .askToLeave(target))
    }

    @Test(arguments: ["javascript:alert(1)", "file:///etc/passwd"])
    func someSchemesNeverLeaveEvenOnATap(url: String) throws {
        #expect(try Self.decide(url, from: Self.sketchy, tapped: true) == .block(.unsupported))
    }

    @Test(arguments: ["about:blank", "about:srcdoc", "data:text/html,hi", "blob:https://example.com/0b7e2f5a-1c3d"])
    func theWebsOwnSchemesPass(url: String) throws {
        #expect(try Self.decide(url, from: Self.sketchy, kind: .script, tapped: false) == .allow)
    }

    // MARK: - Local addresses

    @Test(arguments: [
        "http://192.168.1.1/?fbclid=1&utm_source=x",
        "http://localhost:3000/url?q=https://example.com/",
        "http://printer.local/?gclid=1",
        "http://[::1]:8080/?fbclid=1",
        "http://10.0.0.1/amp/s/example.com/",
    ])
    func aLocalAddressIsNeverRewritten(url: String) throws {
        #expect(try Self.decide(url, from: Self.search) == .allow)
        #expect(try Self.decide(url, from: nil, kind: .typed) == .allow)
    }

    // MARK: - The shield off

    @Test(arguments: [
        ("https://www.google.com/url?q=https://developer.apple.com/&sa=D", Navigation.Kind.link, true),
        ("https://www.nytimes.com/?fbclid=IwAR2xyz", .link, true),
        ("https://www.google.com/amp/s/www.bbc.co.uk/news/amp/world-1", .link, true),
        ("https://apps.apple.com/app/id1234567890", .script, false),
    ])
    func withTheShieldOffOnlyTheSchemeGateIsLeft(url: String, kind: Navigation.Kind, tapped: Bool) throws {
        #expect(try Self.decide(url, from: Self.sketchy, kind: kind, tapped: tapped, shield: false) == .allow)
    }

    @Test func theSchemeGateStaysWithTheShieldOff() throws {
        #expect(try Self.decide("fb://profile/4", from: Self.sketchy, kind: .script, tapped: false, shield: false)
                    == .block(.otherApp))
    }

    // MARK: - Kinds of navigation

    @Test(arguments: [Navigation.Kind.formSubmit, .backForward, .reload])
    func onlyFreshNavigationsAreRewritten(kind: Navigation.Kind) throws {
        #expect(try Self.decide("https://www.nytimes.com/?fbclid=1", from: "https://www.facebook.com/", kind: kind) == .allow)
        #expect(try Self.decide("https://www.google.com/url?q=https://example.org/", kind: kind) == .allow)
    }

    @Test func aFrameIsntRewritten() throws {
        #expect(try Self.decide("https://www.nytimes.com/?fbclid=1", from: "https://www.facebook.com/", mainFrame: false) == .allow)
    }

    @Test(arguments: [Navigation.Kind.link, .script, .other])
    func aScriptOrRedirectIsRewrittenToo(kind: Navigation.Kind) throws {
        #expect(try Self.decide("https://www.nytimes.com/?fbclid=1", from: "https://www.facebook.com/", kind: kind, tapped: false)
                    == Self.rewrite("https://www.nytimes.com/"))
    }

    // MARK: - HTTPS first

    @Test(arguments: [
        ("http://example.com/", true, true),
        ("http://neverssl.com/online", true, true),
        ("https://example.com/", true, false),
        ("http://localhost:8080/", true, false),
        ("http://192.168.0.1/", true, false),
        ("http://example.com/", false, false),
        ("about:blank", true, false),
    ])
    func httpsFirst(url: String, shield: Bool, expected: Bool) throws {
        let nav = Navigation(url: try #require(URL(string: url)), source: nil, kind: .typed)
        #expect(Self.field.prefersHTTPS(nav, shieldOn: shield) == expected)
    }

    // MARK: - Malformed

    @Test(arguments: [
        "https:",
        "https:///path?fbclid=1",
        "https://www.google.com/url?q=%ZZ%",
        "https://www.google.com/url?q=https://",
        "https://www.google.com/url?q=not%20a%20url",
        "https://www.google.com/url?q=https%3A%2F%2F%5B%3A%3A1",
        "https://example.lt.acemlna.com/Prod/link-tracker?redirectUrl=!!notbase64!!",
        "https://example.lt.acemlna.com/Prod/link-tracker?redirectUrl=%FF%FE",
        "https://abc.awstrack.me/L0/%E0%A4%A/1/x",
        "https://y2u.be/",
        "//example.com/?fbclid=1",
        "https://example.org/?&&=&fbclid",
    ])
    func malformedIsAllowedNotCrashed(url: String) throws {
        let verdict = try Self.decide(url, from: "https://example.net/")
        if case .rewrite(let target) = verdict {
            // Only the stray parameters come off.
            #expect(!target.absoluteString.contains("fbclid"))
        } else {
            #expect(verdict == .allow)
        }
    }

    @Test func aTowerOfShimsEnds() throws {
        var url = "https://example.org/end"
        for host in ["www.google.com", "www.google.de", "www.google.fr", "www.google.it", "www.google.es",
                     "www.google.nl", "www.google.pl", "www.google.ca"] {
            url = "https://\(host)/url?q=" + url.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        }
        guard case .rewrite(let target) = try Self.decide(url) else {
            Issue.record("expected a rewrite")
            return
        }
        #expect(target.host() != "www.google.ca")
    }
}
