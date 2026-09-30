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
