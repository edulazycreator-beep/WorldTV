import Foundation

/// Where a channel record came from. Kept separate from the stream URLs so the
/// directory can be refreshed without shipping a new app version.
enum ChannelOrigin: Codable, Hashable, Sendable {
    /// The public iptv-org database (https://github.com/iptv-org/database).
    case directory
    /// A playlist the user imported; the associated value is the playlist ID.
    case playlist(UUID)

    var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }
}

/// A single playable source for a channel.
struct StreamSource: Codable, Hashable, Sendable, Identifiable {
    var id: String { url.absoluteString }
    var url: URL
    var title: String?
    /// e.g. "1080p", "720p" — reported by the source when known.
    var quality: String?
    /// Optional HTTP headers some broadcasters require.
    var referrer: String?
    var userAgent: String?
    /// Known caveats from the source, e.g. "Geo-blocked", "Not 24/7".
    var labels: [String]

    init(url: URL, title: String? = nil, quality: String? = nil,
         referrer: String? = nil, userAgent: String? = nil, labels: [String] = []) {
        self.url = url
        self.title = title
        self.quality = quality
        self.referrer = referrer
        self.userAgent = userAgent
        self.labels = labels
    }

    /// Numeric vertical resolution parsed from `quality` ("720p" -> 720).
    var qualityRank: Int {
        guard let quality else { return 0 }
        let digits = quality.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    var isGeoBlocked: Bool { labels.contains { $0.localizedCaseInsensitiveContains("geo") } }
}

/// A television channel, independent of how it is streamed.
struct Channel: Codable, Hashable, Sendable, Identifiable {
    /// Stable key, unique across directory and playlists.
    /// Directory channels use the iptv-org ID (e.g. "RTB1.bn");
    /// playlist channels use "pl:<playlistID>:<tvg-id or index>".
    var id: String
    var name: String
    var altNames: [String]
    /// ISO 3166-1 alpha-2, upper-case. Nil when unknown (e.g. some playlists).
    var countryCode: String?
    /// ISO 639-3 codes (directory) or free-text language names (playlists).
    var languages: [String]
    /// Category IDs, lower-case ("news", "sports", …).
    var categories: [String]
    var logoURL: URL?
    var website: URL?
    var streams: [StreamSource]
    var origin: ChannelOrigin
    /// Human-readable source attribution shown in the UI.
    var attribution: String
    var usageNotes: String?
    /// XMLTV channel ID used to match programme data.
    var epgID: String?
    /// Heuristic ranking used for "Popular"; see `CatalogBuilder.popularity`.
    var popularity: Int
    /// When the channel first appeared in the local catalog.
    var firstSeen: Date?

    init(id: String, name: String, altNames: [String] = [], countryCode: String? = nil,
         languages: [String] = [], categories: [String] = [], logoURL: URL? = nil,
         website: URL? = nil, streams: [StreamSource] = [], origin: ChannelOrigin = .directory,
         attribution: String = "", usageNotes: String? = nil, epgID: String? = nil,
         popularity: Int = 0, firstSeen: Date? = nil) {
        self.id = id
        self.name = name
        self.altNames = altNames
        self.countryCode = countryCode
        self.languages = languages
        self.categories = categories
        self.logoURL = logoURL
        self.website = website
        self.streams = streams
        self.origin = origin
        self.attribution = attribution
        self.usageNotes = usageNotes
        self.epgID = epgID
        self.popularity = popularity
        self.firstSeen = firstSeen
    }

    /// Streams ordered best-first: not geo-blocked, then highest quality.
    var rankedStreams: [StreamSource] {
        streams.sorted { lhs, rhs in
            if lhs.isGeoBlocked != rhs.isGeoBlocked { return !lhs.isGeoBlocked }
            return lhs.qualityRank > rhs.qualityRank
        }
    }

    var primaryStream: StreamSource? { rankedStreams.first }

    var bestQualityLabel: String? { rankedStreams.first(where: { $0.quality != nil })?.quality }

    var primaryCategory: String? { categories.first }
}
