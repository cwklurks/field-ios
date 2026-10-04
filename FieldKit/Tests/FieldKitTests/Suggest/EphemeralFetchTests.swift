#if os(macOS)
import Foundation
import Testing
@testable import FieldKit

/// A real loopback server sees headers added by URLSession, which a
/// URLRequest assertion alone cannot see. It never contacts an engine.
@MainActor struct EphemeralFetchTests {
    @Test func privacyAndResponseLimitsOnTheWire() async throws {
        let server = Process()
        let output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", #"""
import http.server, json
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/headers')
            self.end_headers()
            return
        self.send_response(200)
        self.end_headers()
        body = b'x' * 70000 if self.path == '/large' else json.dumps(dict(self.headers)).encode()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
"""#]
        server.standardOutput = output
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data([10]) {
            line.append(byte)
        }
        let port = try #require(Int(String(decoding: line, as: UTF8.self)))
        let base = URL(string: "http://127.0.0.1:\(port)")!
        let fetch = EphemeralFetch()
        let data = try await fetch.data(for: base.appendingPathComponent("headers"))
        let headers = try JSONDecoder().decode([String: String].self, from: data)
        let lower = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(lower["user-agent"] == "Mozilla/5.0")
        #expect(lower["accept-language"] == "en")
        #expect(lower["cookie"] == nil)
        #expect(lower["referer"] == nil)
        #expect(lower["authorization"] == nil)
        #expect(Set(lower.keys).isSubset(of: ["host", "accept", "accept-language", "accept-encoding",
                                             "user-agent", "connection", "cache-control", "pragma"]))
        await #expect(throws: URLError.self) { try await fetch.data(for: base.appendingPathComponent("redirect")) }
        await #expect(throws: URLError.self) { try await fetch.data(for: base.appendingPathComponent("large")) }
    }
}
#endif
