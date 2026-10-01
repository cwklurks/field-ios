import FieldKit
import UIKit
import WebKit

/// Private: a second set of tabs that keeps nothing (docs/research/private-mode.md).
///
/// One non-persistent data store for the whole session, shared by its tabs so
/// a sign-in carries from one to the next. Its tab list, their pictures and
/// their history live only in memory: no session.json, no history.json, no
/// Saved. What the app fetches for it goes through an ephemeral URLSession.
/// Wiping it throws all of that away, in PrivateWipe's order, and the files
/// its pages made in tmp with it.
@MainActor @Observable final class PrivateSpace {
    /// Its tabs: made on the way in, gone with a wipe.
    private(set) var tabs: Tabs?
    /// Where its tabs' visits go: a history that can never be read or
    /// written, since it lives under /dev/null. Gone with a wipe.
    @ObservationIgnored private(set) var history: HistoryStore?
    @ObservationIgnored private(set) var files: PrivateFiles?
    @ObservationIgnored private var store: WKWebsiteDataStore?
    @ObservationIgnored private var fetching: URLSession?
    /// Each private web view's delegate, kept as long as its web view is.
    @ObservationIgnored private let delegates = NSMapTable<WKWebView, PrivateUIDelegate>.weakToStrongObjects()
    /// Each step, as the wipe finishes it. For the tests.
    @ObservationIgnored var stepped: (PrivateWipe.Step) -> Void = { _ in }
    /// Where WebKit copies uploads, and Private keeps its downloads.
    @ObservationIgnored let temporary: URL

    init(temporary: URL = FileManager.default.temporaryDirectory) {
        self.temporary = temporary
    }

    /// Its tabs, made now if this is the way into a new session.
    @discardableResult
    func open() -> Tabs {
        if let tabs { return tabs }
        let history = HistoryStore(directory: URL(filePath: "/dev/null", directoryHint: .isDirectory), seed: 0)
        let tabs = Tabs(history: history, restoring: .init(), store: SessionStore(directory: nil), snapshots: Snapshots(directory: nil))
        // The app is up; a private tab may wake as soon as it's shown.
        tabs.started = true
        tabs.space = self
        self.history = history
        files = PrivateFiles(root: temporary, since: .now)
        self.tabs = tabs
        return tabs
    }

    /// Something is open in it, worth locking or wiping.
    var holding: Bool {
        tabs?.all.contains { $0.url != nil } ?? false
    }

    /// The session's store, made on first use.
    var dataStore: WKWebsiteDataStore {
        if let store { return store }
        let store = WKWebsiteDataStore.nonPersistent()
        self.store = store
        return store
    }

    /// For anything the app fetches for a private page: nothing cached,
    /// no cookies of its own (see fetch(_:)).
    var session: URLSession {
        if let fetching { return fetching }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = HTTPCookieStorage()
        let session = URLSession(configuration: configuration)
        fetching = session
        return session
    }

    /// A private page's resource, with the private store's cookies for it.
    func fetch(_ url: URL) async throws -> Data {
        if url.scheme == "data" { return try await session.data(from: url).0 }
        var request = URLRequest(url: url)
        let cookies = await dataStore.httpCookieStore.allCookies()
        HTTPCookie.requestHeaderFields(with: cookies.filter { $0.matches(url) }).forEach {
            request.setValue($1, forHTTPHeaderField: $0)
        }
        request.httpShouldHandleCookies = false
        return try await session.data(for: request).0
    }

    // MARK: - its web views

    /// A private tab's configuration, before its web view is made: the
    /// session's store and Private's hardening (PrivateWeb).
    func configure(_ config: WKWebViewConfiguration) {
        PrivateWeb.harden(config, store: dataStore)
    }

    /// Once the web view is made and its tab is its delegate: Private's own
    /// long-press menu in front of the tab. `offer` is the tab's toast with
    /// a button, for the confirm before Photos.
    func built(_ web: WKWebView, offer: @escaping (String, Toaster.Offer) -> Void, announce: @escaping (String) -> Void) {
        guard let tab = web.uiDelegate as? NSObject & WKUIDelegate else { return }
        let delegate = PrivateUIDelegate(wrapping: tab) { [weak self] _, web in
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggested in
                UIMenu(children: PrivateWeb.menu(from: suggested) {
                    offer("It'll leave Private for Photos.", Toaster.Offer(title: "Save") { [weak self, weak web] in
                        guard let self, let web else { return }
                        Task { await self.savePicture(from: web, announce: announce) }
                    })
                })
            }
        }
        delegates.setObject(delegate, forKey: web)
        web.uiDelegate = delegate
    }

    /// The picture last pressed on the page, fetched as the page would.
    private func savePicture(from web: WKWebView, announce: (String) -> Void) async {
        let source = try? await web.evaluateJavaScript(PrivateWeb.pressedImage, contentWorld: Tab.world) as? String
        guard let url = source.flatMap(URL.init(string:)), let data = try? await fetch(url), let image = UIImage(data: data) else {
            return announce("Couldn't save that picture.")
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        announce("Saved to Photos.")
    }

    // MARK: - wiping

    /// Throws the session away, in PrivateWipe's order, inside a background
    /// task so leaving the app doesn't stop it halfway. If iOS ends the app
    /// anyway, what was in memory goes with it.
    func wipe() async {
        let task = UIApplication.shared.beginBackgroundTask(withName: "private.wipe")
        defer { UIApplication.shared.endBackgroundTask(task) }
        for step in PrivateWipe.order {
            switch step {
            case .webViews:
                tabs?.all.forEach { $0.sleep() }
            case .websiteData:
                if let store {
                    await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
                }
            case .store:
                store = nil
                fetching?.invalidateAndCancel()
                fetching = nil
            case .tabs:
                tabs = nil
                history = nil
                PrivatePasteboard.forget()
            case .files:
                await files?.purge()
                files = nil
            }
            stepped(step)
        }
    }
}

/// What a private session's pages leave in tmp: WebKit's copies of files
/// picked for an upload (each in a folder of its own, made for it), and
/// Private's downloads. Anything made in tmp since the session began goes
/// with it; what was there before stays.
nonisolated struct PrivateFiles: Sendable {
    let root: URL
    let since: Date

    /// Readable only while the phone is unlocked; made on first use.
    var downloads: URL? {
        let folder = root.appendingPathComponent("Private-\(Int(since.timeIntervalSince1970))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            return folder
        } catch {
            return nil
        }
    }

    /// Off the main thread.
    func purge() async {
        let (root, since) = (root, since)
        await Task.detached(priority: .userInitiated) {
            for url in PrivateFiles.made(in: root, since: since) { try? FileManager.default.removeItem(at: url) }
        }.value
    }

    /// What's been made under `root` since `since`; a new folder whole.
    private static func made(in root: URL, since: Date) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            guard let made = values?.creationDate, made >= since else { continue }
            found.append(url)
            if values?.isDirectory == true { walk.skipDescendants() }
        }
        return found
    }
}

private extension HTTPCookie {
    /// Whether a request to `url` would carry it.
    func matches(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let domain = self.domain.lowercased()
        let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let hostMatches = host == bare || host.hasSuffix("." + bare)
        let pathMatches = url.path().isEmpty || url.path().hasPrefix(path)
        return hostMatches && pathMatches && (!isSecure || url.scheme == "https")
    }
}
