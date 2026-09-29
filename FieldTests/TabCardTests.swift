import Foundation
import Testing
@testable import Field

/// The site's letter beside a card's title: the host's first letter, or
/// nothing when the host doesn't start with one (an address by number).
struct TabCardTests {
    @Test func aNamedHostGivesItsFirstLetter() {
        #expect(TabCard.letter(for: URL(string: "https://www.apple.com")) == "A")
    }

    @Test func anAddressByNumberGivesNone() {
        #expect(TabCard.letter(for: URL(string: "http://127.0.0.1:8080")) == nil)
        #expect(TabCard.letter(for: URL(string: "http://[::1]/")) == nil)
    }

    @Test func noAddressGivesNone() {
        #expect(TabCard.letter(for: nil) == nil)
    }
}
