/// The one surface's story: the bar, the field, or the field on its way back
/// into the bar. Whatever happens to it (a tap, the keyboard leaving, Return)
/// comes here, and what comes back is what to draw. Pure, so the rules can be
/// tested without a window or a keyboard.
///
/// There is no "opening" between bar and field: the field is there from the
/// frame after the tap, changing shape, and the keyboard rises under it. A
/// close can be taken over by a tap, so each close is numbered, and only the
/// latest one's landing makes the surface the bar again.
struct FieldFlow: Equatable {
    enum Phase: Equatable { case bar, field, closing }

    enum Event: Equatable {
        /// The address, in the bar. Shrunk to the pill, it brings the whole
        /// bar back instead.
        case tap(collapsed: Bool)
        /// The field is wanted without a tap: a blank tab.
        case open
        /// A tap outside the field, or escape.
        case cancel
        /// Return, or a suggestion.
        case go
        /// The keyboard is on its way down, whoever sent it: a swipe, the
        /// app leaving the screen.
        case keyboardHiding
        /// The field lost focus without the keyboard saying anything: a
        /// hardware keyboard.
        case editingEnded
        /// A close's motion finished.
        case landed(Int)
    }

    enum Effect: Equatable {
        /// The pill back to the whole bar.
        case expand
        /// Into the field, focused, the address selected.
        case showField
        /// Back into the bar, with the keyboard going down. The number comes
        /// back in `landed`.
        case showBar(Int)
    }

    private(set) var phase: Phase = .bar
    private var closes = 0

    mutating func handle(_ event: Event) -> [Effect] {
        switch (event, phase) {
        case (.tap(collapsed: true), .bar):
            return [.expand]
        case (.tap, .bar), (.tap, .closing), (.open, .bar), (.open, .closing):
            phase = .field
            return [.showField]
        case (.cancel, .field), (.go, .field), (.keyboardHiding, .field), (.editingEnded, .field):
            phase = .closing
            closes += 1
            return [.showBar(closes)]
        case (.landed(let number), .closing) where number == closes:
            phase = .bar
            return []
        default:
            return []
        }
    }
}
