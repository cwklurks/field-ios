import Foundation
import WebKit
import os

/// Ad and tracker blocking: EasyList, EasyPrivacy and HaGeZi's tracker and
/// ad domains as WebKit content rule lists, enforced inside WebKit before a
/// request is made, so a page costs nothing extra to run. See
/// docs/research/blocking-and-redirects.md.
///
/// The lists ship as gzipped JSON (scripts/lists/build.sh) and compile once,
/// in the background, after the first frame; from then on a launch only looks
/// them up, which takes a fraction of a millisecond. Until they're ready,
/// pages load unprotected; each list goes onto the open pages as it's ready,
/// covering everything they load from then on.
///
/// Every call into WKContentRuleListStore is made on the main actor: Brave
/// crashed on iOS 26 until it did. The compiling itself runs on WebKit's
/// own queue, but WebKit parses the list first, on the thread that asked,
/// which holds the main thread for about 40 ms per list: so each waits for
/// a lull (Lull), never while scrolling, typing into the app's fields or
/// leaving the app. Past a deadline a short lull will do, keyboard or not.
@MainActor final class ContentBlocking {
    static let shared = ContentBlocking()

    /// Every list is compiled and goes on every page the shield is on for.
    private(set) var ready = false

    private var shields: Shields
    private var lists: [WKContentRuleList] = []
    private let manifestURL: URL?
    private let storeURL: URL?
    private let idle: Duration
    private var lull: Lull
    private var keyboardUp = false
    /// The keyboard last moved, or the app's own fields were last typed in.
    private var lastInput: ContinuousClock.Instant?
    private var ticking: Timer?
    private(set) var preparing: Task<Void, Never>?
    /// Between `prepare()` and the lists being looked up: navigations
    /// decided then wait for it (`whenLookedUp`).
    private var lookingUp = false
    private var waiting: [() -> Void] = []
    /// How many of `lists` each controller has on, so a navigation that
    /// changes nothing sends WebKit nothing.
    private let applied = NSMapTable<WKUserContentController, NSNumber>.weakToStrongObjects()
    /// Whether each controller's page is to have the lists, so a list that
    /// becomes ready goes straight onto the pages already open.
    private let wanting = NSMapTable<WKUserContentController, NSNumber>.weakToStrongObjects()
    /// Controllers whose next page loads without the lists: "Load anyway".
    private let passing = NSHashTable<WKUserContentController>.weakObjects()

    /// `store` is a directory for a store of its own (tests), or nil for
    /// WebKit's default. `idle` is how long the app has to be quiet before
    /// the first list is compiled; the rest need a quarter of that, and after
    /// `deadline` so does the first. Made before the field first focuses, so
    /// it sees the keyboard come up.
    init(
        manifest: URL? = Bundle.main.url(forResource: BlockingManifest.resource, withExtension: "json"),
        store: URL? = nil,
        defaults: UserDefaults = .standard,
        domain: @escaping (String) -> String = Shields.registrableDomain,
        idle: Duration = .seconds(2),
        deadline: Duration = .seconds(10)
    ) {
        manifestURL = manifest
        storeURL = store
        self.idle = idle
        lull = Lull(needed: idle, interval: .milliseconds(250), then: idle / 4, deadline: deadline)
        shields = Shields(defaults: defaults, domain: domain)
        let center = NotificationCenter.default
        let inputs: [(Notification.Name, Bool?)] = [
            (UIResponder.keyboardWillShowNotification, true),
            (UIResponder.keyboardWillHideNotification, nil),
            (UIResponder.keyboardDidHideNotification, false),
            (UITextField.textDidChangeNotification, nil),
            (UITextView.textDidChangeNotification, nil),
        ]
        for (name, up) in inputs {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastInput = .now
                    if let up { self.keyboardUp = up }
                }
            }
        }
    }

    /// Once, after the first frame: looks the lists up, and if either is
    /// missing or out of date, compiles it once things are quiet.
    func prepare() {
        guard preparing == nil else { return }
        lookingUp = true
        preparing = Task { await load() }
    }

    /// Runs `go` once the compiled lists have been looked up: straight away
    /// if they have (or nothing's looking), otherwise when they are, a few
    /// milliseconds from launch. So the restored tab's first page, decided in
    /// the same turn as `prepare()`, gets the lists. A lookUp that recompiles
    /// (after an iOS update) can take seconds, so the wait stops at `limit`
    /// and the lists reach the page as they're ready instead.
    func whenLookedUp(limit: Duration = .milliseconds(100), _ go: @escaping () -> Void) {
        guard lookingUp else { return go() }
        var gone = false
        let once = {
            guard !gone else { return }
            gone = true
            go()
        }
        waiting.append(once)
        Task {
            try? await Task.sleep(for: limit)
            once()
        }
    }

    private func lookedUp() {
        lookingUp = false
        let waiting = waiting
        self.waiting = []
        waiting.forEach { $0() }
    }

    /// Before each main-frame navigation: the lists go on or come off this
    /// tab's controller for the site it's heading to. A rule list holds from
    /// the moment it's added, so doing this here covers the whole page.
    func apply(to controller: WKUserContentController, host: String?) {
        let passes = passing.contains(controller)
        passing.remove(controller)
        let wants = !passes && shields.isOn(for: host)
        wanting.setObject(NSNumber(value: wants), forKey: controller)
        put(wants ? lists.count : 0, on: controller)
    }

    private func put(_ count: Int, on controller: WKUserContentController) {
        guard applied.object(forKey: controller)?.intValue ?? 0 != count else { return }
        lists.forEach(controller.remove)
        lists.prefix(count).forEach(controller.add)
        applied.setObject(NSNumber(value: count), forKey: controller)
    }

    /// A host's site, which the shield is kept by: the guard's
    /// `GuardRules.site(of:)` once its rules have loaded, off the main thread.
    var site: (String) -> String {
        get { shields.domain }
        set { shields.domain = newValue }
    }

    func isShieldOn(for host: String?) -> Bool {
        shields.isOn(for: host)
    }

    /// Takes effect at each tab's next navigation; reload the page to see it.
    func setShield(_ on: Bool, for host: String) {
        shields.set(on, for: host)
    }

    /// "Load anyway": this one page without the lists. They come back at
    /// the tab's next navigation.
    func loadAnyway(_ url: URL, in web: WKWebView) {
        passing.add(web.configuration.userContentController)
        web.load(URLRequest(url: url))
    }

    /// The address the lists stopped, when a load failed because they did
    /// (WebKit's "blocked by content blocker", 104): the page to offer
    /// "Load anyway" for.
    nonisolated static func blockedURL(from error: Error) -> URL? {
        let error = error as NSError
        guard error.domain == "WebKitErrorDomain", error.code == 104 else { return nil }
        return error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }

    // MARK: Loading

    private func load() async {
        let probe = BlockingProbe.start()
        guard let manifestURL, let manifest = await Self.readManifest(manifestURL),
              let store = storeURL.map(WKContentRuleListStore.init(url:)) ?? WKContentRuleListStore.default()
        else {
            Self.log.error("No block lists to load")
            lookedUp()
            return
        }
        var found: [String: WKContentRuleList] = [:]
        probe?.watchMainThread()
        for id in manifest.identifiers {
            let lookUp = ContinuousClock.now
            found[id] = try? await store.contentRuleList(forIdentifier: id)
            probe?.note("lookUp \(id) \(found[id] == nil ? "missing" : "found")", since: lookUp)
        }
        probe?.noteMainThread(while: "looking up")
        use(manifest, found)
        lookedUp()

        let missing = zip(manifest.lists, manifest.identifiers).filter { found[$0.1] == nil }
        if !missing.isEmpty, let directory = manifest.directory {
            for (list, id) in missing {
                let inflating = ContinuousClock.now
                guard let json = await Self.inflate(directory.appendingPathComponent(list.file)) else {
                    Self.log.error("Couldn't read \(list.file, privacy: .public)")
                    continue
                }
                probe?.note("inflate \(list.name)", since: inflating)
                let waiting = ContinuousClock.now
                await quiet()
                probe?.note("waited for a lull", since: waiting)
                let compiling = ContinuousClock.now
                probe?.watchMainThread()
                do {
                    found[id] = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json)
                } catch {
                    Self.log.error("Compiling \(list.name, privacy: .public) failed: \(error, privacy: .public)")
                }
                probe?.note("compile \(list.name) (\(list.rules) rules)", since: compiling)
                probe?.noteMainThread(while: "compiling")
                use(manifest, found)
            }
        }

        let stale = manifest.stale(among: await store.availableIdentifiers() ?? [])
        for id in stale { try? await store.removeContentRuleList(forIdentifier: id) }
        probe?.finish(removed: stale, measuring: ready ? self : nil)
    }

    /// Returns once the app has been quiet for `idle`: in front, no keyboard
    /// up, and the main run loop free to fire a timer on time.
    private func quiet() async {
        guard idle > .zero else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
                MainActor.assumeIsolated {
                    let now = ContinuousClock.now
                    let quiet = Lull.isQuiet(
                        active: UIApplication.shared.applicationState == .active, keyboardUp: self.keyboardUp,
                        lastInput: self.lastInput, pastDeadline: self.lull.isPastDeadline(at: now), at: now, calm: self.idle
                    )
                    guard self.lull.tick(at: now, quiet: quiet) else { return }
                    self.ticking?.invalidate()
                    self.ticking = nil
                    done.resume()
                }
            }
            timer.tolerance = 0.05
            ticking = timer
            RunLoop.main.add(timer, forMode: .default)
        }
    }

    /// The lists found so far, in the manifest's order, onto every open page
    /// that wants them. They only ever grow, which is what lets `apply` count them.
    private func use(_ manifest: BlockingManifest, _ found: [String: WKContentRuleList]) {
        lists = manifest.identifiers.compactMap { found[$0] }
        ready = lists.count == manifest.lists.count
        for case let controller as WKUserContentController in wanting.keyEnumerator().allObjects
        where wanting.object(forKey: controller)?.boolValue == true {
            put(lists.count, on: controller)
        }
    }

    @concurrent private nonisolated static func readManifest(_ url: URL) async -> BlockingManifest? {
        BlockingManifest.load(from: url)
    }

    /// The list as a Foundation string, made here, off the main thread.
    /// WebKit copies the JSON on the thread that calls it, and from an
    /// 8-bit NSString that's a memcpy; from a native Swift string it's a
    /// character-by-character walk that held the main thread for about 50 ms.
    @concurrent private nonisolated static func inflate(_ url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url), let json = try? Gzip.inflate(data),
              let string = NSString(data: json, encoding: String.Encoding.utf8.rawValue) else { return nil }
        return string as String
    }

    nonisolated static let log = Logger(subsystem: "com.connork.field", category: "blocking")
}
