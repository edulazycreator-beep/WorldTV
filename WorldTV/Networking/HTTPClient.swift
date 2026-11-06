import Foundation

enum NetworkError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case unsupportedScheme(String)
    case httpStatus(Int)
    case timedOut
    case offline
    case cancelled
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid address: \(value)"
        case .unsupportedScheme(let scheme): return "Unsupported address type “\(scheme)”."
        case .httpStatus(let code):
            return "The server responded with HTTP \(code) (\(HTTPURLResponse.localizedString(forStatusCode: code)))."
        case .timedOut: return "The connection timed out."
        case .offline: return "You appear to be offline."
        case .cancelled: return "The request was cancelled."
        case .decoding(let detail): return "The data could not be read: \(detail)"
        case .transport(let detail): return detail
        }
    }

    /// Whether repeating the same request might succeed.
    var isRetryable: Bool {
        switch self {
        case .timedOut, .transport: return true
        case .httpStatus(let code): return code == 408 || code == 429 || (500...599).contains(code)
        default: return false
        }
    }

    static func from(_ error: Error) -> NetworkError {
        if let error = error as? NetworkError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timedOut
            case .notConnectedToInternet, .dataNotAllowed: return .offline
            case .cancelled: return .cancelled
            case .badURL, .unsupportedURL: return .invalidURL(urlError.failingURL?.absoluteString ?? "")
            default: return .transport(urlError.localizedDescription)
            }
        }
        return .transport(error.localizedDescription)
    }
}

struct RetryPolicy: Sendable, Equatable {
    var maxAttempts: Int
    var baseDelay: TimeInterval
    var maxDelay: TimeInterval

    static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 8)
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)

    /// Exponential backoff for the given 1-based attempt that just failed.
    func delay(afterAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let exponential = baseDelay * pow(2, Double(attempt - 1))
        return min(maxDelay, exponential)
    }
}

/// Abstraction over URLSession so services can be unit-tested with a mock.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Reads at most `maxBytes` of the body and then cancels the transfer.
    /// Used for health checks so live streams are never downloaded in full.
    func prefix(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse)
}

extension HTTPClient {
    func get(_ url: URL, timeout: TimeInterval = 20, headers: [String: String] = [:],
             retry: RetryPolicy = .standard) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request, retry: retry).0
    }

    /// Sends a request, retrying transient failures with exponential backoff.
    func send(_ request: URLRequest, retry: RetryPolicy) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            do {
                try Task.checkCancellation()
                let (body, response) = try await self.data(for: request)
                guard (200...299).contains(response.statusCode) else {
                    throw NetworkError.httpStatus(response.statusCode)
                }
                return (body, response)
            } catch {
                let networkError = NetworkError.from(error)
                guard networkError.isRetryable, attempt < max(1, retry.maxAttempts) else {
                    throw networkError
                }
                let delay = retry.delay(afterAttempt: attempt)
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            }
        }
    }
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = URLSessionHTTPClient.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "WorldTV/1.0 (macOS)"]
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                          diskCapacity: 256 * 1024 * 1024)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.transport("Non-HTTP response")
        }
        return (data, http)
    }

    func prefix(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw NetworkError.transport("Non-HTTP response")
        }
        var buffer = Data()
        buffer.reserveCapacity(min(maxBytes, 64 * 1024))
        if (200...299).contains(http.statusCode) {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= maxBytes { break }
            }
        }
        bytes.task.cancel()
        return (buffer, http)
    }
}
