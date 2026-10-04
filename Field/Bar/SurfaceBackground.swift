import UIKit

/// The surface's fill in the chosen look: Liquid Glass clouded with the
/// ground of its tone, or the Mac's raised surface lifted by its shadow.
final class SurfaceBackground: UIView {
    var look: BarLook = .glass {
        didSet { if look != oldValue { build() } }
    }
    var tone: UIUserInterfaceStyle = .unspecified {
        didSet { if tone != oldValue || !UIView.areAnimationsEnabled { paint() } }
    }
    var radius: CGFloat = 0 {
        didSet { shape() }
    }

    private var glass: UIVisualEffectView?
    /// Marks a glass on its way out after a change of tone.
    static let leaving = 0x676f
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
        for old in subviews where old.tag == Self.leaving {
            old.cornerConfiguration = .corners(radius: .fixed(radius))
        }
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
        let finishing = !UIView.areAnimationsEnabled && subviews.contains { $0.tag == Self.leaving }
        guard traits.userInterfaceStyle != painted || finishing else { return }
        painted = traits.userInterfaceStyle
        // An immediate change (notably entry into Private) also ends any
        // earlier tone fade, so no light material survives its first frame.
        if UIView.inheritedAnimationDuration == 0 || !UIView.areAnimationsEnabled {
            subviews.filter { $0.tag == Self.leaving }.forEach { $0.removeFromSuperview() }
        }
        if let old = glass {
            let effect = UIGlassEffect(style: .regular)
            effect.tintColor = Palette.UI.ground.resolvedColor(with: traits).withAlphaComponent(0.6)
            // A new view in the new tone, not the old one changed: glass
            // changed in place keeps its old look for a few frames, and a
            // field opening into Private rose light (polish-6 P6-01).
            let glass = UIVisualEffectView(effect: nil)
            glass.frame = old.frame
            glass.autoresizingMask = old.autoresizingMask
            glass.cornerConfiguration = .corners(radius: .fixed(radius))
            glass.overrideUserInterfaceStyle = tone
            glass.effect = effect
            insertSubview(glass, aboveSubview: old)
            // The old one goes in the same animation as this one comes, when
            // there is one: taken away in a frame, a dark pill cut to grey
            // before the light glass had come in.
            let going = UIView.inheritedAnimationDuration
            if going > 0 && UIView.areAnimationsEnabled {
                old.tag = Self.leaving
                old.effect = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + going) { [weak old] in old?.removeFromSuperview() }
            } else {
                old.removeFromSuperview()
            }
            self.glass = glass
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
