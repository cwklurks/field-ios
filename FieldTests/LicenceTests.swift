import Foundation
import Testing
@testable import Field

/// Settings › About's licences: each is in the app, whole, and reads the
/// same once reflowed for the phone.
struct LicenceTests {
    @Test(arguments: Licence.allCases)
    func eachLicenceIsBundled(_ licence: Licence) throws {
        let url = try #require(licence.url, "\(licence.resource.name) isn't in the app")
        #expect(try Data(contentsOf: url).count > 1_000)
        #expect(!licence.text().isEmpty)
    }

    @Test func theNoticeIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "NOTICE", withExtension: "md"))
        #expect(try Data(contentsOf: url).count > 1_000)
    }

    /// Only spacing changes, and the asterisks of the MPL's box.
    @Test(arguments: Licence.allCases)
    func reflowingKeepsEveryWordInOrder(_ licence: Licence) throws {
        let file = try String(contentsOf: try #require(licence.url), encoding: .utf8)
        let words = { (text: String) in
            text.split(whereSeparator: \.isWhitespace).filter { !$0.allSatisfy { $0 == "*" } }
        }
        #expect(words(Licence.reflow(file)) == words(file))
    }

    @Test func reflowingJoinsAParagraphButKeepsItemsAndRulesApart() {
        let file = """
        1. Definitions
        --------------

        1.1. "Contributor"
            means each individual
            or legal entity.
         a. one
            more
         b. two
        """
        #expect(Licence.reflow(file) == """
        1. Definitions
        --------------

        1.1. "Contributor" means each individual or legal entity.
        a. one more
        b. two
        """)
    }
}
