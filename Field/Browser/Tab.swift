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
    /// Whether the page reads as light or dark, from its background; nil
    /// until it has one. The glass bar over it takes the same.
    private(set) var tone: ColorScheme?

    @ObservationIgnored var announce: (String) -> Void = { _ in }
    /// A new page has replaced the old one.
    @ObservationIgnored var committed: () -> Void = {}
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
            web.load(URLRequest(url: url))
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
        guard let web else {
            pending = url
            return
        }
        web.load(URLRequest(url: url))
    }

    func goBack() { web?.goBack() }
    func go(to item: WKBackForwardListItem) { web?.go(to: item) }

    func retry() {
        guard let target = failed ?? url else { return }
        load(target)
    }

    private func reload() {
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
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let byLink = action.navigationType == .linkActivated
        switch Opening.decide(action.request.url, newWindow: action.targetFrame == nil, byLink: byLink) {
        case .allow:
            decisionHandler(.allow)
        case .sameTab:
            decisionHandler(.cancel)
            webView.load(action.request)
        case .block:
            decisionHandler(.cancel)
            announce("Popup blocked")
        case .ignore:
            decisionHandler(.cancel)
            if byLink, action.targetFrame?.isMainFrame != false {
                announce("Field doesn't open that kind of link yet.")
            }
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
        case .sameTab: webView.load(action.request)
        case .block: announce("Popup blocked")
        case .allow, .ignore: break
        }
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        failure = nil
        failed = nil
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
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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
