import SwiftUI
import UIKit

/// What Private does, and what it can't, said plainly (docs/PLAN.md, "What
/// Field tells people it can't do"). The short form is the page of every new
/// private tab, so the first entry always shows it without Field keeping a
/// note on disk that Private was ever used; the whole list is a tap away
/// there and in Settings › Private.
enum PrivateLimitsText {
    static let does: [(symbol: String, text: String)] = [
        ("clock.arrow.circlepath", "Nothing here is kept: no history, no tabs, no sign-ins. Close Private and it's gone."),
        ("faceid", "It locks when you leave, and the app switcher shows a cover instead."),
        ("record.circle", "It goes blank while the screen is recorded or shared."),
        ("antenna.radiowaves.left.and.right.slash", "Pages can't use WebRTC to find your address."),
    ]

    static let cannot: [(symbol: String, text: String)] = [
        ("camera.viewfinder", "Screenshots. iOS has no way for an app to stop them, or a photo of the screen."),
        ("keyboard", "The keyboard. iOS may still learn words you type into pages."),
        ("network", "Your IP address. Networks and websites still see it. Private isn't a VPN."),
        ("square.and.arrow.up", "Anything you save, copy or share. It leaves Private."),
        ("lock.open", "Anyone who knows your passcode can unlock it."),
    ]
}

/// The whole list, as a sheet.
struct PrivateLimits: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    Label { Text("Private") } icon: { PrivateMark() }
                        .ramp(.heading)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .ramp(.row)
                        .fontWeight(.medium)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                section("What it does", PrivateLimitsText.does)
                section("What it can't do", PrivateLimitsText.cannot)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Palette.ground)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("private.limits")
    }

    private func section(_ title: String, _ lines: [(symbol: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).ramp(.label).foregroundStyle(Palette.muted)
            ForEach(lines, id: \.text) { line in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: line.symbol)
                        .ramp(.row)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 24)
                    Text(line.text).ramp(.row).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Up over whatever is showing, from Settings or a private page.
    static func present() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.compactMap(\.keyWindow).first?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let host = UIHostingController(rootView: PrivateLimits().tint(Palette.ink).dynamicTypeSize(...Ramp.cap))
        host.overrideUserInterfaceStyle = .dark
        top.present(host, animated: true)
    }
}

/// A new private tab's page, under the field: the mark, what Private is in
/// a line, and the way to the rest. Dark, as all of Private is.
struct PrivateWelcome: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.muted)
            Text("Private").ramp(.heading).foregroundStyle(Palette.ink)
            Text(PrivateLimitsText.does[0].text)
                .ramp(.row)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("What Private can't do", action: PrivateLimits.present)
                .buttonStyle(.plain)
                .ramp(.row)
                .fontWeight(.medium)
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityIdentifier("private.limits.open")
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: 420)
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Welcome") {
    PrivateWelcome()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .environment(\.colorScheme, .dark)
}

#Preview("Limits") {
    PrivateLimits()
}
