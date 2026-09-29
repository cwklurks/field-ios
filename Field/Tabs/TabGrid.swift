import UIKit

/// Every tab as a card, two to a row, over the ground, with a row along the
/// bottom: Settings, a new tab (hold it for the ones recently closed), how many there
/// are, and Done. Only the cards on screen, and a screen's worth either side,
/// exist; the rest are made as they scroll in, with their pictures decoded
/// off the main thread (see Snapshots).
///
/// Opening and closing it is the Stage's: the page and a card are one
/// object moving between the two, and this only says where the card is.
final class TabGrid: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    static let rowHeight: CGFloat = 50

    let scroll = UIScrollView()
    private let tabs: Tabs
    private let row = UIView()
    private let count = UILabel()
    private let settings = UIButton(type: .system)
    private let new = UIButton(type: .system)
    private let done = UIButton(type: .system)
    private var cards: [ObjectIdentifier: TabCard] = [:]
    private var spare: [TabCard] = []
    /// Cards under a finger or on their way out, left out of the layout's
    /// moves and never recycled mid-flight.
    private var loose: [TabCard] = []
    /// The offset is being set under a reflow, which places the cards itself.
    private var reflowing = false

    var onSelect: (Tab) -> Void = { _ in }
    var onNew: () -> Void = {}
    var onDone: () -> Void = {}
    var onSettings: () -> Void = {}

    init(tabs: Tabs) {
        self.tabs = tabs
        super.init(frame: .zero)
        backgroundColor = Palette.UI.ground
        accessibilityIdentifier = "tabs.grid"

        scroll.delegate = self
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false
        // Cards blur away under the status bar, as the page does.
        scroll.topEdgeEffect.style = .soft
        addSubview(scroll)

        row.backgroundColor = Palette.UI.ground
        let hairline = UIView()
        hairline.backgroundColor = Palette.UI.hairline
        hairline.autoresizingMask = [.flexibleWidth]
        hairline.frame = CGRect(x: 0, y: 0, width: 1, height: 1 / 3)
        row.addSubview(hairline)

        var plus = UIButton.Configuration.plain()
        plus.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: Ramp.row.size, weight: .medium))
        plus.baseForegroundColor = Palette.UI.ink
        var gear = UIButton.Configuration.plain()
        gear.image = UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: Ramp.row.size, weight: .medium))
        gear.baseForegroundColor = Palette.UI.ink
        settings.configuration = gear
        settings.accessibilityLabel = "Settings"
        settings.accessibilityIdentifier = "tabs.settings"
        // Straight to the sheet: no menu to close first.
        settings.addAction(UIAction { [weak self] _ in self?.onSettings() }, for: .primaryActionTriggered)
        row.addSubview(settings)

        new.configuration = plus
        new.accessibilityLabel = "New tab"
        new.accessibilityIdentifier = "tabs.new"
        new.addAction(UIAction { [weak self] _ in self?.onNew() }, for: .primaryActionTriggered)
        new.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.closedItems() ?? [])
        }])
        row.addSubview(new)

        count.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: Ramp.row.size), maximumPointSize: 21)
        count.textColor = Palette.UI.muted
        count.textAlignment = .center
        row.addSubview(count)

        var finish = UIButton.Configuration.plain()
        var label = AttributedString("Done")
        label.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: Ramp.row.size, weight: .medium), maximumPointSize: 21)
        finish.attributedTitle = label
        finish.baseForegroundColor = Palette.UI.ink
        done.configuration = finish
        done.accessibilityIdentifier = "tabs.done"
        done.addAction(UIAction { [weak self] _ in self?.onDone() }, for: .touchUpInside)
        row.addSubview(done)
        addSubview(row)
    }

    required init?(coder: NSCoder) { fatalError() }

    var layout: GridLayout {
        GridLayout(
            width: bounds.width,
            count: tabs.all.count,
            top: safeAreaInsets.top + 16,
            bottom: Self.rowHeight + safeAreaInsets.bottom + 16
        )
    }

    /// Scrolled so the tab on screen is in the middle, laid out, now.
    func prepare() {
        setNeedsLayout()
        layoutIfNeeded()
        scroll.contentOffset.y = layout.offset(showing: tabs.index, viewport: bounds.height)
        layoutCards()
    }

    /// The row along the bottom comes in only once the bar has gone, and goes
    /// before it comes back, so the two are never both on screen. `now`, it
    /// goes in the frame the bar takes its place.
    func showRow(_ shown: Bool, now: Bool = false) {
        row.layer.removeAllAnimations()
        if now {
            row.alpha = shown ? 1 : 0
        } else if shown {
            row.alpha = 0
            UIView.animate(withDuration: 0.14, delay: 0.1, options: [.curveEaseOut, .allowUserInteraction]) { self.row.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) { self.row.alpha = 0 }
        }
    }

    /// Where a tab's picture is, in this view's coordinates.
    func pictureFrame(of tab: Tab) -> CGRect? {
        guard let i = tabs.all.firstIndex(where: { $0 === tab }) else { return nil }
        return scroll.convert(layout.picture(i), to: self)
    }

    func card(for tab: Tab) -> TabCard? {
        cards[ObjectIdentifier(tab)]
    }

    /// A card's picture has come in.
    func pictureChanged(_ tab: Tab) {
        guard let card = card(for: tab), let image = tabs.snapshots.image(tab.id) else { return }
        card.drop()
        card.picture.image = image
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let bottom = safeAreaInsets.bottom
        row.frame = CGRect(x: 0, y: bounds.height - Self.rowHeight - bottom, width: bounds.width, height: Self.rowHeight + bottom)
        let buttons = GridRow(width: bounds.width)
        settings.frame = buttons.settings
        new.frame = buttons.new
        done.frame = buttons.done
        count.frame = buttons.count
        count.text = tabs.all.count == 1 ? "1 Tab" : "\(tabs.all.count) Tabs"
        scroll.contentSize = CGSize(width: bounds.width, height: layout.contentHeight)
        layoutCards()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutCards()
    }

    /// Makes, places and lets go of cards around what's on screen. After a
    /// close or a reopen (see reflow), each card that was on screen goes
    /// from where it was, `from`, and one new to the list grows in.
    func layoutCards(from: [ObjectIdentifier: CGRect] = [:], was: [ObjectIdentifier: Int]? = nil) {
        guard bounds.width > 0, !reflowing else { return }
        let layout = layout
        let margin = bounds.height
        let wanted = layout.visible(from: scroll.contentOffset.y - margin, height: bounds.height + 2 * margin)
        let list = tabs.all
        var keep = Set<ObjectIdentifier>()
        var moves: [(TabCard, CGRect)] = []
        var arriving: [TabCard] = []
        for i in wanted {
            let tab = list[i]
            let key = ObjectIdentifier(tab)
            keep.insert(key)
            let made = cards[key] == nil
            let card = cards[key] ?? make(for: tab)
            card.show(tab, index: i, current: tab === tabs.current, image: tabs.snapshots.image(tab.id))
            if card.picture.image == nil { load(tab) }
            guard !isLoose(card) else { continue }
            let frame = layout.card(i)
            if let was {
                // Whoever changes row passes behind those sliding along one.
                if let before = was[key], GridLayout.wraps(from: before, to: i) { scroll.sendSubviewToBack(card) }
                if made, was[key] == nil {
                    UIView.performWithoutAnimation {
                        card.frame = frame
                        card.alpha = 0
                        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                    }
                    arriving.append(card)
                    continue
                }
            }
            // Its model frame is where it's going, so a card already on its
            // way there is left alone, not snapped there by the next pass.
            let start = from[key] ?? card.frame
            if start != frame, start != .zero, !from.isEmpty {
                UIView.performWithoutAnimation { card.frame = start }
                moves.append((card, frame))
            } else if card.frame != frame {
                UIView.performWithoutAnimation { card.frame = frame }
            }
        }
        // One coming back grows in under those making room for it.
        for card in arriving { scroll.sendSubviewToBack(card) }
        if !moves.isEmpty || !arriving.isEmpty {
            UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                for (card, frame) in moves { card.frame = frame }
                for card in arriving {
                    card.alpha = 1
                    card.transform = .identity
                }
            }
        }
        for (key, card) in cards where !keep.contains(key) && !isLoose(card) {
            cards[key] = nil
            card.removeFromSuperview()
            card.drop()
            card.layer.removeAllAnimations()
            card.transform = .identity
            card.alpha = 1
            card.pictureHidden = false
            card.decorationHidden = false
            spare.append(card)
        }
    }

    private func isLoose(_ card: TabCard) -> Bool {
        loose.contains { $0 === card }
    }

    private func make(for tab: Tab) -> TabCard {
        let card = spare.popLast() ?? {
            let card = TabCard()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.delegate = self
            card.addGestureRecognizer(pan)
            return card
        }()
        card.frame = .zero
        card.onSelect = { [weak self] in self?.onSelect($0) }
        card.onClose = { [weak self] in self?.close($0, card: nil, velocity: 0) }
        cards[ObjectIdentifier(tab)] = card
        scroll.addSubview(card)
        return card
    }

    private func load(_ tab: Tab) {
        guard tab.url != nil else { return }
        Task { [weak self] in
            guard await self?.tabs.snapshots.load(tab.id) != nil else { return }
            self?.pictureChanged(tab)
        }
    }

    // MARK: - closing a card

    /// Sideways only: up and down is the grid scrolling.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: self)
        return abs(v.x) > abs(v.y) * 1.2
    }

    /// The card follows the finger 1:1, fading as it goes, and on release is
    /// thrown away or springs back with the finger's speed.
    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let card = pan.view as? TabCard, let tab = card.tab else { return }
        let x = pan.translation(in: self).x
        let width = card.bounds.width
        switch pan.state {
        case .began:
            if !isLoose(card) { loose.append(card) }
            card.layer.removeAllAnimations()
        case .changed:
            card.transform = CGAffineTransform(translationX: x, y: 0)
            card.alpha = 1 - min(0.7, abs(x) / (width * 1.6))
        case .ended, .cancelled:
            let v = pan.velocity(in: self).x
            if pan.state == .ended, Swipe.dismisses(offset: x, velocity: v, width: width) {
                close(tab, card: card, velocity: v)
            } else {
                let speed = Swipe.relative(velocity: v, from: x, to: 0)
                UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: speed, options: [.allowUserInteraction]) {
                    card.transform = .identity
                    card.alpha = 1
                } completion: { [weak self] _ in
                    self?.loose.removeAll { $0 === card }
                }
            }
        default:
            break
        }
    }

    /// Off the side with the finger's speed (or, from its button, shrinking
    /// where it is), while the others close the gap in the same moment.
    private func close(_ tab: Tab, card: TabCard?, velocity: CGFloat) {
        let card = card ?? self.card(for: tab)
        if let card, !isLoose(card) { loose.append(card) }
        UISelectionFeedbackGenerator().selectionChanged()
        let begin = Signpost.log.beginAnimationInterval("card.close")
        let before = tabs.all
        tabs.close(tab)
        reflow(from: before)
        guard let card else { return Signpost.log.endInterval("card.close", begin) }
        // Under the others, which close the gap over it as it goes.
        scroll.sendSubviewToBack(card)
        let gone: (Bool) -> Void = { [weak self] _ in
            Signpost.log.endInterval("card.close", begin)
            guard let self else { return }
            self.loose.removeAll { $0 === card }
            if let key = self.cards.first(where: { $0.value === card })?.key { self.cards[key] = nil }
            card.removeFromSuperview()
            card.transform = .identity
            card.alpha = 1
            self.spare.append(card)
        }
        if velocity != 0 {
            let x = card.transform.tx
            let away = (x < 0 ? -1 : 1) * bounds.width
            let speed = Swipe.relative(velocity: velocity, from: x, to: away)
            UIView.animate(springDuration: 0.30, bounce: 0, initialSpringVelocity: speed, options: [.allowUserInteraction]) {
                card.transform = CGAffineTransform(translationX: away, y: 0)
                card.alpha = 0
            } completion: { gone($0) }
        } else {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                card.alpha = 0
            } completion: { gone($0) }
        }
    }

    /// After a close or a reopen, in one spring: every card from where it is
    /// on screen to its new place. A grid now shorter than where it was
    /// scrolled to is scrolled back at once, and the cards moved by as much,
    /// so nothing on screen jumps: it all comes back with the cards.
    private func reflow(from before: [Tab]) {
        count.text = tabs.all.count == 1 ? "1 Tab" : "\(tabs.all.count) Tabs"
        let layout = layout
        let old = scroll.contentOffset.y
        let offset = layout.offset(keeping: old, viewport: bounds.height)
        let shift = offset - old
        var from: [ObjectIdentifier: CGRect] = [:]
        for (key, card) in cards {
            if isLoose(card) {
                UIView.performWithoutAnimation { card.center.y += shift }
            } else {
                // Mid-move from the last close, it carries on from where it is.
                from[key] = (card.layer.presentation()?.frame ?? card.frame).offsetBy(dx: 0, dy: shift)
                card.layer.removeAllAnimations()
            }
        }
        reflowing = true
        scroll.contentSize = CGSize(width: bounds.width, height: layout.contentHeight)
        scroll.contentOffset.y = offset
        reflowing = false
        let was = Dictionary(uniqueKeysWithValues: before.enumerated().map { (ObjectIdentifier($1), $0) })
        layoutCards(from: from, was: was)
    }

    // MARK: - recently closed

    private func closedItems() -> [UIMenuElement] {
        let entries = tabs.closed.items
        guard !entries.isEmpty else { return [] }
        let items = entries.prefix(10).enumerated().map { position, entry in
            let name = entry.title.isEmpty ? (Bar.host(of: URL(string: entry.url)) ?? entry.url) : entry.title
            return UIAction(title: name) { [weak self] _ in
                guard let self else { return }
                let before = tabs.all
                tabs.reopen(at: position)
                reflow(from: before)
            }
        }
        return [UIMenu(title: "Recently Closed", options: .displayInline, children: items)]
    }
}
