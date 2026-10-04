import SwiftUI
import UIKit
import os

/// The bar and the field as one surface, riding the keyboard.
///
/// The field sits on the keyboard's layout guide, so UIKit moves it with
/// the keyboard on every frame: rising, going down, and under a finger
/// dragging the keyboard away. The bar sits on the ground (see pin). Only its shape and what's on it are this
/// controller's to move, and it moves them with Core Animation, which keeps
/// going while the main thread is held.
///
/// That's how a tap answers on the next frame although focusing a field holds
/// the main thread: the morph is handed to the render server first
/// (AfterCommit), then the field takes focus while it runs, and the
/// keyboard rises under a surface that's already on its way to being the
/// field. The keyboard itself is loaded once, early, while nothing moves
/// (Keyboard.warm), so that focus is short.
final class FieldSurface: UIViewController {
    static let log = Logger(subsystem: "com.connork.field", category: "motion")

    private let browser: Browser
    private var page: Tab { browser.tab }

    private let scrim = Scrim()
    /// Full height, its foot on the keyboard or the ground (pin): the
    /// keyboard moves it, and nothing inside it has to be laid out again
    /// for that.
    private let rider = PassThrough()
    private let coordinator: AddressField.Coordinator
    private let rows: UIHostingController<SuggestionRows>
    /// Starred pages, above a new tab's field until something is typed.
    private let starred: StarredShelf
    private let surface: SurfaceView
    private let sampler = ToneSampler()

    private var flow = FieldFlow()
    /// The shrink the bar is drawn at.
    private var amount: CGFloat = 0
    /// How tall the suggestions are.
    private var listed: CGFloat = 0
    /// The keyboard's curve as it last started down, for the surface to
    /// land with it.
    private var hiding: SurfaceMotion.Curve?
    /// The keyboard's curve as it last came up, which it goes down on too.
    private var rising: SurfaceMotion.Curve?
    /// How tall the keyboard is when it's all the way up.
    private var keyboardHeight: CGFloat = 0
    /// A finger taking the keyboard down: the field turning into the bar,
    /// held at as far as the keyboard has gone (KeyboardDrag), on the
    /// surface's own stopped clock (beginDragging).
    private var dragging = false
    /// The drag ended with the scrub stopped part way, UIKit yet to say
    /// what the keyboard does (scrollViewDidEndDragging).
    private var held = false
    /// What the scrub animates, to leave where it is when it stops.
    private var scrubbed: [(layer: CALayer, key: String, path: String)] = []
    /// UIKit's resign, held back (holdFocus).
    private var resignDue: (() -> Void)?
    private var lettingGo = false
    /// What the rider stands on (see pin).
    private var onKeyboard: NSLayoutConstraint?
    private var onGround: NSLayoutConstraint?
    /// Under the bar, for glass; nil until read.
    private var pageTone: ColorScheme?
    /// The tab the tone was last read for.
    private weak var sampled: Tab?
    private var look: BarLook = .glass
    /// Where Go is going, for the bar to say as the field turns back into it.
    private var goingTo: URL?
    /// What the drag on the bar is for, from when it began.
    private var swipe: BarSwipe?
    /// Where the last finger came down on the surface, across.
    private var touchDown: CGFloat = 0
    /// How far the finger had gone when the drag was recognised, and the
    /// frames since (see BarSwipe.shown).
    private var slop: CGFloat = 0
    private var step = 0

    /// The field's side margins: well inside the bar's, so the bar is seen
    /// to widen into it, and the field lines up with the keyboard's keys.
    static let fieldMargin: CGFloat = 4
    /// Between the field and the keyboard.
    static let gap: CGFloat = 8
    /// How far the field rises at the tap, before the keyboard has started:
    /// the keyboard then takes it the rest of the way, on its own curve,
    /// so the rise is one motion that began on the frame after the tap.
    static let ahead: CGFloat = 24

    init(browser: Browser) {
        self.browser = browser
        let history = browser.history
        let omnibox = Omnibox(initial: nil, history: history, privately: { [weak browser] in browser?.privately ?? true })
        coordinator = AddressField.Coordinator(omnibox: omnibox)
        rows = UIHostingController(rootView: SuggestionRows(omnibox: omnibox, onGo: { _ in }))
        rows.sizingOptions = []
        rows.safeAreaRegions = []
        rows.view.backgroundColor = .clear
        surface = SurfaceView(field: AddressField.make(coordinator), rows: rows.view)
        starred = StarredShelf(store: browser.saved)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = PassThrough()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        browser.tabs.chrome = view  // Stage fades the bar in the same animator as the tab flight
        scrim.translatesAutoresizingMaskIntoConstraints = false
        rider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrim)
        view.addSubview(rider)
        addChild(rows)
        rider.addSubview(surface)
        rows.didMove(toParent: self)
        starred.install(in: self, rider: rider, above: Self.gap + Bar.height + 12)
        surface.field.mayFocus = { [weak self] in self?.flow.phase == .field }
        starred.onOpen = { [weak self] in self?.go(to: $0) }
        starred.onShowSaved = { [weak self] start in
            guard let self else { return }
            SavedSheets.showList(browser.saved, start: start) { [weak self] in self?.go(to: $0) }
        }
        let guide = view.keyboardLayoutGuide
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: view.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rider.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])
        onKeyboard = rider.bottomAnchor.constraint(equalTo: guide.topAnchor)
        onGround = rider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        pin()
        // A swipe down the scrim starts taking the keyboard, and the field
        // on it, as soon as the finger reaches the field.
        guide.keyboardDismissPadding = Bar.height + Self.gap
        view.accessibilityElements = [rider, scrim]

        scrim.cancel = { [weak self] in self?.cancel() }
        // Private's welcome link, under the dim on a new private tab: one tap opens it.
        scrim.passes = { PrivateSide.showing?.linkContains($0) ?? false }
        scrim.delegate = self
        scrim.cover = { [weak self] in
            guard let self else { return .zero }
            let top = rider.convert(surface.frame, to: scrim).minY
            return CGRect(x: 0, y: 0, width: scrim.bounds.width, height: max(0, top))
        }

        let bar = surface.bar
        bar.address.addTarget(self, action: #selector(tapAddress(_:event:)), for: .touchUpInside)
        // Its press, the dim, is the bar's own (BarContent).
        bar.address.addAction(UIAction { [weak self] _ in self?.prepare() }, for: .touchDown)
        bar.goBack = { [weak self] in self?.page.goBack() }
        bar.go = { [weak self] item in self?.page.go(to: item) }
        bar.history = { [weak self] in
            guard let page = self?.page else { return ([], []) }
            return (page.back, page.forward)
        }
        bar.showTabs = { [weak self] in self?.browser.showTabs() }
        bar.newTab = { [weak self] in self?.browser.newTab() }
        bar.reopenClosedTab = { [weak self] in self?.browser.reopenClosedTab() }
        bar.canReopen = { [weak self] in self?.browser.tabs.closed.isEmpty == false }
        bar.address.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.addressMenu() ?? [])
        }])
        let pill = UITapGestureRecognizer(target: self, action: #selector(tapPill))
        pill.delaysTouchesEnded = false
        pill.delegate = self
        surface.addGestureRecognizer(pill)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        swipe.maximumNumberOfTouches = 1
        swipe.delegate = self
        surface.addGestureRecognizer(swipe)
        bar.tabCount = { [weak self] in self?.browser.tabs.all.count ?? 1 }

        coordinator.onGo = { [weak self] in self?.go(to: $0) }
        coordinator.onEdited = { [weak self] in self?.edited() }
        coordinator.onRefused = { [weak self] in self?.refuse() }
        coordinator.onEnded = { [weak self] in
            // A held focus let go is the close already under way, or the
            // field wanted again: nothing for the flow.
            guard self?.lettingGo != true else { return }
            // After the keyboard has had its say: a swipe that took the
            // keyboard away closes on the keyboard's own curve.
            DispatchQueue.main.async { self?.handle(.editingEnded) }
        }

        browser.bar.draw = { [weak self] amount, spring, done in
            self?.draw(amount, spring: spring, done: done)
        }
        sampler.strip = { [weak self] in self?.strip() }
        sampler.picture = { [weak self] in self?.picture() }
        sampler.changed = { [weak self] tone in
            guard let self else { return }
            pageTone = tone
            SurfaceMotion.animate(.settle) { self.paintTone() }
        }

        Keyboard.watch()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardHiding(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardShowing(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
        center.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(stopKeeping), name: UIApplication.willResignActiveNotification, object: nil)
        defaultsChanged()
        if browser.opensInField { restInField() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrim.contentSize = scrim.bounds.size
        if !dragging, !held { place() }
        // A finger taking the keyboard down takes the field with it, turning
        // it into the bar as far as the keyboard has gone, and the dimming
        // going with it. Where the finger lifts, UIKit decides whether the
        // keyboard goes (keyboardHiding) or comes back (keyboardShowing).
        guard flow.phase == .field, scrim.isTracking, Keyboard.up else { return }
        let gone = KeyboardDrag.gone(height: view.keyboardLayoutGuide.layoutFrame.height,
                                     full: keyboardHeight, rest: view.safeAreaInsets.bottom)
        if !dragging, !held, gone > 0 { beginDragging() }
        guard dragging else { return }
        surface.layer.timeOffset = min(gone, 0.999)
        scrim.alpha = 1 - gone
        // Riding the keyboard down, and going with the dimming.
        if wantsStarred { starred.view.alpha = 1 - gone }
        // Brought all the way back with the finger still down: the field
        // again now, its own text in the address's place, not at the lift.
        if gone == 0 { springBack(on: .quick) }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        stopKeeping()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        stopKeeping()
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        warmSoon()
        if let scene = view.window?.windowScene { browser.capture.attach(to: scene) }
    }

    /// Everything read here is watched: UIKit calls this again when any of
    /// it changes.
    override func updateProperties() {
        super.updateProperties()
        let page = page
        // The bar and the field are Private's own dark while it's on screen,
        // from before the field opens there, so it never rises light: the
        // new look reaches every view now, not at the next layout, which
        // would fade it in on the field's own curve.
        let style: UIUserInterfaceStyle = browser.privately ? .dark : .unspecified
        if view.overrideUserInterfaceStyle != style {
            view.overrideUserInterfaceStyle = style
            UIView.performWithoutAnimation {
                paintTone()
                view.updateTraitsIfNeeded()
            }
        }
        surface.bar.privately = browser.privately
        surface.bar.show(url: goingTo ?? browser.tabs.arriving ?? page.url, loading: page.isLoading, canGoBack: page.canGoBack, canGoForward: page.canGoForward)
        if flow.phase == .bar { place() }
        // Another tab is read afresh, at once, even when neither has a page
        // yet: its picture is under the bar until its page is.
        sampler.watch(look == .glass ? page.web : nil, fresh: page !== sampled)
        sampled = page
        if browser.fieldBehindWelcome, resting, !entering { hideUntilKeyboard() }
        // A field waiting for focus isn't open yet: the browser opening it
        // is what gives it focus.
        let open = browser.fieldOpen
        if open != (flow.phase == .field && !resting) {
            // Not from inside UIKit's update: focusing a field here is too early.
            DispatchQueue.main.async { [weak self] in self?.sync() }
        }
    }

    // MARK: What happens

    /// Escape, or VoiceOver's scrub: back to the page.
    override func accessibilityPerformEscape() -> Bool {
        guard flow.phase == .field else { return false }
        cancel()
        return true
    }

    @objc private func tapAddress(_ sender: UIButton, event: UIEvent) {
        let lag = Int((CACurrentMediaTime() - event.timestamp) * 1000)
        Self.log.notice("tap handled \(lag) ms after the touch ended")
        handle(.tap(collapsed: amount > 0.5))
    }

    @objc private func tapPill() {
        handle(.tap(collapsed: true))
    }

    /// Sideways on the bar, the page follows the finger from where it came
    /// down, and springs on with its speed; up, the tab grid.
    @objc private func swiped(_ pan: UIPanGestureRecognizer) {
        // UIKit counts the translation from where it recognised the drag.
        let moved = pan.translation(in: view).x
        if pan.state == .began {
            // The address's touch-down drafted the field for the page it was on.
            prepared = false
            slop = pan.location(in: view).x - touchDown - moved
            step = 0
        }
        switch (swipe, pan.state) {
        case (.up, .began):
            browser.showTabs()
        case (.sideways, .began), (.sideways, .changed):
            browser.tabs.track(BarSwipe.shown(travel: moved + slop, slop: slop, step: step))
            step += 1
        case (.sideways, .ended), (.sideways, .cancelled):
            // Where the finger lifted, and on from there with its speed.
            browser.tabs.track(BarSwipe.shown(travel: moved + slop, slop: slop, step: step))
            browser.tabs.release(velocity: pan.velocity(in: view).x)
        default:
            break
        }
    }

    private func cancel() {
        Self.log.notice("cancel handled")
        handle(.cancel)
    }

    /// The address's long press: Save (or the saved page's sheet), the
    /// page's address to copy or share without its tracking parameters, and
    /// the blocker's switch for its site. A tap still opens the field.
    private func addressMenu() -> [UIMenuElement] {
        let tab = page
        guard let url = tab.url, ["http", "https"].contains(url.scheme?.lowercased()) else { return [] }
        let isSaved = browser.saved.contains(url)
        let save = UIAction(title: isSaved ? "Edit Saved Page" : "Save",
                            image: UIImage(systemName: isSaved ? "bookmark.fill" : "bookmark")) { [weak self] _ in
            guard let self else { return }
            SavedSheets.save(url, title: tab.title, in: browser.saved)
        }
        let passing = UIMenu(options: .displayInline, children: [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [browser] _ in
                browser.privately ? PrivatePasteboard.copy(url) : Guarded.copy(url)
            },
            UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(url) },
        ] + [browser.capture.menu(presenter: self, source: surface.bar.address)].compactMap { $0 })
        return [save, passing, ContentBlocking.shared.shieldAction(for: url, reload: tab.reload)].compactMap { $0 }
    }

    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [Guarded.stripped(url)], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = surface.bar.address
        present(sheet, animated: true)
    }

    /// Return or a suggestion: the field turns back into the bar saying where
    /// it's going, and the page starts loading straight away.
    private func go(to url: URL) {
        guard flow.phase == .field else { return }
        goingTo = url
        handle(.go)
        // The close is on its way to the screen before the load, which on a
        // blank tab builds the first web view, can hold the main thread.
        AfterCommit.run { [weak self] in
            self?.browser.go(to: url)
            self?.goingTo = nil
        }
    }

    /// The browser's own say: a blank tab wants the field; something else
    /// closed it.
    private func sync() {
        if browser.fieldOpen, flow.phase != .field {
            handle(.open)
        } else if browser.fieldOpen, resting {
            resting = false
            if entering { enterIfNoKeyboard() }
            pin()
            let t = ContinuousClock.now
            coordinator.open(surface.field)
            Self.log.notice("rest: focus took \(Self.ms(since: t)) ms")
            // No keyboard coming (a hardware one): the shelf where it is.
            Task { [weak self] in
                try? await Task.sleep(for: FieldOpening.patience)
                guard let self, flow.phase == .field, !Keyboard.up else { return }
                showStarred()
            }
        } else if !browser.fieldOpen, flow.phase == .field, !resting {
            handle(.cancel)
        }
    }

    private func handle(_ event: FieldFlow.Event) {
        if event == .open || event == .tap(collapsed: false) || event == .tap(collapsed: true) { letFocusGo() }
        for effect in flow.handle(event) {
            switch effect {
            case .expand: browser.bar.expand()
            case .showField: showField(tapped: event == .tap(collapsed: false))
            case .showBar(let number): showBar(number)
            }
        }
        pin()
    }

    /// The field stands on the keyboard; the bar, and a field waiting for
    /// focus, on the ground, so nothing the keyboard does meanwhile (loading
    /// it early, a page's own field) moves them. With the keyboard down the
    /// two are the same place, so the switch is unseen.
    private func pin() {
        let keyboard = flow.phase != .bar && !resting
        // Neither is active before the first pin.
        guard (keyboard ? onKeyboard : onGround)?.isActive == false else { return }
        onKeyboard?.isActive = false
        onGround?.isActive = false
        (keyboard ? onKeyboard : onGround)?.isActive = true
    }

    @objc private func keyboardShowing(_ note: Notification) {
        guard !Keyboard.warming else { return }
        rising = SurfaceMotion.Curve(keyboard: note) ?? rising
        if entering { enter() }
        if dragging || held { springBack(on: SurfaceMotion.Curve(keyboard: note) ?? .glide) }
        // The keyboard comes up under a field that started ahead of it, and
        // takes over the rise on its own curve.
        if flow.phase == .field, surface.transform != .identity {
            SurfaceMotion.animate(rising ?? .glide) { self.surface.transform = .identity }
        }
        // The shelf comes in as the field rises, on the keyboard's curve,
        // never ahead of it.
        if flow.phase == .field, !resting, !dragging, !held { showStarred(on: rising ?? .glide) }
        guard let opened else { return }
        Self.log.notice("keyboard will show \(Self.ms(since: opened)) ms after the tap")
    }

    @objc private func keyboardShown() {
        if flow.phase == .field { keyboardHeight = view.keyboardLayoutGuide.layoutFrame.height }
        guard let opened else { return }
        Self.log.notice("keyboard up \(Self.ms(since: opened)) ms after the tap")
        self.opened = nil
    }

    @objc private func keyboardHiding(_ note: Notification) {
        guard !Keyboard.warming else { return }
        hiding = SurfaceMotion.Curve(keyboard: note)
        // A close already on its way (a tap outside, Go) is what sent the
        // keyboard down: the bar goes down on it.
        let closing = flow.phase == .closing
        handle(.keyboardHiding)
        if closing { keepOnKeyboard() }
    }

    @objc private func defaultsChanged() {
        let look = UserDefaults.standard.string(forKey: "bar.look").flatMap(BarLook.init(rawValue:)) ?? .glass
        guard look != self.look || surface.background.look != look else { return }
        self.look = look
        surface.background.look = look
        paintTone()
        setNeedsUpdateProperties()
    }

    // MARK: The morph

    /// When the tap came, for the log.
    private var opened: ContinuousClock.Instant?
    /// The field has its draft for the coming opening (see prepare).
    private var prepared = false
    /// The field is drawn, waiting for the browser to start before it takes
    /// focus (restInField).
    private var resting = false
    /// The field is unseen until the keyboard shows (hideUntilKeyboard).
    private var entering = false

    /// The finger is down on the address: everything the tap will show is
    /// made now, unseen, so that at the lift there is only a switch to throw
    /// and the frame after it goes out at once.
    private func prepare() {
        guard flow.phase != .field else { return }
        draft()
    }

    /// A new draft from the page's address. Opened from the code (a new
    /// tab, Private) rather than a finger, the field needs its own: the
    /// finger's is only for its tap, and one left from a long press, or the
    /// last thing typed, may be another tab's, or a wiped Private session's.
    private func draft() {
        let omnibox = Omnibox(initial: page.url, history: browser.history, privately: { [weak browser] in browser?.privately ?? true })
        coordinator.omnibox = omnibox
        coordinator.show(surface.field)
        prepared = true
    }

    private func showField(tapped: Bool) {
        let t0 = ContinuousClock.now
        if tapped {
            FieldOpening.begin()
            opened = .now
        }
        // Only the completed tap commits the destination. Touch-down also
        // begins a swipe, which must still be able to catch the glide.
        let switched = browser.tabs.stage?.finishSwitching() ?? false
        if !(tapped && prepared && !switched) { draft() }
        prepared = false
        letKeepGo()
        hiding = nil
        held = false
        listed = 0
        rows.view.alpha = 0

        // The frame after the tap: the field's text in place of the address,
        // where the address was, all of it selected, and back and tabs gone
        // rather than fading over it. Out on its own, before anything else.
        let field = surface.field
        let bar = surface.bar
        let from = surface.convert(CGPoint(x: bar.textStart, y: 0), from: bar).x
        surface.row.isHidden = false
        surface.row.transform = CGAffineTransform(translationX: from - surface.row.frame.minX - SurfaceView.textStart, y: 0)
        surface.magnifier.alpha = 0
        bar.address.isHidden = true
        bar.address.alpha = 1
        bar.back.alpha = 0
        bar.tabs.alpha = 0
        scrim.isHidden = false
        TouchMarks.flag(in: view.window)
        CATransaction.flush()
        let t1 = ContinuousClock.now

        // Then the morph, on its way before the focus holds the main thread:
        // the focus waits for the commit that starts it, or the surface
        // would sit still until the keyboard came. On the quick curve, whose
        // start is steep, and a frame along already: the frame after the
        // lift shows the surface widening and the dim coming, where a
        // spring's first frame barely moves. It's done before the keyboard
        // arrives to carry it. The surface also starts up, ahead of the
        // keyboard (see ahead).
        SurfaceMotion.quickFromNextFrame { [self] in
            place()
            rider.transform = .identity
            surface.transform = CGAffineTransform(translationX: 0, y: -Self.ahead)
            surface.row.transform = .identity
            surface.magnifier.alpha = 1
            scrim.alpha = 1
            paintTone()
        }
        // No keyboard coming (a hardware one): it settles where it is.
        Task { [weak self] in
            try? await Task.sleep(for: FieldOpening.patience)
            guard let self, flow.phase == .field else { return }
            if !Keyboard.up { showStarred() }
            guard surface.transform != .identity else { return }
            SurfaceMotion.animate(.settle) { self.surface.transform = .identity }
        }
        AfterCommit.run { [weak self] in
            guard let self, flow.phase == .field else { return }
            // The browser hears of it after the frame too: what SwiftUI
            // redraws for it would otherwise make that frame late.
            if !browser.fieldOpen { browser.openField() }
            let focusing = ContinuousClock.now
            coordinator.open(field)
            // Nothing to list yet: the rows can wait until the frame is out.
            rows.rootView = SuggestionRows(omnibox: coordinator.omnibox, onGo: { [weak self] in self?.go(to: $0) })
            Self.log.notice("first frame \(Self.ms(since: t0) - Self.ms(since: t1)) ms, focus took \(Self.ms(since: focusing)) ms")
        }
    }

    /// A blank tab at launch: the field from the first frame, where the bar
    /// would be, with nothing to turn from. Focus, and the keyboard carrying
    /// it up, come once the browser starts (sync).
    private func restInField() {
        prepare()
        prepared = false
        // Straight into the field: the tap's morph is left out.
        _ = flow.handle(.open)
        resting = true
        pin()
        rows.rootView = SuggestionRows(omnibox: coordinator.omnibox, onGo: { [weak self] in self?.go(to: $0) })
        surface.row.isHidden = false
        surface.bar.address.isHidden = true
        scrim.isHidden = false
        scrim.alpha = 1
        paintTone()
    }

    /// The field that waited under the welcome, where Continue was: unseen
    /// until the keyboard starts up, then in as it rides the keyboard's top
    /// edge, so no frame shows it through the welcome's going.
    private func hideUntilKeyboard() {
        entering = true
        surface.alpha = 0
    }

    /// Focused, so in with the keyboard; or, with none coming (a hardware
    /// one), where it is.
    private func enterIfNoKeyboard() {
        Task { [weak self] in
            try? await Task.sleep(for: FieldOpening.patience)
            self?.enter()
        }
    }

    private func enter() {
        guard entering else { return }
        entering = false
        SurfaceMotion.animate(.quick) { self.surface.alpha = 1 }
    }

    private func showBar(_ number: Int) {
        let t0 = ContinuousClock.now
        if browser.fieldOpen { browser.closeField() }

        // A swipe has the address out already, part of the way home: it
        // carries on from there. Otherwise the address takes the place of
        // the field's text, starting where that text is. Set up before the
        // keyboard is told to go: its animation lays the surface out, and has
        // to start from here.
        let dragged = dragging || held
        held = false
        stopDragging()
        let bar = surface.bar
        if dragged { bar.say(goingTo ?? page.url) } else { showAddress() }

        // Along the keyboard's own curve when it's going with the field: the
        // one it's already on, after a swipe, or else the one it came up on.
        // The shape starts changing this frame, and the keyboard, told to go
        // just after, carries the surface down on the same curve.
        let field = surface.field
        let keyboard = field.isFirstResponder && Keyboard.up
        // A swipe's keyboard is UIKit's to put away: taking focus from the
        // field under it would have it jump back up for a frame first. UIKit
        // finishes it on a short curve of its own, which carries the rider
        // down with it (it lays the rider out inside that animation). Taking
        // that animation off the rider would end UIKit's early, and the
        // keyboard, drawn by another process, would vanish in a frame.
        let swiped = hiding != nil && (scrim.isTracking || dragged)
        let curve = swiped ? .glide : hiding ?? (keyboard ? rising : nil) ?? .glide
        hiding = nil
        if swiped {
            trailKeyboard()
            holdFocus()
        }

        // The rows go in the frame the address comes, so no frame has both
        // (a row can be the very place Go is going to), and the surface's
        // height goes with them: nothing is left above the field to empty.
        if listed > 0 {
            listed = 0
            rows.view.alpha = 0
            if !dragged { UIView.performWithoutAnimation { place(.field) } }
        }
        starred.show(false)
        SurfaceMotion.animate(curve) { [self] in
            place()
            rider.transform = .identity
            surface.transform = .identity
            bar.address.transform = .identity
            scrim.alpha = 0
            paintTone()
        } completion: { [weak self] _ in
            guard let self else { return }
            handle(.landed(number))
            guard flow.phase == .bar else { return }
            scrim.isHidden = true
            letFocusGo()
            if surface.field.isFirstResponder { surface.field.resignFirstResponder() }
            sampler.look()
        }
        Self.log.notice("close: setup \(Self.ms(since: t0)) ms")
        // As with the focus: the shape is moving before the resign holds the
        // main thread.
        guard !swiped else { return }
        AfterCommit.run { [weak self] in
            guard let self, flow.phase != .field, field.isFirstResponder else { return }
            field.resignFirstResponder()
        }
    }

    /// The address back in place of the field's text, where that text is,
    /// ready to slide home.
    private func showAddress() {
        let bar = surface.bar
        bar.say(goingTo ?? page.url)
        bar.address.isHidden = false
        surface.row.isHidden = true
        surface.setNeedsLayout()
        UIView.performWithoutAnimation { surface.layoutIfNeeded() }
        bar.address.transform = addressOnField()
    }

    /// Moves the address, as laid out, onto where the field's text starts.
    private func addressOnField() -> CGAffineTransform {
        let bar = surface.bar
        let to = surface.convert(CGPoint(x: bar.textStart, y: 0), from: bar).x
        return CGAffineTransform(translationX: SurfaceView.textStart + surface.row.frame.minX - to, y: 0)
    }

    // MARK: A swipe down the keyboard

    /// The keyboard has started down under a finger: from here the field is
    /// the bar in the making, scrubbed by how far the keyboard has gone, the
    /// address sliding home and the dimming lifting with it.
    private func beginDragging() {
        UIView.performWithoutAnimation { showAddress() }
        // Not a paused UIViewPropertyAnimator: while one is paused, UIKit
        // ends its own finish of the keyboard's dismissal at once, and the
        // keyboard, drawn by another process, vanishes in a frame. A plain
        // animation on a stopped clock instead, which the scrub moves.
        let layer = surface.layer
        layer.speed = 0
        layer.timeOffset = 0
        UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear, .overrideInheritedDuration, .overrideInheritedCurve, .overrideInheritedOptions]) { [self] in
            place(.closing)
            surface.bar.address.transform = .identity
            rows.view.alpha = 0
        }
        scrubbed = Self.animated(in: layer)
        dragging = true
    }

    /// UIKit gives the rider a short animation for the keyboard's finish,
    /// but the keyboard itself, drawn by another process, takes longer: the
    /// surface goes down on the same curve stretched to the keyboard's time,
    /// so it stays on the keyboard's top edge rather than ducking behind it.
    /// Two additive animations: one undoing the rider's, one redoing it
    /// slower. The rider's own is left alone (see showBar).
    private func trailKeyboard() {
        guard let ride = rider.layer.animation(forKey: "position") as? CABasicAnimation,
              let from = (ride.fromValue as? NSValue)?.cgPointValue else { return }
        let dy = ride.isAdditive ? from.y : from.y - rider.layer.position.y
        guard dy != 0 else { return }
        for (offset, duration) in [(-dy, ride.duration), (dy, max(ride.duration, Self.keyboardFinish))] {
            guard let trail = ride.copy() as? CABasicAnimation else { return }
            trail.delegate = nil
            trail.keyPath = "transform.translation.y"
            trail.isAdditive = true
            trail.fromValue = offset
            trail.toValue = 0
            trail.duration = duration
            surface.layer.add(trail, forKey: offset == -dy ? "undoRide" : "ride")
        }
    }

    /// UIKit takes focus from the field as soon as its own short finish of a
    /// swiped keyboard is done, and the keyboard, drawn by another process
    /// and still on its way down, vanishes then. So the field keeps focus
    /// for as long as the keyboard takes (keyboardFinish).
    private func holdFocus() {
        surface.field.resignLater = { [weak self] resign in
            self?.resignDue = resign
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyboardFinish) { self?.letFocusGo() }
        }
    }

    /// The held focus goes now: its time is up, or the field is wanted again
    /// (before the flow hears of it, so the keyboard's notice can't close it).
    private func letFocusGo() {
        surface.field.resignLater = nil
        guard let resign = resignDue else { return }
        resignDue = nil
        lettingGo = true
        resign()
        lettingGo = false
    }

    /// How long the keyboard, drawn in another process, takes to finish
    /// going down after a swipe: about seven frames, as in Messages, where
    /// UIKit gives the rider a few.
    static let keyboardFinish: CFTimeInterval = 7.0 / 60

    /// The bar down on the keyboard's own spring, the field's gap above its
    /// top until it's home (KeyboardRide), not on the rider, which the
    /// keyboard outran. Additive on the surface, timed as the rider's ride,
    /// and nothing at either end, so it lands where it would have.
    private func keepOnKeyboard() {
        // Never stack a second close on the previous reopen's correction.
        // Unknown or interrupted UIKit timing falls back to the layout guide.
        stopKeeping()
        guard !UIAccessibility.isReduceMotionEnabled,
              surface.layer.speed == 1, rider.layer.speed == 1,
              let (keep, offset) = KeyboardRide.keep(along: rider.layer.animation(forKey: "position"),
                                                     rest: view.safeAreaInsets.bottom, gap: Self.gap) else { return }
        if keep.beginTime > 0 {
            keep.beginTime = surface.layer.convertTime(keep.beginTime, from: rider.layer)
        }
        surface.layer.add(keep, forKey: Self.keep)
        let layer = surface.layer
        kept = { [weak layer] in
            guard let layer, let begun = layer.animation(forKey: Self.keep)?.beginTime, begun > 0 else { return 0 }
            return offset(layer.convertTime(CACurrentMediaTime(), from: nil) - begun)
        }
    }

    /// Where the keep has the bar now, below the rider.
    private var kept: () -> CGFloat = { 0 }
    private static let keep = "keepOnKeyboard"

    @objc private func stopKeeping() {
        surface.layer.removeAnimation(forKey: Self.keep)
        surface.layer.removeAnimation(forKey: "letKeepGo")
        kept = { 0 }
    }

    /// The field wanted again mid-close, with the keyboard turning back:
    /// the keep goes from where it has the bar, on the quick curve, not in a
    /// jump.
    private func letKeepGo() {
        guard surface.layer.animation(forKey: Self.keep) != nil else { return }
        let now = kept()
        surface.layer.removeAnimation(forKey: Self.keep)
        kept = { 0 }
        guard now > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        let fade = CABasicAnimation(keyPath: "transform.translation.y")
        fade.fromValue = now
        fade.toValue = 0
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.isAdditive = true
        surface.layer.add(fade, forKey: "letKeepGo")
    }

    /// Leaves everything where the finger had it.
    private func stopDragging() {
        guard dragging else { return }
        dragging = false
        for (layer, key, path) in scrubbed {
            if let value = layer.presentation()?.value(forKeyPath: path) { layer.setValue(value, forKeyPath: path) }
            layer.removeAnimation(forKey: key)
        }
        scrubbed = []
        let layer = surface.layer
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
    }

    /// Every animation under `layer`, with the layer it's on and what it moves.
    private static func animated(in layer: CALayer) -> [(layer: CALayer, key: String, path: String)] {
        let own = (layer.animationKeys() ?? []).compactMap { key -> (layer: CALayer, key: String, path: String)? in
            guard let path = (layer.animation(forKey: key) as? CAPropertyAnimation)?.keyPath else { return nil }
            return (layer, key, path)
        }
        return own + (layer.sublayers ?? []).flatMap(animated(in:))
    }

    /// The finger let the keyboard come back: the field again, its own text
    /// back at once where the address had got to, and home from there on
    /// the keyboard's way up, as at a tap.
    private func springBack(on curve: SurfaceMotion.Curve) {
        stopDragging()
        held = false
        let bar = surface.bar
        let from = surface.convert(CGPoint(x: bar.textStart + bar.address.transform.tx, y: 0), from: bar).x
        bar.address.isHidden = true
        bar.address.transform = .identity
        surface.row.isHidden = false
        surface.row.transform = CGAffineTransform(translationX: from - surface.row.frame.minX - SurfaceView.textStart, y: 0)
        surface.magnifier.alpha = 0
        SurfaceMotion.animate(curve) { [self] in
            place()
            surface.row.transform = .identity
            surface.magnifier.alpha = 1
            rows.view.alpha = listed > 0 ? 1 : 0
            showStarred()
            scrim.alpha = 1
        }
    }

    /// Lays the surface out for where the story is, in whatever animation
    /// is running.
    private func place(_ phase: FieldFlow.Phase? = nil) {
        let size = rider.bounds.size
        guard size.width > 0 else { return }
        let phase = phase ?? flow.phase
        switch phase {
        case .bar, .closing:
            let room = size.width - 2 * Bar.margin
            let a = phase == .bar ? amount : 0
            let g = BarGeometry(room: room, address: surface.bar.idealAddressWidth, amount: a)
            surface.mode = .bar(g, amount: a)
            surface.bounds = CGRect(x: 0, y: 0, width: g.width, height: g.height)
            surface.center = CGPoint(x: size.width / 2, y: size.height - g.height / 2 + g.drop)
        case .field:
            let width = size.width - 2 * Self.fieldMargin
            let height = Bar.height + listed
            surface.mode = .field(rows: listed)
            surface.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            surface.center = CGPoint(x: size.width / 2, y: size.height - Self.gap - height / 2)
        }
        surface.layoutIfNeeded()
    }

    /// The page's scrolling, from BarState.
    private func draw(_ amount: CGFloat, spring: CGFloat?, done: @escaping () -> Void) {
        self.amount = amount
        guard flow.phase == .bar else { return done() }
        guard let spring else {
            place()
            return done()
        }
        SurfaceMotion.animate(.glide(velocity: spring)) { self.place() } completion: { _ in done() }
    }

    /// The glass takes the page's tone, but in Private it's Private's dark,
    /// said outright: left to the app's look, the glass reads what's under
    /// it, the light grid sliding away, and rises light.
    private func paintTone() {
        guard !browser.privately else { return surface.paint(.dark) }
        let bar = flow.phase != .field
        let tone: UIUserInterfaceStyle = switch (bar && look == .glass) ? pageTone : nil {
        case .dark?: .dark
        case .light?: .light
        default: .unspecified
        }
        surface.paint(tone)
    }

    /// Under the bar, in the page's coordinates, while the bar is up.
    private func strip() -> CGRect? {
        guard flow.phase == .bar, let web = page.web else { return nil }
        return rider.convert(surface.frame, to: web)
    }

    /// The tab's picture, and the bar over it, in its points: it's drawn
    /// across the page's width from the top (PagePicture).
    private func picture() -> (UIImage, CGRect)? {
        guard flow.phase == .bar, look == .glass, let image = browser.tabs.snapshots.image(page.id),
              view.bounds.width > 0 else { return nil }
        let scale = image.size.width / view.bounds.width
        let bar = rider.convert(surface.frame, to: view)
        return (image, bar.applying(CGAffineTransform(scaleX: scale, y: scale)))
    }

    // MARK: The field

    /// The starred shelf: a new tab's field with nothing offered yet.
    private var wantsStarred: Bool {
        flow.phase == .field && page.url == nil && coordinator.omnibox.offers.isEmpty
    }

    private func showStarred(on curve: SurfaceMotion.Curve = .quick) {
        starred.show(wantsStarred, on: curve)
    }

    /// A keystroke was answered: the rows may have come, gone or changed.
    private func edited() {
        if surface.rim.alpha > 0 {
            SurfaceMotion.animate(.settle) { self.surface.rim.alpha = 0 }
        }
        guard flow.phase == .field else { return }
        let width = rider.bounds.width - 2 * Self.fieldMargin
        let offers = !coordinator.omnibox.offers.isEmpty
        // Gone at once when rows are coming into its place, so no frame
        // shows both; back on the quick fade when they've gone.
        if offers { starred.show(false, on: nil) } else { showStarred() }
        // SwiftUI takes in the new offers at its next update, which a
        // measure alone doesn't bring: without it the first keystroke
        // measured the rows as they were, none.
        rows.view.setNeedsLayout()
        rows.view.layoutIfNeeded()
        let height = offers ? ceil(rows.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height) : 0
        guard height != listed else { return }
        let arriving = (listed == 0) != (height == 0)
        listed = height
        // Their arrival and leaving are brief; the rows otherwise follow what
        // was typed in the same frame.
        if arriving {
            SurfaceMotion.animate(.quick) { [self] in
                place()
                rows.view.alpha = offers ? 1 : 0
            }
        } else {
            place()
        }
    }

    /// Nowhere to go: a red rim, and a shiver.
    private func refuse() {
        SurfaceMotion.animate(.settle) { self.surface.rim.alpha = 1 }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        // Three there-and-backs, tapering to nothing (the Shake effect's).
        let steps = 30
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = (0...steps).map { i -> Double in
            let t = Double(i) / Double(steps)
            return sin(t * .pi * 6) * 7 * (1 - t)
        }
        shake.duration = 0.5
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shake.isAdditive = true
        surface.layer.add(shake, forKey: "shake")
    }

    // MARK: The keyboard, early

    /// Once the page is up and still, load the keyboard (see Keyboard.warm).
    private func warmSoon(_ tries: Int = 0) {
        guard tries < 20, !Keyboard.loaded else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(tries == 0 ? 1.5 : 0.5))
            guard let self, let window = view.window else { return }
            let scroll = page.web?.scrollView
            // The bar over a page that's up, or a field waiting for focus
            // (under the welcome): both stand on the ground, so the hidden
            // keyboard coming and going doesn't move them (pin).
            let still = flow.phase == .bar ? page.web != nil : resting
            let busy = !still || scroll?.isTracking == true
                || scroll?.isDecelerating == true || scrim.isTracking
            guard !busy else { return warmSoon(tries + 1) }
            let start = ContinuousClock.now
            Keyboard.warm(in: window)
            Self.log.notice("keyboard warmed in \(Self.ms(since: start)) ms")
        }
    }

    private static func ms(since start: ContinuousClock.Instant) -> Int {
        let d = ContinuousClock.now - start
        return Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)
    }
}

extension FieldSurface: UIScrollViewDelegate {
    /// The drag is over: UIKit says what the keyboard does, going
    /// (keyboardHiding) or coming back (keyboardShowing), before this on a
    /// lift and just after it on a cancelled touch. Saying neither, it stays.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard dragging, flow.phase == .field else { return }
        // Stopped here, outside UIKit's animation of the keyboard: stopping
        // it inside would end that animation, and the keyboard with it.
        stopDragging()
        held = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, held, flow.phase == .field else { return }
            springBack(on: rising ?? .glide)
        }
    }
}

extension FieldSurface: UIGestureRecognizerDelegate {
    /// The pill is one button: the whole bar again. A drag on the bar is
    /// only for a clear sideways or upward one, with the page showing.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return flow.phase == .bar && amount > 0.5 }
        guard flow.phase == .bar, !browser.fieldOpen, !browser.tabs.gridShown else { return false }
        swipe = BarSwipe(velocity: pan.velocity(in: view))
        return swipe != nil
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gesture is UIPanGestureRecognizer { touchDown = touch.location(in: view).x }
        return true
    }
}

/// Touches go through wherever nothing is drawn.
final class PassThrough: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// The page, dimmed under the open field: a tap on it closes the field, and
/// a swipe down it takes the keyboard with it. It scrolls, with nothing in
/// it, only so that UIKit's interactive keyboard dismissal has a scroll to
/// follow.
final class Scrim: UIScrollView {
    var cancel: () -> Void = {}
    /// A point on screen the dim lets through to what's under it.
    var passes: (CGPoint) -> Bool = { _ in false }
    /// The part of it VoiceOver and the tests treat as the way back.
    var cover: () -> CGRect = { .zero }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor { Palette.UI.ground.resolvedColor(with: $0).withAlphaComponent(0.74) }
        alpha = 0
        isHidden = true
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityLabel = "Cancel"
        accessibilityTraits = .button
        accessibilityIdentifier = "field.cancel"
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { cancel() }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !passes(convert(point, to: nil)) else { return false }
        return super.point(inside: point, with: event)
    }

    override func accessibilityActivate() -> Bool {
        cancel()
        return true
    }

    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(cover(), in: self) }
        set {}
    }
}

/// The surface in the SwiftUI tree, over the page and under nothing.
struct FieldSurfaceHost: UIViewControllerRepresentable {
    let browser: Browser

    func makeUIViewController(context: Context) -> FieldSurface {
        FieldSurface(browser: browser)
    }

    func updateUIViewController(_ surface: FieldSurface, context: Context) {}
}
