import UIKit

/// One tab in the grid: a picture of its page with a close button on it, and
/// under it the site's letter and the page's title. The one on screen wears
/// a ring of ink. Reused as the grid scrolls, so it's handed its tab each time.
final class TabCard: UIView {
    static let ring: CGFloat = 2.5
    static let ringGap: CGFloat = 3

    let picture = PagePicture()
    private let letter = UILabel()
    private let badge = UIView()
    private let title = UILabel()
    private let close = UIButton(type: .system)
    /// The ring, in something that hides it with the close button while
    /// the card's picture flies (see decorationHidden).
    private let ringHolder = UIView()
    private let ring = TabCard.makeRing()
    /// Stands in for the picture while the page's own is on its way: the
    /// live page itself, just landed from the transition.
    private var adopted: UIView?

    private(set) var tab: Tab?
    var onSelect: (Tab) -> Void = { _ in }
    var onClose: (Tab) -> Void = { _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)

        ringHolder.isUserInteractionEnabled = false
        ringHolder.addSubview(ring)
        addSubview(ringHolder)

        picture.layer.cornerRadius = Radius.card
        picture.layer.cornerCurve = .continuous
        picture.layer.borderWidth = 1
        picture.isAccessibilityElement = true
        picture.accessibilityTraits = .button
        picture.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addSubview(picture)

        close.configuration = Self.closeLook
        close.accessibilityLabel = "Close tab"
        close.addAction(UIAction { [weak self] _ in self?.closeTapped() }, for: .touchUpInside)
        addSubview(close)

        badge.backgroundColor = Palette.UI.wash
        badge.layer.cornerRadius = Radius.icon(18)
        badge.layer.cornerCurve = .continuous
        letter.font = .systemFont(ofSize: Ramp.glyph.size)
        letter.textColor = Palette.UI.muted
        letter.textAlignment = .center
        badge.addSubview(letter)
        addSubview(badge)

        title.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: Ramp.tab.size), maximumPointSize: 19)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Palette.UI.ink
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)

        tint()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: TabCard, _) in card.tint() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The site's letter: the first of its host, when that's a letter, so an
    /// address by number (127.0.0.1, ::1) has none rather than a digit.
    static func letter(for url: URL?) -> String? {
        guard let first = Bar.host(of: url)?.first, first.isLetter else { return nil }
        return String(first).uppercased()
    }

    private static let closeSymbol = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold))
    private static let closeFill = Palette.UI.raised.withAlphaComponent(0.92)

    static var closeLook: UIButton.Configuration {
        var look = UIButton.Configuration.plain()
        look.image = closeSymbol
        look.baseForegroundColor = Palette.UI.ink
        look.background.backgroundColor = closeFill
        look.background.cornerRadius = 11
        look.contentInsets = .zero
        return look
    }

    /// Where the close button sits on a picture this wide.
    static func closeFrame(width: CGFloat) -> CGRect {
        CGRect(x: width - 30, y: 8, width: 22, height: 22)
    }

    /// The close button's look, for a copy of a picture on its way to or
    /// from its card (see Stage), keeping to the picture's top right. Plain
    /// views, which draw in the frame they're added in, as a button doesn't.
    static func makeCloseMark(width: CGFloat) -> UIView {
        let mark = UIView(frame: closeFrame(width: width))
        mark.isUserInteractionEnabled = false
        mark.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        mark.backgroundColor = closeFill
        mark.layer.cornerRadius = 11
        let cross = UIImageView(image: closeSymbol)
        cross.tintColor = Palette.UI.ink
        cross.contentMode = .center
        cross.frame = mark.bounds
        mark.addSubview(cross)
        return mark
    }

    /// The ring of ink around the current tab's picture, which also flies
    /// with the page into its card (see Stage.openGrid).
    static func makeRing() -> UIView {
        let ring = CardRing()
        ring.isUserInteractionEnabled = false
        ring.layer.cornerRadius = Radius.card + Self.ringGap
        ring.layer.cornerCurve = .continuous
        ring.layer.borderWidth = Self.ring
        return ring
    }

    /// Layer colours don't follow the look by themselves.
    private func tint() {
        let traits = traitCollection
        picture.layer.borderColor = Palette.UI.ink.resolvedColor(with: traits).withAlphaComponent(0.08).cgColor
    }

    func show(_ tab: Tab, index: Int, current: Bool, image: UIImage?) {
        let same = self.tab === tab
        if !same { drop() }
        self.tab = tab
        let name = tab.title.isEmpty ? (Bar.host(of: tab.url) ?? "New tab") : tab.title
        title.text = name
        letter.text = Self.letter(for: tab.url)
        if badge.isHidden != (letter.text == nil) {
            badge.isHidden = letter.text == nil
            setNeedsLayout()
        }
        picture.image = image
        // Another tab made current fades its ring in, and this one's out,
        // rather than popping; a card handed a new tab just has it.
        let ringAlpha: CGFloat = current ? 1 : 0
        if ring.alpha != ringAlpha {
            if same, window != nil {
                UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                    self.ring.alpha = ringAlpha
                }
            } else {
                UIView.performWithoutAnimation { ring.alpha = ringAlpha }
            }
        }
        picture.accessibilityLabel = name
        picture.accessibilityIdentifier = "tabs.card.\(index)"
        close.accessibilityIdentifier = "tabs.close.\(index)"
    }

    /// The live page, landed here by the grid's opening, until the card's
    /// own picture arrives.
    func adopt(_ view: UIView) {
        drop()
        adopted = view
        picture.addSubview(view)
    }

    func drop() {
        adopted?.removeFromSuperview()
        adopted = nil
    }

    /// Hidden while a copy of it flies to or from the page, so there's only
    /// ever one.
    var pictureHidden: Bool {
        get { picture.alpha == 0 }
        set { picture.alpha = newValue ? 0 : 1 }
    }

    /// The ring and the close button, which come and go with the motion
    /// rather than after it.
    var decorationHidden: Bool {
        get { close.alpha == 0 }
        set { closeHidden = newValue; ringHidden = newValue }
    }

    var closeHidden: Bool {
        get { close.alpha == 0 }
        set { close.alpha = newValue ? 0 : 1 }
    }

    /// The ring, if it's the current tab's, or else nothing.
    var ringHidden: Bool {
        get { ringHolder.alpha == 0 }
        set { ringHolder.alpha = newValue ? 0 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let face = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - GridLayout.titleHeight)
        picture.frame = face
        ringHolder.frame = face.insetBy(dx: -Self.ringGap, dy: -Self.ringGap)
        ring.frame = ringHolder.bounds
        close.frame = Self.closeFrame(width: face.width)
        let row = face.maxY + 8
        badge.frame = CGRect(x: 2, y: row, width: 18, height: 18)
        letter.frame = badge.bounds
        let titleX = badge.isHidden ? 2 : badge.frame.maxX + 7
        title.frame = CGRect(x: titleX, y: row - 1, width: bounds.width - titleX - 2, height: 20)
    }

    /// A bigger target than it looks: the whole corner.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if close.alpha > 0, close.frame.insetBy(dx: -10, dy: -10).contains(point) { return close }
        return super.hitTest(point, with: event)
    }

    @objc private func tapped() {
        guard let tab else { return }
        onSelect(tab)
    }

    private func closeTapped() {
        guard let tab else { return }
        onClose(tab)
    }
}

/// A ring of ink that keeps its colour with the look.
private final class CardRing: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tint()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (ring: CardRing, _) in ring.tint() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func tint() {
        layer.borderColor = Palette.UI.ink.resolvedColor(with: traitCollection).cgColor
    }
}
