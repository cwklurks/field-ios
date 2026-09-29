import UIKit

/// A picture of a page, as wide as the view and from its top, over the
/// ground: a card's face, a neighbour in the carousel, the cover while a tab
/// wakes. The picture is always a whole screen's shape, so at the screen's
/// size it lines up with the page exactly, and on a card shows its top.
final class PagePicture: UIView {
    private let imageView = UIImageView()

    var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            imageView.image = image
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.UI.ground
        clipsToBounds = true
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let size = image?.size, size.width > 0 else {
            imageView.frame = .zero
            return
        }
        imageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width * size.height / size.width)
    }
}
