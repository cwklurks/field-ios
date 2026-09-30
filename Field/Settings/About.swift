import SwiftUI

/// What Field is, what it keeps to itself, and whose work it's built on.
/// The notices are read from the bundle only when they're opened.
struct About: View {
    @State private var reading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Field").ramp(.row).fontWeight(.semibold)
                Text("Version \(Self.version)")
                    .ramp(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Text("Nothing leaves your phone except the pages you open.")
                .ramp(.row)
                .fixedSize(horizontal: false, vertical: true)
            Button { reading = true } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Built on Search by Office Commun").ramp(.row)
                        Text("MIT License").ramp(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .ramp(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .buttonStyle(Held())
            .background(Palette.raised, in: .corner(Radius.card))
            .clipShape(.corner(Radius.card))
            .overlay(RoundedRectangle.corner(Radius.card).strokeBorder(Palette.hairline, lineWidth: 1))
            .accessibilityHint("Shows the notices in full")
            .accessibilityIdentifier("about.notices")
        }
        .sheet(isPresented: $reading) { Notices() }
    }

    /// "0.1 (5)": the version people see, and the build TestFlight counts.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// NOTICE.md in full: Search's MIT notice, then each list's licence as the
/// lists arrive.
private struct Notices: View {
    @AppStorage("look") private var look: Look = .system
    @Environment(\.dismiss) private var dismiss
    @State private var text: AttributedString?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Notices").ramp(.heading)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .ramp(.row)
                        .fontWeight(.medium)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("notices.done")
                }
                if let text {
                    Text(text)
                        .ramp(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Palette.ground)
        .preferredColorScheme(look.scheme)
        .task { text = await Task.detached(priority: .userInitiated) { Self.load() }.value }
        .accessibilityIdentifier("notices")
    }

    /// The file is wrapped for a terminal, so each paragraph is joined back
    /// into one and left to wrap at the phone's width. Its own title goes,
    /// since the sheet has one, and the headings under it become bold lines.
    nonisolated private static func load() -> AttributedString {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md"),
              let file = try? String(contentsOf: url, encoding: .utf8) else {
            return AttributedString("Field includes code adapted from Search by Office Commun (github.com/driceroland/Search), under the MIT License.")
        }
        let markdown = file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .split(separator: "")
            .map(Array.init)
            .filter { !$0[0].hasPrefix("# ") }
            .flatMap { lines -> [String] in
                // A heading is its own paragraph, whatever follows it without a blank line.
                guard lines[0].hasPrefix("#") else { return [lines.joined(separator: " ")] }
                let heading = "**" + lines[0].drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**"
                return lines.count == 1 ? [heading] : [heading, lines.dropFirst().joined(separator: " ")]
            }
            .joined(separator: "\n\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(file)
    }
}

/// Ink at 5% under a finger, as everywhere else in Settings.
private struct Held: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.ink.opacity(0.05) : .clear)
    }
}
