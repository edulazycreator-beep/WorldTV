import Foundation

/// A standalone XMLTV guide source added by the user (in addition to guides
/// declared inside playlists).
struct GuideSource: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var source: Playlist.Source
    var updatedAt: Date?

    init(id: UUID = UUID(), name: String, source: Playlist.Source, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.updatedAt = updatedAt
    }
}

/// Persisted document for everything imported by the user.
struct ImportedContent: Codable, Sendable {
    var playlists: [Playlist] = []
    var guides: [GuideSource] = []

    init(playlists: [Playlist] = [], guides: [GuideSource] = []) {
        self.playlists = playlists
        self.guides = guides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlists = (try? c.decode([Playlist].self, forKey: .playlists)) ?? []
        guides = (try? c.decode([GuideSource].self, forKey: .guides)) ?? []
    }
}

enum PlaylistImportError: LocalizedError {
    case noChannels
    case accessDenied
    case invalidAddress(StreamURLIssue)

    var errorDescription: String? {
        switch self {
        case .noChannels: return "No playable channels were found in this playlist."
        case .accessDenied: return "World TV no longer has permission to read this file. Import it again."
        case .invalidAddress(let issue): return issue.localizedDescription
        }
    }
}

/// Reads playlists and guides from files or URLs.
struct PlaylistService: Sendable {
    let client: HTTPClient
    var timeout: TimeInterval = 30
    var retry: RetryPolicy = .standard

    /// Reads a source's raw bytes. Local files are re-opened through their
    /// security-scoped bookmark (the app is sandboxed).
    func read(_ source: Playlist.Source) async throws -> Data {
        switch source {
        case .remote(let url):
            return try await client.get(url, timeout: timeout, retry: retry)
        case .file(_, let bookmark):
            guard let bookmark else { throw PlaylistImportError.accessDenied }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale) else {
                throw PlaylistImportError.accessDenied
            }
            return try Self.readSecurityScoped(url)
        }
    }

    static func readSecurityScoped(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    /// Creates a bookmark for a file the user picked so it can be re-read later.
    static func bookmark(for url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                     includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Parses playlist bytes into a `Playlist` value (new or updated).
    static func makePlaylist(from data: Data, existing: Playlist?, name: String,
                             source: Playlist.Source, knownCategoryIDs: Set<String>,
                             now: Date = Date()) throws -> Playlist {
        let parsed = try M3UParser.parse(data: data)
        let id = existing?.id ?? UUID()
        let channels = parsed.channels(playlistID: id, playlistName: name, knownCategoryIDs: knownCategoryIDs)
        guard !channels.isEmpty else { throw PlaylistImportError.noChannels }

        // Preserve when each channel first appeared so "Recently added" works.
        let previousFirstSeen = Dictionary((existing?.channels ?? []).map { ($0.id, $0.firstSeen) }) { a, _ in a }
        let stamped = channels.map { channel -> Channel in
            var copy = channel
            if let seen = previousFirstSeen[channel.id] { copy.firstSeen = seen ?? now } else { copy.firstSeen = now }
            return copy
        }
        return Playlist(id: id, name: name, source: source,
                        epgURL: existing?.epgURL ?? parsed.epgURLs.first,
                        channels: stamped,
                        addedAt: existing?.addedAt ?? now,
                        updatedAt: now,
                        validation: existing?.validation ?? [:])
    }

    func fetchGuide(_ source: Playlist.Source) async throws -> ProgrammeGuide {
        let data = try await read(source)
        return try XMLTVParser.parse(data: data)
    }
}
