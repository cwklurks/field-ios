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
                        .background {
                            if option == selection {
                                RoundedRectangle.corner(Radius.chip)
                                    .fill(Palette.ground)
                                    .lift(.chip)
                                    .matchedGeometryEffect(id: "chosen", in: slide)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.wash, in: .corner(Radius.row))
    }
}
