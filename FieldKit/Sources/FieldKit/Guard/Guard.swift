import Foundation

/// A main-frame navigation as `decidePolicyFor` sees it, reduced to what the
/// guard needs.
public struct Navigation: Sendable {
    public enum Kind: Sendable {
        case link, typed, script, formSubmit, backForward, reload, other
    }

    public var url: URL
    /// The page the navigation starts from, or nil when there is none: typed,
    /// or opened from another app.
    public var source: URL?
    public var kind: Kind
    public var isMainFrame: Bool
    public var opensNewWindow: Bool
    /// `.linkActivated`: the only public sign that a person asked for this.
    public var userTapped: Bool

    public init(url: URL, source: URL? = nil, kind: Kind = .link, isMainFrame: Bool = true,
                opensNewWindow: Bool = false, userTapped: Bool = false) {
        self.url = url
        self.source = source
        self.kind = kind
        self.isMainFrame = isMainFrame
        self.opensNewWindow = opensNewWindow
        self.userTapped = userTapped
    }
}

public enum Verdict: Sendable, Equatable {
    case allow
    /// Cancel, then load this instead.
    case rewrite(URL)
    case block(Reason)
    /// Another app or scheme: ask first, then hand it to the system.
    case askToLeave(URL)

    public enum Reason: Sendable, Equatable {
        /// A page, not a person, tried to open another app.
        case otherApp
        /// A page, not a person, tried to throw you into the App Store.
        case appStore
        /// A scheme nothing should open from a page: javascript:, file:.
        case unsupported
    }
}

/// Decides what happens to a navigation before it leaves: the scheme gate,
/// link shims unwrapped, tracking parameters stripped, AMP undone and pages
/// kept from throwing you into other apps (docs/PLAN.md, "Navigation guard").
/// Every step is a hash lookup on the host; nothing here touches the network.
public struct Guard: Sendable {
    public let rules: GuardRules

    public init(rules: GuardRules) {
        self.rules = rules
    }

    /// Schemes a tab shows itself.
    private static let web: Set<String> = ["http", "https", "about", "data", "blob"]
    /// Schemes nothing should hand to the system from a page, tapped or not.
    private static let never: Set<String> = ["javascript", "file"]
    private static let appStoreSchemes: Set<String> = ["itms", "itms-apps", "itms-appss"]
    private static let appStoreHosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]
    /// Navigations that can be cancelled and loaded again as something else.
    /// Not a form, which may be a POST, and not history, which would grow.
    private static let fresh: Set<Navigation.Kind> = [.link, .typed, .script, .other]
    /// A shim inside a shim is real; a tower of them isn't worth following.
    private static let unwrapLimit = 4

    public func decide(_ nav: Navigation, shieldOn: Bool) -> Verdict {
        // 1. The scheme gate, the one step the shield's off switch keeps.
        guard let scheme = nav.url.scheme?.lowercased() else { return .allow }
        let asked = nav.userTapped || nav.kind == .typed
        if !Self.web.contains(scheme) {
            if Self.never.contains(scheme) { return .block(.unsupported) }
            if asked { return .askToLeave(nav.url) }
            return .block(Self.appStoreSchemes.contains(scheme) ? .appStore : .otherApp)
        }
        guard shieldOn, nav.isMainFrame, scheme == "http" || scheme == "https",
              let host = GuardRules.host(of: nav.url), !Address.isLocal(host: host) else { return .allow }

        // 2–4. Unwrap, strip, de-AMP.
        let target = Self.fresh.contains(nav.kind)
            ? cleaned(nav.url, host: host, from: nav.kind == .typed ? nil : nav.source)
            : nav.url

        // 5. A page sending you to the App Store without a tap.
        if !asked, nav.kind != .backForward, nav.kind != .reload,
           let to = GuardRules.host(of: target), Self.appStoreHosts.contains(to),
           let source = nav.source, GuardRules.host(of: source) != to {
            return .block(.appStore)
        }
        return target == nav.url ? .allow : .rewrite(target)
    }

    /// 6. Whether to set `preferredHTTPSNavigationPolicy` to
    /// `.automaticFallbackToHTTP` for this navigation: plain http to anywhere
    /// but this machine or its network, which rarely has a certificate.
    public func prefersHTTPS(_ nav: Navigation, shieldOn: Bool) -> Bool {
        guard shieldOn, nav.isMainFrame, nav.url.scheme?.lowercased() == "http",
              let host = GuardRules.host(of: nav.url) else { return false }
        return !Address.isLocal(host: host)
    }

    /// The address to copy or share: its tracking parameters stripped
    /// whatever site it's on, since whoever gets it comes from somewhere
    /// else. A page's `pushState` can put them back after a navigation was
    /// cleaned.
    public func stripped(_ url: URL) -> URL {
        guard let host = GuardRules.host(of: url), !Address.isLocal(host: host) else { return url }
        return rules.tracking.stripped(url, host: host) ?? url
    }

    /// The address with its shims unwrapped and, when it crosses to another
    /// site, its tracking parameters stripped. Same-site navigations keep
    /// theirs, as in Brave: a site's own utm_source is its own business. An
    /// address a shim was hiding always crosses, since the shim is the page
    /// it came from as far as the target can tell.
    private func cleaned(_ url: URL, host: String, from source: URL?) -> URL {
        var url = url, host = host
        var site = rules.suffixes.site(of: host)
        var unwrapped = false
        for _ in 0..<Self.unwrapLimit {
            guard let next = rules.unwraps.target(of: url, host: host, site: site, suffixes: rules.suffixes),
                  let nextHost = GuardRules.host(of: next) else { break }
            url = next
            host = nextHost
            site = rules.suffixes.site(of: host)
            unwrapped = true
        }
        let crossSite = unwrapped
            || source.flatMap(GuardRules.host(of:)).map { rules.suffixes.site(of: $0) != site } ?? true
        guard crossSite, !Address.isLocal(host: host),
              let stripped = rules.tracking.stripped(url, host: host) else { return url }
        return stripped
    }
}
