import Foundation
import Testing
@testable import FieldKit

// Pinned against the Mac's Address.swift, run as it ships. Every expected
// value is what Search itself returns for the same input, except the cases
// marked "Unlike the Mac", where Field differs on purpose.
struct AddressTests {
    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("sub.example.co.uk", "https://sub.example.co.uk"),
        ("example.com/path?q=1#x", "https://example.com/path?q=1#x"),
        ("example.com:8080/a", "https://example.com:8080/a"),
        ("café.fr", "https://xn--caf-dma.fr"),
        ("xn--caf-dma.fr", "https://xn--caf-dma.fr"),
        ("8.8.8.8", "https://8.8.8.8"),
        ("172.32.0.1", "https://172.32.0.1"),
        // Unlike the Mac, which gave these plain http for starting like a
        // local network's numbers.
        ("10.tv", "https://10.tv"),
        ("192.168.evil.com", "https://192.168.evil.com"),
        // Unlike the Mac, which took everything before the first :// for a
        // scheme and refused these.
        ("web.archive.org/web/2020/https://example.com", "https://web.archive.org/web/2020/https://example.com"),
        ("example.com/?next=https://x.com", "https://example.com/?next=https://x.com"),
    ])
    func aHostGetsHTTPS(typed: String, expected: String) {
        #expect(Address.url(from: typed)?.absoluteString == expected)
    }

    @Test(arguments: [
        ("localhost", "http://localhost"),
        ("localhost:3000", "http://localhost:3000"),
        ("localhost/x", "http://localhost/x"),
        ("foo.localhost", "http://foo.localhost"),
        ("127.0.0.1:8080", "http://127.0.0.1:8080"),
        ("0.0.0.0", "http://0.0.0.0"),
        ("192.168.1.1", "http://192.168.1.1"),
        ("192.168.1.1/admin", "http://192.168.1.1/admin"),
        ("10.0.0.1", "http://10.0.0.1"),
        // Unlike the Mac, which refused this for the :// in its query.
        ("localhost:3000/x?u=http://y", "http://localhost:3000/x?u=http://y"),
        // Unlike the Mac, which gave these https.
        ("127.0.0.2", "http://127.0.0.2"),
        ("172.16.0.1", "http://172.16.0.1"),
        ("172.31.255.255", "http://172.31.255.255"),
        ("169.254.1.1", "http://169.254.1.1"),
        ("printer.local", "http://printer.local"),
        ("printer.local:631", "http://printer.local:631"),
    ])
    func aLocalHostGetsHTTP(typed: String, expected: String) {
        #expect(Address.url(from: typed)?.absoluteString == expected)
    }

    // Field's own: one answer for the field and the history alike. Names
    // for this machine and its network, and the loopback and private ranges
    // written as numbers.
    @Test(arguments: [
        "localhost", "LOCALHOST", "dev.localhost", "printer.local", "Printer.Local",
        "127.0.0.1", "127.1.2.3", "0.0.0.0", "10.1.2.3", "172.16.0.1", "172.31.255.255",
        "192.168.0.1", "169.254.10.20",
        "::1", "[::1]", "fc00::1", "fd12:3456::1", "fe80::1", "FE80::1", "febf::1", "[fe80::1]", "fe80::1%25en0",
    ])
    func local(host: String) {
        #expect(Address.isLocal(host: host))
    }

    @Test(arguments: [
        "example.com", "10.tv", "192.168.evil.com", "local", "notlocalhost",
        "example.local.com", "1.2.3", "256.1.1.1", "1.2.3.4.5",
        "8.8.8.8", "11.0.0.1", "172.15.255.255", "172.32.0.1", "192.169.0.1", "169.253.0.1",
        "2001:db8::1", "[2001:db8::1]", "::2", "fe00::1", "fec0::1", "fbff::1",
    ])
    func notLocal(host: String) {
        #expect(!Address.isLocal(host: host))
    }

    @Test(arguments: [
        ("https://x.y/path", "https://x.y/path"),
        ("HTTPS://Example.com", "HTTPS://Example.com"),
        ("http://[::1]:8080/", "http://[::1]:8080/"),
        ("file:///Users/x", "file:///Users/x"),
        ("about:blank", "about:blank"),
        ("About:Blank", "About:Blank"),
        ("data:text/plain,hi", "data:text/plain,hi"),
    ])
    func aSchemeIsTakenAtItsWord(typed: String, expected: String) {
        #expect(Address.url(from: typed)?.absoluteString == expected)
    }

    @Test(arguments: [
        "", "   ",
        "foo bar", "what is x.y", "example.com?q=a b",
        "todo",
        "1.2.3", "v1.2", "a.b", "example.c0m",
        "256.1.1.1", "1.2.3.4.5",
        "-foo.com", "foo-.com", "example..com", "example.com.", "my_site.com",
        "example.com:abc",
        "mailto:x@y.com", "user@example.com", "ftp://x.com",
        // An IPv6 literal is only understood with a scheme in front of it.
        "[::1]", "[::1]:8080",
    ])
    func notAPlace(typed: String) {
        #expect(Address.url(from: typed) == nil)
    }

    @Test func surroundingSpaceIsIgnored() {
        #expect(Address.url(from: "  example.com  ")?.absoluteString == "https://example.com")
        #expect(Address.url(from: "example.com\n")?.absoluteString == "https://example.com")
    }

    @Test func caseIsKeptAsTyped() {
        #expect(Address.url(from: "EXAMPLE.COM")?.absoluteString == "https://EXAMPLE.COM")
    }

    @Test(arguments: [
        ("https://www.example.com/", "example.com"),
        ("https://www.example.com", "example.com"),
        ("https://example.com/a/b?q=1#f", "example.com/a/b"),
        ("https://example.com/?q=1", "example.com"),
        ("https://example.com/#top", "example.com"),
        ("https://example.com/a%20b", "example.com/a%20b"),
        ("http://localhost:3000/", "localhost"),
        ("http://localhost:3000/x", "localhost/x"),
        ("http://[::1]:8080/p", "::1/p"),
        ("https://www.www.example.com/", "www.example.com"),
        ("https://wwwexample.com/", "wwwexample.com"),
        // Only a lowercase www is taken off; WebKit hands hosts over lowercased.
        ("https://WWW.Example.COM/Path", "WWW.Example.COM/Path"),
        // No host: the whole address.
        ("file:///Users/x/a.html", "file:///Users/x/a.html"),
        ("about:blank", "about:blank"),
        ("data:text/plain,hi", "data:text/plain,hi"),
    ])
    func pretty(address: String, expected: String) throws {
        let url = try #require(URL(string: address))
        #expect(Address.pretty(url) == expected)
    }
}
