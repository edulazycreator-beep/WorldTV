import XCTest
@testable import WorldTV

final class URLValidationTests: XCTestCase {
    func testAcceptsHTTPAndHTTPS() {
        XCTAssertNoThrow(try StreamValidator.validate("https://a.example/live.m3u8").get())
        XCTAssertNoThrow(try StreamValidator.validate("  http://a.example:8080/x.ts  ").get())
    }

    func testRejectsInvalidAddresses() {
        XCTAssertEqual(issue(""), .empty)
        XCTAssertEqual(issue("   "), .empty)
        XCTAssertEqual(issue("rtmp://a.example/live"), .unsupportedScheme("rtmp"))
        XCTAssertEqual(issue("ftp://a.example/file"), .unsupportedScheme("ftp"))
        XCTAssertEqual(issue("https:///nohost.m3u8"), .missingHost)
        XCTAssertEqual(issue("just some words"), .malformed)
    }

    func testStreamKindDetection() {
        XCTAssertEqual(StreamValidator.kind(of: URL(string: "https://a.example/x/index.m3u8?token=1")!), .hls)
        XCTAssertEqual(StreamValidator.kind(of: URL(string: "https://a.example/clip.mp4")!), .mp4)
        XCTAssertEqual(StreamValidator.kind(of: URL(string: "https://a.example/live.ts")!), .other)
    }

    private func issue(_ raw: String) -> StreamURLIssue? {
        if case .failure(let issue) = StreamValidator.validate(raw) { return issue }
        return nil
    }
}

final class StreamHealthTests: XCTestCase {
    private func stream(_ url: String, referrer: String? = nil) -> StreamSource {
        StreamSource(url: URL(string: url)!, referrer: referrer, userAgent: referrer == nil ? nil : "Agent/1")
    }

    func testHealthyHLSManifest() async {
        let client = MockHTTPClient { _ in (200, Data("#EXTM3U\n#EXT-X-VERSION:3\n".utf8)) }
        let health = await StreamValidator(client: client).check(stream("https://a.example/live.m3u8"))
        guard case .ok = health else { return XCTFail("expected ok, got \(health)") }
    }

    func testHLSURLReturningHTMLIsUnreachable() async {
        let client = MockHTTPClient { _ in (200, Data("<html>Login</html>".utf8)) }
        let health = await StreamValidator(client: client).check(stream("https://a.example/live.m3u8"))
        XCTAssertTrue(health.isUnreachable)
    }

    func testForbiddenIsReportedAsGeoBlockHint() async {
        let client = MockHTTPClient { _ in (403, Data()) }
        let health = await StreamValidator(client: client).check(stream("https://a.example/live.m3u8"))
        guard case .unreachable(let reason, _) = health else { return XCTFail("expected unreachable") }
        XCTAssertTrue(reason.contains("geo-blocked"))
    }

    func testNotFoundAndServerErrors() async {
        for status in [404, 500] {
            let client = MockHTTPClient { _ in (status, Data()) }
            let health = await StreamValidator(client: client).check(stream("https://a.example/live.m3u8"))
            XCTAssertTrue(health.isUnreachable, "status \(status)")
        }
    }

    func testTimeoutIsUnreachable() async {
        let client = MockHTTPClient { _ in throw URLError(.timedOut) }
        let health = await StreamValidator(client: client).check(stream("https://a.example/live.m3u8"))
        guard case .unreachable(let reason, _) = health else { return XCTFail("expected unreachable") }
        XCTAssertEqual(reason, NetworkError.timedOut.localizedDescription)
    }

    func testUnsupportedSchemeFailsWithoutNetwork() async {
        let client = MockHTTPClient { _ in (200, Data()) }
        let health = await StreamValidator(client: client).check(stream("rtmp://a.example/live"))
        XCTAssertTrue(health.isUnreachable)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testNonHLSUsesRangeRequestAndSendsHeaders() async {
        let client = MockHTTPClient { _ in (206, Data(repeating: 0, count: 10)) }
        let health = await StreamValidator(client: client).check(stream("https://a.example/video.mp4", referrer: "https://ref.example"))
        guard case .ok = health else { return XCTFail("expected ok") }
        let request = client.requests.first
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Range"), "bytes=0-65535")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Referer"), "https://ref.example")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "Agent/1")
    }

    func testProbeNeverReadsMoreThanLimit() async {
        let client = MockHTTPClient { _ in (200, Data(repeating: 1, count: 1_000_000)) }
        var validator = StreamValidator(client: client)
        validator.maxProbeBytes = 1024
        let (data, _) = try! await client.prefix(for: URLRequest(url: URL(string: "https://a.example/x.ts")!),
                                                 maxBytes: validator.maxProbeBytes)
        XCTAssertEqual(data.count, 1024)
    }

    func testCheckAllRespectsConcurrencyAndReportsEveryStream() async {
        let client = MockHTTPClient { request in
            request.url!.path.contains("bad") ? (404, Data()) : (200, Data("#EXTM3U".utf8))
        }
        var validator = StreamValidator(client: client)
        validator.maxConcurrentChecks = 3
        let streams = (0..<10).map { stream("https://a.example/\($0 % 3 == 0 ? "bad" : "ok")\($0).m3u8") }
        let results = await validator.checkAll(streams)
        XCTAssertEqual(results.count, 10)
        XCTAssertEqual(results.values.filter(\.isUnreachable).count, 4) // 0, 3, 6, 9
    }
}

final class HTTPClientRetryTests: XCTestCase {
    func testRetriesTransientFailuresThenSucceeds() async throws {
        var calls = 0
        let lock = NSLock()
        let client = MockHTTPClient { _ in
            lock.lock(); calls += 1; let attempt = calls; lock.unlock()
            if attempt < 3 { return (503, Data()) }
            return (200, Data("ok".utf8))
        }
        let data = try await client.get(URL(string: "https://a.example")!,
                                        retry: RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(client.requests.count, 3)
    }

    func testDoesNotRetryClientErrors() async {
        let client = MockHTTPClient { _ in (404, Data()) }
        do {
            _ = try await client.get(URL(string: "https://a.example")!,
                                     retry: RetryPolicy(maxAttempts: 5, baseDelay: 0, maxDelay: 0))
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NetworkError, .httpStatus(404))
            XCTAssertEqual(client.requests.count, 1)
        }
    }

    func testGivesUpAfterMaxAttempts() async {
        let client = MockHTTPClient { _ in throw URLError(.timedOut) }
        do {
            _ = try await client.get(URL(string: "https://a.example")!,
                                     retry: RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0))
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NetworkError, .timedOut)
            XCTAssertEqual(client.requests.count, 2)
        }
    }

    func testBackoffIsExponentialAndCapped() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 0.5, maxDelay: 3)
        XCTAssertEqual(policy.delay(afterAttempt: 1), 0.5)
        XCTAssertEqual(policy.delay(afterAttempt: 2), 1.0)
        XCTAssertEqual(policy.delay(afterAttempt: 3), 2.0)
        XCTAssertEqual(policy.delay(afterAttempt: 4), 3.0)
    }

    func testErrorMapping() {
        XCTAssertEqual(NetworkError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(NetworkError.from(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(NetworkError.from(CancellationError()), .cancelled)
        XCTAssertTrue(NetworkError.httpStatus(503).isRetryable)
        XCTAssertFalse(NetworkError.httpStatus(403).isRetryable)
        XCTAssertFalse(NetworkError.offline.isRetryable)
    }
}
