import Foundation

enum StreamURLIssue: LocalizedError, Equatable, Sendable {
    case empty
    case malformed
    case missingHost
    case unsupportedScheme(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "No stream address was provided."
        case .malformed: return "The stream address is not a valid URL."
        case .missingHost: return "The stream address has no server name."
        case .unsupportedScheme(let scheme):
            return "“\(scheme)” streams are not supported. World TV plays HTTP(S) HLS and MP4 streams."
        }
    }
}

enum StreamKind: String, Sendable {
    case hls, mp4, other
}

/// Validates stream URLs and performs lightweight availability checks.
/// A check downloads at most a few kilobytes (the HLS manifest or the first
/// bytes of a file) — never the stream itself.
struct StreamValidator: Sendable {
    let client: HTTPClient
    var timeout: TimeInterval = 10
    var maxProbeBytes = 64 * 1024
    var maxConcurrentChecks = 8

    static let supportedSchemes: Set<String> = ["http", "https"]

    /// Static validation: parses and checks scheme and host.
    static func validate(_ raw: String) -> Result<URL, StreamURLIssue> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let components = URLComponents(string: trimmed), let url = components.url,
              let scheme = components.scheme?.lowercased() else {
            return .failure(.malformed)
        }
        guard supportedSchemes.contains(scheme) else { return .failure(.unsupportedScheme(scheme)) }
        guard let host = components.host, !host.isEmpty else { return .failure(.missingHost) }
        return .success(url)
    }

    static func kind(of url: URL) -> StreamKind {
        let path = url.path.lowercased()
        if path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") || url.absoluteString.lowercased().contains("m3u8") {
            return .hls
        }
        if path.hasSuffix(".mp4") || path.hasSuffix(".m4v") || path.hasSuffix(".mov") { return .mp4 }
        return .other
    }

    /// Checks whether a stream currently responds with playable content.
    func check(_ stream: StreamSource, now: Date = Date()) async -> StreamHealth {
        switch Self.validate(stream.url.absoluteString) {
        case .failure(let issue):
            return .unreachable(reason: issue.localizedDescription, checkedAt: now)
        case .success(let url):
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = "GET"
            if Self.kind(of: url) != .hls { request.setValue("bytes=0-\(maxProbeBytes - 1)", forHTTPHeaderField: "Range") }
            if let referrer = stream.referrer { request.setValue(referrer, forHTTPHeaderField: "Referer") }
            if let agent = stream.userAgent { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
            do {
                let (body, response) = try await client.prefix(for: request, maxBytes: maxProbeBytes)
                return evaluate(url: url, status: response.statusCode, body: body, now: now)
            } catch {
                let networkError = NetworkError.from(error)
                return .unreachable(reason: networkError.localizedDescription, checkedAt: now)
            }
        }
    }

    func evaluate(url: URL, status: Int, body: Data, now: Date) -> StreamHealth {
        switch status {
        case 200...299:
            if Self.kind(of: url) == .hls {
                let head = String(decoding: body.prefix(1024), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
                guard head.hasPrefix("#EXTM3U") else {
                    return .unreachable(reason: "The server did not return an HLS playlist.", checkedAt: now)
                }
            }
            return .ok(checkedAt: now)
        case 401, 403:
            return .unreachable(reason: "Access denied (HTTP \(status)). The stream may be geo-blocked.", checkedAt: now)
        case 404, 410:
            return .unreachable(reason: "The stream no longer exists (HTTP \(status)).", checkedAt: now)
        default:
            return .unreachable(reason: NetworkError.httpStatus(status).localizedDescription, checkedAt: now)
        }
    }

    /// Checks many streams with bounded concurrency. Reports progress as (done, total).
    func checkAll(_ streams: [StreamSource],
                  progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: StreamHealth] {
        var results: [String: StreamHealth] = [:]
        let total = streams.count
        guard total > 0 else { return results }
        let limit = max(1, maxConcurrentChecks)
        await withTaskGroup(of: (String, StreamHealth).self) { group in
            var iterator = streams.makeIterator()
            var inFlight = 0
            while inFlight < limit, let stream = iterator.next() {
                group.addTask { (stream.url.absoluteString, await self.check(stream)) }
                inFlight += 1
            }
            while let (key, health) = await group.next() {
                results[key] = health
                progress?(results.count, total)
                if Task.isCancelled { group.cancelAll(); break }
                if let stream = iterator.next() {
                    group.addTask { (stream.url.absoluteString, await self.check(stream)) }
                }
            }
        }
        return results
    }
}
