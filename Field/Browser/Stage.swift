import SwiftUI
import UIKit
import WebKit
import os

/// The page, the carousel and the tab grid (see Stage), in SwiftUI's
/// terms: the current tab's web view is put in place by UIKit and never
/// rebuilt by SwiftUI. Its scrolling drives the bar's shrink straight from
/// UIKit. Takes PageView's place once the browser has tabs.
struct StageView: UIViewRepresentable {
    let browser: Browser
    /// The grid's Saved button.
    var openSaved: () -> Void = {}
    /// The grid's Settings button.
    let openSettings: () -> Void

    /// Your tabs' stage, and Private's while there's a session.
    final class Coordinator {
        var everyday: Stage?
        var side: PrivateSide?
        var privateStage: Stage? { side?.stage as? Stage }
        /// A finger is moving the strip: nothing else slides it meanwhile.
        var dragging = false
        /// How far a drag that can't move the strip has gone.
        var asked: CGFloat = 0
        /// The side the bar was last shown or hidden for.
        var barFor: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Both stages side by side, Private to the right (PrivateStrip).
    func makeUIView(context: Context) -> PrivateStrip {
        let stage = makeStage(for: browser.everyday)
        context.coordinator.everyday = stage
        let strip = PrivateStrip(everyday: stage)
        // The switch's lift and the grid row's tone ride the same spring.
        strip.alongside = { [weak coordinator = context.coordinator] p in
            coordinator?.everyday?.privateProgress(p)
            coordinator?.privateStage?.privateProgress(p)
            // VoiceOver reads the side that's on screen, not the one off it.
            coordinator?.everyday?.accessibilityElementsHidden = p > 0.5
            coordinator?.side?.accessibilityElementsHidden = p < 0.5
        }
        // A drag let go on the other side is the same as the switch.
        strip.landed = { [browser] inside in
            guard inside != browser.privately else { return }
            inside ? browser.enterPrivate() : browser.leavePrivate()
        }
        connect(stage, to: strip, context.coordinator)
        return strip
    }

    /// Reads the current tab and its web view, and Private's session, so
    /// SwiftUI calls again when any of them changes.
    func updateUIView(_ strip: PrivateStrip, context: Context) {
        let c = context.coordinator
        _ = browser.tabs.current.web
        if let tabs = browser.privateSpace.tabs, c.privateStage.map({ $0.tabs !== tabs }) ?? true {
            let stage = makeStage(for: tabs)
            connect(stage, to: strip, c)
            let side = PrivateSide(stage: stage)
            // The list over a closing field, on one tap. The field lets go of
            // the keyboard first, so the list has nothing to give it back to.
            side.openLimits = { [browser] in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                browser.closeField()
                PrivateLimits.present()
            }
            c.side = side
            strip.hold(side)
        } else if browser.privateSpace.tabs == nil, !browser.privately {
            strip.release()
            c.side = nil
        }
        c.side?.welcomeShown = browser.privately && browser.tab.url == nil && !browser.tabs.gridShown
        let inside = browser.privately
        if !c.dragging, (strip.progress > 0.5) != inside { strip.slide(toPrivate: inside) }
        // The bar is the one surface over both sides: it shows over a page
        // and goes over a grid, for the side it's going to, as it slides.
        if c.barFor != inside, let bar = browser.tabs.chrome {
            if c.barFor != nil {
                let shown: CGFloat = browser.tabs.gridShown ? 0 : 1
                UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                    bar.alpha = shown
                }
            }
            c.barFor = inside
        }
        c.everyday?.sync()
        c.privateStage?.sync()
    }

    private func makeStage(for tabs: Tabs) -> Stage {
        let stage = Stage(tabs: tabs, bar: browser.bar, scroller: Scroller(bar: browser.bar))
        stage.openSettings = openSettings
        stage.openSaved = openSaved
        stage.enterPrivate = { [browser] in browser.enterPrivate() }
        stage.leavePrivate = { [browser] in browser.leavePrivate() }
        tabs.stage = stage
        return stage
    }

    /// The grid row's drag moves the strip. With no session to drag into,
    /// or one that's locked, which must come in under its lock screen from
    /// the first frame, a flick or a long drag left goes in as a tap would.
    private func connect(_ stage: Stage, to strip: PrivateStrip, _ c: Coordinator) {
        let draggable = { [browser] in
            browser.privately || (browser.privateSpace.tabs != nil && browser.gate.lock.state == .open)
        }
        stage.trackPrivate = { [weak strip, weak c] dx in
            guard draggable() else {
                c?.asked = dx
                return
            }
            c?.dragging = true
            strip?.track(dx)
        }
        stage.releasePrivate = { [weak strip, weak c, browser] velocity in
            c?.dragging = false
            guard draggable() else {
                let dx = c?.asked ?? 0
                c?.asked = 0
                let far = (strip?.bounds.width ?? 0) / 3
                if velocity < -300 || dx < -far { browser.enterPrivate() }
                return
            }
            strip?.release(velocity: velocity)
        }
    }
}

/// The page and the tab grid, in one UIKit view, so that everything moving
/// between them moves in one space:
///
/// - **The page.** The current tab's web view, over a picture of it (the
///   cover) that shows while it wakes, since a web view stays unseen until
///   its first paint. No white flash, ever.
/// - **The carousel.** Swiping sideways on the bar slides the page with the
///   finger, with the neighbours' pictures beside it, and on release springs
///   on with the finger's speed. The tab it lands on wakes after it lands.
/// - **The grid.** Opening it shrinks the page into its own card; choosing a
///   card grows it back into the page. It is one object each way (a copy of
///   the page moving and changing shape) and its card is hidden while it
///   flies, so there's never two of it on screen.
///
/// Nothing is built while anything moves: a tab wakes when its motion ends.
final class Stage: UIView {
    let tabs: Tabs
    private let bar: BarState
    let scroller: Scroller
    var openSettings: () -> Void = {}
    var openSaved: () -> Void = {}
    var enterPrivate: () -> Void = {}
    var leavePrivate: () -> Void = {}
    /// The grid row's sideways drag, for the strip.
    var trackPrivate: (CGFloat) -> Void = { _ in }
    var releasePrivate: (CGFloat) -> Void = { _ in }

    /// Tidy's groups changed: the grid's cards move to their new places.
    func regrouped() { grid?.regrouped() }

    /// Apply, then Undo from the toast.
    private static func flow(for tabs: Tabs) -> TidyFlow {
        TidyFlow(grouping: { tabs.grouping }, regroup: { tabs.regroup($0) }, toast: { tabs.offer($0, $1) })
    }

    /// 0 on your tabs, 1 in Private: the grid's switch follows it.
    func privateProgress(_ p: CGFloat) {
        privateAt = p
        grid?.privateProgress(p)
    }

    /// The strip's last progress, for a grid made after it moved.
    private var privateAt: CGFloat = 0

    /// Holds the web view and its cover; slides in the carousel.
    private let page = UIView()
    private let cover = PagePicture()
    private var web: WKWebView?
    private weak var placed: Tab?
    private var grid: TabGrid?
    /// The pictures beside the page while it slides: -1 and 1.
    private var neighbours: [Int: PagePicture] = [:]
    private var offset: CGFloat = 0
    /// Where the page was when the finger came down.
    private var sliding: CGFloat?
    /// Whatever is moving now: the carousel, or the grid opening or closing.
    private var animator: UIViewPropertyAnimator?
    /// The page's copy, flying between the page and its card: a clipped,
    /// rounded frame, and the page inside it.
    private var flight: (hero: UIView, content: UIView, tab: Tab)?
    /// The ring flying with it, on the way into the grid.
    private var halo: UIView?
    private var interval: (name: StaticString, state: OSSignpostIntervalState)?

    init(tabs: Tabs, bar: BarState, scroller: Scroller) {
        self.tabs = tabs
        self.bar = bar
        self.scroller = scroller
        super.init(frame: .zero)
        backgroundColor = Palette.UI.ground
        // Touches go to the page under it, whose own wait is short.
        cover.isUserInteractionEnabled = false
        page.addSubview(cover)
        addSubview(page)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var moving: Bool { animator != nil || sliding != nil }

    // MARK: - the page

    /// What SwiftUI calls on every update: puts the current tab's web view in
    /// place when it's changed underneath (built, rebuilt after a crash, a
    /// tab closed or reopened).
    func sync() {
        let tab = tabs.current
        guard !moving else { return }
        if tab !== placed || tab.web !== web { place(tab) }
    }

    /// Shows `tab` in the page, with `picture` (or its own) as the cover
    /// until it paints, and wakes it on the next turn if it's asleep.
    private func place(_ tab: Tab, picture: UIImage? = nil) {
        if placed !== tab {
            placed?.revealed = {}
            placed = tab
            bar.expand()
            preloadNeighbours()
        }
        // A live page coming back into the window takes a frame to draw
        // again, which would show as a blank one.
        let returning = tab.web != nil && tab.web !== web && tab.web?.window == nil && tab.isPainted
        if web !== tab.web {
            web?.removeFromSuperview()
            web = tab.web
            if let web {
                web.scrollView.delegate = scroller
                // What scrolls under the status bar blurs away rather than
                // running into the time and battery.
                web.scrollView.topEdgeEffect.style = .soft
                page.addSubview(web)
                setNeedsLayout()
            }
        }
        if tab.isPainted, let web {
            if returning, let image = picture ?? tabs.snapshots.image(tab.id) {
                // Over the page, not under it, until it has drawn.
                cover.image = image
                cover.isHidden = false
                page.bringSubviewToFront(cover)
                Stage.whenDrawn(web) { [weak self, weak tab] in
                    guard let self, self.placed === tab else { return }
                    self.cover.isHidden = true
                    self.page.sendSubviewToBack(self.cover)
                }
            } else {
                cover.isHidden = true
            }
        } else {
            cover.isHidden = false
            // At launch, the picture on its way since the start, or a frame's
            // wait for it (see Tabs.launch).
            let frame = tabs.barHeld ? 0 : 1 / Double(window?.screen.maximumFramesPerSecond ?? 60)
            cover.image = picture ?? tabs.snapshots.picture(tab.id, waiting: frame)
            if cover.image != nil, tabs.barHeld { tabs.barHeld = false }
            // A picture stays over the page until the page has drawn, since
            // its first frames can draw the band under the bar (its scroll
            // edge) before the page's own pixels; with none, the page fades
            // in over the ground.
            if cover.image != nil { page.bringSubviewToFront(cover) } else { page.sendSubviewToBack(cover) }
            if cover.image == nil, tab.url != nil {
                // Later than that: the bar waits with the page.
                let late = tabs.snapshots.prefetching(tab.id)
                if late { tabs.barHeld = true }
                let id = tab.id
                Task { [weak self, weak tab] in
                    let image = await self?.tabs.snapshots.load(id)
                    guard let self else { return }
                    if let tab, let image, self.placed === tab, !tab.isPainted { self.cover.image = image }
                    if late { self.tabs.barHeld = false }
                }
            }
        }
        tab.revealed = { [weak self, weak tab] in
            guard let self, let tab, self.placed === tab else { return }
            self.prewarmGrid()
            guard let web = self.web, self.cover.superview === self.page, self.page.subviews.last === self.cover else {
                self.cover.isHidden = true
                return
            }
            Stage.whenDrawn(web) { [weak self, weak tab] in
                guard let self, self.placed === tab else { return }
                self.cover.isHidden = true
                self.page.sendSubviewToBack(self.cover)
            }
        }
        wakeIfAsleep(tab)
    }

    /// On the next turn: never inside SwiftUI's update, nor while anything
    /// moves, nor before the first frame (Browser.start builds the first).
    private func wakeIfAsleep(_ tab: Tab) {
        guard tab.asleep, tabs.started else { return }
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab, self.placed === tab, !self.moving, !self.tabs.gridShown, tab.asleep else { return }
            tab.build()
        }
    }

    /// Once the page has drawn twice since now, or a moment has passed,
    /// whichever comes first.
    private static func whenDrawn(_ web: WKWebView, _ then: @escaping () -> Void) {
        let once = Once(then)
        let twoFrames = "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))"
        web.callAsyncJavaScript(twoFrames, arguments: [:], in: nil, in: Tab.world) { _ in once.fire() }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            once.fire()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        page.bounds = CGRect(origin: .zero, size: bounds.size)
        page.center = CGPoint(x: bounds.midX, y: bounds.midY)
        cover.frame = page.bounds
        grid?.frame = bounds
        guard let web else { return }
        web.frame = page.bounds
        let covered = UIEdgeInsets(top: safeAreaInsets.top, left: 0, bottom: safeAreaInsets.bottom + Bar.clearance, right: 0)
        if web.obscuredContentInsets != covered {
            web.obscuredContentInsets = covered
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    /// A tab's new picture: the grid's card, or the cover if it's still waiting.
    func pictureChanged(_ tab: Tab) {
        grid?.pictureChanged(tab)
    }

    private func preloadNeighbours() {
        for step in [-1, 1] {
            guard let tab = tabs.neighbour(by: step), tab.url != nil else { continue }
            Task { _ = await tabs.snapshots.load(tab.id) }
        }
    }

    // MARK: - the carousel

    /// The finger has moved `dx` sideways since the swipe began.
    func track(_ dx: CGFloat) {
        guard !tabs.gridShown else { return }
        if sliding == nil { beginSliding() }
        guard let base = sliding else { return }
        var x = base + dx
        if (x > 0 && tabs.neighbour(by: -1) == nil) || (x < 0 && tabs.neighbour(by: 1) == nil) {
            x = Swipe.rubber(x, limit: bounds.width)
        }
        slide(to: x)
    }

    /// The finger let go, moving `velocity` points a second sideways.
    func release(velocity: CGFloat) {
        guard sliding != nil else { return }
        sliding = nil
        let step = Swipe.step(offset: offset, velocity: velocity, width: bounds.width,
                              previous: tabs.neighbour(by: -1) != nil, next: tabs.neighbour(by: 1) != nil)
        settle(step, velocity: velocity)
    }

    /// One tab along, as if swiped.
    func switchTab(by step: Int) {
        guard tabs.neighbour(by: step) != nil, !tabs.gridShown else { return }
        if sliding == nil { beginSliding() }
        sliding = nil
        settle(step, velocity: 0)
    }

    /// Picks up from wherever the page is, even mid-spring.
    private func beginSliding() {
        if let animator, flight == nil {
            // Left where it is on screen; its completion won't run.
            animator.stopAnimation(true)
            self.animator = nil
            endInterval()
            offset = page.transform.tx
            // Caught by the finger: the tab on screen is still this one.
            tabs.heading(by: 0)
        } else if animator != nil {
            return
        } else {
            offset = 0
            tabs.capture(tabs.current)
        }
        sliding = offset
        for step in [-1, 1] {
            guard let tab = tabs.neighbour(by: step) else { continue }
            let picture = neighbours[step] ?? PagePicture()
            picture.image = tabs.snapshots.image(tab.id)
            // Reused: its last slide's transform goes before its frame is set.
            picture.transform = .identity
            picture.frame = bounds
            if picture.image == nil, tab.url != nil {
                Task { [weak self, weak picture] in
                    guard let image = await self?.tabs.snapshots.load(tab.id) else { return }
                    picture?.image = image
                }
            }
            neighbours[step] = picture
            insertSubview(picture, belowSubview: page)
        }
        slide(to: offset)
    }

    private func slide(to x: CGFloat) {
        offset = x
        page.transform = CGAffineTransform(translationX: x, y: 0)
        let step = bounds.width + Swipe.pageGap
        neighbours[-1]?.transform = CGAffineTransform(translationX: x - step, y: 0)
        neighbours[1]?.transform = CGAffineTransform(translationX: x + step, y: 0)
    }

    private func settle(_ step: Int, velocity: CGFloat) {
        let target = -CGFloat(step) * (bounds.width + Swipe.pageGap)
        beginInterval("tab.switch")
        // The bar says where the page is going as it sets off, and grows
        // back from the pill alongside it: one motion, not a second one
        // once the spring's long tail has landed (bar-polish B-02).
        tabs.heading(by: step)
        if step != 0 { bar.expand() }
        let speed = Swipe.relative(velocity: velocity, from: offset, to: target)
        let animator = Stage.glide(velocity: speed)
        animator.addAnimations { [weak self] in self?.slide(to: target) }
        animator.addCompletion { [weak self] _ in self?.landed(step) }
        self.animator = animator
        animator.startAnimation()
    }

    private func landed(_ step: Int) {
        animator = nil
        let picture = neighbours[step]?.image
        let tab = step == 0 ? nil : tabs.neighbour(by: step)
        slide(to: 0)
        for view in neighbours.values { view.removeFromSuperview() }
        if let tab {
            UISelectionFeedbackGenerator().selectionChanged()
            tabs.select(tab)
            place(tab, picture: picture)
        }
        endInterval()
    }

    // MARK: - the grid

    /// The page shrinks into its own card, and the grid comes up around it.
    /// The bar goes as the page starts to shrink, and the grid's row takes
    /// its place once it has gone; the ring flies in with the page. Caught
    /// mid-close, the same copy turns around from where it is.
    func openGrid() {
        // Tidy's model loads while the grid opens, so its tap waits for nothing.
        if tabs.space == nil { TidyEngine.shared.prewarm() }
        let tab = tabs.current
        let turning = turnAround(for: tab)
        if turning == nil { finishMoving() }
        beginInterval("tabs.open")
        if turning == nil { tabs.capture(tab) }
        let grid = self.grid ?? makeGrid()
        if turning == nil {
            grid.isHidden = false
            grid.frame = bounds
            grid.alpha = 0
            grid.prepare()
        }
        guard !UIAccessibility.isReduceMotionEnabled, let target = grid.pictureFrame(of: tab) else {
            showBar(false)
            page.isHidden = true
            grid.showRow(true)
            run(Stage.quick()) { grid.alpha = 1 } done: { [weak self] in self?.endInterval() }
            return
        }
        let card = grid.card(for: tab)
        card?.pictureHidden = true
        if turning == nil { card?.decorationHidden = true } else { card?.ringHidden = true }
        grid.showRow(true)
        // Gone in the frame the page starts to shrink: the bar floats over
        // the page, so fading it would draw it over the card for a moment.
        showBar(false, now: true)
        // From rest, the page itself takes the first step, out at once:
        // copying it for the flight takes several milliseconds, which would
        // otherwise hold the frame after the tap.
        let frame = 1 / Double(window?.screen.maximumFramesPerSecond ?? 60)
        let tapped = CACurrentMediaTime()
        if turning == nil {
            let first = Stage.glide(after: frame).progress
            // Over the grid for this step, which its copy then takes over.
            bringSubviewToFront(page)
            pose(page, in: Stage.mix(bounds, target, first), radius: Stage.mix(Stage.screenRadius, Radius.card, first))
            grid.alpha = first
            CATransaction.flush()
            bringSubviewToFront(grid)
        }
        let content = turning?.content ?? pageCopy(of: tab)
        let hero = turning?.hero ?? flyer(content, at: bounds, radius: Stage.screenRadius)
        let ring = halo ?? makeHalo(around: hero)
        let mark = self.mark(on: hero, alpha: 0)
        flight = (hero, content, tab)
        page.isHidden = true
        pose(page, in: bounds, radius: 0)
        let scale = target.width / bounds.width
        let from = (frame: hero.frame, radius: hero.layer.cornerRadius, scale: content.transform.a,
                    ring: ring.frame, ringRadius: ring.layer.cornerRadius, ringAlpha: ring.alpha, mark: mark.alpha,
                    grid: turning == nil ? 0 : grid.alpha)
        let goal = target.insetBy(dx: -TabCard.ringGap, dy: -TabCard.ringGap)
        let apply = { (p: CGFloat) in
            let s = Stage.mix(from.scale, scale, p)
            hero.frame = Stage.mix(from.frame, target, p)
            hero.layer.cornerRadius = Stage.mix(from.radius, Radius.card, p)
            content.transform = CGAffineTransform(scaleX: s, y: s)
            ring.frame = Stage.mix(from.ring, goal, p)
            ring.layer.cornerRadius = Stage.mix(from.ringRadius, Radius.card + TabCard.ringGap, p)
            ring.alpha = Stage.mix(from.ringAlpha, 1, p)
            mark.alpha = Stage.mix(from.mark, 1, p)
            grid.alpha = Stage.mix(from.grid, 1, p)
        }
        // Its copy picks up where it will be when this frame is out: the
        // second step, or a later one if the copy took longer than a frame.
        let along = frame * (2 + ((CACurrentMediaTime() - tapped) / frame).rounded(.down))
        run(startGlide(after: turning == nil ? along : 0, apply)) { apply(1) } done: { [weak self] in
            guard let self else { return }
            self.land()
            if let card {
                card.pictureHidden = false
                card.decorationHidden = false
                if card.picture.image == nil {
                    // The page itself, until its picture comes in.
                    content.transform = CGAffineTransform(scaleX: scale, y: scale)
                    card.adopt(content)
                }
            }
            self.endInterval()
        }
    }

    /// The live page drawn where the flight's copy would be, `frame`, with
    /// that corner; `bounds` and no corner put it back.
    private func pose(_ page: UIView, in frame: CGRect, radius: CGFloat) {
        let scale = frame.width / bounds.width
        UIView.performWithoutAnimation {
            page.transform = scale == 1 ? .identity : CGAffineTransform(
                translationX: frame.minX + bounds.width * scale / 2 - bounds.midX,
                y: frame.minY + bounds.height * scale / 2 - bounds.midY
            ).scaledBy(x: scale, y: scale)
            page.layer.cornerRadius = radius / scale
            page.layer.cornerCurve = .continuous
            page.clipsToBounds = radius > 0
        }
    }

    /// The chosen card grows into the page, and the tab wakes once it's
    /// there. The grid's row goes at once and the bar comes back as the
    /// page arrives; the ring stays with the card it was on, and fades.
    /// A card that's off screen (a new tab's, at the end) isn't flown: the
    /// grid gives way to the page instead. Caught mid-open, the same copy
    /// turns around from where it is.
    ///
    /// `field`: a new tab from the grid's + , whose field opens from the
    /// bar at once, as the blank page comes (see Tabs.newTabFromGrid).
    func closeGrid(selecting tab: Tab, field: Bool = false) {
        guard let grid else { return }
        let turning = turnAround(for: tab)
        if turning == nil { finishMoving() }
        beginInterval("tabs.close")
        tabs.select(tab)
        // The rings move to the chosen tab now, fading, and a new tab's card
        // is made, so it's hidden under its copy rather than showing beside it.
        grid.layoutCards()
        let card = grid.card(for: tab)
        let picture = tabs.snapshots.image(tab.id) ?? card?.picture.image
        let source = grid.pictureFrame(of: tab).flatMap { bounds.intersects($0) ? $0 : nil }
        if field {
            // The bar in the row's place, turning into the field.
            grid.clearRow()
            showBar(true, now: true)
            tabs.openField()
        } else {
            grid.showRow(false)
            showBar(true, after: 0.1)
        }

        let landed: () -> Void = { [weak self] in
            guard let self else { return }
            grid.isHidden = true
            grid.alpha = 1
            card?.pictureHidden = false
            card?.decorationHidden = false
            self.page.isHidden = false
            self.place(tab, picture: picture)
            self.endInterval()
        }
        guard !UIAccessibility.isReduceMotionEnabled, turning != nil || source != nil else {
            page.isHidden = false
            place(tab, picture: picture)
            run(Stage.quick()) { grid.alpha = 0 } done: { landed() }
            return
        }
        card?.pictureHidden = true
        // Under the copy leaving it, so it goes without a fade of its own.
        UIView.performWithoutAnimation { card?.decorationHidden = true }
        let content: UIView
        let hero: UIView
        if let turning {
            content = turning.content
            hero = turning.hero
        } else if let source {
            let copy = PagePicture(frame: bounds)
            copy.image = picture
            copy.transform = CGAffineTransform(scaleX: source.width / bounds.width, y: source.width / bounds.width)
            content = copy
            hero = flyer(copy, at: source, radius: Radius.card)
        } else {
            return
        }
        flight = (hero, content, tab)
        let ring = halo
        // A new tab's card was never on screen, nor its button.
        let mark = self.mark(on: hero, alpha: field ? 0 : 1)
        let from = (frame: hero.frame, radius: hero.layer.cornerRadius, scale: content.transform.a,
                    ring: ring?.frame ?? .zero, ringRadius: ring?.layer.cornerRadius ?? 0, ringAlpha: ring?.alpha ?? 0,
                    mark: mark.alpha, grid: grid.alpha)
        let screen = bounds
        let apply = { (p: CGFloat) in
            let s = Stage.mix(from.scale, 1, p)
            hero.frame = Stage.mix(from.frame, screen, p)
            hero.layer.cornerRadius = Stage.mix(from.radius, Stage.screenRadius, p)
            content.transform = CGAffineTransform(scaleX: s, y: s)
            ring?.frame = Stage.mix(from.ring, screen.insetBy(dx: -TabCard.ringGap, dy: -TabCard.ringGap), p)
            ring?.layer.cornerRadius = Stage.mix(from.ringRadius, Stage.screenRadius + TabCard.ringGap, p)
            ring?.alpha = Stage.mix(from.ringAlpha, 0, p)
            mark.alpha = Stage.mix(from.mark, 0, p)
            grid.alpha = Stage.mix(from.grid, 0, p)
        }
        run(startGlide(after: turning == nil ? 1 / Double(window?.screen.maximumFramesPerSecond ?? 60) : 0, apply)) { apply(1) } done: { [weak self] in
            self?.land()
            landed()
        }
    }

    /// The bar, which gives way to the grid's own row: it goes as the grid
    /// starts to come, and comes back as the page does, on the grid's
    /// timeline rather than SwiftUI's, so the two are never both on screen.
    private func showBar(_ shown: Bool, after delay: TimeInterval = 0, now: Bool = false) {
        guard let bar = tabs.chrome else { return }
        let alpha: CGFloat = shown ? 1 : 0
        guard !now else {
            bar.layer.removeAllAnimations()
            bar.alpha = alpha
            return
        }
        UIView.animate(withDuration: shown ? 0.12 : 0.1, delay: delay, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            bar.alpha = alpha
        }
    }

    /// The card's close button, on its picture's copy: it comes and goes
    /// with the flight, since the copy covers the card's own.
    private func mark(on hero: UIView, alpha: CGFloat) -> UIView {
        if let mark = hero.subviews.first(where: { $0.tag == Stage.markTag }) { return mark }
        let mark = TabCard.makeCloseMark(width: hero.bounds.width)
        mark.tag = Stage.markTag
        mark.alpha = alpha
        hero.addSubview(mark)
        return mark
    }

    private static let markTag = 0x7ab

    /// The current tab's ring, flying with its page into the card.
    private func makeHalo(around hero: UIView) -> UIView {
        let ring = TabCard.makeRing()
        ring.frame = hero.frame.insetBy(dx: -TabCard.ringGap, dy: -TabCard.ringGap)
        ring.layer.cornerRadius = hero.layer.cornerRadius + TabCard.ringGap
        ring.alpha = 0
        insertSubview(ring, belowSubview: hero)
        halo = ring
        return ring
    }

    /// The copy in flight, stopped where it is on screen, when it's `tab`'s:
    /// the next motion carries on from there. Anything else in flight is
    /// left to finish.
    private func turnAround(for tab: Tab) -> (hero: UIView, content: UIView)? {
        guard let flight, flight.tab === tab, let animator else { return nil }
        animator.stopAnimation(true)
        self.animator = nil
        endInterval()
        return (flight.hero, flight.content)
    }

    private func land() {
        flight?.hero.removeFromSuperview()
        flight = nil
        halo?.removeFromSuperview()
        halo = nil
    }

    /// The grid's views take a couple of frames to make, so they're made
    /// ahead, a moment after a page has painted and while nothing moves,
    /// rather than on the tap that opens it. Never while the field is up
    /// on a blank tab: the frames would fall between two keystrokes.
    private func prewarmGrid(after delay: TimeInterval = 1.5) {
        guard grid == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.grid == nil, self.placed?.isPainted == true else { return }
            // Not under a finger or while anything coasts: a little later.
            if self.moving || self.web?.scrollView.isTracking == true || self.web?.scrollView.isDecelerating == true {
                return self.prewarmGrid(after: 0.5)
            }
            // Laid out, with its cards made and their pictures decoded, so
            // the first open only has to show it.
            let grid = self.makeGrid()
            grid.frame = self.bounds
            grid.prepare()
            // Drawn once, too faintly to see, so the first open doesn't wait
            // for its pictures to reach the screen: that open's first frame
            // would come late, and its copy's first step with it.
            grid.isUserInteractionEnabled = false
            grid.alpha = 0.01
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak grid] in
                guard let self, let grid else { return }
                grid.isUserInteractionEnabled = true
                guard !self.tabs.gridShown, self.animator == nil else { return }
                grid.isHidden = true
            }
        }
    }

    private func makeGrid() -> TabGrid {
        let grid = TabGrid(tabs: tabs)
        grid.onSelect = { [weak self] tab in self?.tabs.hideGrid(selecting: tab) }
        grid.onDone = { [weak self] in self?.tabs.hideGrid() }
        grid.onNew = { [weak self] in self?.tabs.newTabFromGrid() }
        grid.onSettings = { [weak self] in self?.openSettings() }
        grid.onSaved = { [weak self] in self?.openSaved() }
        // Private's tabs never get here: the grid shows no Tidy for them.
        grid.onTidy = { [tabs] in
            guard tabs.space == nil else { return }
            TidySheets.show(tabs.all.compactMap(\.info), flow: Stage.flow(for: tabs))
        }
        grid.onSimilar = { [tabs] group, members in
            guard tabs.space == nil else { return }
            let loose = tabs.all.filter { $0.group == nil }.compactMap(\.info)
            TidySheets.showSimilar(to: group, members: members.compactMap(\.info), among: loose, flow: Stage.flow(for: tabs))
        }
        grid.onPrivate = { [weak self] entering in entering ? self?.enterPrivate() : self?.leavePrivate() }
        grid.trackPrivate = { [weak self] in self?.trackPrivate($0) }
        grid.releasePrivate = { [weak self] in self?.releasePrivate($0) }
        grid.privateProgress(privateAt)
        addSubview(grid)
        self.grid = grid
        return grid
    }

    /// What the page looks like now: the live page's own layers when it has
    /// painted, which is cheap (no pixels are copied), or its picture.
    private func pageCopy(of tab: Tab) -> UIView {
        if let web, tab.isPainted, let copy = web.snapshotView(afterScreenUpdates: false) {
            copy.frame = bounds
            anchorTopLeft(copy)
            return copy
        }
        let picture = PagePicture(frame: bounds)
        picture.image = tabs.snapshots.image(tab.id) ?? cover.image
        anchorTopLeft(picture)
        return picture
    }

    /// A rounded, clipped frame for the page's copy to fly in; the copy
    /// scales from its top left, so a card shows the top of the page.
    private func flyer(_ content: UIView, at frame: CGRect, radius: CGFloat) -> UIView {
        land()
        let hero = UIView(frame: frame)
        hero.clipsToBounds = true
        hero.layer.cornerRadius = radius
        hero.layer.cornerCurve = .continuous
        hero.backgroundColor = Palette.UI.ground
        anchorTopLeft(content)
        hero.addSubview(content)
        addSubview(hero)
        // Laid out now, or its first layout lands inside the animation and
        // its picture grows from nothing.
        content.layoutIfNeeded()
        return hero
    }

    private func anchorTopLeft(_ view: UIView) {
        let transform = view.transform
        view.transform = .identity
        let size = view.bounds.size
        view.layer.anchorPoint = .zero
        view.frame = CGRect(origin: .zero, size: size)
        view.transform = transform
    }

    /// A motion still running is brought to its end at once, so a new one
    /// starts from a settled place.
    private func finishMoving() {
        sliding = nil
        guard let animator else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .end)
    }

    // MARK: - motion

    /// The corner the page has when it fills the screen: rounded off by the
    /// screen itself, so a match hides the moment it starts to shrink.
    static let screenRadius: CGFloat = 44

    /// A glide from rest for a flight that `apply(progress)` lays out, put
    /// `along` seconds in at once with the speed it has there (0: from where
    /// it is). Core Animation draws a new animation's first frame where it
    /// starts, so from rest the frame after a tap would show nothing moving.
    private func startGlide(after along: TimeInterval, _ apply: (CGFloat) -> Void) -> UIViewPropertyAnimator {
        guard along > 0, !UIAccessibility.isReduceMotionEnabled else { return Stage.glide(velocity: 0) }
        let start = Stage.glide(after: along)
        UIView.performWithoutAnimation { apply(start.progress) }
        return Stage.glide(velocity: start.velocity)
    }

    /// A glide from rest (Motion.glide: response 0.34, damping 0.82) `t`
    /// seconds in: how far along, and how fast, as a share of the distance
    /// still to go each second, which is how UIKit's springs take a speed.
    static func glide(after t: TimeInterval) -> (progress: CGFloat, velocity: CGFloat) {
        guard t > 0 else { return (0, 0) }
        let omega = 2 * Double.pi / 0.34, zeta = 0.82
        let decay = zeta * omega, damped = omega * (1 - zeta * zeta).squareRoot()
        let envelope = exp(-decay * t)
        let progress = 1 - envelope * (cos(damped * t) + decay / damped * sin(damped * t))
        let speed = envelope * omega * omega / damped * sin(damped * t)
        return (progress, progress < 1 ? speed / (1 - progress) : 0)
    }

    static func mix(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }

    static func mix(_ a: CGRect, _ b: CGRect, _ p: CGFloat) -> CGRect {
        CGRect(x: mix(a.minX, b.minX, p), y: mix(a.minY, b.minY, p),
               width: mix(a.width, b.width, p), height: mix(a.height, b.height, p))
    }

    /// Motion.glide in UIKit's terms: the same spring, picking up a finger's
    /// speed (as a fraction of the distance left, each second).
    static func glide(velocity: CGFloat) -> UIViewPropertyAnimator {
        guard !UIAccessibility.isReduceMotionEnabled else { return quick() }
        let spring = UISpringTimingParameters(duration: 0.34, bounce: 0.18, initialVelocity: CGVector(dx: velocity, dy: velocity))
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: spring)
        animator.isUserInteractionEnabled = true
        return animator
    }

    /// Motion.quick: the ease out that Reduce Motion turns every spring into.
    static func quick() -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(duration: 0.14, curve: .easeOut)
    }

    private func run(_ animator: UIViewPropertyAnimator, _ animations: @escaping () -> Void, done: @escaping () -> Void) {
        animator.addAnimations(animations)
        animator.addCompletion { [weak self, weak animator] _ in
            if let self, self.animator === animator { self.animator = nil }
            done()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func beginInterval(_ name: StaticString) {
        endInterval()
        interval = (name, Signpost.log.beginAnimationInterval(name))
    }

    private func endInterval() {
        guard let interval else { return }
        Signpost.log.endInterval(interval.name, interval.state)
        self.interval = nil
    }
}

/// Runs its work the first time it's fired, and never again.
private final class Once {
    private var work: (() -> Void)?

    init(_ work: @escaping () -> Void) {
        self.work = work
    }

    func fire() {
        let work = self.work
        self.work = nil
        work?()
    }
}
