import Foundation
import Network

/// A long article served by the test runner itself, so the scroll test needs
/// no internet. The server listens on 127.0.0.1 only: on the simulator the
/// runner and the app are both Mac processes, and on a device both are
/// iPhone processes, so either way they share one loopback interface.
/// Loopback is exempt from local network privacy, so nothing asks permission.
///
/// If the server can't start or doesn't answer its own request, `url` is the
/// same page as a `data:` URL instead. Its figures don't load then, but they
/// keep their size, so the page is just as long.
final class Fixture: Sendable {
    let url: URL
    private let listener: NWListener?

    private init(url: URL, listener: NWListener?) {
        self.url = url
        self.listener = listener
    }

    static func start() async -> Fixture {
        if let listener = try? await listen(), let port = listener.port?.rawValue,
           let url = URL(string: "http://127.0.0.1:\(port)/article"),
           (try? await URLSession.shared.data(from: url)) != nil {
            return Fixture(url: url, listener: listener)
        }
        let data = Data(Article.html.utf8).base64EncodedString()
        return Fixture(url: URL(string: "data:text/html;charset=utf-8;base64,\(data)")!, listener: nil)
    }

    func stop() {
        listener?.cancel()
    }

    private static let queue = DispatchQueue(label: "com.connork.field.perftests.fixture")

    private static func listen() async throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: listener) }
                case .failed(let error), .waiting(let error):
                    once.run { continuation.resume(throwing: error) }
                    listener.cancel()
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Reads until the end of the request's headers, then answers and closes.
    private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let path = head.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
                respond(on: connection, path: path)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private static func respond(on connection: NWConnection, path: String) {
        let (status, type, body): (String, String, Data) = switch path {
        case "/article": ("200 OK", "text/html; charset=utf-8", Data(Article.html.utf8))
        case let path where path.hasPrefix("/figure/"):
            ("200 OK", "image/svg+xml", Data(Article.svg(Int(path.dropFirst(8).prefix { $0.isNumber }) ?? 0).utf8))
        default: ("404 Not Found", "text/plain", Data("Not found".utf8))
        }
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Resumes a continuation once, whichever listener state comes first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
