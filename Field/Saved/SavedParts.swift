import FieldKit
import SwiftUI

/// A site's first letter in a squircle, where its icon will go.
struct SiteMark: View {
    let url: URL
    let size: CGFloat
    var pressed = false

    var body: some View {
        Text(Self.letter(url))
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(width: size, height: size)
            .background(RoundedRectangle.corner(Radius.icon(size)).fill(Palette.ink.opacity(pressed ? 0.11 : 0.06)))
    }

    static func letter(_ url: URL) -> String {
        var host = url.host() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host.first.map { String($0).uppercased() } ?? "•"
    }
}

/// Ink at 5% under a finger, and no other change.
struct SavedPress: ButtonStyle {
    var radius: CGFloat = Radius.row

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle.corner(radius)
                    .fill(Palette.ink.opacity(configuration.isPressed ? 0.05 : 0))
            }
    }
}

/// A choice in a row of them: grey until chosen, then lifted onto the
/// ground, the lift sliding from the last one chosen.
struct Chip: View {
    let title: String
    var detail: String?
    let chosen: Bool
    let slide: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                if let detail {
                    Text(detail).foregroundStyle(Palette.muted)
                }
            }
            .ramp(chosen ? .label : .caption)
            .foregroundStyle(chosen ? Palette.ink : Palette.muted)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background {
                if chosen {
                    RoundedRectangle.corner(Radius.chip)
                        .fill(Palette.ground)
                        .lift(.chip)
                        .matchedGeometryEffect(id: "chosen", in: slide)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        // The lift slides under the others, never over their names.
        .zIndex(chosen ? 0 : 1)
    }
}

/// The grey track a row of chips sits in, scrolling sideways when it's
/// longer than the screen.
struct ChipTrack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) { content }
                .padding(2)
                .background(Palette.wash, in: .corner(Radius.row))
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Where a page goes: no folder, one of the folders, or a new one named
/// here. Chosen with one tap, which closes it.
struct FolderPicker: View {
    let folders: [String]
    let current: String?
    let pick: (String?) -> Void

    @State private var name = ""
    @FocusState private var naming: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Move to").ramp(.heading)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .ramp(.row)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            ScrollView {
                VStack(spacing: 0) {
                    row("No folder", symbol: "tray", chosen: current == nil) { choose(nil) }
                    ForEach(folders, id: \.self) { folder in
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 46)
                        row(folder, symbol: "folder", chosen: current == folder) { choose(folder) }
                            .accessibilityIdentifier("move.\(folder)")
                    }
                }
                .background(Palette.raised, in: .corner(Radius.card))
                .overlay(RoundedRectangle.corner(Radius.card).strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .scrollBounceBehavior(.basedOnSize)
            TextField("New folder", text: $name)
                .ramp(.row)
                .submitLabel(.done)
                .focused($naming)
                .onSubmit { if !name.trimmingCharacters(in: .whitespaces).isEmpty { choose(name) } }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.wash, in: .corner(Radius.filter))
                .accessibilityIdentifier("move.new")
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Palette.ground)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.ground)
        .presentationCornerRadius(Radius.panel)
        // One element holding the rest, which keep their own identifiers:
        // on a plain container this one would replace theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("move")
    }

    private func choose(_ folder: String?) {
        pick(folder)
        dismiss()
    }

    private func row(_ title: String, symbol: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .ramp(.row)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22)
                Text(title).ramp(.row).lineLimit(1)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark").ramp(.row).fontWeight(.medium)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(SavedPress(radius: 0))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Whether a row's swipe actions were open when the last touch came down.
/// On iOS that first tap only closes them, but SwiftUI's List lets a row's
/// Button have it too, so rows ask here before they open anything.
@MainActor final class SwipeWatch {
    private(set) var wasOpen = false
    private weak var list: UICollectionView?

    fileprivate func watch(_ list: UICollectionView) {
        guard self.list !== list else { return }
        self.list = list
        let down = TouchDown { [weak self, weak list] in
            guard let self, let list else { return }
            wasOpen = list.visibleCells.contains { $0.configurationState.isSwiped }
            // Nothing else closes them, since the row's Button has the
            // touch. Into editing and out again, in one turn, does.
            if wasOpen {
                list.isEditing = true
                list.isEditing = false
            }
        }
        list.addGestureRecognizer(down)
    }
}

extension View {
    /// Tells `watch` which list this row is in.
    func swipeWatch(_ watch: SwipeWatch) -> some View {
        background(SwipeProbe(watch: watch).accessibilityHidden(true))
    }
}

private struct SwipeProbe: UIViewRepresentable {
    let watch: SwipeWatch

    func makeUIView(context: Context) -> Probe { Probe(watch: watch) }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        let watch: SwipeWatch

        init(watch: SwipeWatch) {
            self.watch = watch
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var up = superview
            while let view = up, !(view is UICollectionView) { up = view.superview }
            if let list = up as? UICollectionView { watch.watch(list) }
        }
    }
}

/// Sees every touch come down and never takes one.
private final class TouchDown: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let began: () -> Void

    init(began: @escaping () -> Void) {
        self.began = began
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        began()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
