import FieldKit
import SwiftUI

/// The starred pages, for the new tab, just above the keyboard: two rows
/// of four at most, a letter for each site and its title under it, then a
/// row that opens everything saved. Nothing at all until something is saved.
struct StarredGrid: View {
    let store: SavedStore
    var onOpen: (URL) -> Void
    /// Everything saved, or with `.readLater` from the count of pages to read.
    var onShowSaved: (SavedFilter) -> Void

    /// Two rows: past that, the grid would climb into the page it's over.
    static let most = 8

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4)

    var body: some View {
        let starred = Array(store.saved.starred.prefix(Self.most))
        if !store.saved.pages.isEmpty {
            VStack(spacing: 10) {
                if !starred.isEmpty {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(starred.enumerated()), id: \.element.id) { index, page in
                            Tile(page: page) { onOpen(page.url) }
                                .contextMenu {
                                    Button("Unstar", systemImage: "star.slash") { store.star(page.id, false) }
                                }
                                .accessibilityIdentifier("starred.tile.\(index)")
                        }
                    }
                }
                bottom
            }
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("starred")
        }
    }

    private var bottom: some View {
        let later = store.saved.readLater.count
        return HStack(spacing: 0) {
            Button { onShowSaved(.all) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark")
                    Text("Saved")
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(SavedPress())
            .accessibilityIdentifier("starred.saved")
            Spacer(minLength: 8)
            if later > 0 {
                Button { onShowSaved(.readLater) } label: {
                    Text("\(later) to read")
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(SavedPress())
                .accessibilityIdentifier("starred.later")
            }
        }
        .ramp(.caption)
        .foregroundStyle(Palette.muted)
    }
}

private struct Tile: View {
    let page: SavedPage
    let open: () -> Void

    @ScaledMetric(relativeTo: .callout) private var size: CGFloat = 54

    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                SiteMark(url: page.url, size: size)
                Text(page.title)
                    .ramp(.glyph)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .frame(maxWidth: size + 16)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(TilePress())
        .accessibilityLabel(page.title)
    }
}

/// A tile dims under a finger.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
