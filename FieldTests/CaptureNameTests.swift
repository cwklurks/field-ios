import Foundation
import Testing
@testable import Field

/// What a captured page is called in Files, Messages and Photos:
/// `<host> – <title>.<ext>`, safe to be a file name.
struct CaptureNameTests {
    private func name(_ url: String?, _ title: String, _ ext: String = "pdf") -> String {
        CaptureName.file(url: url.flatMap(URL.init(string:)), title: title, extension: ext)
    }

    @Test func hostThenTitle() {
        #expect(name("https://example.com/a", "Example Domain") == "example.com – Example Domain.pdf")
        #expect(name("https://example.com/a", "Example Domain", "png") == "example.com – Example Domain.png")
    }

    /// As the bar shows it.
    @Test func dropsWww() {
        #expect(name("https://www.nytimes.com/", "Today") == "nytimes.com – Today.pdf")
    }

    @Test func noTitleIsTheHostAlone() {
        #expect(name("https://example.com/", "") == "example.com.pdf")
        #expect(name("https://example.com/", "  \n ") == "example.com.pdf")
        #expect(name("https://www.example.com/", "Example.com") == "example.com.pdf")
    }

    @Test func noHostIsPage() {
        #expect(name(nil, "Notes") == "Page – Notes.pdf")
        #expect(name(nil, "") == "Page.pdf")
    }

    /// No slashes (a folder in Files) and no colons (a slash in the Finder).
    @Test func separatorsBecomeDashes() {
        #expect(name("https://a.com/", "AC/DC: Back in Black") == "a.com – AC-DC Back in Black.pdf")
        #expect(name("https://a.com/", "News / World") == "a.com – News - World.pdf")
        #expect(name("https://a.com/", "Opens 12:30") == "a.com – Opens 12-30.pdf")
        #expect(name("https://a.com/", #"Back\Slash"#) == "a.com – Back-Slash.pdf")
    }

    @Test func whitespaceIsOneSpace() {
        #expect(name("https://a.com/", "  Two\n\tlines   here ") == "a.com – Two lines here.pdf")
    }

    @Test func controlCharactersGo() {
        #expect(name("https://a.com/", "Bell\u{7}Ring\u{0}") == "a.com – BellRing.pdf")
    }

    /// Well under the 255 bytes a file name may have, cut between words.
    @Test func longTitlesAreCut() {
        let title = String(repeating: "word ", count: 40)
        let result = name("https://a.com/", title)
        #expect(result.hasPrefix("a.com – word word"))
        #expect(result.hasSuffix("word….pdf"))
        #expect(result.count <= 100)
        #expect(result.utf8.count < 255)
    }

    @Test func aLongWordIsCutMidWord() {
        let result = name("https://a.com/", String(repeating: "x", count: 300))
        #expect(result.hasSuffix("x….pdf"))
        #expect(result.count <= 100)
    }
}
