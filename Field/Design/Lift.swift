// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// How a surface stands off what's under it. In light a shadow does the
/// lifting. In dark there's nothing darker for a shadow to fall on, so the
/// surface is drawn a step lighter instead (Palette.raised) and the shadow
/// stays off, even over a white page.
struct Lift {
    struct Shadow {
        var opacity: Double
        var radius: CGFloat
        var y: CGFloat
    }

    /// A tight shadow at the edge, when there is one, and a soft one below.
    var near = Shadow(opacity: 0, radius: 0, y: 0)
    var far: Shadow

    static let field = Lift(near: Shadow(opacity: 0.05, radius: 1, y: 1), far: Shadow(opacity: 0.10, radius: 30, y: 14))
    static let panel = Lift(far: Shadow(opacity: 0.16, radius: 34, y: 12))
    static let toast = Lift(far: Shadow(opacity: 0.10, radius: 18, y: 6))
    static let chip = Lift(far: Shadow(opacity: 0.08, radius: 3, y: 1))
}

extension View {
    /// Lifts a surface's shape; put it on the fill, not on what's drawn on it.
    func lift(_ lift: Lift) -> some View {
        modifier(Lifted(lift: lift))
    }
}

private struct Lifted: ViewModifier {
    let lift: Lift
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        // Faded out rather than removed, so changing looks doesn't rebuild
        // whatever the surface holds.
        let shown = scheme == .light ? 1.0 : 0
        content
            .shadow(color: .black.opacity(lift.near.opacity * shown), radius: lift.near.radius, y: lift.near.y)
            .shadow(color: .black.opacity(lift.far.opacity * shown), radius: lift.far.radius, y: lift.far.y)
    }
}
