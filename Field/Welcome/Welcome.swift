import SwiftUI
import os

/// The first launch: one screen, one question. The bar over a page in both
/// looks, side by side; tapping one chooses it there and then.
struct Welcome: View {
    let done: () -> Void

    @AppStorage("bar.look") private var look: BarLook = .glass
    @State private var chosen: BarLook?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Two ways to see the bar.")
                    .ramp(.title)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Glass lets the page show through. Solid is lifted off it, as on the Mac. Tap one to try it; Settings can change it later.")
                    .ramp(.message)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(BarLook.allCases) { option in
                    BarLookCard(look: option, chosen: chosen.map { $0 == option }) { choose(option) }
                        .accessibilityIdentifier("welcome.\(option.rawValue)")
                }
            }
            .padding(.top, 28)
            Spacer(minLength: 24)
            // Waiting, it's a grey you can still read; chosen, it's ink.
            Button(action: done) {
                Text("Continue")
                    .ramp(.row)
                    .fontWeight(.medium)
                    .foregroundStyle(chosen == nil ? Palette.muted : Palette.ground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(chosen == nil ? Palette.wash : Palette.ink, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(chosen == nil)
            .animation(Motion.quick, value: chosen)
        }
        .padding(.horizontal, 22)
        .padding(.top, 32)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .sensoryFeedback(.selection, trigger: chosen)
    }

    private func choose(_ option: BarLook) {
        let choosing = Signpost.log.beginAnimationInterval(Signpost.welcomeChoose)
        look = option
        withAnimation(Motion.calm(Motion.settle)) {
            chosen = option
        } completion: {
            Signpost.log.endInterval(Signpost.welcomeChoose, choosing)
        }
    }
}
