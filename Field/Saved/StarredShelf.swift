import FieldKit
import SwiftUI
import UIKit

/// The starred grid on a new tab, for UIKit: on the ground just above the
/// field, in the view that rides the keyboard (FieldSurface's rider), so it
/// moves with the keyboard on every frame and never catches up after it.
final class StarredShelf: UIHostingController<AnyView> {
    /// A starred page chosen.
    var onOpen: (URL) -> Void = { _ in }
    /// Saved's row: everything, or with `.readLater` the pages to read.
    var onShowSaved: (SavedFilter) -> Void = { _ in }

    init(store: SavedStore) {
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(StarredGrid(
            store: store,
            onOpen: { [weak self] in self?.onOpen($0) },
            onShowSaved: { [weak self] in self?.onShowSaved($0) }
        ).tint(Palette.ink).dynamicTypeSize(...Ramp.cap))
        sizingOptions = .intrinsicContentSize
        safeAreaRegions = []
        view.backgroundColor = .clear
        view.alpha = 0
        view.isUserInteractionEnabled = false
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    /// Into `rider`, its foot `above` points over the rider's (the field's
    /// top, with room between).
    func install(in parent: UIViewController, rider: UIView, above: CGFloat) {
        parent.addChild(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        rider.insertSubview(view, at: 0)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rider.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rider.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: rider.bottomAnchor, constant: -above),
        ])
        didMove(toParent: parent)
    }

    /// In on a new tab's field with nothing typed, out otherwise: the quick
    /// fade either way, from wherever it is.
    func show(_ shown: Bool) {
        view.isUserInteractionEnabled = shown
        SurfaceMotion.animate(.quick) { self.view.alpha = shown ? 1 : 0 }
    }
}
