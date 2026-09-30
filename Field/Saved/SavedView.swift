import FieldKit
import SwiftUI

/// Everything saved, in one list: a field to find a page by its title or
/// site, a row of filters (all of it, "Read later", or one folder), the
/// folders themselves, then the pages, newest first. Swipe a page to star
/// it, move it or delete it.
struct SavedView: View {
    let store: SavedStore
    /// A page was chosen; the caller opens it and closes this.
    var onOpen: (URL) -> Void
    var onDone: () -> Void
    /// Where to start: the grid's "to read" count opens on Read later.
    var start: SavedFilter = .all

    @State private var text = ""
    /// What the list shows. Changed without animation: a list of hundreds
    /// swapped at once reads better as a cut than as rows flying about.
    @State private var filter: SavedFilter = .all
    /// What the chips show, changed with the settle, so the lift slides.
    @State private var chip: SavedFilter = .all
    @State private var moving: SavedPage?
    @State private var renaming: String?
    @State private var newName = ""
    @Namespace private var slide
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 12) {
            header
            search
            ChipTrack {
                Chip(title: "All", chosen: chip == .all, slide: slide) { show(.all) }
                    .accessibilityIdentifier("saved.filter.all")
                Chip(title: "Read later", detail: laterCount, chosen: chip == .readLater, slide: slide) { show(.readLater) }
                    .accessibilityIdentifier("saved.filter.later")
                ForEach(store.saved.folders, id: \.self) { folder in
                    Chip(title: folder, chosen: chip == .folder(folder), slide: slide) { show(.folder(folder)) }
                        .accessibilityIdentifier("saved.filter.\(folder)")
                }
            }
            .padding(.horizontal, 16)
            list
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.ground)
        .sheet(item: $moving) { page in
            FolderPicker(folders: store.saved.folders, current: page.folder) { folder in
                store.move(page.id, to: folder)
            }
        }
        .alert("Rename folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .onAppear {
            // Kept between openings (SavedSheets): each starts clean.
            text = ""
            filter = start
            chip = start
        }
        .onChange(of: store.saved.folders) { _, folders in
            // A folder deleted or renamed while it was the filter.
            if case .folder(let name) = filter, !folders.contains(name) { show(.all) }
        }
        // One element holding the rest, which keep their own identifiers:
        // on a plain container this one would replace theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saved")
    }

    // MARK: - parts

    private var header: some View {
        HStack {
            Text("Saved").ramp(.heading)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.plain)
                .ramp(.row)
                .fontWeight(.medium)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .accessibilityIdentifier("saved.done")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .ramp(.row)
                .foregroundStyle(Palette.muted)
            TextField("Search saved", text: $text)
                .ramp(.row)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .accessibilityIdentifier("saved.search")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .ramp(.row)
                        .foregroundStyle(Palette.faint)
                        .frame(minWidth: 32, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Palette.wash, in: .corner(Radius.filter))
        .padding(.horizontal, 16)
    }

    private var list: some View {
        let pages = shown
        let folders = filter == .all && text.isEmpty ? store.saved.folders : []
        return List {
            if !folders.isEmpty {
                Section {
                    label("Folders")
                    ForEach(folders, id: \.self) { folder in
                        FolderRow(name: folder, count: store.saved.count(in: folder)) { show(.folder(folder)) }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteFolder(folder)
                                }
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    newName = folder
                                    renaming = folder
                                }
                                Button("Delete Folder", systemImage: "trash", role: .destructive) {
                                    store.deleteFolder(folder)
                                }
                            }
                            .row()
                    }
                }
            }
            Section {
                if !folders.isEmpty, !pages.isEmpty { label("Pages") }
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    PageRow(page: page) { onOpen(page.url) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(page.starred ? "Unstar" : "Star", systemImage: page.starred ? "star.slash" : "star") {
                                store.star(page.id, !page.starred)
                            }
                            .tint(Palette.muted)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.remove(page.id)
                            }
                            Button("Move", systemImage: "folder") { moving = page }
                                .tint(Palette.muted)
                        }
                        .contextMenu { menu(for: page) }
                        .accessibilityIdentifier("saved.row.\(index)")
                        .row()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // Rows fade out under the filters, as cards do under the status bar.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .environment(\.defaultMinListRowHeight, 44)
        .overlay {
            if pages.isEmpty, folders.isEmpty {
                Text(emptyLine)
                    .ramp(.message)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 80)
                    .accessibilityIdentifier("saved.empty")
            }
        }
        .accessibilityIdentifier("saved.list")
    }

    @ViewBuilder private func menu(for page: SavedPage) -> some View {
        Button("Open", systemImage: "arrow.up.forward") { onOpen(page.url) }
        Button(page.starred ? "Unstar" : "Star", systemImage: page.starred ? "star.slash" : "star") {
            store.star(page.id, !page.starred)
        }
        Menu("Move to", systemImage: "folder") {
            Button("No Folder") { store.move(page.id, to: nil) }
            ForEach(store.saved.folders, id: \.self) { folder in
                Button(folder) { store.move(page.id, to: folder) }
            }
            Button("New Folder…", systemImage: "folder.badge.plus") { moving = page }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { store.remove(page.id) }
    }

    /// A heading in the list, as a row of its own: a section's header would
    /// stay pinned at the top, the rows showing through it as they pass.
    private func label(_ title: String) -> some View {
        Text(title)
            .ramp(.label)
            .foregroundStyle(Palette.muted)
            .padding(.leading, 6)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
            .row()
            .listRowSeparator(.hidden)
    }

    // MARK: - what's shown

    private var shown: [SavedPage] {
        let base: [SavedPage]
        switch filter {
        case .all: base = store.saved.pages
        case .readLater: base = store.saved.readLater
        case .folder(let name): base = store.saved.pages(in: name)
        }
        return store.saved.search(text, among: base)
    }

    private var laterCount: String? {
        let count = store.saved.readLater.count
        return count > 0 ? "\(count)" : nil
    }

    private var emptyLine: String {
        if !text.isEmpty { return "Nothing saved matches." }
        switch filter {
        case .all: return "Nothing saved yet."
        case .readLater: return "Nothing to read later."
        case .folder: return "Nothing in this folder."
        }
    }

    private func show(_ next: SavedFilter) {
        filter = next
        withAnimation(Motion.calm(Motion.settle)) { chip = next }
    }

    private func rename() {
        guard let old = renaming else { return }
        store.renameFolder(old, to: newName)
        let name = store.saved.folders.first { $0.caseInsensitiveCompare(newName.trimmingCharacters(in: .whitespaces)) == .orderedSame }
        if filter == .folder(old), let name { show(.folder(name)) }
        renaming = nil
    }
}

enum SavedFilter: Hashable {
    case all, readLater
    case folder(String)
}

private struct PageRow: View {
    let page: SavedPage
    let open: () -> Void

    @ScaledMetric(relativeTo: .callout) private var mark: CGFloat = 32

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                SiteMark(url: page.url, size: mark)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .ramp(.row)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(page.host)
                        if let folder = page.folder {
                            Text("·")
                            Text(folder)
                        }
                    }
                    .ramp(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if page.starred {
                    Image(systemName: "star.fill")
                        .ramp(.glyph)
                        .foregroundStyle(Palette.muted)
                        .accessibilityLabel("Starred")
                }
                if page.isUnread {
                    Circle()
                        .fill(Palette.ink.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Not read")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(SavedPress())
    }
}

private struct FolderRow: View {
    let name: String
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .ramp(.row)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32)
                Text(name).ramp(.row).lineLimit(1)
                Spacer()
                Text("\(count)").ramp(.caption).foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right")
                    .ramp(.glyph)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(SavedPress())
        .accessibilityIdentifier("saved.folder.\(name)")
    }
}

private extension View {
    /// A list row drawn as the app draws rows: on the ground, edge to edge
    /// but for a small inset, hairlines between.
    func row() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .listRowBackground(Palette.ground)
            .listRowSeparatorTint(Palette.hairline)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 56 }
    }
}
