import FieldKit
import SwiftUI
import UIKit
import os

/// Every tab, which one is on screen, and what was closed. Most tabs are
/// asleep: only the one on screen and the couple used just before it keep a
/// web view (see Sleep). The pictures that stand in for the rest are in
/// Snapshots; what's open is saved to session.json a moment after it changes.
///
/// The motion (the grid opening from the page, the carousel under the bar)
/// is the Stage's; this is the list it moves.
@MainActor @Observable final class Tabs {
    private(set) var all: [Tab]
    private(set) var current: Tab
    /// The tab grid is up, or on its way up.
    private(set) var gridShown = false
    @ObservationIgnored private(set) var closed = RecentlyClosed<Session.Entry>()

    @ObservationIgnored let snapshots: Snapshots
    @ObservationIgnored let store: SessionStore
    /// Draws all of this. Nil in the unit tests, where nothing moves.
    @ObservationIgnored weak var stage: Stage?
    /// Hooked up to every tab.
    @ObservationIgnored var announce: (String) -> Void = { _ in }
    @ObservationIgnored var committed: () -> Void = {}
    /// A new blank tab is shown and wants the field.
    @ObservationIgnored var openField: () -> Void = {}
    /// The bar, which only the Stage fades, as the grid comes and goes (see
    /// Stage.showBar). Set by the bar itself.
    @ObservationIgnored weak var chrome: UIView? {
        didSet { if barHeld { chrome?.alpha = 0 } }
    }
    /// The bar waits for the page at launch, when the page's picture is
    /// late, rather than showing over a blank page (see Stage.place).
    @ObservationIgnored var barHeld = false {
        didSet { chrome?.alpha = barHeld ? 0 : 1 }
    }
    /// The first frame is up, and tabs may be woken (see Browser.start).
    @ObservationIgnored var started = false

    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(history: HistoryStore, restoring shape: Session.Shape, store: SessionStore, snapshots: Snapshots) {
        self.history = history
        self.store = store
        self.snapshots = snapshots
        let restored = shape.tabs.map { Tab(history: history, entry: $0) }
        let list = restored.isEmpty ? [Tab(history: history)] : restored
        all = list
        current = list[restored.isEmpty ? 0 : shape.active]
        all.forEach(wire)
        current.show()
        observers = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.memoryShort() }
            },
        ]
    }

    /// The tabs the app starts with: the last session, or for the perf tests
    /// (`-FieldSeedTabs N`, `-FieldOpen <url>`) made-up tabs that never touch
    /// the user's session or pictures. `-FieldSeedTabs 0` alone is one blank
    /// tab and no session, for a launch that must start from nothing.
    static func launch(history: HistoryStore) -> Tabs {
        let caches = URL.cachesDirectory.appending(path: "Field", directoryHint: .isDirectory)
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let seeding = arguments["FieldSeedTabs"] != nil
        let seed = seeding ? max(0, UserDefaults.standard.integer(forKey: "FieldSeedTabs")) : 0
        let opening = (arguments["FieldOpen"] as? String).flatMap { URL(string: $0) }
        guard !seeding, opening == nil else {
            let seedDirectory = caches.appending(path: "Seed", directoryHint: .isDirectory)
            // Last run's pictures; only ever the perf tests', so here and now is fine.
            try? FileManager.default.removeItem(at: seedDirectory)
            let snapshots = Snapshots(directory: seedDirectory)
            var entries = Tabs.seed(seed)
            if let opening { entries.append(Session.Entry(url: opening.absoluteString, title: "")) }
            let tabs = Tabs(history: history, restoring: Session.Shape(tabs: entries, active: entries.count - 1),
                            store: SessionStore(directory: nil), snapshots: snapshots)
            tabs.drawSeedPictures(entries.prefix(seed))
            return tabs
        }
        let store = SessionStore(directory: URL.applicationSupportDirectory.appending(path: "Field", directoryHint: .isDirectory))
        let snapshots = Snapshots(directory: caches.appending(path: "Snapshots", directoryHint: .isDirectory))
        // Unreadable (before the first unlock) is a blank tab for now, and
        // the file and its pictures are left as they are for next time.
        let read = store.read()
        let tabs = Tabs(history: history, restoring: read ?? Session.Shape(), store: store, snapshots: snapshots)
        if let read {
            // On its way now, for the first frame (see Stage.place).
            if tabs.current.url != nil { snapshots.prefetch(tabs.current.id) }
            snapshots.prune(keeping: Set(read.tabs.map(\.id)))
        }
        return tabs
    }

    var index: Int { all.firstIndex { $0 === current } ?? 0 }

    var shape: Session.Shape {
        Session.Shape(tabs: all.map(\.entry), active: index)
    }

    /// The tab `step` places along, if there is one.
    func neighbour(by step: Int) -> Tab? {
        let i = index + step
        return all.indices.contains(i) ? all[i] : nil
    }

    // MARK: - what the bar asks for

    /// The page shrinks into its card, and the grid comes up around it.
    func showGrid() {
        guard !gridShown else { return }
        gridShown = true
        stage?.openGrid()
    }

    /// A card grows into the page: `tab`'s, or the current one's.
    func hideGrid(selecting tab: Tab? = nil) {
        guard gridShown else { return }
        gridShown = false
        let tab = tab ?? current
        if let stage { stage.closeGrid(selecting: tab) } else { select(tab) }
    }

    /// The grid's + : a blank page and the field, as the grid goes.
    func newTabFromGrid() {
        let tab = newTab()
        gridShown = false
        if let stage { stage.closeGrid(selecting: tab, field: true) } else { openField() }
    }

    /// Swiping sideways on the bar: the page follows the finger `dx` points
    /// from where it came down, with the tabs either side beside it.
    func track(_ dx: CGFloat) { stage?.track(dx) }

    /// The finger lifted, going `velocity` points a second sideways: the
    /// page springs on to the next tab or back, with that speed.
    func release(velocity: CGFloat) { stage?.release(velocity: velocity) }

    /// One tab along (+1) or back (-1), sliding as if swiped.
    func switchTab(by step: Int) {
        if let stage { stage.switchTab(by: step) } else if let tab = neighbour(by: step) { select(tab) }
    }

    // MARK: - the list

    /// Puts `tab` on screen, as far as the list goes; the Stage places its
    /// web view, waking it if it sleeps.
    func select(_ tab: Tab) {
        guard tab !== current else { return }
        current.visible = false
        current = tab
        tab.show()
        changed()
        sleepIdle(.normal)
    }

    @discardableResult
    func newTab(_ url: URL? = nil) -> Tab {
        leaving()
        let tab = Tab(history: history)
        wire(tab)
        if let url { tab.load(url) }
        all.append(tab)
        select(tab)
        return tab
    }

    func close(_ tab: Tab) {
        guard let i = all.firstIndex(where: { $0 === tab }) else { return }
        // Its picture stays on disk while it can still be reopened.
        if tab.url == nil {
            snapshots.remove(tab.id)
        } else if let dropped = closed.push(tab.entry, at: i) {
            snapshots.remove(dropped.id)
        }
        tab.sleep()
        tab.visible = false
        all.remove(at: i)
        if all.isEmpty {
            let blank = Tab(history: history)
            wire(blank)
            all = [blank]
        }
        if tab === current {
            current = all[min(i, all.count - 1)]
            current.show()
        }
        changed()
    }

    /// A closed tab (the last, unless `position` in `closed.items` says
    /// otherwise), back in its place with its history, asleep until the Stage
    /// shows it.
    @discardableResult
    func reopen(at position: Int = 0) -> Tab? {
        guard closed.items.indices.contains(position) else { return nil }
        let last = closed.remove(at: position)
        leaving()
        let tab = Tab(history: history, entry: last.item)
        wire(tab)
        all.insert(tab, at: min(last.index, all.count))
        select(tab)
        return tab
    }

    /// The address or title of a tab changed, or the list did.
    func changed() {
        store.changed { [weak self] in self?.shape ?? Session.Shape() }
    }

    func flush() async {
        await store.flush()
    }

    private func wire(_ tab: Tab) {
        tab.announce = { [weak self] in self?.announce($0) }
        tab.committed = { [weak self] in self?.committed() }
        tab.changed = { [weak self] in self?.changed() }
    }

    // MARK: - sleep

    /// The page on screen is about to be left from the bar, where nothing
    /// else pictured it (the grid and the carousel do when they start).
    private func leaving() {
        guard !gridShown else { return }
        capture(current)
    }

    /// Takes the tab's picture for its card, the carousel and its wake.
    func capture(_ tab: Tab) {
        Task {
            guard let image = await tab.snapshot(width: Snapshots.width) else { return }
            snapshots.put(image, for: tab.id)
            stage?.pictureChanged(tab)
        }
    }

    /// Puts to sleep what the policy says should be, once each has been
    /// asked whether it holds something typed.
    func sleepIdle(_ pressure: Sleep.Pressure) {
        let candidates = all.map {
            Sleep.Tab(id: $0.id, seen: $0.seen, awake: $0.web != nil, held: $0.held)
        }
        let ids = Sleep.toSleep(candidates, active: current.id, pressure: pressure)
        for id in ids {
            guard let tab = all.first(where: { $0.id == id }) else { continue }
            Task {
                guard !(await tab.holdsTyping()), tab !== current, !tab.visible else { return }
                tab.sleep()
            }
        }
    }

    private func memoryShort() {
        Signpost.log.emitEvent("tabs.memoryWarning")
        snapshots.trim()
        capture(current)
        sleepIdle(.warning)
    }

    // MARK: - the perf tests' tabs

    /// Each made-up page's colour, the same in its picture.
    nonisolated static func seedColour(_ i: Int) -> UIColor {
        UIColor(hue: CGFloat(i * 47 % 360) / 360, saturation: 0.45, brightness: 0.92, alpha: 1)
    }

    /// Made-up pages that open without a network, each its own colour.
    static func seed(_ count: Int) -> [Session.Entry] {
        (0..<count).map { i in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            seedColour(i).getRed(&r, green: &g, blue: &b, alpha: &a)
            let rgb = "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
            let html = "<meta name=viewport content='width=device-width'><body style='margin:0;background:\(rgb)'><h1 style='margin:0;padding:96px 24px 0;font:600 34px -apple-system'>Tab \(i + 1)</h1>"
            let url = "data:text/html," + (html.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            return Session.Entry(url: url, title: "Seeded tab \(i + 1)")
        }
    }

    /// Their pictures, drawn off the main thread as a real one would be
    /// decoded: the page's own colour and heading, at half size.
    private func drawSeedPictures(_ entries: ArraySlice<Session.Entry>) {
        let list = Array(entries.enumerated()).map { ($0.offset, $0.element.id) }
        // The one on screen now, for the first frame, as a restored tab's
        // picture would be; the rest off the main thread.
        if let (i, id) = list.first(where: { $0.1 == current.id }) {
            snapshots.put(Tabs.seedPicture(i), for: id)
        }
        let rest = list.filter { $0.1 != current.id }
        Task.detached(priority: .utility) {
            let drawn = rest.map { ($0.1, Tabs.seedPicture($0.0)) }
            await MainActor.run { [drawn] in
                for (id, image) in drawn { self.snapshots.put(image, for: id) }
            }
        }
    }

    nonisolated private static func seedPicture(_ i: Int) -> UIImage {
        let size = CGSize(width: Snapshots.width, height: Snapshots.width * 2.17)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            Tabs.seedColour(i).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            ("Tab \(i + 1)" as NSString).draw(
                at: CGPoint(x: 12, y: 80),  // below the status bar, as the page draws it
                withAttributes: [.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]
            )
        }
    }
}
