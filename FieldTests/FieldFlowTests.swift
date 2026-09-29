import Testing
@testable import Field

/// The bar turning into the field and back: which taps and keyboard moves
/// open it, close it, or do nothing.
@MainActor struct FieldFlowTests {
    @Test func aTapOnTheAddressOpensTheField() {
        let story = Story()
        #expect(story.send(.tap(collapsed: false)) == [.showField])
        #expect(story.phase == .field)
    }

    @Test func aTapOnThePillBringsBackTheBarInstead() {
        let story = Story()
        #expect(story.send(.tap(collapsed: true)) == [.expand])
        #expect(story.phase == .bar)
    }

    @Test func cancelGoAndTheKeyboardLeavingEachCloseIt() {
        for event: FieldFlow.Event in [.cancel, .go, .keyboardHiding, .editingEnded] {
            let story = Story()
            story.send(.tap(collapsed: false))
            #expect(story.send(event) == [.showBar(1)])
            #expect(story.phase == .closing)
        }
    }

    /// Closing resigns the field, and the keyboard then says it's going:
    /// that's the same close, not a second one.
    @Test func theCloseItsOwnKeyboardAnnouncesIsOneClose() {
        let story = Story()
        story.send(.tap(collapsed: false))
        story.send(.cancel)
        #expect(story.send(.keyboardHiding) == [])
        #expect(story.send(.editingEnded) == [])
        #expect(story.send(.landed(1)) == [])
        #expect(story.phase == .bar)
    }

    /// The keyboard warmed at launch comes and goes while the bar is up.
    @Test func theKeyboardComingAndGoingUnderTheBarChangesNothing() {
        let story = Story()
        #expect(story.send(.keyboardHiding) == [])
        #expect(story.send(.editingEnded) == [])
        #expect(story.send(.cancel) == [])
        #expect(story.phase == .bar)
    }

    /// A tap while the field is shrinking back takes it over from there,
    /// and the interrupted close's landing no longer counts.
    @Test func aTapMidCloseReopensAndTheOldLandingIsIgnored() {
        let story = Story()
        story.send(.tap(collapsed: false))
        story.send(.cancel)
        #expect(story.send(.tap(collapsed: false)) == [.showField])
        #expect(story.send(.landed(1)) == [])
        #expect(story.phase == .field)

        #expect(story.send(.go) == [.showBar(2)])
        #expect(story.send(.landed(1)) == [])
        #expect(story.phase == .closing)
        #expect(story.send(.landed(2)) == [])
        #expect(story.phase == .bar)
    }

    @Test func openingAnOpenFieldDoesNothing() {
        let story = Story()
        story.send(.open)
        #expect(story.send(.open) == [])
        #expect(story.send(.tap(collapsed: false)) == [])
        #expect(story.phase == .field)
    }

    /// One flow, told one thing after another.
    private final class Story {
        private var flow = FieldFlow()
        var phase: FieldFlow.Phase { flow.phase }

        @discardableResult
        func send(_ event: FieldFlow.Event) -> [FieldFlow.Effect] {
            flow.handle(event)
        }
    }
}
