import Foundation
@testable import WorldTV

/// Scriptable HTTP client for tests. Thread-safe; records every request.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler
    private var _requests: [URLRequest] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func setHandler(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }

    private func respond(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        lock.lock()
        _requests.append(request)
        let handler = self.handler
        lock.unlock()
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (data, response)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try respond(request)
    }

    func prefix(for request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try respond(request)
        return (data.prefix(maxBytes), response)
    }
}

enum TestData {
    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorldTVTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func channel(_ id: String, name: String? = nil, country: String? = "ID",
                        languages: [String] = ["ind"], categories: [String] = ["news"],
                        streams: [StreamSource]? = nil, popularity: Int = 0,
                        firstSeen: Date? = nil) -> Channel {
        Channel(id: id, name: name ?? id, countryCode: country, languages: languages,
                categories: categories,
                streams: streams ?? [StreamSource(url: URL(string: "https://example.com/\(id).m3u8")!, quality: "720p")],
                attribution: "test", popularity: popularity, firstSeen: firstSeen)
    }

    /// Minimal directory payloads in the shape of the iptv-org API.
    static let directoryChannels = """
    [
      {"id":"Alpha.id","name":"Alpha News","alt_names":["Alpha"],"network":null,"owners":[],"country":"ID",
       "categories":["news"],"is_nsfw":false,"launched":null,"closed":null,"replaced_by":null,"website":"https://alpha.example"},
      {"id":"Beta.bn","name":"Beta TV","alt_names":[],"country":"BN","categories":["general"],"is_nsfw":false,
       "closed":null,"website":null},
      {"id":"Closed.us","name":"Closed","alt_names":[],"country":"US","categories":["news"],"is_nsfw":false,
       "closed":"2020-01-01","website":null},
      {"id":"Adult.us","name":"Adult","alt_names":[],"country":"US","categories":[],"is_nsfw":true,"closed":null},
      {"id":"Blocked.us","name":"Blocked","alt_names":[],"country":"US","categories":["movies"],"is_nsfw":false,"closed":null},
      {"id":"NoStream.jp","name":"No Stream","alt_names":[],"country":"JP","categories":["music"],"is_nsfw":false,"closed":null},
      {"broken": true}
    ]
    """

    static let directoryStreams = """
    [
      {"channel":"Alpha.id","feed":null,"title":"Alpha","url":"https://alpha.example/live/720.m3u8","referrer":null,"user_agent":null,"quality":"720p","labels":[]},
      {"channel":"Alpha.id","feed":null,"title":"Alpha HD","url":"https://alpha.example/live/1080.m3u8","quality":"1080p","labels":["Geo-blocked"]},
      {"channel":"Alpha.id","title":"Duplicate","url":"https://alpha.example/live/720.m3u8","quality":"720p","labels":[]},
      {"channel":"Beta.bn","title":"Beta","url":"http://beta.example/stream.m3u8","quality":null,"labels":[]},
      {"channel":"Closed.us","title":"Closed","url":"https://closed.example/a.m3u8","labels":[]},
      {"channel":"Adult.us","title":"Adult","url":"https://adult.example/a.m3u8","labels":[]},
      {"channel":"Blocked.us","title":"Blocked","url":"https://blocked.example/a.m3u8","labels":[]},
      {"channel":"Beta.bn","title":"Bad scheme","url":"rtmp://beta.example/live","labels":[]},
      {"channel":null,"title":"Orphan","url":"https://orphan.example/a.m3u8","labels":[]}
    ]
    """

    static let directoryFeeds = """
    [{"channel":"Alpha.id","id":"SD","name":"SD","alt_names":[],"is_main":true,"broadcast_area":["c/ID"],"timezones":[],"languages":["ind"],"format":"576i"},
     {"channel":"Beta.bn","id":"Main","name":"Main","is_main":true,"languages":["msa","eng"],"format":"1080i"}]
    """

    static let directoryLogos = """
    [{"channel":"Alpha.id","feed":null,"in_use":true,"tags":[],"width":512,"height":512,"format":"PNG","url":"https://logos.example/alpha.png"},
     {"channel":"Alpha.id","feed":"SD","in_use":true,"tags":[],"width":1000,"height":1000,"format":"PNG","url":"https://logos.example/alpha-sd.png"}]
    """

    static let directoryCategories = """
    [{"id":"news","name":"News","description":"x"},{"id":"general","name":"General","description":"x"}]
    """

    static let directoryLanguages = """
    [{"code":"ind","name":"Indonesian"},{"code":"msa","name":"Malay"},{"code":"eng","name":"English"}]
    """

    static let directoryCountries = """
    [{"name":"Indonesia","code":"ID","languages":["ind"],"flag":"🇮🇩"},
     {"name":"Brunei","code":"BN","languages":["msa"],"flag":"🇧🇳"},
     {"name":"United States","code":"US","languages":["eng"],"flag":"🇺🇸"}]
    """

    static let directoryBlocklist = """
    [{"channel":"Blocked.us","reason":"dmca","ref":"https://example.com"}]
    """

    static func directoryRaw() -> [DirectoryAPI.Resource: Data] {
        [
            .channels: Data(directoryChannels.utf8),
            .streams: Data(directoryStreams.utf8),
            .feeds: Data(directoryFeeds.utf8),
            .logos: Data(directoryLogos.utf8),
            .categories: Data(directoryCategories.utf8),
            .languages: Data(directoryLanguages.utf8),
            .countries: Data(directoryCountries.utf8),
            .blocklist: Data(directoryBlocklist.utf8),
        ]
    }

    /// gzip of a one-programme XMLTV document ("Compressed Hour" on Gz.tv).
    static let gzippedGuide = Data(base64Encoded:
        "H4sIAAAAAAAC/1WOzQrCMBCEXyXkKm3SHrTCNj0I1geo3kMTNJA/khi0T2/FonUPyzIfOzPQPYxGWYaonG1xVVKMpB2dUPba4vNwLBrcMUiZwXjj1kqNlGhxP5UpYwZCRa/5s7DcSNZPyqPhAuRPBbI8MvDBXQM3RqKYeEgtrmm9rSq6ow2dB23eG8/Q+RXbr9ni9WuQVNKSHZzxQcYoBTq5ewDykYF8I+c7ZfYCdMgmHO8AAAA=")!
}
