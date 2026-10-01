import FieldKit
import SwiftUI
import UIKit

/// The few things there are to choose: how the bar looks, how the app looks,
/// and where searches go.
struct SettingsView: View {
    @AppStorage("bar.look") private var barLook: BarLook = .glass
    @AppStorage("look") private var look: Look = .system
    @AppStorage("engine") private var engine: Engine = .standard
    @AppStorage("engine.custom") private var custom = ""
    /// Read by the stale-tabs rule (StaleTabs.days).
    @AppStorage("staleDays") private var staleDays = Stale.defaultDays
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    Text("Settings").ramp(.heading)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .ramp(.row)
                        .fontWeight(.medium)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("settings.done")
                }
                section("Bar") {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(BarLook.allCases) { option in
                            BarLookCard(look: option, chosen: option == barLook) {
                                withAnimation(Motion.calm(Motion.settle)) { barLook = option }
                            }
                        }
                    }
                    .sensoryFeedback(.selection, trigger: barLook)
                }
                section("Appearance") {
                    Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $look)
                }
                section("Search engine") {
                    Engines(engine: $engine, custom: $custom)
                }
                section("Tabs untouched for") {
                    Segmented(options: [(7, "1 week"), (14, "2 weeks"), (30, "1 month")], selection: $staleDays)
                }
                section("Private") { PrivateSettingsSection() }
                section("About") { About() }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground)
        // The root's preference doesn't reach a sheet that's already up, so
        // the sheet says it too, and changes the moment Appearance does.
        .preferredColorScheme(look.scheme)
        .accessibilityIdentifier("settings")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).ramp(.label).foregroundStyle(Palette.muted)
            content()
        }
    }
}

/// Settings in the system sheet, made before the tap. SwiftUI's `.sheet`
/// builds its content on the tap, about 75 ms the first time, and the sheet
/// waited that long to move. This one is built and drawn once while nothing
/// moves, then only presented, so it moves as soon as UIKit's sheet can.
@MainActor
enum SettingsSheet {
    private static var host: Host?

    /// Two seconds on, when no finger is down (the timer doesn't fire while
    /// the run loop tracks one) and `busy` says nothing else is going on.
    static func prepareSoon(unless busy: @escaping @MainActor () -> Bool, tries: Int = 0) {
        guard tries < 20 else { return }
        Timer.scheduledTimer(withTimeInterval: tries == 0 ? 2 : 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard host == nil else { return }
                if busy() { return prepareSoon(unless: busy, tries: tries + 1) }
                _ = prepared()
            }
        }
    }

    static func present(onDismiss: @escaping () -> Void) {
        guard var top = window?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let host = prepared()
        guard host.presentingViewController == nil else { return }
        host.onDismiss = onDismiss
        top.present(host, animated: true)
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    private static func prepared() -> Host {
        if let host { return host }
        // A sheet would have these from the root; a UIKit one doesn't.
        let host = Host(rootView: AnyView(SettingsView().tint(Palette.ink).dynamicTypeSize(...Ramp.cap)))
        host.view.backgroundColor = Palette.UI.ground
        self.host = host
        // A hosting view builds nothing out of a window, and the first open
        // would wait for its pictures to reach the screen, so it's laid out
        // and drawn once under the app's own view, where it can't be seen.
        guard let window else { return host }
        host.view.frame = window.bounds
        host.view.accessibilityElementsHidden = true
        window.insertSubview(host.view, at: 0)
        host.view.layoutIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            host.view.accessibilityElementsHidden = false
            if host.presentingViewController == nil { host.view.removeFromSuperview() }
        }
        return host
    }

    /// Says when it has gone, however it went: Done or a swipe down.
    final class Host: UIHostingController<AnyView> {
        var onDismiss: () -> Void = {}

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if presentingViewController == nil { onDismiss() }
        }
    }
}

/// The presets, one tick for the chosen one, and a template of your own.
private struct Engines: View {
    @Binding var engine: Engine
    @Binding var custom: String

    @State private var draft = ""
    @State private var travel: CGFloat = 0
    @State private var refused = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Engine.allCases.filter { $0 != .custom }) { option in
                row(option.title, chosen: engine == option) { engine = option }
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
            }
            row("Custom", chosen: engine == .custom) {
                if Engine.accepts(custom) { engine = .custom } else { typing = true }
            }
            TextField("https://example.com/search?q=%s", text: $draft)
                .ramp(.row)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typing)
                .onSubmit(save)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Palette.wash, in: .corner(Radius.filter))
                .overlay {
                    RoundedRectangle.corner(Radius.filter)
                        .strokeBorder(refused ? Color.red.opacity(0.35) : .clear, lineWidth: 1)
                }
                .modifier(Shake(travel: travel))
                .padding(.horizontal, 14)
            Text("Put %s where the words go.")
                .ramp(.caption)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(Palette.raised, in: .corner(Radius.card))
        .overlay(RoundedRectangle.corner(Radius.card).strokeBorder(Palette.hairline, lineWidth: 1))
        .onAppear { draft = custom }
        .onChange(of: draft) { withAnimation(Motion.quick) { refused = false } }
    }

    private func row(_ title: String, chosen: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack {
                Text(title).ramp(.row)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark").ramp(.row).fontWeight(.medium)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(Pressed())
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A template that names a site and has a place for the words is kept and
    /// chosen; anything else is refused with a shake, never an alert.
    private func save() {
        let template = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Engine.accepts(template) else {
            refused = true
            travel = 0
            withAnimation(.easeOut(duration: 0.5)) { travel = 1 } completion: { travel = 0 }
            typing = true
            return
        }
        custom = template
        engine = .custom
    }
}

/// Ink at 5% under a finger, and no other change.
private struct Pressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.ink.opacity(0.05) : .clear)
    }
}
