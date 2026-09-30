import FieldKit
import SwiftUI

/// What comes up after Save. The page is saved already; this only tidies
/// it: its title, a folder (the likeliest one chosen for you, when there is
/// one), and a star to put it on the new tab. Done keeps it and closes, and
/// so does a swipe down. Remove takes the save back.
struct SaveSheet: View {
    let store: SavedStore
    /// The page just saved, from `store.save`.
    let page: SavedPage
    /// Called to close; the sheet has already kept what was chosen.
    var onDone: () -> Void

    @State private var title = ""
    @State private var folder: String?
    @State private var starred = false
    @State private var suggested: String?
    /// Set once a folder is chosen by hand, after which a suggestion
    /// arriving late never moves the choice.
    @State private var chosenByHand = false
    @State private var naming = false
    @State private var newFolder = ""
    @State private var removed = false
    @Namespace private var slide
    @FocusState private var focus: Field?

    private enum Field { case title, folder }

    /// Seeded from the page as it's kept now, so a saved page's sheet rises
    /// already showing its star and folder, with nothing to animate in.
    init(store: SavedStore, page: SavedPage, onDone: @escaping () -> Void) {
        self.store = store
        self.page = page
        self.onDone = onDone
        let now = store.saved.pages.first { $0.id == page.id } ?? page
        _title = State(initialValue: now.title)
        _folder = State(initialValue: now.folder)
        _starred = State(initialValue: now.starred)
        // A page already in a folder was put there by someone.
        _chosenByHand = State(initialValue: now.folder != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Saved").ramp(.heading)
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(.plain)
                    .ramp(.row)
                    .fontWeight(.medium)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityIdentifier("savesheet.done")
            }

            HStack(spacing: 12) {
                SiteMark(url: page.url, size: 32)
                    .accessibilityHidden(true)
                TextField(page.host, text: $title)
                    .ramp(.row)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .accessibilityIdentifier("savesheet.title")
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .background(Palette.wash, in: .corner(Radius.filter))

            ScrollViewReader { track in
            ChipTrack {
                Chip(title: "No folder", chosen: folder == nil && !naming, slide: slide) { choose(nil) }
                    .accessibilityIdentifier("savesheet.folder.none")
                ForEach(store.saved.folders, id: \.self) { name in
                    Chip(title: name, detail: name == suggested ? "Suggested" : nil,
                         chosen: folder == name && !naming, slide: slide) { choose(name) }
                        .id(name)
                        .accessibilityIdentifier("savesheet.folder.\(name)")
                }
                if naming {
                    TextField("Folder name", text: $newFolder)
                        .ramp(.label)
                        .submitLabel(.done)
                        .focused($focus, equals: .folder)
                        .onSubmit(makeFolder)
                        .frame(width: 140)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Palette.ground, in: .corner(Radius.chip))
                        .accessibilityIdentifier("savesheet.newfolder")
                } else {
                    Button {
                        naming = true
                        focus = .folder
                    } label: {
                        Image(systemName: "plus")
                            .ramp(.label)
                            .foregroundStyle(Palette.muted)
                            .frame(minWidth: 34, minHeight: 34)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New folder")
                    .accessibilityIdentifier("savesheet.folder.new")
                }
            }
            .onChange(of: suggested) { _, name in
                // In the same motion as the choice, never after it.
                withAnimation(Motion.calm(Motion.settle)) { track.scrollTo(name, anchor: .center) }
            }
            }

            HStack {
                Button {
                    // Word and star change on the same frame, not on two
                    // timelines of their own.
                    starred.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: starred ? "star.fill" : "star")
                        Text(starred ? "Starred" : "Star")
                    }
                    .ramp(.row)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(SavedPress())
                .sensoryFeedback(.selection, trigger: starred)
                .accessibilityAddTraits(starred ? .isSelected : [])
                .accessibilityIdentifier("savesheet.star")
                Spacer()
                Button("Remove") {
                    removed = true
                    store.remove(page.id)
                    onDone()
                }
                .buttonStyle(.plain)
                .ramp(.row)
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .accessibilityIdentifier("savesheet.remove")
            }
            .padding(.horizontal, -10)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.ground)
        .task { await suggest() }
        .onDisappear(perform: keep)
        // One element holding the rest, which keep their own identifiers:
        // on a plain container this one would replace theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savesheet")
    }

    /// Room for the four rows and the home indicator, and no more.
    static let height: CGFloat = 250

    private func suggest() async {
        let saved = store.saved
        guard !saved.folders.isEmpty,
              let guess = await FolderSuggester.shared.folder(for: page.url, title: page.title, in: saved) else { return }
        withAnimation(Motion.calm(Motion.settle)) {
            suggested = guess
            if !chosenByHand { folder = guess }
        }
    }

    private func choose(_ name: String?) {
        chosenByHand = true
        focus = nil
        withAnimation(Motion.calm(Motion.settle)) {
            naming = false
            folder = name
        }
    }

    private func makeFolder() {
        guard let made = store.addFolder(newFolder) else {
            withAnimation(Motion.calm(Motion.settle)) { naming = false }
            return
        }
        newFolder = ""
        choose(made)
    }

    /// Whatever was chosen, however the sheet went.
    private func keep() {
        guard !removed else { return }
        if naming, !newFolder.trimmingCharacters(in: .whitespaces).isEmpty { makeFolder() }
        guard let now = store.saved.pages.first(where: { $0.id == page.id }) else { return }
        if title != now.title { store.retitle(page.id, title) }
        if folder != now.folder { store.move(page.id, to: folder) }
        if starred != now.starred { store.star(page.id, starred) }
    }
}
