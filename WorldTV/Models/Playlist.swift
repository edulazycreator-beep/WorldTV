import Foundation

/// A user-imported IPTV playlist (M3U / M3U8), optionally with an XMLTV guide.
struct Playlist: Codable, Hashable, Sendable, Identifiable {
    enum Source: Codable, Hashable, Sendable {
        /// A local file. `bookmark` is a security-scoped bookmark so the
        /// sandboxed app can re-read the file when the user taps Update.
        case file(name: String, bookmark: Data?)
        case remote(URL)

        var displayValue: String {
            switch self {
            case .file(let name, _): return name
            case .remote(let url): return url.absoluteString
            }
        }
    }

    var id: UUID
    var name: String
    var source: Source
    /// XMLTV URL declared in the playlist header (`url-tvg` / `x-tvg-url`) or set by the user.
    var epgURL: URL?
    var channels: [Channel]
    var addedAt: Date
    var updatedAt: Date
    /// Result of the last validation pass, keyed by stream URL.
    var validation: [String: StreamHealth]

    init(id: UUID = UUID(), name: String, source: Source, epgURL: URL? = nil,
         channels: [Channel] = [], addedAt: Date = Date(), updatedAt: Date = Date(),
         validation: [String: StreamHealth] = [:]) {
        self.id = id
        self.name = name
        self.source = source
        self.epgURL = epgURL
        self.channels = channels
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.validation = validation
    }

    var invalidStreamCount: Int {
        validation.values.filter { if case .unreachable = $0 { return true }; return false }.count
    }
}

/// Outcome of a lightweight stream check.
enum StreamHealth: Codable, Hashable, Sendable {
    case unknown
    case ok(checkedAt: Date)
    case unreachable(reason: String, checkedAt: Date)

    var isUnreachable: Bool {
        if case .unreachable = self { return true }
        return false
    }
}
