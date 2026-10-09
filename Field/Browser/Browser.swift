import FieldKit
import SwiftUI
import UIKit

/// The app's one browser: the tab, the bar's shrink, the field, and what's
/// remembered.
@MainActor @Observable final class Browser {
    let history: HistoryStore
    let saved: SavedStore
    /// Your tabs, kept from one launch to the next.
    let everyday: Tabs
    let privateSpace = PrivateSpace()
    @ObservationIgnored private(set) lazy var gate = makeGate()
    /// Private's tabs are on screen.
    private(set) var privately = false
    /// On screen: Private's tabs, or your everyday ones.
    var tabs: Tabs { privately ? privateSpace.tabs ?? everyday : everyday }
    /// The one on screen.
    var tab: Tab { tabs.current }
    let bar = BarState()
    let toaster = Toaster()
    /// Links from other apps, held until the browser has started.
    let arrivals = Arrivals()
    /// The whole page, as a file to share or the screenshot's Full Page (Field/Capture).
    let capture: Capture
    /// The field is up and focused, over the page, in place of the bar.
    /// Never in the first frame: a blank tab's field is drawn in it (see
    /// opensInField) but focused the turn after (see start), since focusing
    /// sets up the keyboard, which would hold that frame.
    private(set) var fieldOpen = false
    /// The field was waiting under the welcome, where Continue is: from
    /// Continue it stays unseen until the keyboard brings it in
    /// (FieldSurface), so it never shows through the welcome's going.
    private(set) var fieldBehindWelcome = false
    var settingsShown = false
    /// The strip's next move to your tabs is a cut, under Private's shade,
    /// not the slide (see open(incoming:)). Read once by StageView.
    @ObservationIgnored var cutToEveryday = false

    @ObservationIgnored private var started = false
    @ObservationIgnored private var unlocked: (any NSObjectProtocol)?
    @ObservationIgnored private var warmUp = WarmUp()
    @ObservationIgnored private var typing: [any NSObjectProtocol] = []
    @ObservationIgnored private var waiting: Task<Void, Never>?

    /// `restoring` false starts from one blank tab and keeps no session:
    /// the unit tests, which mustn't read the simulator's.
    init(restoring: Bool = true) {
        capture = Capture(page: { nil }, announce: { [toaster] in toaster.show($0) })
        history = HistoryStore(directory: URL.applicationSupportDirectory.appending(path: "Field", directoryHint: .isDirectory))
        saved = SavedStore(directory: URL.applicationSupportDirectory.appending(path: "Field", directoryHint: .isDirectory))
        // The last session, or with `-FieldOpen <url>` or `-FieldSeedTabs N`
        // the perf tests' tabs. A blank tab is the field, ready to type in.
        everyday = restoring
            ? Tabs.launch(history: history)
            : Tabs(history: history, restoring: .init(), store: SessionStore(directory: nil), snapshots: Snapshots(directory: nil))
        everyday.announce = { [toaster] in toaster.show($0) }
        everyday.offer = { [toaster] in toaster.show($0, offering: $1) }
        everyday.committed = { [bar] in bar.expand() }
        everyday.openField = { [weak self] in self?.openField() }
        everyday.finished = { [saved] in saved.opened($0) }
        capture.page = { [weak self] in self?.tab }
        capture.isPrivate = { [weak self] in self?.privately ?? false }
        arrivals.open = { [weak self] in self?.open(incoming: $0) }
        arrivals.announce = { [toaster] in toaster.show($0) }
    }

    /// A blank tab, not yet started: the surface is the field from the first
    /// frame, rather than the bar turning into it once the browser starts.
    var opensInField: Bool { !started && tab.url == nil }

    /// On the turn after the first frame, and only then. A page to load gets
    /// its web view now: the first starts WebKit's processes and holds the
    /// main thread while it does. A blank tab opens the field instead, and its
    /// web view waits until something is loaded, or until the field has been
    /// quiet a while (see WarmUp). History is read from disk either way.
    func start() {
        guard !started else { return }
        started = true
        everyday.started = true
        Signpost.log.emitEvent("launch.start")
        if tab.url != nil {
            tab.build()
        } else {
            fieldOpen = true
            warmUpWhenQuiet()
        }
        Task { await history.load() }
        Task { await saved.load() }
        arrivals.restored()
        // Launched before the phone's first unlock, the file can't be read
        // yet; try again once it can, until a load has worked.
        unlocked = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [history, saved] _ in
            MainActor.assumeIsolated {
                Task { await history.load() }
                if !saved.isLoaded { Task { await saved.load() } }
            }
        }
    }

    /// Continue, in the same update as the tap.
    func leaveWelcome() {
        fieldBehindWelcome = true
    }

    /// The field is wanted: the surface turns the bar into it (FieldSurface).
    func openField() {
        fieldOpen = true
    }

    func closeField() {
        fieldOpen = false
    }

    func go(to url: URL) {
        tab.load(url)
        tab.build()
        closeField()
    }

    private func warmUpWhenQuiet() {
        let center = NotificationCenter.default
        typing = [
            center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.warmUp.focused(at: .now)
                    self?.waitForQuiet()
                }
            },
            center.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.warmUp.typed(at: .now) }
            },
        ]
    }

    /// Sleeps until the quiet is due, and again whenever typing has moved it
    /// on; done once there's a web view, whoever built it.
    private func waitForQuiet() {
        guard waiting == nil else { return }
        waiting = Task { [weak self] in
            while let due = self?.warmUp.due, self?.tab.web == nil {
                if self?.warmUp.isDue(at: .now) == true {
                    self?.tab.build()
                    break
                }
                try? await Task.sleep(until: due)
            }
            guard let self else { return }
            typing.forEach(NotificationCenter.default.removeObserver)
            typing = []
        }
    }

    /// Going to the background: whatever history hasn't been written yet is,
    /// before the app is suspended.
    func flush() {
        let task = UIApplication.shared.beginBackgroundTask(withName: "history")
        Task {
            await history.flush()
            await saved.flush()
            await everyday.flush()
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    // MARK: - tabs

    /// The page shrinks into its card, and the grid comes up around it.
    func showTabs() { tabs.showGrid() }

    /// The current card grows back into the page.
    func hideTabs() { tabs.hideGrid() }

    func newTab() {
        tabs.newTab()
        openField()
    }

    /// One tab along (+1) or back (-1), the pages sliding as if swiped.
    func switchTab(by step: Int) { tabs.switchTab(by: step) }

    func reopenClosedTab() {
        guard tabs.reopen() != nil else { return announce("Nothing to reopen.") }
    }

    private func announce(_ text: String) { toaster.show(text) }

    // MARK: - Private

    /// From the grid's switch. The strip slides at once (StageView); the
    /// session's tabs are made now if it's a new one.
    func enterPrivate() {
        let fresh = privateSpace.tabs == nil
        let tabs = privateSpace.open()
        if fresh { wirePrivate(tabs) }
        tabs.chrome = everyday.chrome
        privately = true
        gate.entered()
        // A new session opens on its blank tab with the field, rising with the slide.
        if fresh { openField() }
    }

    /// `underShade`: Private's shade stays over the strip while it cuts to
    /// your tabs, and goes once that frame is on its way, so nothing private
    /// shows through its fade.
    func leavePrivate(underShade: Bool = false) {
        closeField()
        privately = false
        guard underShade else { return gate.left() }
        cutToEveryday = true
        AfterCommit.run { [gate] in gate.left() }
    }

    // MARK: - links from other apps

    /// A link from another app (Arrivals), already checked and cleaned: in
    /// a tab of your own, shown, as FieldKit's LinkRoute decides. Never in
    /// Private, and never past its lock.
    func open(incoming url: URL) {
        let side: LinkRoute.Side = !privately ? .everyday : gate.shadeShown ? .privateCovered : .privateShown
        let route = LinkRoute(side: side, fieldOpen: fieldOpen, gridShown: everyday.gridShown,
                              currentBlank: everyday.current.url == nil)
        // A sheet over the browser (Settings, Saved) gives way to the page.
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        window?.rootViewController?.presentedViewController?.dismiss(animated: route.leave != .underShade)
        if route.closeField { closeField() }
        switch route.leave {
        case .stay: break
        case .slide: leavePrivate()
        case .underShade: leavePrivate(underShade: true)
        }
        let tab: Tab
        switch route.into {
        case .blankTab:
            // As Go from its field.
            tab = everyday.current
            tab.load(url)
            tab.build()
        case .newTab:
            tab = everyday.newTab(url)
        }
        switch route.grid {
        case .none: break
        case .close: everyday.hideGrid(selecting: tab)
        case .closeAtOnce: everyday.hideGrid(selecting: tab, now: true)
        }
    }

    /// The hooks everyday tabs have, less Saved's `finished`.
    private func wirePrivate(_ tabs: Tabs) {
        tabs.announce = { [toaster] in toaster.show($0) }
        tabs.offer = { [toaster] in toaster.show($0, offering: $1) }
        tabs.committed = { [bar] in bar.expand() }
        tabs.openField = { [weak self] in self?.openField() }
    }

    private func makeGate() -> PrivateGate {
        let gate = PrivateGate(space: privateSpace)
        gate.leave = { [weak self] in self?.leavePrivate() }
        // Wiped while inside (wipe-instead, or the clock): a new session, empty.
        gate.wiped = { [weak self] in
            guard let self, self.privately else { return }
            self.wirePrivate(self.privateSpace.open())
            self.privateSpace.tabs?.chrome = self.everyday.chrome
            self.openField()
        }
        return gate
    }
}
