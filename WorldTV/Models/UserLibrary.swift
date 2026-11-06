import Foundation

struct HistoryEntry: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var channelID: String
    var channelName: String
    var startedAt: Date
    /// Seconds watched; updated when playback stops or switches channel.
    var duration: TimeInterval

    init(id: UUID = UUID(), channelID: String, channelName: String,
         startedAt: Date = Date(), duration: TimeInterval = 0) {
        self.id = id
        self.channelID = channelID
        self.channelName = channelName
        self.startedAt = startedAt
        self.duration = duration
    }
}

struct ChannelGroup: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var channelIDs: [String]

    init(id: UUID = UUID(), name: String, channelIDs: [String] = []) {
        self.id = id
        self.name = name
        self.channelIDs = channelIDs
    }
}

/// Everything the user personalises. Persisted as one JSON document.
struct UserLibrary: Codable, Hashable, Sendable {
    var favoriteIDs: [String] = []
    var history: [HistoryEntry] = []
    var groups: [ChannelGroup] = []
    /// Per-channel play counts, used to personalise "Popular".
    var playCounts: [String: Int] = [:]

    static let historyLimit = 500

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        favoriteIDs = (try? c.decode([String].self, forKey: .favoriteIDs)) ?? []
        history = (try? c.decode([HistoryEntry].self, forKey: .history)) ?? []
        groups = (try? c.decode([ChannelGroup].self, forKey: .groups)) ?? []
        playCounts = (try? c.decode([String: Int].self, forKey: .playCounts)) ?? [:]
    }

    func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    mutating func toggleFavorite(_ id: String) {
        if let index = favoriteIDs.firstIndex(of: id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.insert(id, at: 0)
        }
    }

    /// Records a new viewing session and returns its ID.
    @discardableResult
    mutating func recordPlay(channelID: String, channelName: String, at date: Date = Date()) -> UUID {
        let entry = HistoryEntry(channelID: channelID, channelName: channelName, startedAt: date)
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        playCounts[channelID, default: 0] += 1
        return entry.id
    }

    mutating func finishSession(_ id: UUID, at date: Date = Date()) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].duration = max(0, date.timeIntervalSince(history[index].startedAt))
    }

    /// Unique channel IDs, most recent first.
    func recentChannelIDs(limit: Int = 20) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in history where seen.insert(entry.channelID).inserted {
            result.append(entry.channelID)
            if result.count == limit { break }
        }
        return result
    }

    mutating func clearHistory() {
        history.removeAll()
    }

    // MARK: Groups

    @discardableResult
    mutating func createGroup(named name: String) -> ChannelGroup {
        let group = ChannelGroup(name: name)
        groups.append(group)
        return group
    }

    mutating func renameGroup(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    mutating func toggle(channelID: String, inGroup id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        if let position = groups[index].channelIDs.firstIndex(of: channelID) {
            groups[index].channelIDs.remove(at: position)
        } else {
            groups[index].channelIDs.append(channelID)
        }
    }
}

/// User preferences. Persisted as JSON alongside the library.
struct AppSettings: Codable, Hashable, Sendable {
    enum Theme: String, Codable, CaseIterable, Sendable, Identifiable {
        case dark, system, light
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum VideoGravity: String, Codable, CaseIterable, Sendable, Identifiable {
        case fit, fill, stretch
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fit: return "Fit (letterbox)"
            case .fill: return "Fill (crop)"
            case .stretch: return "Stretch"
            }
        }
    }

    var theme: Theme = .dark
    var autoplayOnSelect: Bool = true
    var startMuted: Bool = false
    var defaultVolume: Double = 0.8
    var videoGravity: VideoGravity = .fit
    /// Prefer the highest-quality variant listed by the source.
    var preferHighestQuality: Bool = true
    /// Hide channels whose source marks them geo-blocked.
    var hideGeoBlocked: Bool = false
    var requestTimeout: TimeInterval = 15
    var maxRetries: Int = 3
    var reconnectAttempts: Int = 3
    /// Refresh the public directory if the cache is older than this many hours.
    var directoryRefreshHours: Int = 24
    var directoryEnabled: Bool = true

    init() {}

    // Decode leniently so new settings never wipe a user's saved preferences.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = (try? c.decode(Theme.self, forKey: .theme)) ?? d.theme
        autoplayOnSelect = (try? c.decode(Bool.self, forKey: .autoplayOnSelect)) ?? d.autoplayOnSelect
        startMuted = (try? c.decode(Bool.self, forKey: .startMuted)) ?? d.startMuted
        defaultVolume = (try? c.decode(Double.self, forKey: .defaultVolume)) ?? d.defaultVolume
        videoGravity = (try? c.decode(VideoGravity.self, forKey: .videoGravity)) ?? d.videoGravity
        preferHighestQuality = (try? c.decode(Bool.self, forKey: .preferHighestQuality)) ?? d.preferHighestQuality
        hideGeoBlocked = (try? c.decode(Bool.self, forKey: .hideGeoBlocked)) ?? d.hideGeoBlocked
        requestTimeout = (try? c.decode(TimeInterval.self, forKey: .requestTimeout)) ?? d.requestTimeout
        maxRetries = (try? c.decode(Int.self, forKey: .maxRetries)) ?? d.maxRetries
        reconnectAttempts = (try? c.decode(Int.self, forKey: .reconnectAttempts)) ?? d.reconnectAttempts
        directoryRefreshHours = (try? c.decode(Int.self, forKey: .directoryRefreshHours)) ?? d.directoryRefreshHours
        directoryEnabled = (try? c.decode(Bool.self, forKey: .directoryEnabled)) ?? d.directoryEnabled
    }
}
