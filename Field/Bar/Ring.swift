// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// An almost-closed ring, turning: small enough to sit beside the address
/// without becoming the loudest thing in the bar. There is no progress bar.
struct Ring: View {
    var size: CGFloat = 10
    var colour = Palette.muted
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.78)
            .stroke(
                colour.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
