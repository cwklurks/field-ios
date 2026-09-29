import SwiftUI
import UIKit

/// The one surface that is the bar and becomes the field: a single shape
/// that changes size and corners, with the bar's buttons and the field's row
/// on it, and the suggestions growing out of its top. FieldSurface decides
/// what it shows and moves it; this lays it out for a mode, so that laying
/// it out inside an animation is the whole morph.
final class SurfaceView: UIView {
    enum Mode: Equatable {
        /// The bar at a shrink, sized by `geometry`.
        case bar(BarGeometry, amount: CGFloat)
        /// The field, with `rows` of suggestions above it.
        case field(rows: CGFloat)
    }

    var mode: Mode = .bar(BarGeometry(room: 0, address: 0, amount: 0), amount: 0) {
        didSet { if mode != oldValue { setNeedsLayout() } }
    }

    let background = SurfaceBackground()
    /// Everything drawn on the surface, cut to its shape.
    let content = UIView()
    let bar = BarContent()
    /// The field's row: the magnifier and the field.
    let row = UIView()
    let magnifier = UIImageView()
    let field: AddressField.Input
    let rows: UIView
    /// Above the field's row, up to the surface's top edge: the rows stand
    /// in it on the row, and the edge uncovers them as it rises and covers
    /// them as it comes down. Its bounds count up from its bottom edge, so
    /// the rows stay put however tall it is.
    private let shelf = UIView()
    /// Red, when Return has nowhere to go.
    let rim = UIView()
    /// How tall the rows were last shown, kept while they go.
    private var listed: CGFloat = 0

    /// Before the field, where Spotlight says what it's for.
    static let fieldInset: CGFloat = 18
    static let textStart: CGFloat = 44

    init(field: AddressField.Input, rows: UIView) {
        self.field = field
        self.rows = rows
        super.init(frame: .zero)
        addSubview(background)
        content.clipsToBounds = true
        content.layer.cornerCurve = .continuous
        addSubview(content)

        let symbol = UIImage.SymbolConfiguration(pointSize: UIFontMetrics(forTextStyle: .body).scaledValue(for: 14), weight: .medium)
        magnifier.image = UIImage(systemName: "magnifyingglass", withConfiguration: symbol)
        magnifier.tintColor = Palette.UI.muted
        magnifier.contentMode = .center
        row.addSubview(magnifier)
        row.addSubview(field)
        row.isHidden = true

        rows.alpha = 0
        shelf.clipsToBounds = true
        shelf.addSubview(rows)
        content.addSubview(shelf)
        content.addSubview(bar)
        content.addSubview(row)

        rim.isUserInteractionEnabled = false
        rim.layer.borderWidth = 1
        rim.layer.cornerCurve = .continuous
        rim.alpha = 0
        addSubview(rim)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.paintRim() }
        paintRim()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func paintRim() {
        rim.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        content.frame = bounds
        rim.frame = bounds
        let radius: CGFloat
        let rowHeight = Bar.height
        switch mode {
        case .bar(let g, let amount):
            radius = bounds.height / 2
            place(bar, in: bounds)
            bar.lay(g, amount: amount)
            place(row, in: CGRect(x: 0, y: (bounds.height - rowHeight) / 2, width: bounds.width, height: rowHeight))
        case .field(let height):
            radius = Radius.field
            let bottom = CGRect(x: 0, y: bounds.height - rowHeight, width: bounds.width, height: rowHeight)
            place(bar, in: bottom)
            bar.lay(BarGeometry(room: bounds.width, address: bar.idealAddressWidth, amount: 0), amount: 0, ends: false)
            place(row, in: bottom)
            // None is the rows going: they keep their height to be covered.
            if height > 0 { listed = height }
            // Never animated: they stand still on the row while the edge
            // moves. In the bar they stay as they were, going.
            UIView.performWithoutAnimation {
                rows.frame = CGRect(x: 0, y: -listed, width: bounds.width, height: listed)
            }
        }
        let top = row.center.y - row.bounds.height / 2
        shelf.bounds = CGRect(x: 0, y: -top, width: bounds.width, height: top)
        shelf.center = CGPoint(x: bounds.midX, y: top / 2)
        background.radius = radius
        content.layer.cornerRadius = radius
        rim.layer.cornerRadius = radius
        let w = row.bounds.width
        magnifier.frame = CGRect(x: Self.fieldInset, y: 0, width: 16, height: rowHeight)
        field.frame = CGRect(x: Self.textStart, y: 0, width: max(0, w - Self.textStart - Self.fieldInset), height: rowHeight)
    }

    /// By centre and bounds, so a transform on it survives.
    private func place(_ view: UIView, in frame: CGRect) {
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }

    /// The look the surface takes: the page's tone for glass in the bar,
    /// the app's own (`.unspecified`) otherwise.
    func paint(_ tone: UIUserInterfaceStyle) {
        bar.overrideUserInterfaceStyle = tone
        background.tone = tone
    }
}
