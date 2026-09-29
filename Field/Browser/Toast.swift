// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// One sentence at a time, gone after 1.7 seconds. A new one replaces the old
/// and starts the clock again.
@MainActor @Observable final class Toaster {
    private(set) var text: String?
    @ObservationIgnored private var hush: Task<Void, Never>?

    func show(_ text: String) {
        withAnimation(Motion.calm(Motion.settle)) { self.text = text }
        hush?.cancel()
        hush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.calm(Motion.settle)) { self?.text = nil }
        }
    }
}

/// A line that rises above the bar, says one thing, and leaves.
struct Toast: View {
    let toaster: Toaster
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        if let text = toaster.text {
            Text(text)
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
