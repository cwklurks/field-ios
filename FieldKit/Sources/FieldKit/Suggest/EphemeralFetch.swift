import Foundation

/// A session that keeps nothing: no cookies sent or taken, no cache, no
/// stored credentials, and not long to wait. URLSession sends no referrer of
/// its own, and the request says it has no cookies to handle.
public struct EphemeralFetch: SuggestFetching {
    public static let shared = EphemeralFetch()

    private let session: URLSession

    public init() {
        session = URLSession(configuration: Self.configuration(), delegate: NoRedirects(), delegateQueue: nil)
    }

    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json, text/javascript"]
        return config
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        // Fixed values disclose neither the app nor the preferred-language list.
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    public func data(for url: URL) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: Self.request(for: url))
        defer { bytes.task.cancel() }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard response.expectedContentLength <= SuggestResponse.largest else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < SuggestResponse.largest else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

/// An endpoint may fail, but cannot forward typed words to another server.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
