import FieldKit
import UIKit

/// What lies over Private when it mustn't show: a window of its own above
/// everything, the keyboard included, since the switcher's snapshot has the
/// keyboard's suggestions in it too. Always dark, with the Mac's mark.
///
/// - `cover`: the mark alone, for the app switcher.
/// - `locked`: Unlock, and a way back to your everyday tabs.
/// - `captured`: said plainly, with the same way back.
final class PrivateShade: UIWindow {
    private(set) var showing: PrivateLock.Shade?
    var unlock: () -> Void = {}
    var leave: () -> Void = {}

    private let mark = UIImageView(image: PrivateMark.image(pointSize: 34))
    private let title = UILabel()
    private let open = UIButton(type: .system)
    private let back = UIButton(type: .system)
    private let stack: UIStackView

    override init(windowScene: UIWindowScene) {
        stack = UIStackView(arrangedSubviews: [mark, title, open, back])
        super.init(windowScene: windowScene)
        // Over the keyboard's window as well as the app's.
        windowLevel = UIWindow.Level(rawValue: 10_000_010)
        overrideUserInterfaceStyle = .dark
        backgroundColor = Palette.UI.ground
        accessibilityIdentifier = "private.shade"
        accessibilityViewIsModal = true
        isHidden = true

        mark.tintColor = Palette.UI.muted
        title.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: Ramp.heading.size, weight: .semibold), maximumPointSize: 28)
        title.textColor = Palette.UI.ink
        title.textAlignment = .center
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true

        var filled = UIButton.Configuration.filled()
        filled.baseBackgroundColor = Palette.UI.raised
        filled.baseForegroundColor = Palette.UI.ink
        filled.background.cornerRadius = Radius.field
        filled.cornerStyle = .fixed
        filled.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 40, bottom: 14, trailing: 40)
        filled.image = UIImage(systemName: "faceid")
        filled.imagePadding = 8
        filled.title = "Unlock"
        filled.titleTextAttributesTransformer = Self.font(weight: .medium)
        open.configuration = filled
        open.accessibilityIdentifier = "private.unlock"
        open.addAction(UIAction { [weak self] _ in self?.unlock() }, for: .primaryActionTriggered)

        var plain = UIButton.Configuration.plain()
        plain.baseForegroundColor = Palette.UI.muted
        plain.title = "Your tabs"
        plain.titleTextAttributesTransformer = Self.font(weight: .regular)
        back.configuration = plain
        back.accessibilityIdentifier = "private.leave"
        back.addAction(UIAction { [weak self] _ in self?.leave() }, for: .primaryActionTriggered)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.setCustomSpacing(28, after: title)
        stack.setCustomSpacing(6, after: open)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = UIViewController()
        root.view.backgroundColor = Palette.UI.ground
        root.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.view.centerYAnchor, constant: -24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.view.trailingAnchor, constant: -32),
        ])
        rootViewController = root
        // Built and laid out now, so showing it is only unhiding it.
        root.view.layoutIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// At once: the snapshot is taken as soon as the scene's handlers return.
    func show(_ shade: PrivateLock.Shade) {
        guard shade != .none else { return hide(animated: false) }
        layer.removeAllAnimations()
        alpha = 1
        if shade != showing {
            title.text = switch shade {
            case .locked: "Private is locked."
            case .captured: "Private is hidden while the screen is recorded or shared."
            default: nil
            }
            title.isHidden = shade == .cover
            open.isHidden = shade != .locked
            back.isHidden = shade == .cover
            stack.layoutIfNeeded()
        }
        showing = shade
        isHidden = false
        CATransaction.flush()
    }

    /// Unlocked, or back in front: it fades rather than blinks away.
    func hide(animated: Bool) {
        guard showing != nil else { return }
        showing = nil
        // Motion.quick, which Reduce Motion keeps as it is.
        guard animated else {
            isHidden = true
            return
        }
        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.alpha = 0
        } completion: { _ in
            guard self.showing == nil else { return }
            self.isHidden = true
            self.alpha = 1
        }
    }

    private static func font(weight: UIFont.Weight) -> UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .systemFont(ofSize: Ramp.row.size, weight: weight), maximumPointSize: 21)
            return outgoing
        }
    }
}
