import SwiftUI
import UIKit

/// The Mac's mark for tabs that keep nothing: `eye.slash`, quiet, beside
/// the address in the bar and on the lock screen.
struct PrivateMark: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .ramp(.caption)
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("Private")
    }

    static func image(pointSize: CGFloat, weight: UIImage.SymbolWeight = .light) -> UIImage? {
        UIImage(systemName: "eye.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }
}

/// The tab grid's way in and out: your tabs' count, and the mark, in one
/// track, with a lift under the side you're on. It goes in the middle of the
/// grid's row, where the count is now (GridRow.count).
///
/// It never moves itself. `progress` puts the lift anywhere between the two,
/// so the strip (PrivateStrip) moves it on the same spring as the grids, and
/// under a finger as the grids are. A tap asks, with `.primaryActionTriggered`,
/// for the other side.
final class PrivateSwitch: UIControl {
    /// 0 on your tabs, 1 in Private.
    var progress: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    var count = 1 {
        didSet { label.text = count == 1 ? "1 Tab" : "\(count) Tabs" }
    }

    /// The side a tap asks for.
    var wantsPrivate: Bool { progress < 0.5 }

    private let track = UIView()
    private let lift = UIView()
    private let label = UILabel()
    private let mark = UIImageView(image: PrivateMark.image(pointSize: Ramp.row.size, weight: .medium))

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = Palette.UI.wash
        track.layer.cornerRadius = Radius.row
        track.layer.cornerCurve = .continuous
        track.isUserInteractionEnabled = false
        lift.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : Palette.UI.ground.resolvedColor(with: $0) }
        lift.layer.cornerRadius = Radius.chip
        lift.layer.cornerCurve = .continuous
        lift.layer.shadowColor = UIColor.black.cgColor
        lift.layer.shadowRadius = 3
        lift.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: Ramp.tab.size, weight: .medium), maximumPointSize: 20)
        label.textColor = Palette.UI.ink
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        mark.contentMode = .center
        mark.tintColor = Palette.UI.ink
        for view in [track, lift, label, mark] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        count = 1
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "private.switch"
        addAction(UIAction { [weak self] _ in self?.sendActions(for: .primaryActionTriggered) }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var accessibilityLabel: String? {
        get { wantsPrivate ? "Private" : "Your tabs" }
        set {}
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Not laid out yet: inset, a zero rect is a null one, and NaN frames.
        guard bounds.width > 4, bounds.height > 4 else { return }
        let box = bounds.insetBy(dx: 0, dy: max(0, (bounds.height - 36) / 2))
        track.frame = box
        let inner = box.insetBy(dx: 2, dy: 2)
        // The mark's side is a finger wide; the count has the rest.
        let markWidth = min(52, inner.width / 2)
        let left = CGRect(x: inner.minX, y: inner.minY, width: inner.width - markWidth, height: inner.height)
        let right = CGRect(x: left.maxX, y: inner.minY, width: markWidth, height: inner.height)
        label.frame = left.insetBy(dx: 6, dy: 0)
        mark.frame = right
        let p = min(1, max(0, progress))
        lift.frame = CGRect(x: left.minX + (right.minX - left.minX) * p, y: inner.minY,
                            width: left.width + (right.width - left.width) * p, height: inner.height)
        // The chosen side is ink, the other muted, crossing as the lift does.
        label.alpha = 1 - 0.45 * p
        mark.alpha = 0.55 + 0.45 * p
        lift.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0 : 0.08
    }
}

/// Your tabs and Private side by side, as two places: Private is to the
/// right, and the way between them is one spring that moves both at once,
/// the way the pages under the bar move (Stage's carousel). Coming in, the
/// grid slides away as the dark one takes its place, so the grid seems to
/// turn dark from the right edge; going back is the same, reversed.
///
/// A finger on the grid's edge moves both 1:1 (`track`) and lets go with its
/// speed (`release`); a tap on the switch runs the same spring (`slide`). A
/// new slide picks up from wherever the last one is, mid-spring included.
/// `alongside` is given the progress inside the animation, for anything
/// that moves with it: the switch's lift, the row's colour.
final class PrivateStrip: UIView {
    let everyday: UIView
    /// Private's stage, while there's a session.
    private(set) var inside: UIView?
    /// 0 on your tabs, 1 in Private, anywhere between while moving.
    private(set) var progress: CGFloat = 0
    var alongside: (CGFloat) -> Void = { _ in }
    /// Where it came to rest: true in Private.
    var landed: (Bool) -> Void = { _ in }

    private var animator: UIViewPropertyAnimator?
    /// The progress when the finger came down.
    private var from: CGFloat?

    init(everyday: UIView) {
        self.everyday = everyday
        super.init(frame: .zero)
        // Private's own ground shows in the gap between the two.
        backgroundColor = Palette.UI.ground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        addSubview(everyday)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Private's stage, dark whatever the app's look, off to the right.
    func hold(_ view: UIView) {
        inside?.removeFromSuperview()
        view.overrideUserInterfaceStyle = .dark
        inside = view
        addSubview(view)
        setNeedsLayout()
        layoutIfNeeded()
        apply(progress)
    }

    /// Private's stage gone (the session is over), once it's off screen.
    func release() {
        guard progress == 0 else { return }
        inside?.removeFromSuperview()
        inside = nil
    }

    private var step: CGFloat { bounds.width + Swipe.pageGap }

    override func layoutSubviews() {
        super.layoutSubviews()
        for view in [everyday, inside].compactMap({ $0 }) {
            let transform = view.transform
            view.transform = .identity
            view.frame = bounds
            view.transform = transform
        }
    }

    func slide(toPrivate: Bool, velocity: CGFloat = 0) {
        pickUp()
        from = nil
        run(to: toPrivate ? 1 : 0, velocity: velocity)
    }

    /// There at once: under Private's shade, which hides the change
    /// (Browser.leavePrivate).
    func cut(toPrivate: Bool) {
        pickUp()
        from = nil
        apply(toPrivate ? 1 : 0)
        landed(toPrivate)
    }

    /// The finger has moved `dx` points sideways since it came down.
    func track(_ dx: CGFloat) {
        if from == nil {
            pickUp()
            from = progress
        }
        guard let from, inside != nil else { return }
        var p = from - dx / step
        if p < 0 || p > 1 {
            let over = p < 0 ? p : p - 1
            p = (p < 0 ? 0 : 1) + Swipe.rubber(over * step, limit: step) / step
        }
        apply(p)
    }

    /// The finger let go, going `velocity` points a second (positive right).
    func release(velocity: CGFloat) {
        guard from != nil else { return }
        from = nil
        let landing = progress - velocity * Swipe.projection / step
        run(to: landing > 0.5 && inside != nil ? 1 : 0, velocity: -velocity / step)
    }

    /// Stopped where it is on screen, so the next motion starts from there.
    private func pickUp() {
        guard let animator else { return }
        animator.stopAnimation(true)
        self.animator = nil
        progress = -everyday.transform.tx / step
    }

    /// `velocity`: progress a second.
    private func run(to target: CGFloat, velocity: CGFloat) {
        let distance = target - progress
        let animator = Stage.glide(velocity: abs(distance) > 0.001 ? velocity / distance : 0)
        animator.addAnimations { [weak self] in self?.apply(target) }
        animator.addCompletion { [weak self] position in
            guard let self, position == .end, self.animator === animator else { return }
            self.animator = nil
            self.landed(target == 1)
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func apply(_ p: CGFloat) {
        progress = p
        everyday.transform = CGAffineTransform(translationX: -p * step, y: 0)
        inside?.transform = CGAffineTransform(translationX: (1 - p) * step, y: 0)
        alongside(p)
    }
}

/// Private's side of the strip: its stage, with the welcome over a new
/// tab's blank page (PrivateWelcome), in the space above the keyboard. The
/// welcome slides in with the stage, as part of it.
final class PrivateSide: UIView {
    let stage: UIView
    /// "What Private can't do", tapped.
    var openLimits: () -> Void = { PrivateLimits.present() }
    private lazy var welcome = UIHostingConfiguration { [weak self] in
        PrivateWelcome { self?.openLimits() }
    }.margins(.all, 0).makeContentView()

    /// The side whose welcome is up, if one is.
    private(set) static weak var showing: PrivateSide?

    /// The tab on screen is blank and the grid isn't up.
    var welcomeShown = false {
        didSet {
            guard welcomeShown != oldValue else { return }
            if welcomeShown { Self.showing = self } else if Self.showing === self { Self.showing = nil }
            UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.welcome.alpha = self.welcomeShown ? 1 : 0
            }
        }
    }

    init(stage: UIView) {
        self.stage = stage
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        welcome.alpha = 0
        addSubview(stage)
        addSubview(welcome)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Whether a point on screen is on the welcome's "What Private can't do",
    /// its last line: the field's dim lets a tap there through to it.
    func linkContains(_ point: CGPoint) -> Bool {
        guard welcomeShown, welcome.alpha > 0.5, let window else { return false }
        let frame = welcome.convert(welcome.bounds, to: window)
        return CGRect(x: frame.minX, y: frame.maxY - 44, width: frame.width, height: 44).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stage.frame = bounds
        // Centred in the top part, clear of a keyboard's worth of bottom.
        let top = safeAreaInsets.top
        let room = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height * 0.5 - top)
        let size = welcome.systemLayoutSizeFitting(CGSize(width: bounds.width, height: room.height),
                                                   withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        welcome.frame = CGRect(x: 0, y: room.midY - size.height / 2 + 24, width: bounds.width, height: size.height)
    }
}

#Preview("Switch") {
    SwitchPreview().frame(width: 150, height: 44).padding()
}

private struct SwitchPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PrivateSwitch {
        let control = PrivateSwitch()
        control.count = 3
        control.addAction(UIAction { [weak control] _ in
            guard let control else { return }
            let target: CGFloat = control.wantsPrivate ? 1 : 0
            let animator = Stage.glide(velocity: 0)
            animator.addAnimations {
                control.progress = target
                control.layoutIfNeeded()
            }
            animator.startAnimation()
        }, for: .primaryActionTriggered)
        return control
    }

    func updateUIView(_ view: PrivateSwitch, context: Context) {}
}
