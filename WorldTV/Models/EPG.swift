import Foundation

/// A single XMLTV `<programme>` entry. Times are absolute (`Date`), so display
/// in any time zone is a formatting concern only.
struct Programme: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(channelID)|\(start.timeIntervalSince1970)" }
    var channelID: String
    var start: Date
    var stop: Date
    var title: String
    var subtitle: String?
    var description: String?
    var categories: [String]

    init(channelID: String, start: Date, stop: Date, title: String,
         subtitle: String? = nil, description: String? = nil, categories: [String] = []) {
        self.channelID = channelID
        self.start = start
        self.stop = stop
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.categories = categories
    }

    func isAiring(at date: Date) -> Bool { start <= date && date < stop }

    /// 0…1 progress through the programme at `date`.
    func progress(at date: Date) -> Double {
        let total = stop.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

struct EPGChannel: Codable, Hashable, Sendable {
    var id: String
    var displayNames: [String]
    var iconURL: URL?
}

/// Parsed XMLTV document, indexed for fast "now / next" lookups.
struct ProgrammeGuide: Sendable {
    var channels: [String: EPGChannel]
    /// Programmes per XMLTV channel ID, sorted by start time.
    var programmes: [String: [Programme]]
    /// Lower-cased display name -> XMLTV channel ID, for name-based matching.
    private(set) var nameIndex: [String: String] = [:]

    init(channels: [String: EPGChannel] = [:], programmes: [Programme] = []) {
        self.channels = channels
        var grouped = Dictionary(grouping: programmes, by: \.channelID)
        for key in grouped.keys { grouped[key]?.sort { $0.start < $1.start } }
        self.programmes = grouped
        rebuildNameIndex()
    }

    private mutating func rebuildNameIndex() {
        var index: [String: String] = [:]
        for channel in channels.values.sorted(by: { $0.id < $1.id }) {
            for name in channel.displayNames {
                let key = name.lowercased()
                if index[key] == nil { index[key] = channel.id }
            }
        }
        nameIndex = index
    }

    var isEmpty: Bool { programmes.isEmpty }

    func current(for channelID: String, at date: Date = Date()) -> Programme? {
        programmes[channelID]?.first { $0.isAiring(at: date) }
    }

    func upcoming(for channelID: String, after date: Date = Date(), limit: Int = 10) -> [Programme] {
        guard let list = programmes[channelID] else { return [] }
        return Array(list.filter { $0.start >= date }.prefix(limit))
    }

    func schedule(for channelID: String, from: Date, to: Date) -> [Programme] {
        (programmes[channelID] ?? []).filter { $0.stop > from && $0.start < to }
    }

    /// Merge another guide in; later data wins for duplicate programme starts.
    mutating func merge(_ other: ProgrammeGuide) {
        channels.merge(other.channels) { _, new in new }
        for (key, list) in other.programmes {
            var combined = Dictionary((programmes[key] ?? []).map { ($0.start, $0) }) { a, _ in a }
            for programme in list { combined[programme.start] = programme }
            programmes[key] = combined.values.sorted { $0.start < $1.start }
        }
        rebuildNameIndex()
    }

    /// Resolve which XMLTV channel ID belongs to a catalog channel.
    func guideID(for channel: Channel) -> String? {
        if let epgID = channel.epgID, programmes[epgID] != nil { return epgID }
        if programmes[channel.id] != nil { return channel.id }
        for name in [channel.name] + channel.altNames {
            if let id = nameIndex[name.lowercased()], programmes[id] != nil { return id }
        }
        return nil
    }
}
