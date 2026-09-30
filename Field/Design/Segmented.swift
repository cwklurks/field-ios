// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// A row of choices in a grey track, the chosen one lifted out. The lift
/// slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option
    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Button {
                    withAnimation(Motion.calm(Motion.settle)) { selection = option }
                } label: {
                    Text(title)
                        .ramp(option == selection ? .label : .caption)
                        .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: option, in: slide)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        // One lift, always there, under all the names: it slides to the one
        // picked. Made anew in each place, it faded out and in as it went, and
        // for a few frames nothing looked chosen.
        .background {
            RoundedRectangle.corner(Radius.chip)
                .fill(segmentLift)
                .lift(.chip)
                .matchedGeometryEffect(id: selection, in: slide, isSource: false)
        }
        .padding(2)
        .background(Palette.wash, in: .corner(Radius.row))
    }
}

/// The ground in light, where its shadow lifts it off the track. In dark
/// the ground is darker than the track and a shadow has nothing to fall
/// on, so it's a step lighter instead.
private let segmentLift = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : Palette.UI.ground.resolvedColor(with: traits)
})
