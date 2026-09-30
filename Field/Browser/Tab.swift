import FieldKit
import SwiftUI
import WebKit
import os

/// A tab: its web view, and what the bar, the page and the tab grid need to
/// know about it. The web view is built after the first frame, and SwiftUI
/// never rebuilds it. Asleep, a tab has no web view at all: only its address,
/// its interaction state (the back and forward list, where it was scrolled
/// to) and a picture, until it's shown again (see Tabs).
@MainActor @Observable final class Tab: NSObject, Identifiable {
    let id: UUID
    private(set) var web: WKWebView?
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// For the back button's menu.
    private(set) var back: [WKBackForwardListItem] = []
    private(set) var forward: [WKBackForwardListItem] = []
    /// A load that failed, said in one sentence in place of the page.
    private(set) var failure: String?
    /// The address the blocker stopped, when that's why `failure` is set.
    private(set) var blocked: URL?
    /// Whether the page reads as light or dark, from its background; nil
    /// until it has one. The glass bar over it takes the same.
    private(set) var tone: ColorScheme?

    @ObservationIgnored var announce: (String) -> Void = { _ in }
    /// A toast with something to do about it: "Open".
    @ObservationIgnored var offer: (String, Toaster.Offer) -> Void = { _, _ in }
    /// A popup the person asked for after all, in a tab of its own.
    @ObservationIgnored var openTab: (URL) -> Void = { _ in }
    /// A new page has replaced the old one.
    @ObservationIgnored var committed: () -> Void = {}
    /// A web page finished loading, at this address.
    @ObservationIgnored var finished: (URL) -> Void = { _ in }
    /// The address or the title changed: what the session keeps.
    @ObservationIgnored var changed: () -> Void = {}
    /// The page has painted since the web view was built; whatever covered
    /// it can go.
    @ObservationIgnored var revealed: () -> Void = {}
    /// On screen. Set by Tabs.
    @ObservationIgnored var visible = false
    /// When it was last on screen, for the sleep policy.
    @ObservationIgnored var seen = Date.now
    /// The interaction state to come back to, while asleep.
    @ObservationIgnored private(set) var saved: Data?
    @ObservationIgnored private var revival = Revival()
    @ObservationIgnored private var waking: OSSignpostIntervalState?

    @ObservationIgnored private let history: HistoryStore
    /// Asked for before there was a web view to load it.
    @ObservationIgnored private var pending: URL?
    @ObservationIgnored private var failed: URL?
    @ObservationIgnored private var unpainted = true
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []
    /// The web view's, kept: `web.configuration` makes a copy on every call.
    @ObservationIgnored private var content: WKUserContentController?
    /// The app's own load is under way, until it commits or fails: its
    /// navigations, and the redirects it meets, are the guard's `.typed`.
    @ObservationIgnored private var asked = false

    init(history: HistoryStore, entry: Session.Entry? = nil) {
        self.history = history
        id = entry?.id ?? UUID()
        if let entry {
            url = URL(string: entry.url)
            title = entry.title
            saved = entry.interactionState
        }
    }

    /// Has somewhere to be but no web view: shown, it wakes.
    var asleep: Bool { web == nil && (url != nil || saved != nil) }
    var isPainted: Bool { !unpainted }

    /// Doing something that waking couldn't give back: on a call.
    var held: Bool {
        guard let web else { return false }
        return web.cameraCaptureState != .none || web.microphoneCaptureState != .none
    }

    /// What session.json keeps of it.
    var entry: Session.Entry {
        let state = (web?.interactionState as? Data) ?? saved
        return Session.Entry(id: id, url: url?.absoluteString ?? "", title: title, interactionState: state)
    }

    /// Where Field's own scripts run: a world beside the page's, so the page
    /// sees none of them, and no `window.webkit` that would mark it as an
    /// app's web view rather than a browser.
    static let world = WKContentWorld.world(name: "Field")

    /// Makes the web view, and loads what was asked for before it, or wakes
    /// where the tab was when it went to sleep.
    func build() {
        guard web == nil else { return }
        if asleep { waking = Signpost.log.beginInterval("tab.wake") }
        let building = Signpost.log.beginInterval("tab.build")
        defer { Signpost.log.endInterval("tab.build", building) }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .audio
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.applicationNameForUserAgent = Tab.userAgentName
        let paint = PaintRelay()
        paint.tab = self
        config.userContentController.add(paint, contentWorld: Tab.world, name: PaintRelay.name)
        config.userContentController.addUserScript(
            WKUserScript(source: PaintRelay.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Tab.world)
        )

        content = config.userContentController
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = Palette.UI.ground
        web.accessibilityIdentifier = "page"
        #if DEBUG
        web.isInspectable = true
        #endif
        // Unseen until the page first paints: a web view that has never drawn
        // shows nothing worth seeing, and the ground under it is the same colour.
        web.alpha = 0

        let refresh = UIRefreshControl()
        refresh.tintColor = Palette.UI.muted
        refresh.addAction(UIAction { [weak self] _ in self?.reload() }, for: .valueChanged)
        web.scrollView.refreshControl = refresh

        watching = [
            watch(web, \.url) { tab, web in
                if let url = web.url { tab.url = url }
            },
            watch(web, \.isLoading) { tab, web in tab.isLoading = web.isLoading },
            watch(web, \.canGoBack) { tab, web in tab.canGoBack = web.canGoBack },
            watch(web, \.canGoForward) { tab, web in tab.canGoForward = web.canGoForward },
            watch(web, \.underPageBackgroundColor) { tab, web in tab.sampleTone() },
            watch(web, \.title) { tab, web in
                guard let title = web.title, !title.isEmpty, let url = web.url else { return }
                tab.title = title
                tab.changed()
                tab.history.retitled(url, title)
            },
        ]
        self.web = web
        if let pending {
            self.pending = nil
            saved = nil
            load(pending)
        } else if let saved {
            self.saved = nil
            web.interactionState = saved
        } else if let url {
            // Restored from a session without a state (the Mac's): the address alone.
            open(URLRequest(url: url))
        }
    }

    /// Gives the web view back, keeping where it was. The picture to show
    /// while it wakes was taken when it was last left (see Tabs).
    func sleep() {
        guard let web else { return }
        saved = web.interactionState as? Data
        watching.forEach { $0.invalidate() }
        watching = []
        web.navigationDelegate = nil
        web.uiDelegate = nil
        web.scrollView.delegate = nil
        web.configuration.userContentController.removeAllScriptMessageHandlers()
        web.stopLoading()
        web.removeFromSuperview()
        self.web = nil
        content = nil
        asked = false
        unpainted = true
        isLoading = false
        endWake()
    }

    /// A picture of the page as it is, `width` points wide.
    func snapshot(width: CGFloat) async -> UIImage? {
        guard let web, !unpainted, failure == nil else { return nil }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(width))
        config.afterScreenUpdates = false
        return try? await web.takeSnapshot(configuration: config)
    }

    /// Something typed into the page and not sent, which sleeping would lose.
    func holdsTyping() async -> Bool {
        guard let web else { return false }
        let found = try? await web.evaluateJavaScript(Tab.typedScript, contentWorld: Tab.world)
        return (found as? Bool) == true
    }

    private static let typedScript = """
    (() => {
        const skip = new Set(["hidden", "submit", "button", "reset", "checkbox", "radio", "range", "color", "file", "image"]);
        for (const el of document.querySelectorAll("input, textarea")) {
            if (el.tagName === "INPUT" && skip.has(el.type)) continue;
            if (el.type === "password") continue;
            if (el.value && el.value !== el.defaultValue) return true;
        }
        return false;
    })()
    """

    /// Shown, or hidden, by Tabs. A page whose process died while hidden
    /// comes back now.
    func show() {
        visible = true
        seen = .now
        if let action = revival.shown() { revive(action) }
    }

    private func revive(_ action: Revival.Action) {
        switch action {
        case .reload:
            web?.reload()
        case .rebuild:
            // The state from before the crash, since the list lives in the app.
            sleep()
            build()
        }
    }

    private func endWake() {
        guard let waking else { return }
        Signpost.log.endInterval("tab.wake", waking)
        self.waking = nil
    }

    private func watch<Value>(
        _ web: WKWebView,
        _ path: KeyPath<WKWebView, Value>,
        _ changed: @escaping @MainActor (Tab, WKWebView) -> Void
    ) -> NSKeyValueObservation {
        web.observe(path) { [weak self] web, _ in
            // WebKit changes all of these on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                changed(self, web)
            }
        }
    }

    func load(_ url: URL) {
        failure = nil
        self.url = url
        guard web != nil else {
            pending = url
            return
        }
        open(URLRequest(url: url))
    }

    /// The app's own load, which the guard takes as typed.
    private func open(_ request: URLRequest) {
        guard let web else { return }
        asked = true
        web.load(request)
    }

    func goBack() { web?.goBack() }
    func go(to item: WKBackForwardListItem) { web?.go(to: item) }

    func retry() {
        if let blocked, let web {
            failure = nil
            self.blocked = nil
            asked = true
            ContentBlocking.shared.loadAnyway(blocked, in: web)
            return
        }
        guard let target = failed ?? url else { return }
        load(target)
    }

    /// On a failed page it tries again; on any other, it reloads.
    func reload() {
        if failure != nil { retry() } else { web?.reload() }
    }

    fileprivate func painted() {
        Signpost.log.emitEvent(Signpost.firstPaint)
        revival.painted()
        reveal()
    }

    /// In quickly: the page is there, and the fade covers only the frame
    /// between WebKit laying it out and putting it on screen.
    private func reveal() {
        guard unpainted, let web else { return }
        unpainted = false
        // Opaque from here on, so WebKit draws the page's own colour above
        // and below it, under the status bar too, instead of the app's
        // ground. Only where the status bar can take the page's tone (see
        // BrowserView): elsewhere the ground keeps the time legible.
        if #available(iOS 27, *) { web.isOpaque = true }
        sampleTone()
        endWake()
        UIView.animate(withDuration: 0.12) { web.alpha = 1 } completion: { [weak self] _ in
            self?.revealed()
        }
    }

    private func sampleTone() {
        guard let web else { return }
        let background = web.underPageBackgroundColor.resolvedColor(with: web.traitCollection)
        let tone = Tab.scheme(for: background)
        if tone != self.tone { self.tone = tone }
    }

    /// Light or dark, by how bright the colour looks (Rec. 709 luma), or nil
    /// for a colour that's mostly see-through.
    static func scheme(for colour: UIColor?) -> ColorScheme? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard let colour, colour.getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5 else { return nil }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5 ? .dark : .light
    }

    private func settled() {
        sampleTone()
        web?.scrollView.refreshControl?.endRefreshing()
        guard let list = web?.backForwardList else { return }
        back = list.backList
        forward = list.forwardList
    }

    private func fail(_ error: Error) {
        settled()
        if let stopped = ContentBlocking.blockedURL(from: error) {
            failed = stopped
            url = stopped
            blocked = stopped
            failure = "Field's blocker stopped this page."
            return
        }
        guard let message = Trouble.message(for: error) else { return }
        failed = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url
        url = failed
        failure = message
    }

    /// What Safari says after "AppleWebKit … (KHTML, like Gecko)". Left alone,
    /// WKWebView says only "Mobile/15E148", and sites that don't recognise it
    /// serve something older and plainer.
    static var userAgentName: String {
        let version = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        return "Version/\(version) Mobile/15E148 Safari/604.1"
    }
}

extension Tab: WKNavigationDelegate, WKUIDelegate {
    /// The guard first (FieldKit's Guard/README.md), once its rules have
    /// loaded: it may clean the address, stop a page throwing you into
    /// another app, or ask before a link leaves Field. Then what a new window
    /// may do (Opening), and the blocker's lists for the page's site.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        let byLink = action.navigationType == .linkActivated
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        if mainFrame, action.navigationType != .other { asked = false }
        if let url = action.request.url, let navigationGuard = Guarded.current {
            let shield = ContentBlocking.shared.isShieldOn(for: url.host())
            let nav = Navigation(
                url: url,
                // Declared non-optional, but nil for some navigations.
                source: (action.sourceFrame as WKFrameInfo?)?.request.url ?? webView.url,
                kind: Tab.kind(of: action.navigationType, asked: asked && mainFrame),
                isMainFrame: mainFrame,
                opensNewWindow: action.targetFrame == nil,
                userTapped: byLink
            )
            if navigationGuard.prefersHTTPS(nav, shieldOn: shield) {
                preferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
            }
            let verdict = navigationGuard.decide(nav, shieldOn: shield)
            if verdict != .allow {
                Guarded.log.notice("\(String(describing: nav.kind), privacy: .public) \(url) → \(String(describing: verdict))")
            }
            switch verdict {
            case .allow:
                break
            case .rewrite(let clean):
                decisionHandler(.cancel, preferences)
                var request = URLRequest(url: clean)
                request.setValue(action.request.value(forHTTPHeaderField: "Referer"), forHTTPHeaderField: "Referer")
                open(request)
                return
            case .block(let reason):
                decisionHandler(.cancel, preferences)
                if reason == .appStore, mainFrame { announce("Stopped a jump to the App Store.") }
                return
            case .askToLeave(let target):
                decisionHandler(.cancel, preferences)
                askToLeave(for: target)
                return
            }
        }
        switch Opening.decide(action.request.url, newWindow: action.targetFrame == nil, byLink: byLink) {
        case .allow:
            if action.targetFrame?.isMainFrame == true, let content {
                ContentBlocking.shared.apply(to: content, host: action.request.url?.host())
            }
            decisionHandler(.allow, preferences)
        case .sameTab:
            decisionHandler(.cancel, preferences)
            open(action.request)
        case .block:
            decisionHandler(.cancel, preferences)
            popupBlocked(action.request.url)
        case .ignore:
            decisionHandler(.cancel, preferences)
            if byLink, action.targetFrame?.isMainFrame != false {
                announce("Field doesn't open that kind of link yet.")
            }
        }
    }

    /// What the guard calls a navigation. The app's own loads, and the
    /// redirects they meet, are `.typed`: asked for, with no page to compare
    /// sites against, so a rewritten address isn't rewritten again.
    static func kind(of type: WKNavigationType, asked: Bool) -> Navigation.Kind {
        switch type {
        case .linkActivated: .link
        case .formSubmitted, .formResubmitted: .formSubmit
        case .backForward: .backForward
        case .reload: .reload
        default: asked ? .typed : .other
        }
    }

    /// Windows a script opens. A link asking for one never gets here: it was
    /// sent to this tab above.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        switch Opening.decide(action.request.url, newWindow: true, byLink: action.navigationType == .linkActivated) {
        case .sameTab: open(action.request)
        case .block: popupBlocked(action.request.url)
        case .allow, .ignore: break
        }
        return nil
    }

    /// A window a script opened stays shut, with a way to open it after all
    /// in a tab of its own, when there's a page to open.
    private func popupBlocked(_ url: URL?) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else { return announce("Popup blocked") }
        offer("Popup blocked", Toaster.Offer(title: "Open") { [weak self] in self?.openTab(url) })
    }

    /// A link to another app, tapped: it goes once you say so.
    private func askToLeave(for url: URL) {
        offer(Tab.leaving(to: url), Toaster.Offer(title: "Open") { [weak self] in
            UIApplication.shared.open(url) { opened in
                if !opened { self?.announce("No app here opens that link.") }
            }
        })
    }

    /// Which app a link opens, as far as its scheme says.
    static func leaving(to url: URL) -> String {
        let app: String? = switch url.scheme?.lowercased() {
        case "mailto": "Mail"
        case "tel", "telprompt": "Phone"
        case "sms", "imessage": "Messages"
        case "facetime", "facetime-audio": "FaceTime"
        case "maps": "Maps"
        case "itms", "itms-apps", "itms-appss": "the App Store"
        default: nil
        }
        return app.map { "This link opens \($0)." } ?? "This link opens another app."
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        failure = nil
        failed = nil
        blocked = nil
        asked = false
        settled()
        committed()
        changed()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settled()
        // A page that never paints anything but its background still comes in.
        reveal()
        guard let url = webView.url, ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        history.visited(url, title: webView.title ?? "")
        finished(url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        asked = false
        fail(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    /// iOS killed the page's process, which leaves the view blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        unpainted = true
        if let action = revival.terminated(visible: visible) { revive(action) }
    }
}

/// Tells the tab when its page first paints, through WebKit's Paint Timing
/// API (first-contentful-paint), watched from Field's own script world. It's
/// the public stand-in for the private rendering-progress event the Mac uses.
private final class PaintRelay: NSObject, WKScriptMessageHandler {
    static let name = "firstPaint"

    static let script = """
    try {
        new PerformanceObserver(function (list, observer) {
            observer.disconnect();
            window.webkit.messageHandlers.\(name).postMessage(0);
        }).observe({ type: "paint", buffered: true });
    } catch (e) {}
    """

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let tab, message.webView === tab.web else { return }
        tab.painted()
    }
}
