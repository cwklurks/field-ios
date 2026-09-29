import FieldKit
import UIKit
import WebKit

/// `‹  host  ▢1`: the one bar, at the bottom, whose parts never move. Scrolling
/// down the page shrinks it to a pill holding only the host; scrolling up or a
/// tap brings it back. It is drawn on the surface (FieldSurface), which is also
/// the field: a tap on the address turns the one into the other.
enum Bar {
    static let height: CGFloat = 50
    static let pillHeight: CGFloat = 34
    /// The address's size in the pill.
    static let pillScale: CGFloat = 0.82
    /// From the screen's sides.
    static let margin: CGFloat = 16
    /// How much of the page, above the safe area, the whole bar covers.
    static let clearance: CGFloat = height + 8
    /// Either side of the address, inside its slot.
    static let addressPadding: CGFloat = 10

    /// What the bar says about a page: its host, without the www. Nil for a
    /// blank tab, which asks for an address instead.
    static func host(of url: URL?) -> String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static let placeholder = "Search or enter an address"
}

/// The bar's buttons, laid out for a shrink: back and tabs at the ends,
/// fading out over the first half, the address between them, scaled down
/// rather than cut shorter. Colours resolve in the look the surface gives it
/// (the page's tone, for glass).
final class BarContent: UIView {
    let back = UIButton(type: .custom)
    let address = UIButton(type: .custom)
    let tabs = UIButton(type: .custom)
    /// The address's text: the host, or the placeholder.
    let label = UILabel()
    private let ring = RingView()
    private let count = UILabel()

    /// The back button's long-press list, asked for when it opens.
    var history: () -> (back: [WKBackForwardListItem], forward: [WKBackForwardListItem]) = { ([], []) }
    var goBack: () -> Void = {}
    var go: (WKBackForwardListItem) -> Void = { _ in }
    var showTabs: () -> Void = {}
    /// The tabs button's long-press menu.
    var newTab: () -> Void = {}
    var reopenClosedTab: () -> Void = {}
    /// Whether there's a closed tab to reopen, asked for when the menu opens.
    var canReopen: () -> Bool = { false }
    /// How many tabs are open. What it reads is watched: the count changes
    /// with the tabs, and nothing else on the bar is redone for it.
    var tabCount: () -> Int = { 1 } {
        didSet { setNeedsUpdateProperties() }
    }

    private var canGoBack = false
    /// A blank tab: the placeholder, muted.
    private(set) var blank = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        let symbol = UIImage.SymbolConfiguration(font: .systemFont(ofSize: AddressField.font.pointSize, weight: .medium))
        back.setImage(UIImage(systemName: "chevron.left", withConfiguration: symbol), for: .normal)
        back.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.historyMenu() ?? [])
        }])
        back.addAction(UIAction { [weak self] _ in self?.goBack() }, for: .primaryActionTriggered)
        back.accessibilityLabel = "Back"
        back.accessibilityIdentifier = "bar.back"

        label.font = AddressField.font
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingMiddle
        label.textAlignment = .center
        label.isAccessibilityElement = false
        address.addSubview(label)
        address.addSubview(ring)
        address.accessibilityIdentifier = "bar.address"

        count.text = "1"
        count.font = .systemFont(ofSize: UIFontMetrics(forTextStyle: .footnote).scaledValue(for: Ramp.label.size), weight: .medium)
        count.textAlignment = .center
        count.layer.borderWidth = 1.5
        count.layer.cornerRadius = Radius.icon(22)
        count.layer.cornerCurve = .continuous
        count.isUserInteractionEnabled = false
        tabs.addSubview(count)
        tabs.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            done(self?.tabsMenu() ?? [])
        }])
        tabs.addAction(UIAction { [weak self] _ in self?.showTabs() }, for: .primaryActionTriggered)
        tabs.accessibilityLabel = "Tabs"
        tabs.accessibilityIdentifier = "bar.tabs"

        [back, address, tabs].forEach(addSubview)
        accessibilityIdentifier = "bar"
        accessibilityElements = [back, address, tabs]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.paint() }
        say(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateProperties() {
        super.updateProperties()
        let number = "\(tabCount())"
        count.text = number
        tabs.accessibilityValue = number
        // By its bounds, so it stays centred on the button.
        count.bounds.size.width = max(22, count.intrinsicContentSize.width + 8)
    }

    /// What the tab says now.
    func show(url: URL?, loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        say(url)
        ring.isHidden = !loading
        self.canGoBack = canGoBack
        back.isEnabled = canGoBack || canGoForward
        paint()
    }

    /// The address for `url`: its host, or for a page with none (a `data:`
    /// page) its scheme, as the Mac says; the placeholder only for a blank
    /// tab. Go says the new host at once, before the tab has caught up.
    func say(_ url: URL?) {
        let text = url.map { Bar.host(of: $0) ?? $0.scheme.map { $0 + ":" } ?? "" } ?? Bar.placeholder
        blank = url == nil
        guard label.text != text else { return paint() }
        label.text = text
        address.accessibilityLabel = text
        paint()
        setNeedsLayout()
    }

    private func paint() {
        let ink = Palette.UI.ink
        label.textColor = blank ? Palette.UI.muted : ink
        back.tintColor = canGoBack ? ink : Palette.UI.faint
        count.textColor = ink
        count.layer.borderColor = ink.resolvedColor(with: traitCollection).cgColor
        ring.colour = Palette.UI.muted
    }

    /// The address at its natural width, with its padding, untruncated.
    var idealAddressWidth: CGFloat {
        ceil(label.intrinsicContentSize.width) + 2 * Bar.addressPadding
    }

    /// Lays the buttons out across `bounds` for the shrink `g` was worked out
    /// for. Without `ends`, back and tabs are gone: the field is up.
    func lay(_ g: BarGeometry, amount: CGFloat, ends shown: Bool = true) {
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        address.bounds = CGRect(x: 0, y: 0, width: g.slot, height: 44)
        address.center = mid
        address.transform = CGAffineTransform(scaleX: g.scale, y: g.scale)
        label.frame = address.bounds.insetBy(dx: Bar.addressPadding, dy: 0)
        // Just after the text, wherever the text ends.
        ring.frame = CGRect(x: label.frame.midX + textWidth / 2 + 8, y: address.bounds.midY - 5, width: 10, height: 10)

        let a = min(max(amount, 0), 1)
        let ends = shown ? max(0, 1 - a * 2) : 0
        back.frame = CGRect(x: 3, y: mid.y - 22, width: 44, height: 44)
        tabs.frame = CGRect(x: bounds.width - 47, y: mid.y - 22, width: 44, height: 44)
        count.frame = CGRect(x: 0, y: 0, width: max(22, count.intrinsicContentSize.width + 8), height: 22)
        count.center = CGPoint(x: 22, y: 22)
        back.alpha = ends
        tabs.alpha = ends
        back.isUserInteractionEnabled = a < 0.5
        tabs.isUserInteractionEnabled = a < 0.5
    }

    /// How wide the address's text is drawn, before any scaling.
    private var textWidth: CGFloat {
        min(ceil(label.intrinsicContentSize.width), label.bounds.width)
    }

    /// Where the address's text starts, in this view, as laid out.
    var textStart: CGFloat {
        address.center.x - textWidth / 2 * address.transform.a
    }

    private func tabsMenu() -> [UIMenuElement] {
        var items: [UIMenuElement] = [UIAction(title: "New Tab", image: UIImage(systemName: "plus")) { [weak self] _ in
            self?.newTab()
        }]
        if canReopen() {
            items.append(UIAction(title: "Reopen Closed Tab", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                self?.reopenClosedTab()
            })
        }
        return items
    }

    private func historyMenu() -> [UIMenuElement] {
        let (back, forward) = history()
        var sections: [UIMenuElement] = [UIMenu(options: .displayInline, children: back.reversed().map(item))]
        if !forward.isEmpty {
            sections.append(UIMenu(title: "Forward", options: .displayInline, children: forward.map(item)))
        }
        return sections
    }

    private func item(_ entry: WKBackForwardListItem) -> UIAction {
        let title = entry.title.flatMap { $0.isEmpty ? nil : $0 } ?? Address.pretty(entry.url)
        return UIAction(title: title) { [weak self] _ in self?.go(entry) }
    }
}

/// An almost-closed ring, turning, beside the address while a page loads.
/// Core Animation turns it, so it keeps turning whatever the main thread does.
final class RingView: UIView {
    var colour: UIColor = Palette.UI.muted {
        didSet { paint() }
    }
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        shape.fillColor = nil
        shape.lineWidth = 1.4
        shape.lineCap = .round
        shape.strokeEnd = 0.78
        layer.addSublayer(shape)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.paint() }
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func paint() {
        shape.strokeColor = colour.resolvedColor(with: traitCollection).withAlphaComponent(0.7).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        shape.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 0.7, dy: 0.7)).cgPath
    }

    override var isHidden: Bool {
        didSet { turn() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        turn()
    }

    private func turn() {
        guard window != nil, !isHidden else { return shape.removeAnimation(forKey: "turn") }
        guard shape.animation(forKey: "turn") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 0.85
        spin.repeatCount = .infinity
        shape.add(spin, forKey: "turn")
    }
}
