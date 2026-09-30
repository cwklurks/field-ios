// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// One sentence at a time, gone after 1.7 seconds. A new one replaces the old
/// and starts the clock again.
@MainActor @Observable final class Toaster {
    private(set) var text: String?
    /// The one thing to do about it, if there is one: "Open".
    private(set) var offer: Offer?
    @ObservationIgnored private var hush: Task<Void, Never>?

    struct Offer {
        let title: String
        let perform: () -> Void
    }

    /// With an offer it stays long enough to reach for.
    func show(_ text: String, offering offer: Offer? = nil) {
        withAnimation(Motion.calm(Motion.settle)) {
            self.text = text
            self.offer = offer
        }
        hush?.cancel()
        hush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(offer == nil ? 1.7 : 4))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// The offer, taken: the toast goes as it's done.
    func take() {
        guard let offer else { return }
        hush?.cancel()
        hide()
        offer.perform()
    }

    private func hide() {
        withAnimation(Motion.calm(Motion.settle)) {
            text = nil
            offer = nil
        }
    }
}

/// A line that rises above the bar, says one thing, and leaves. An offer
/// sits after the sentence, in the same capsule.
struct Toast: View {
    let toaster: Toaster
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        if let text = toaster.text {
            HStack(spacing: 14) {
                Text(text)
                if let offer = toaster.offer {
                    Button(offer.title, action: toaster.take)
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        // Easier to hit than the word, without a bigger capsule.
                        .contentShape(Rectangle().inset(by: -12))
                        .accessibilityIdentifier("toast.offer")
                }
            }
            .ramp(.toast)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(Palette.raised)
                    .lift(.toast)
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .padding(.horizontal, Bar.margin)
            .transition(still ? .opacity : .opacity.combined(with: .offset(y: 14)))
            .id(text)
        }
    }
}
