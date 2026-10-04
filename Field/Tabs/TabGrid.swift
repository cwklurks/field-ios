import FieldKit
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
    /// The count, and the way into Private beside it (PrivateSwitch).
    private let count = PrivateSwitch()
    private let settings = UIButton(type: .system)
    private let savedButton = UIButton(type: .system)
    private let new = UIButton(type: .system)
    private let done = UIButton(type: .system)
    private var cards: [ObjectIdentifier: TabCard] = [:]
    private var spare: [TabCard] = []
    /// Cards under a finger or on their way out, left out of the layout's
    /// moves and never recycled mid-flight.
    private var loose: [TabCard] = []
    /// The offset is being set under a reflow, which places the cards itself.
    private var reflowing = false
    /// Tidy's groups, each with its tabs, then the loose ones: the cards'
    /// order, which a card's index runs through (GridLayout).
    private var sections: [Session.Grouping.Section<Tab>] = []
    private var order: [Tab] = []
    /// Each group's name over its cards; a long press for its menu.
    private var headers: [UUID: UIButton] = [:]
    /// The headers' names and menus are the groups' as they are now.
    private var headersFresh = false
    /// "12 tabs untouched for 2 weeks · Review / Close", just over the row:
    /// where it's seen as the grid opens, wherever the tab on screen sits,
    /// next to Tidy. At the top of the cards it was off screen whenever the
    /// tab on screen was far down, as it usually is.
    private var banner: UIView?
    private var bannerLine: String?
    private lazy var tidyButton = TidyButton.make { [weak self] in self?.onTidy() }

    var onSelect: (Tab) -> Void = { _ in }
    var onNew: () -> Void = {}
    var onDone: () -> Void = {}
    var onSettings: () -> Void = {}
    var onSaved: () -> Void = {}
    var onTidy: () -> Void = {}
    /// A group header's "Add Similar Tabs".
    var onSimilar: (Session.Group, [Tab]) -> Void = { _, _ in }
    /// The switch, tapped: true to go into Private.
    var onPrivate: (Bool) -> Void = { _ in }
    /// A sideways drag on the row moves the strip 1:1 (PrivateStrip.track),
    /// and lets go with the finger's speed.
    var trackPrivate: (CGFloat) -> Void = { _ in }
    var releasePrivate: (CGFloat) -> Void = { _ in }

    init(tabs: Tabs) {
        self.tabs = tabs
        super.init(frame: .zero)
        backgroundColor = Palette.UI.ground
        accessibilityIdentifier = "tabs.grid"
        // Not greyed under Settings' sheet, only to come back in one frame
        // as it leaves.
        tintAdjustmentMode = .normal

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

        var mark = UIButton.Configuration.plain()
        mark.image = UIImage(systemName: "bookmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: Ramp.row.size, weight: .medium))
        mark.baseForegroundColor = Palette.UI.ink
        savedButton.configuration = mark
        savedButton.accessibilityLabel = "Saved"
        savedButton.accessibilityIdentifier = "tabs.saved"
        savedButton.addAction(UIAction { [weak self] _ in self?.onSaved() }, for: .primaryActionTriggered)
        row.addSubview(savedButton)

        new.configuration = plus
        new.accessibilityLabel = "New tab"
        new.accessibilityIdentifier = "tabs.new"
        new.addAction(UIAction { [weak self] _ in self?.onNew() }, for: .primaryActionTriggered)
        new.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.closedItems() ?? [])
        }])
        row.addSubview(new)

        count.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onPrivate(self.count.wantsPrivate)
        }, for: .primaryActionTriggered)
        row.addSubview(count)
        // On the row only: sideways on a card closes it.
        let slide = UIPanGestureRecognizer(target: self, action: #selector(slid(_:)))
        slide.delegate = self
        row.addGestureRecognizer(slide)

        var finish = UIButton.Configuration.plain()
        var label = AttributedString("Done")
        label.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: Ramp.row.size, weight: .medium), maximumPointSize: 21)
        finish.attributedTitle = label
        finish.baseForegroundColor = Palette.UI.ink
        done.configuration = finish
        done.accessibilityIdentifier = "tabs.done"
        done.addAction(UIAction { [weak self] _ in self?.onDone() }, for: .touchUpInside)
        row.addSubview(done)
        row.addSubview(tidyButton)
        addSubview(row)
    }

    required init?(coder: NSCoder) { fatalError() }

    var layout: GridLayout {
        GridLayout(
            width: bounds.width,
            sections: sections.map { GridLayout.Section(count: $0.items.count, named: $0.group != nil) },
            top: safeAreaInsets.top + 16,
            // The last cards scroll clear of the banner.
            bottom: Self.rowHeight + safeAreaInsets.bottom + 16 + bannerRoom
        )
    }

    /// What the banner takes over the row, with its margin.
    private var bannerRoom: CGFloat { banner.map { $0.bounds.height + 12 } ?? 0 }

    /// The sections and the cards' order, from the tabs as they are now.
    private func regroup() {
        sections = tabs.grouping.sections(tabs.all, id: \.id)
        order = sections.flatMap(\.items)
        headersFresh = false
    }

    /// Scrolled so the tab on screen is in the middle, laid out, now.
    func prepare() {
        regroup()
        showStale()
        setNeedsLayout()
        layoutIfNeeded()
        scroll.contentOffset.y = layout.offset(showing: order.firstIndex { $0 === tabs.current } ?? 0, viewport: bounds.height)
        layoutCards()
    }

    /// Tidy's Apply, Undo or Ungroup: every card from where it is to its
    /// place in its group, as the same card, and the names fading in and out.
    /// A group that's new is what was asked for, so the grid scrolls to the
    /// first, in the same spring, where it would form out of sight above.
    func regrouped() {
        let before = order
        let known = Set(sections.compactMap(\.group?.id))
        regroup()
        let fresh = sections.firstIndex { $0.group.map { !known.contains($0.id) } ?? false }
        reflow(from: before, showing: fresh)
    }

    /// The row along the bottom comes in only once the bar has gone, and goes
    /// before it comes back, so the two are never both on screen. `now`, it
    /// goes in the frame the bar takes its place.
    func showRow(_ shown: Bool, now: Bool = false) {
        row.layer.removeAllAnimations()
        banner?.layer.removeAllAnimations()
        for view in row.subviews { view.alpha = 1 }
        // The banner comes and goes with the row it sits on.
        let both = { (alpha: CGFloat) in
            self.row.alpha = alpha
            self.banner?.alpha = alpha
        }
        if now {
            both(shown ? 1 : 0)
        } else if shown {
            both(0)
            UIView.animate(withDuration: 0.14, delay: 0.1, options: [.curveEaseOut, .allowUserInteraction]) { both(1) }
        } else {
            UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) { both(0) }
        }
    }

    /// The row's buttons and count go now, and its ground stays over the
    /// cards under it: the bar, turning into the field, takes their place
    /// as the grid fades.
    func clearRow() {
        row.layer.removeAllAnimations()
        row.alpha = 1
        for view in row.subviews { view.alpha = 0 }
        banner?.layer.removeAllAnimations()
        banner?.alpha = 0
    }

    /// The strip's progress, inside its animation: the lift moves with it.
    func privateProgress(_ p: CGFloat) {
        count.progress = p
        count.layoutIfNeeded()
    }

    @objc private func slid(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed: trackPrivate(pan.translation(in: self).x)
        case .ended, .cancelled: releasePrivate(pan.velocity(in: self).x)
        default: break
        }
    }

    /// Where a tab's picture is, in this view's coordinates.
    func pictureFrame(of tab: Tab) -> CGRect? {
        if order.count != tabs.all.count { regroup() }
        guard let i = order.firstIndex(where: { $0 === tab }) else { return nil }
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
        savedButton.frame = buttons.saved
        new.frame = buttons.new
        done.frame = buttons.done
        count.frame = buttons.count
        count.count = tabs.all.count
        tidyButton.frame = buttons.tidy
        // Never over Private's tabs, so they never reach Tidy.
        tidyButton.isHidden = !TidyButton.shows(tabs: tabs.all.count) || tabs.space != nil
        if order.count != tabs.all.count { regroup() }
        if let banner {
            let width = bounds.width - 2 * GridLayout.margin
            let height = banner.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                        withHorizontalFittingPriority: .required,
                                                        verticalFittingPriority: .fittingSizeLevel).height
            banner.frame = CGRect(x: GridLayout.margin, y: row.frame.minY - 8 - height, width: width, height: height)
        }
        // A toast over the grid sits clear of the banner.
        if tabs.overRow != bannerRoom { tabs.overRow = bannerRoom }
        scroll.contentSize = CGSize(width: bounds.width, height: layout.contentHeight)
        layoutCards()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        layoutCards()
    }

    /// Makes, places and lets go of cards around what's on screen. After a
    /// close or a reopen (see reflow), `was` has each card's index before,
    /// and each goes from where it is on screen straight to its new place,
    /// one card each, in one spring: along its row, or over the others to
    /// another (see GridLayout.move). One new to the list grows in.
    func layoutCards(was: [ObjectIdentifier: Int]? = nil, scrollingTo target: CGFloat? = nil) {
        guard bounds.width > 0, !reflowing else { return }
        let layout = layout
        let margin = bounds.height
        // Those where it's scrolling to as well, made before it gets there.
        let from = min(scroll.contentOffset.y, target ?? .infinity) - margin
        let to = max(scroll.contentOffset.y, target ?? -.infinity) + bounds.height + margin
        let wanted = layout.visible(from: from, height: to - from)
        let list = order
        var keep = Set<ObjectIdentifier>()
        var moves: [(TabCard, CGRect)] = []
        var growing: [TabCard] = []
        var rising: [TabCard] = []
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
            // Its model is where it's going, so a card already on its way
            // there is left alone, not snapped there by the next pass.
            guard !Self.rests(card, at: frame) else { continue }
            // Along its row, or to another, over the others so none passes
            // under another: by where it is, since a group can move it anywhere.
            let move: GridLayout.Move? = was.map { was in
                was[key] == nil ? .arrive : abs(card.center.y - frame.midY) > 1 ? .hop : .slide
            }
            if made || move == nil {
                UIView.performWithoutAnimation { Self.place(card, at: frame) }
                if move == .arrive {
                    Self.shrink(card)
                    growing.append(card)
                }
            } else {
                // Changing row, it goes over those sliding along theirs.
                if move == .hop { rising.append(card) }
                moves.append((card, frame))
            }
        }
        layoutHeaders(animated: was != nil)
        for card in rising { scroll.bringSubviewToFront(card) }
        // Under those making room for them.
        for card in growing { scroll.sendSubviewToBack(card) }
        if !moves.isEmpty {
            UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                for (card, frame) in moves { Self.place(card, at: frame) }
            }
        }
        if !growing.isEmpty {
            // Once the card leaving its place is mostly out of it.
            UIView.animate(springDuration: 0.30, bounce: 0.14, delay: 0.08, options: [.allowUserInteraction]) {
                for card in growing {
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

    /// Settled in `frame`, as it is at rest.
    private static func rests(_ card: TabCard, at frame: CGRect) -> Bool {
        card.transform == .identity && card.alpha == 1 && card.frame == frame
    }

    /// In `frame`, whole: by its centre, since it may be mid-shrink.
    private static func place(_ card: TabCard, at frame: CGRect) {
        card.bounds.size = frame.size
        card.center = CGPoint(x: frame.midX, y: frame.midY)
        card.alpha = 1
        card.transform = .identity
    }

    /// Ready to grow in where it is.
    private static func shrink(_ card: TabCard) {
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
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
        let before = order
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
            // Its first frame's worth at once: a new animation's first frame
            // is drawn where it starts, which would show nothing after the tap.
            UIView.performWithoutAnimation {
                card.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
                card.alpha = 0.8
            }
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                card.alpha = 0
            } completion: { gone($0) }
        }
    }

    /// After a close or a reopen, in one spring: every card from where it is
    /// on screen to its new place. A grid now shorter than where it was
    /// scrolled to scrolls back in the same spring, and what's on its way
    /// out stays where it is on screen.
    private func reflow(from before: [Tab], showing section: Int? = nil) {
        regroup()
        showStale()
        layoutIfNeeded()
        count.count = tabs.all.count
        let layout = layout
        let old = scroll.contentOffset.y
        var offset = layout.offset(keeping: old, viewport: bounds.height)
        if let section, let header = layout.header(section) {
            offset = min(max(0, layout.contentHeight - bounds.height), max(0, header.minY - safeAreaInsets.top - 8))
        }
        let leaving = loose
        for card in cards.values where !isLoose(card) {
            // Mid-move from the last close, it carries on from where it is.
            guard card.layer.animationKeys()?.isEmpty == false, let now = card.layer.presentation() else { continue }
            card.layer.removeAllAnimations()
            card.center = now.position
            card.transform = now.affineTransform()
            card.alpha = CGFloat(now.opacity)
        }
        let was = Dictionary(uniqueKeysWithValues: before.enumerated().map { (ObjectIdentifier($1), $0) })
        layoutCards(was: was, scrollingTo: offset)
        let size = CGSize(width: bounds.width, height: layout.contentHeight)
        // A shorter size clamps the offset, at once unless it's animated.
        let resize = {
            self.reflowing = true
            self.scroll.contentSize = size
            self.scroll.contentOffset.y = offset
            self.reflowing = false
        }
        guard offset != old else { return resize() }
        UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            resize()
            for card in leaving { card.center.y += offset - old }
        } completion: { [weak self] _ in
            // The cards where it came to rest, if it went further than any were made.
            self?.layoutCards()
        }
    }

    // MARK: - recently closed

    private func closedItems() -> [UIMenuElement] {
        let entries = tabs.closed.items
        guard !entries.isEmpty else { return [] }
        let items = entries.prefix(10).enumerated().map { position, entry in
            let name = entry.title.isEmpty ? (Bar.host(of: URL(string: entry.url)) ?? entry.url) : entry.title
            return UIAction(title: name) { [weak self] _ in
                guard let self else { return }
                let before = order
                tabs.reopen(at: position)
                reflow(from: before)
            }
        }
        return [UIMenu(title: "Recently Closed", options: .displayInline, children: items)]
    }

    // MARK: - groups

    /// Each group's name over its cards: in place with them, fading in when
    /// a group arrives and out when it goes.
    private func layoutHeaders(animated: Bool) {
        let layout = layout
        var seen = Set<UUID>()
        for (index, section) in sections.enumerated() {
            guard let group = section.group, let frame = layout.header(index) else { continue }
            seen.insert(group.id)
            let made = headers[group.id] == nil
            let header = headers[group.id] ?? makeHeader()
            headers[group.id] = header
            if made || !headersFresh {
                header.configuration?.title = group.name
                header.accessibilityLabel = group.name
                header.menu = menu(for: group, tabs: section.items)
            }
            if made || !animated {
                UIView.performWithoutAnimation { header.frame = frame }
            } else if header.frame != frame {
                UIView.animate(springDuration: 0.34, bounce: 0.18, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                    header.frame = frame
                }
            }
            if made, animated {
                header.alpha = 0
                UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut]) { header.alpha = 1 }
            }
        }
        headersFresh = true
        for (id, header) in headers where !seen.contains(id) {
            headers[id] = nil
            UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut]) { header.alpha = 0 } completion: { _ in
                header.removeFromSuperview()
            }
        }
    }

    private func makeHeader() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = Palette.UI.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .footnote)
                .scaledFont(for: .systemFont(ofSize: Ramp.label.size, weight: .semibold), maximumPointSize: 20)
            return outgoing
        }
        let header = UIButton(configuration: config)
        header.contentHorizontalAlignment = .leading
        // The menu comes on a long press; a tap does nothing.
        header.showsMenuAsPrimaryAction = false
        header.accessibilityTraits.insert(.header)
        header.accessibilityIdentifier = "tabs.group"
        scroll.addSubview(header)
        return header
    }

    /// Rename, Add Similar Tabs, Ungroup.
    private func menu(for group: Session.Group, tabs members: [Tab]) -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.rename(group) },
            UIAction(title: "Add Similar Tabs", image: UIImage(systemName: "plus.rectangle.on.rectangle")) { [weak self] _ in
                self?.onSimilar(group, members)
            },
            UIAction(title: "Ungroup", image: UIImage(systemName: "rectangle.3.group")) { [weak self] _ in
                guard let self else { return }
                var grouping = tabs.grouping
                grouping.membership = grouping.membership.filter { $0.value != group.id }
                tabs.regroup(grouping)
            },
        ])
    }

    private func rename(_ group: Session.Group) {
        let alert = UIAlertController(title: "Rename Group", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = group.name
            field.clearButtonMode = .whileEditing
            // Typing replaces the name; the tap or the arrow keys still edit it.
            field.addAction(UIAction { action in (action.sender as? UITextField)?.selectAll(nil) }, for: .editingDidBegin)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text else { return }
            self?.tabs.rename(group.id, to: name)
        })
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(alert, animated: true)
    }

    // MARK: - stale tabs

    /// The banner, when some tabs have gone untouched long enough: made
    /// again only when what it says changes. Never over Private's tabs.
    private func showStale() {
        let found = tabs.space == nil ? StaleTabs.find(tabs.all.map(\.staleEntry), current: tabs.current.id) : nil
        let line = found.flatMap(StaleTabs.line)
        guard line != bannerLine else { return }
        bannerLine = line
        banner?.removeFromSuperview()
        banner = nil
        guard let line, let found else { return setNeedsLayout() }
        let ids = Set(found.all)
        let banner = StaleBanner.hosted(line: line, onReview: { [weak self] in
            guard let self else { return }
            let infos = tabs.all.filter { ids.contains($0.id) }.compactMap(\.info)
            TidySheets.showStale(infos, line: line) { [weak self] chosen in self?.closeStale(Set(chosen)) }
        }, onClose: { [weak self] in self?.closeStale(ids) })
        banner.alpha = row.alpha
        insertSubview(banner, belowSubview: row)
        self.banner = banner
        setNeedsLayout()
    }

    /// Closed together, each to Recently Closed, with one Undo for them all.
    private func closeStale(_ ids: Set<UUID>) {
        let gone = tabs.all.filter { ids.contains($0.id) && $0 !== tabs.current }
        guard !gone.isEmpty else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let before = order
        let undo = tabs.close(all: gone)
        reflow(from: before)
        let n = gone.count
        tabs.offer("Closed \(n) \(n == 1 ? "tab" : "tabs")", Toaster.Offer(title: "Undo") { [weak self] in
            guard let self else { return }
            let before = order
            undo()
            reflow(from: before)
        })
    }
}

extension Tab {
    /// What Tidy is given: pages only.
    var info: TabInfo? { url.map { TabInfo(id: id, title: title, url: $0) } }

    /// What the stale rule reads, without the web view's state, which it
    /// doesn't need and which is slow to take.
    var staleEntry: Session.Entry {
        Session.Entry(id: id, url: url?.absoluteString ?? "", title: title, viewed: viewed)
    }
}
