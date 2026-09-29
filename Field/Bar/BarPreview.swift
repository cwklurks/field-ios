import SwiftUI

/// A page with the bar over its foot, in one look: how Welcome and Settings
/// show the two bars. It's drawn at a phone's size and scaled down whole, so
/// it's a picture of the real thing rather than a sketch of it.
struct BarPreview: View {
    let look: BarLook

    private static let phone = CGSize(width: 390, height: 844)

    var body: some View {
        GeometryReader { proxy in
            page
                .frame(width: Self.phone.width, height: Self.phone.height)
                .scaleEffect(proxy.size.width / Self.phone.width, anchor: .topLeading)
        }
        .aspectRatio(Self.phone.width / Self.phone.height, contentMode: .fit)
        .clipShape(.corner(Radius.card))
        .overlay(RoundedRectangle.corner(Radius.card).strokeBorder(Palette.hairline, lineWidth: 1))
        // A picture: it keeps its size whatever the reader's text size is.
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var page: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("A quiet page")
                    .ramp(.title)
                Text("One field, your tabs and the page. Ads and trackers are gone before the page draws, and links arrive clean.")
                    .ramp(.row)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                // A photo that runs on under the bar, as a page does: the
                // glass shows it through, the solid covers it.
                Hills()
                    .clipShape(.corner(Radius.card))
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            bar
                .padding(.horizontal, Bar.margin)
                .padding(.bottom, 34)
        }
        .background(Palette.ground)
    }

    /// Glass takes the look of what's under it, as the real bar does: the
    /// dark foot of the photo. Solid keeps the app's.
    private var bar: some View {
        HStack {
            Image(systemName: "chevron.left").fontWeight(.medium)
            Spacer()
            Text("example.com")
            Spacer()
            Text("1")
                .ramp(.label)
                .frame(minWidth: 22, minHeight: 22)
                .overlay(RoundedRectangle.corner(Radius.icon(22)).strokeBorder(Palette.ink, lineWidth: 1.5))
        }
        .ramp(.field)
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 18)
        .frame(height: Bar.height)
        .barSurface(Capsule(), look: look)
        .transformEnvironment(\.colorScheme) { if look == .glass { $0 = Hills.tone } }
    }
}

/// A landscape at dusk, drawn rather than shipped: a hazy sky over two
/// ridges. The near one crosses behind the bar, so glass shows its edge
/// through and solid hides it.
private struct Hills: View {
    /// What the tone sampler would make of the bar's stretch of it.
    static let tone = ColorScheme.dark

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.93, green: 0.84, blue: 0.74)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.5)))
            context.fill(ridge(w, h, from: 0.50, to: 0.36), with: .color(Color(red: 0.84, green: 0.76, blue: 0.66)))
            context.fill(ridge(w, h, from: 1.02, to: 0.62), with: .linearGradient(
                Gradient(colors: [Color(red: 0.22, green: 0.27, blue: 0.25), Color(red: 0.08, green: 0.10, blue: 0.10)]),
                startPoint: CGPoint(x: 0, y: h * 0.6), endPoint: CGPoint(x: 0, y: h)))
        }
    }

    /// A ridge's silhouette from `from` at the left to `to` at the right, as
    /// fractions of the height, filled down to the foot.
    private func ridge(_ w: CGFloat, _ h: CGFloat, from: CGFloat, to: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * from))
            p.addCurve(to: CGPoint(x: w, y: h * to),
                       control1: CGPoint(x: w * 0.4, y: h * (from - 0.02)),
                       control2: CGPoint(x: w * 0.6, y: h * (to + 0.06)))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
    }
}

/// One look, held up to be picked: the chosen one lifts, the other settles
/// back. Before either is picked, both wait level.
struct BarLookCard: View {
    let look: BarLook
    /// Nil until something is chosen.
    let chosen: Bool?
    let pick: () -> Void
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let isChosen = chosen == true
        Button(action: pick) {
            VStack(spacing: 10) {
                BarPreview(look: look)
                Text(look.title)
                    .ramp(.row)
                    .fontWeight(isChosen ? .medium : .regular)
                    .foregroundStyle(chosen == false ? Palette.muted : Palette.ink)
            }
            .padding(8)
            .background {
                RoundedRectangle.corner(Radius.panel)
                    .fill(isChosen ? Palette.raised : Palette.ground)
                    .lift(isChosen ? .panel : Lift(far: Lift.Shadow(opacity: 0, radius: 34, y: 12)))
            }
            .overlay {
                RoundedRectangle.corner(Radius.panel)
                    .strokeBorder(isChosen ? Palette.ink.opacity(0.35) : Palette.hairline, lineWidth: 1)
            }
            .contentShape(.corner(Radius.panel))
        }
        .buttonStyle(.plain)
        // With Reduce Motion, nothing changes size; the rim and the fade say it.
        .scaleEffect(chosen == false && !still ? 0.95 : 1)
        .opacity(chosen == false ? 0.7 : 1)
        .accessibilityLabel(look.title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
