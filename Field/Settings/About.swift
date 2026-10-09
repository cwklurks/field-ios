import SwiftUI

/// What Field is, what it keeps to itself, and whose work it's built on.
/// The notices and licences are read from the bundle only when they're opened.
struct About: View {
    @State private var reading = false
    @State private var licence: Licence?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Field").ramp(.row).fontWeight(.semibold)
                Text("Version \(Self.version)")
                    .ramp(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Text("Nothing leaves your phone except the pages you open and, if they’re on, search suggestions.")
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Licences").ramp(.caption).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    ForEach(Licence.allCases) { option in
                        if option != Licence.allCases.first {
                            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.leading, 14)
                        }
                        Button { licence = option } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).ramp(.row)
                                    Text(option.covers)
                                        .ramp(.caption)
                                        .foregroundStyle(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
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
                        .accessibilityHint("Shows the licence in full")
                        .accessibilityIdentifier("about.licence.\(option.rawValue)")
                    }
                }
                .background(Palette.raised, in: .corner(Radius.card))
                .clipShape(.corner(Radius.card))
                .overlay(RoundedRectangle.corner(Radius.card).strokeBorder(Palette.hairline, lineWidth: 1))
            }
        }
        .sheet(isPresented: $reading) {
            Reading(title: "Notices", id: "notices", load: Notices.load)
        }
        .sheet(item: $licence) { licence in
            Reading(title: licence.title, id: "licence.\(licence.rawValue)") { AttributedString(licence.text()) }
        }
    }

    /// "0.1 (5)": the version people see, and the build TestFlight counts.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// A notice or a licence in full, loaded off the main thread when it opens.
private struct Reading: View {
    let title: String
    let id: String
    let load: @Sendable () -> AttributedString

    @AppStorage("look") private var look: Look = .system
    @Environment(\.dismiss) private var dismiss
    @State private var text: AttributedString?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(title).ramp(.heading)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .ramp(.row)
                        .fontWeight(.medium)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("\(id).done")
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
        .dynamicTypeSize(...Ramp.cap)
        .task { text = await Task.detached(priority: .userInitiated) { [load] in load() }.value }
        .accessibilityIdentifier(id)
    }
}

/// NOTICE.md in full: Search's MIT notice, then each list's licence as the
/// lists arrive.
private enum Notices {
    /// The file is wrapped for a terminal, so each paragraph is joined back
    /// into one and left to wrap at the phone's width. Its own title goes,
    /// since the sheet has one, and the headings under it become bold lines.
    nonisolated static func load() -> AttributedString {
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

/// The licences Field and what it ships come under, each bundled in full
/// from the repository's own copy (project.yml).
enum Licence: String, CaseIterable, Identifiable {
    case mpl, gpl, ccBySA, apache

    var id: Self { self }

    var title: String {
        switch self {
        case .mpl: "Mozilla Public License 2.0"
        case .gpl: "GNU General Public License 3.0"
        case .ccBySA: "Creative Commons BY-SA 3.0"
        case .apache: "Apache License 2.0"
        }
    }

    /// Whose work it covers, as NOTICE says in full.
    var covers: String {
        switch self {
        case .mpl: "Field, Brave's lists and the Public Suffix List"
        case .gpl: "HaGeZi's block lists"
        case .ccBySA: "EasyList and EasyPrivacy"
        case .apache: "DuckDuckGo's tracking parameters"
        }
    }

    nonisolated var resource: (name: String, ext: String?) {
        switch self {
        case .mpl: ("LICENSE", nil)
        case .gpl: ("GPL-3.0", "txt")
        case .ccBySA: ("CC-BY-SA-3.0", "txt")
        case .apache: ("Apache-2.0", "txt")
        }
    }

    nonisolated var url: URL? {
        Bundle.main.url(forResource: resource.name, withExtension: resource.ext)
    }

    nonisolated func text() -> String {
        guard let url, let file = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return Self.reflow(file)
    }

    /// The text wraps at 72 columns, which a phone would break again
    /// mid-line, so the lines of each paragraph are joined and left to wrap
    /// at its width. Only the spacing changes: a numbered or lettered item
    /// and a rule under a heading keep their own lines, and the box the MPL
    /// draws around its disclaimers goes while its words stay.
    nonisolated static func reflow(_ file: String) -> String {
        var lines: [String] = []
        var open = false
        for raw in file.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.count > 1, line.hasPrefix("*"), line.hasSuffix("*") {
                line = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if line.allSatisfy({ $0 == "*" }) { line = "" }
            }
            if line.isEmpty {
                if open { lines.append("") }
                open = false
            } else if open, !startsItem(line), !isRule(line), !isRule(lines[lines.count - 1]) {
                lines[lines.count - 1] += " " + line
            } else {
                lines.append(line)
                open = true
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// "1.1. ", "a. ", "ii. ", "a) " or "(b) ".
    nonisolated private static func startsItem(_ line: String) -> Bool {
        line.range(of: #"^(\d+(\.\d+)*\.|[a-z]\.|[ivx]+\.|[a-z]\)|\([a-z0-9]{1,4}\))\s"#, options: .regularExpression) != nil
    }

    nonisolated private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { "-=_*".contains($0) }
    }
}

/// Ink at 5% under a finger, as everywhere else in Settings.
private struct Held: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.ink.opacity(0.05) : .clear)
    }
}
