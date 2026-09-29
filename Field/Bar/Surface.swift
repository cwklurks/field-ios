import SwiftUI

/// What the bar and the field share while one turns into the other: the
/// namespace their surfaces are matched in. The browser sets it around both.
struct BarMorph {
    let namespace: Namespace.ID
}

extension EnvironmentValues {
    @Entry var barMorph: BarMorph?
    /// The look the glass bar takes from the page under it; nil for the
    /// app's own.
    @Entry var barTone: ColorScheme?
}

extension View {
    /// The bar's surface in the chosen look, behind this view: Liquid Glass,
    /// or the Mac's raised surface lifted by its shadow. The field puts the
    /// same surface behind itself, so inside a morph the bar becomes the field
    /// rather than one leaving and the other arriving. `look` fixes the look
    /// for a preview of it; otherwise it's the chosen one.
    func barSurface(_ shape: some InsettableShape, look: BarLook? = nil) -> some View {
        modifier(Surface(shape: shape, fixed: look))
    }
}

private struct Surface<S: InsettableShape>: ViewModifier {
    let shape: S
    let fixed: BarLook?
    @AppStorage("bar.look") private var chosen: BarLook = .glass
    @Environment(\.barMorph) private var morph
    @Environment(\.barTone) private var tone
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        switch fixed ?? chosen {
        case .glass:
            if let morph {
                content
                    .glassEffect(glass, in: shape)
                    .glassEffectID("bar", in: morph.namespace)
                    .overlay(edge)
            } else {
                content
                    .glassEffect(glass, in: shape)
                    .overlay(edge)
            }
        case .solid:
            content
                .background {
                    if let morph {
                        solid.matchedGeometryEffect(id: "bar", in: morph.namespace)
                    } else {
                        solid
                    }
                }
        }
    }

    /// Regular glass clouded with the ground of the bar's tone, so it sits
    /// under ink of that tone: light glass over a white page even in a dark
    /// app, which plain glass here never became.
    private var glass: Glass {
        .regular.tint(Palette.fixed(Palette.UI.ground, in: tone ?? scheme).opacity(0.6))
    }

    /// Glass's rim: the Mac's edge of ink, which is what marks clear glass off
    /// a white page, and lights its edge over a dark one.
    private var edge: some View {
        shape.strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1)
    }

    /// Raised, with the Mac's rim of ink: barely there over white, the lit
    /// edge of a raised thing over near-black.
    private var solid: some View {
        shape
            .fill(Palette.raised)
            .lift(.field)
            .overlay(shape.strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1))
    }
}

