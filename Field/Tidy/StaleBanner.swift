import FieldKit
import SwiftUI
import UIKit

/// Stale tabs in the grid (M6): FieldKit's rule (Stale.find), the span from
/// settings, and a quiet banner at the top of the grid. Review lists them to
/// uncheck any worth keeping; Close closes them all. Either way they go to
/// Recently Closed, and the toast offers them back.
@MainActor
enum StaleTabs {
    /// Days untouched before a tab counts as stale. Settings can offer 7,
    /// 14 and 30 (docs/integration/tidy.md).
    static var days: Int {
        let set = UserDefaults.standard.integer(forKey: "staleDays")
        return set > 0 ? set : Stale.defaultDays
    }

    /// What's stale among `tabs` (never the private ones), `current` aside.
    static func find(_ tabs: [Session.Entry], current: UUID?, now: Date = .now) -> Stale.Found {
        Stale.find(tabs.map { Stale.Tab(id: $0.id, url: $0.url, title: $0.title, viewed: $0.viewed) },
                   current: current, now: now, days: days)
    }

    static func line(_ found: Stale.Found) -> String? {
        Stale.line(found, days: days)
    }
}

/// "12 tabs untouched for 2 weeks · Review / Close", on the grid's ground,
/// in a grey that doesn't ask for attention.
struct StaleBanner: View {
    let line: String
    var onReview: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(line)
                .ramp(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("stale.line")
            button("Review", onReview).accessibilityIdentifier("stale.review")
            button("Close", onClose).accessibilityIdentifier("stale.close")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Palette.wash, in: .corner(Radius.card))
        .accessibilityElement(children: .contain)
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .ramp(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
    }

    /// For the grid, which is UIKit: a view that sizes itself to the banner.
    static func hosted(line: String, onReview: @escaping () -> Void, onClose: @escaping () -> Void) -> UIView {
        let host = UIHostingController(rootView: StaleBanner(line: line, onReview: onReview, onClose: onClose)
            .dynamicTypeSize(...Ramp.cap))
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.accessibilityIdentifier = "stale"
        return host.view
    }
}

/// Review: the stale tabs, all checked, and Close for the checked ones.
struct StaleSheet: View {
    let tabs: [TabInfo]
    let line: String
    var onClose: ([UUID]) -> Void
    var onCancel: () -> Void

    @State private var kept = Set<UUID>()

    var body: some View {
        let chosen = tabs.filter { !kept.contains($0.id) }.map(\.id)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Review").ramp(.heading)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .ramp(.row)
                        .fontWeight(.medium)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                Text(line).ramp(.caption).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tabs, id: \.id) { tab in
                        Button {
                            withAnimation(Motion.calm(Motion.quick)) {
                                if kept.contains(tab.id) { kept.remove(tab.id) } else { kept.insert(tab.id) }
                            }
                        } label: {
                            TidyRow(tab: tab, checked: !kept.contains(tab.id))
                        }
                        .buttonStyle(SavedPress())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .overlay(alignment: .bottom) {
            Button { onClose(chosen) } label: {
                Text(chosen.count == 1 ? "Close 1 tab" : "Close \(chosen.count) tabs")
                    .ramp(.row)
                    .fontWeight(.semibold)
                    .foregroundStyle(chosen.isEmpty ? Palette.muted : Palette.ground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(chosen.isEmpty ? Palette.wash : Palette.ink, in: .corner(Radius.field))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(chosen.isEmpty)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Palette.ground)
            .accessibilityIdentifier("stale.sheet.close")
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.ground)
    }
}

/// The grid's Tidy button: in the bottom row once there are enough tabs to
/// be worth tidying. Nothing runs until it's tapped.
enum TidyButton {
    static let threshold = 8

    static func shows(tabs count: Int) -> Bool { count >= threshold }

    /// Styled as the row's other buttons are.
    static func make(action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "rectangle.3.group",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: Ramp.row.size, weight: .medium))
        config.baseForegroundColor = Palette.UI.ink
        button.configuration = config
        button.accessibilityLabel = "Tidy"
        button.accessibilityIdentifier = "tabs.tidy"
        button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        return button
    }
}
