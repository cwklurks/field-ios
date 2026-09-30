import FieldKit
import SwiftUI
import UniformTypeIdentifiers

/// Tidy's preview: the groups proposed for the open tabs, as they arrive.
/// Names can be edited, tabs unchecked or dragged to another group, and
/// nothing in the grid moves until Apply. Said plainly where it came from:
/// this iPhone.
struct TidySheet: View {
    let draft: TidyDraft
    var onApply: () -> Void
    var onCancel: () -> Void

    /// The group a dragged tab is over.
    @State private var target: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .overlay(alignment: .bottom) { apply }
        .foregroundStyle(Palette.ink)
        .background(Palette.ground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tidy")
    }

    // MARK: - parts

    private var title: String {
        draft.mode == .tidy ? "Tidy" : "Add similar tabs"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).ramp(.heading)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .ramp(.row)
                    .fontWeight(.medium)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityIdentifier("tidy.cancel")
            }
            Text("Suggested on this iPhone")
                .ramp(.caption)
                .foregroundStyle(Palette.muted)
                .accessibilityIdentifier("tidy.label")
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    /// The groups, then one quiet line under them while the rest is read.
    /// Arriving groups push the line down rather than landing on it, and
    /// its words change by cut: no frame shows two lines in one place.
    @ViewBuilder private var content: some View {
        ForEach(draft.sections) { section in
            group(section)
                .transition(.opacity.combined(with: .offset(y: 10)))
        }
        if draft.thinking || draft.sections.isEmpty {
            Text(draft.thinking ? reading : nothing)
                .ramp(draft.sections.isEmpty ? .message : .caption)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, draft.sections.isEmpty ? 6 : 12)
                .padding(.top, draft.sections.isEmpty ? 8 : 0)
                .contentTransition(.identity)
                .id("status")
                // Straight to its new place under a group arriving above it:
                // gliding there, it would pass under the group's fading rows.
                .transaction { $0.animation = nil }
                .accessibilityIdentifier(draft.thinking ? "tidy.reading" : "tidy.nothing")
        }
    }

    private var reading: String {
        let n = draft.info.count
        return draft.mode == .tidy ? "Reading \(n) tabs" : "Looking for tabs like these"
    }

    private var nothing: String {
        draft.mode == .tidy ? "No groups stand out." : "No other tabs look like these."
    }

    private func group(_ section: TidyDraft.Section) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField("Name", text: Binding(
                    get: { section.name },
                    set: { draft.rename(section.id, to: $0) }
                ))
                .ramp(.label)
                .submitLabel(.done)
                .disabled(draft.thinking || draft.mode != .tidy)
                .accessibilityIdentifier("tidy.name.\(section.name)")
                Text("\(section.tabs.filter(draft.isChecked).count)")
                    .ramp(.caption)
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)

            VStack(spacing: 0) {
                ForEach(section.tabs, id: \.self) { id in
                    if let tab = draft.info[id] { row(tab, in: section) }
                }
            }
            .background {
                RoundedRectangle.corner(Radius.card)
                    .fill(Palette.wash)
                    .opacity(target == section.id ? 1 : 0)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            withAnimation(Motion.calm(Motion.settle)) { draft.move(id, to: section.id) }
            return true
        } isTargeted: { over in
            withAnimation(Motion.calm(Motion.quick)) {
                if over { target = section.id } else if target == section.id { target = nil }
            }
        }
    }

    private func row(_ tab: TabInfo, in section: TidyDraft.Section) -> some View {
        let checked = draft.isChecked(tab.id)
        return Button {
            withAnimation(Motion.calm(Motion.quick)) { draft.toggle(tab.id) }
        } label: {
            TidyRow(tab: tab, checked: checked)
        }
        .buttonStyle(SavedPress())
        .disabled(draft.thinking)
        .draggable(tab.id.uuidString) {
            TidyRow(tab: tab, checked: checked)
                .frame(width: 300)
                .background(Palette.raised, in: .corner(Radius.row))
        }
        .contextMenu {
            let others = draft.sections.filter { $0.id != section.id }
            if !others.isEmpty {
                Menu("Move to", systemImage: "arrow.right") {
                    ForEach(others) { other in
                        Button(other.name) {
                            withAnimation(Motion.calm(Motion.settle)) { draft.move(tab.id, to: other.id) }
                        }
                    }
                }
            }
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityIdentifier("tidy.row.\(tab.title)")
    }

    /// Apply on the sheet's own ground, over the list's end.
    private var apply: some View {
        let ready = draft.canApply
        return Button(action: onApply) {
            Text(draft.mode == .tidy ? "Apply" : "Add")
                .ramp(.row)
                .fontWeight(.semibold)
                .foregroundStyle(ready ? Palette.ground : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(ready ? Palette.ink : Palette.wash, in: .corner(Radius.field))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .animation(Motion.calm(Motion.quick), value: ready)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Palette.ground)
        .accessibilityIdentifier("tidy.apply")
    }
}

/// A tab in a list to choose from: a tick, its site's mark, its title and
/// its site. Unchecked, it greys and the tick empties.
struct TidyRow: View {
    let tab: TabInfo
    let checked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(checked ? Palette.ink : Palette.faint)
                .contentTransition(.symbolEffect(.replace))
            SiteMark(url: tab.url, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? (Tidy.host(of: tab.url) ?? tab.url.absoluteString) : tab.title)
                    .ramp(.row)
                    .lineLimit(1)
                    .foregroundStyle(checked ? Palette.ink : Palette.muted)
                Text(Tidy.host(of: tab.url) ?? "")
                    .ramp(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .contentShape(.rect)
    }
}
