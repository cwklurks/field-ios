import UIKit

/// The surface's fill in the chosen look: Liquid Glass clouded with the
/// ground of its tone, or the Mac's raised surface lifted by its shadow.
final class SurfaceBackground: UIView {
    var look: BarLook = .glass {
        didSet { if look != oldValue { build() } }
    }
    var tone: UIUserInterfaceStyle = .unspecified {
        didSet { if tone != oldValue { paint() } }
    }
    var radius: CGFloat = 0 {
        didSet { shape() }
    }

    private var glass: UIVisualEffectView?
    /// A blur under dark glass. Dark glass clears far more of what's under
    /// it than light glass does, and a page's text read through it as words.
    private var frost: UIVisualEffectView?
    /// Glass's rim: the Mac's edge of ink, which is what marks clear glass off
    /// a white page, and lights its edge over a dark one.
    private var edge: UIView?
    /// The look it was last painted in, so an unchanged one isn't redone.
    private var painted: UIUserInterfaceStyle?
    /// The solid look: a soft far shadow under a tight near one.
    private var far: UIView?
    private var near: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.paint() }
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        glass = nil
        frost = nil
        edge = nil
        far = nil
        near = nil
        switch look {
        case .glass:
            let frost = UIVisualEffectView(effect: nil)
            frost.frame = bounds
            frost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            frost.clipsToBounds = true
            addSubview(frost)
            self.frost = frost
            let view = UIVisualEffectView(effect: nil)
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            glass = view
            let edge = UIView(frame: bounds)
            edge.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            edge.layer.cornerCurve = .continuous
            edge.layer.borderWidth = 1
            addSubview(edge)
            self.edge = edge
        case .solid:
            let far = UIView(frame: bounds)
            let near = UIView(frame: bounds)
            for view in [far, near] {
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.layer.cornerCurve = .continuous
                addSubview(view)
            }
            self.far = far
            self.near = near
        }
        shape()
        painted = nil
        paint()
    }

    private func shape() {
        glass?.cornerConfiguration = .corners(radius: .fixed(radius))
        frost?.cornerConfiguration = .corners(radius: .fixed(radius))
        edge?.layer.cornerRadius = radius
        far?.layer.cornerRadius = radius
        near?.layer.cornerRadius = radius
    }

    /// Resolved in the tone, whatever the app's look.
    private func traits() -> UITraitCollection {
        tone == .unspecified ? traitCollection : traitCollection.modifyingTraits { $0.userInterfaceStyle = tone }
    }

    private func paint() {
        let traits = traits()
        guard traits.userInterfaceStyle != painted else { return }
        painted = traits.userInterfaceStyle
        if let glass {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = Palette.UI.ground.resolvedColor(with: traits).withAlphaComponent(0.6)
            glass.overrideUserInterfaceStyle = tone
            glass.effect = effect
            frost?.effect = traits.userInterfaceStyle == .dark ? UIBlurEffect(style: .systemUltraThinMaterialDark) : nil
        }
        edge?.layer.borderColor = Palette.UI.ink.resolvedColor(with: traits).withAlphaComponent(0.1).cgColor
        if let far, let near {
            // Lifted by shadows in light; in dark there's nothing darker for
            // a shadow to fall on, so the raised grey does the lifting.
            let light = traits.userInterfaceStyle != .dark
            let raised = Palette.UI.raised.resolvedColor(with: traits)
            for (view, shadow) in [(far, Lift.field.far), (near, Lift.field.near)] {
                view.backgroundColor = raised
                view.layer.shadowColor = UIColor.black.cgColor
                view.layer.shadowOpacity = light ? Float(shadow.opacity) : 0
                view.layer.shadowRadius = shadow.radius
                view.layer.shadowOffset = CGSize(width: 0, height: shadow.y)
            }
            near.layer.borderWidth = 1
            near.layer.borderColor = Palette.UI.ink.resolvedColor(with: traits).withAlphaComponent(0.08).cgColor
        }
    }
}
