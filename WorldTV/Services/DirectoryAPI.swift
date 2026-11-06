import Foundation

/// Data transfer objects for the public iptv-org API
/// (https://github.com/iptv-org/api). All decoding is lenient: unknown
/// fields are ignored and missing optional fields fall back to defaults,
/// so upstream schema additions never break the app.
enum DirectoryDTO {
    struct Channel: Decodable, Sendable {
        var id: String
        var name: String
        var altNames: [String]
        var country: String?
        var categories: [String]
        var isNSFW: Bool
        var closed: String?
        var replacedBy: String?
        var website: String?
        var launched: String?

        enum CodingKeys: String, CodingKey {
            case id, name, country, categories, closed, website, launched
            case altNames = "alt_names"
            case isNSFW = "is_nsfw"
            case replacedBy = "replaced_by"
        }

        init(id: String, name: String, altNames: [String] = [], country: String? = nil,
             categories: [String] = [], isNSFW: Bool = false, closed: String? = nil,
             replacedBy: String? = nil, website: String? = nil, launched: String? = nil) {
            self.id = id; self.name = name; self.altNames = altNames; self.country = country
            self.categories = categories; self.isNSFW = isNSFW; self.closed = closed
            self.replacedBy = replacedBy; self.website = website; self.launched = launched
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = (try? c.decode(String.self, forKey: .name)) ?? id
            altNames = (try? c.decode([String].self, forKey: .altNames)) ?? []
            country = try? c.decode(String.self, forKey: .country)
            categories = (try? c.decode([String].self, forKey: .categories)) ?? []
            isNSFW = (try? c.decode(Bool.self, forKey: .isNSFW)) ?? false
            closed = try? c.decode(String.self, forKey: .closed)
            replacedBy = try? c.decode(String.self, forKey: .replacedBy)
            website = try? c.decode(String.self, forKey: .website)
            launched = try? c.decode(String.self, forKey: .launched)
        }
    }

    struct Feed: Decodable, Sendable {
        var channel: String
        var id: String
        var isMain: Bool
        var languages: [String]

        enum CodingKeys: String, CodingKey {
            case channel, id, languages
            case isMain = "is_main"
        }

        init(channel: String, id: String, isMain: Bool = true, languages: [String] = []) {
            self.channel = channel; self.id = id; self.isMain = isMain; self.languages = languages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            channel = try c.decode(String.self, forKey: .channel)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            isMain = (try? c.decode(Bool.self, forKey: .isMain)) ?? false
            languages = (try? c.decode([String].self, forKey: .languages)) ?? []
        }
    }

    struct Logo: Decodable, Sendable {
        var channel: String
        var feed: String?
        var inUse: Bool
        var width: Double
        var url: String

        enum CodingKeys: String, CodingKey {
            case channel, feed, width, url
            case inUse = "in_use"
        }

        init(channel: String, feed: String? = nil, inUse: Bool = true, width: Double = 0, url: String) {
            self.channel = channel; self.feed = feed; self.inUse = inUse; self.width = width; self.url = url
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            channel = try c.decode(String.self, forKey: .channel)
            feed = try? c.decode(String.self, forKey: .feed)
            inUse = (try? c.decode(Bool.self, forKey: .inUse)) ?? true
            width = (try? c.decode(Double.self, forKey: .width)) ?? 0
            url = try c.decode(String.self, forKey: .url)
        }
    }

    struct Stream: Decodable, Sendable {
        var channel: String?
        var feed: String?
        var title: String?
        var url: String
        var referrer: String?
        var userAgent: String?
        var quality: String?
        var labels: [String]

        enum CodingKeys: String, CodingKey {
            case channel, feed, title, url, referrer, quality, labels
            case userAgent = "user_agent"
        }

        init(channel: String?, feed: String? = nil, title: String? = nil, url: String,
             referrer: String? = nil, userAgent: String? = nil, quality: String? = nil, labels: [String] = []) {
            self.channel = channel; self.feed = feed; self.title = title; self.url = url
            self.referrer = referrer; self.userAgent = userAgent; self.quality = quality; self.labels = labels
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            channel = try? c.decode(String.self, forKey: .channel)
            feed = try? c.decode(String.self, forKey: .feed)
            title = try? c.decode(String.self, forKey: .title)
            url = try c.decode(String.self, forKey: .url)
            referrer = try? c.decode(String.self, forKey: .referrer)
            userAgent = try? c.decode(String.self, forKey: .userAgent)
            quality = try? c.decode(String.self, forKey: .quality)
            labels = (try? c.decode([String].self, forKey: .labels)) ?? []
        }
    }

    struct Category: Decodable, Sendable {
        var id: String
        var name: String
    }

    struct Language: Decodable, Sendable {
        var code: String
        var name: String
    }

    struct Country: Decodable, Sendable {
        var code: String
        var name: String
        var flag: String?
        var languages: [String]

        init(code: String, name: String, flag: String? = nil, languages: [String] = []) {
            self.code = code; self.name = name; self.flag = flag; self.languages = languages
        }

        enum CodingKeys: String, CodingKey { case code, name, flag, languages }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            name = (try? c.decode(String.self, forKey: .name)) ?? code
            flag = try? c.decode(String.self, forKey: .flag)
            languages = (try? c.decode([String].self, forKey: .languages)) ?? []
        }
    }

    struct BlocklistEntry: Decodable, Sendable {
        var channel: String
        var reason: String?
    }
}

/// The raw directory files, fetched together and cached on disk as-is.
struct DirectorySnapshot: Sendable {
    var channels: [DirectoryDTO.Channel]
    var feeds: [DirectoryDTO.Feed]
    var logos: [DirectoryDTO.Logo]
    var streams: [DirectoryDTO.Stream]
    var categories: [DirectoryDTO.Category]
    var languages: [DirectoryDTO.Language]
    var countries: [DirectoryDTO.Country]
    var blocklist: [DirectoryDTO.BlocklistEntry]
    var fetchedAt: Date
}

/// Downloads the public directory. The base URL is configurable so a mirror
/// or self-hosted copy can be used without a new app release.
struct DirectoryAPI: Sendable {
    static let defaultBaseURL = URL(string: "https://iptv-org.github.io/api/")!

    enum Resource: String, CaseIterable, Sendable {
        case channels, feeds, logos, streams, categories, languages, countries, blocklist
        var fileName: String { "\(rawValue).json" }
        /// Files the app cannot work without.
        var isRequired: Bool { self == .channels || self == .streams }
    }

    let client: HTTPClient
    var baseURL: URL = DirectoryAPI.defaultBaseURL
    var timeout: TimeInterval = 30
    var retry: RetryPolicy = .standard

    func url(for resource: Resource) -> URL {
        baseURL.appendingPathComponent(resource.fileName)
    }

    /// Downloads every resource concurrently and returns the raw bytes.
    func fetchRaw() async throws -> [Resource: Data] {
        try await withThrowingTaskGroup(of: (Resource, Data?).self) { group in
            for resource in Resource.allCases {
                group.addTask {
                    do {
                        let data = try await client.get(url(for: resource), timeout: timeout, retry: retry)
                        return (resource, data)
                    } catch {
                        if resource.isRequired { throw error }
                        return (resource, nil) // optional resource: degrade gracefully
                    }
                }
            }
            var result: [Resource: Data] = [:]
            for try await (resource, data) in group {
                if let data { result[resource] = data }
            }
            return result
        }
    }

    static func decode(_ raw: [Resource: Data], fetchedAt: Date) throws -> DirectorySnapshot {
        let decoder = JSONDecoder()
        func list<T: Decodable>(_ type: T.Type, _ resource: Resource) throws -> [T] {
            guard let data = raw[resource] else {
                if resource.isRequired { throw NetworkError.decoding("\(resource.fileName) is missing") }
                return []
            }
            do {
                return try decoder.decode(LenientArray<T>.self, from: data).elements
            } catch {
                if resource.isRequired { throw NetworkError.decoding("\(resource.fileName): \(error.localizedDescription)") }
                return []
            }
        }
        return DirectorySnapshot(
            channels: try list(DirectoryDTO.Channel.self, .channels),
            feeds: try list(DirectoryDTO.Feed.self, .feeds),
            logos: try list(DirectoryDTO.Logo.self, .logos),
            streams: try list(DirectoryDTO.Stream.self, .streams),
            categories: try list(DirectoryDTO.Category.self, .categories),
            languages: try list(DirectoryDTO.Language.self, .languages),
            countries: try list(DirectoryDTO.Country.self, .countries),
            blocklist: try list(DirectoryDTO.BlocklistEntry.self, .blocklist),
            fetchedAt: fetchedAt
        )
    }
}

/// Decodes an array, silently skipping elements that fail to decode.
struct LenientArray<Element: Decodable>: Decodable {
    var elements: [Element]

    /// Consumes one element of any JSON type without inspecting it.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        if let count = container.count { result.reserveCapacity(count) }
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        elements = result
    }
}
