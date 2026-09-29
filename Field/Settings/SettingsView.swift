import FieldKit
import SwiftUI

/// The few things there are to choose: how the bar looks, how the app looks,
/// and where searches go.
struct SettingsView: View {
    @AppStorage("bar.look") private var barLook: BarLook = .glass
    @AppStorage("look") private var look: Look = .system
    @AppStorage("engine") private var engine: Engine = .standard
    @AppStorage("engine.custom") private var custom = ""
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
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground)
        .presentationBackground(Palette.ground)
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
