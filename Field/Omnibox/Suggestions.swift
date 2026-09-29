// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI
import FieldKit

/// The rows above the field, hosted on the surface (FieldSurface): the field
/// and what it thinks you mean are one surface, the way Spotlight's are. The
/// field alone while there is nothing to offer; the same surface grown
/// upward, a hairline over the field, when there is.
struct SuggestionRows: View {
    let omnibox: Omnibox
    let onGo: (URL) -> Void

    var body: some View {
        Suggestions(omnibox: omnibox, onGo: onGo)
            // Hosted in UIKit, out of reach of the app's own settings.
            .dynamicTypeSize(...Ramp.cap)
            .tint(Palette.ink)
    }
}

/// What it thinks you mean, the best match last, nearest the field.
struct Suggestions: View {
    let omnibox: Omnibox
    let onGo: (URL) -> Void

    var body: some View {
        if !omnibox.offers.isEmpty {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Keyed by the place, so a keystroke that keeps a row
                    // keeps its view and only redraws the rows it changed.
                    ForEach(Array(omnibox.offers.enumerated()).reversed(), id: \.element.id) { index, offer in
                        let picked = omnibox.picked == offer.key
                        Button {
                            onGo(offer.url)
                        } label: {
                            Row(offer: offer, picked: picked).equatable()
                        }
                        .buttonStyle(Press(picked: picked))
                        .accessibilityIdentifier("suggestion.\(index)")
                    }
                }
                .padding(6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("suggestions")

                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
            }
        }
    }
}

private struct Row: View, Equatable {
    let offer: Suggestion
    let picked: Bool

    @ScaledMetric(relativeTo: .callout) private var mark: CGFloat = 20

    static func == (a: Row, b: Row) -> Bool {
        a.offer == b.offer && a.picked == b.picked
    }

    var body: some View {
        HStack(spacing: 12) {
            Mark(letter: Self.letter(offer.url), size: mark)
                .accessibilityHidden(true)
            KeyFirst {
                Text(offer.key)
                    .ramp(.row)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if !offer.title.isEmpty {
                    Text(offer.title)
                        .ramp(.toast)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if offer.kind == .open {
                // Already open: naming it takes you back to it rather than
                // opening a second copy.
                Circle()
                    .fill(Palette.ink.opacity(0.55))
                    .frame(width: 5, height: 5)
            }
            if picked {
                // What Return does now, so the picked row is told apart by
                // more than a shade.
                Image(systemName: "return")
                    .ramp(.glyph)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private static func letter(_ url: URL) -> String {
        let host = url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        return host.first.map { String($0).uppercased() } ?? "•"
    }
}

/// The address, then the title in what room is left. A title with too little
/// room to say anything isn't drawn: a key long enough to leave a sliver
/// would otherwise end in a clipped letter.
private struct KeyFirst: Layout {
    var spacing: CGFloat = 10
    /// Enough for a short word and its ellipsis.
    var least: CGFloat = 48

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (key, title) = sizes(proposal.width, subviews)
        let width = key.width + (title.map { spacing + $0.width } ?? 0)
        return CGSize(width: width, height: max(key.height, title?.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (key, title) = sizes(bounds.width, subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(key))
        guard subviews.count > 1 else { return }
        // Out of sight rather than squeezed, when it doesn't fit.
        let place = title == nil
            ? CGPoint(x: bounds.maxX + 1_000, y: bounds.midY)
            : CGPoint(x: bounds.minX + key.width + spacing, y: bounds.midY)
        subviews[1].place(at: place, anchor: .leading, proposal: ProposedViewSize(title ?? .zero))
    }

    private func sizes(_ width: CGFloat?, _ subviews: Subviews) -> (key: CGSize, title: CGSize?) {
        let key = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        guard subviews.count > 1 else { return (key, nil) }
        let room = (width ?? .infinity) - key.width - spacing
        guard room >= least else { return (key, nil) }
        return (key, subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil)))
    }
}

/// Ink over the panel rather than a grey of its own, so the step is the same
/// in both looks. The picked row takes a tenth of ink, near enough the
/// selection the field's ending wears: the two are one choice.
private struct Press: ButtonStyle {
    let picked: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if picked || configuration.isPressed {
                    RoundedRectangle.corner(Radius.row)
                        .fill(Palette.ink.opacity(picked ? 0.12 : 0.05))
                }
            }
    }
}

/// A site's first letter in a squircle of ink, where its icon will go.
private struct Mark: View {
    let letter: String
    let size: CGFloat

    var body: some View {
        Text(letter)
            .font(.system(size: size * 0.56, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(width: size, height: size)
            .background(RoundedRectangle.corner(Radius.icon(size)).fill(Palette.ink.opacity(0.06)))
    }
}
