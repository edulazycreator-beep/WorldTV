import Foundation

enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case relevance, name, popularity, country, recentlyAdded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance: return "Relevance"
        case .name: return "Name"
        case .popularity: return "Popularity"
        case .country: return "Country"
        case .recentlyAdded: return "Recently Added"
        }
    }
}

struct SearchQuery: Equatable, Sendable {
    var text = ""
    var countryCode: String?
    var continent: Continent?
    var languageCode: String?
    var categoryID: String?
    var sort: SearchSort = .relevance
    var hideGeoBlocked = false
    var onlyFavorites = false

    var hasFilters: Bool {
        countryCode != nil || continent != nil || languageCode != nil || categoryID != nil || onlyFavorites
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && !hasFilters }
}

/// Lookup tables that let text search match country and language *names*.
struct SearchContext: Sendable {
    var countryNames: [String: String] = [:]
    var languageNames: [String: String] = [:]
    var categoryNames: [String: String] = [:]
    var playCounts: [String: Int] = [:]
    var favoriteIDs: Set<String> = []
}

/// Pure, synchronous search over the catalog. Fast enough for tens of
/// thousands of channels; the view model runs it off the main thread.
enum SearchService {
    static func search(_ channels: [Channel], query: SearchQuery, context: SearchContext = SearchContext()) -> [Channel] {
        let tokens = query.text.searchFolded
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var scored: [(Channel, Int)] = []
        scored.reserveCapacity(channels.count)

        for channel in channels {
            if let code = query.countryCode, channel.countryCode != code { continue }
            if let continent = query.continent, Continent.of(countryCode: channel.countryCode) != continent { continue }
            if let language = query.languageCode, !channel.languages.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) { continue }
            if let category = query.categoryID, !channel.categories.contains(category) { continue }
            if query.hideGeoBlocked, !channel.streams.contains(where: { !$0.isGeoBlocked }) { continue }
            if query.onlyFavorites, !context.favoriteIDs.contains(channel.id) { continue }

            if tokens.isEmpty {
                scored.append((channel, 0))
                continue
            }
            var total = 0
            var allMatched = true
            for token in tokens {
                let tokenScore = Self.score(token: token, channel: channel, context: context)
                if tokenScore == 0 { allMatched = false; break }
                total += tokenScore
            }
            if allMatched { scored.append((channel, total)) }
        }

        let sorted: [(Channel, Int)]
        switch query.sort {
        case .relevance where !tokens.isEmpty:
            sorted = scored.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return popularity(lhs.0, context) > popularity(rhs.0, context)
            }
        case .relevance, .popularity:
            sorted = scored.sorted { lhs, rhs in
                let l = popularity(lhs.0, context), r = popularity(rhs.0, context)
                if l != r { return l > r }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
        case .name:
            sorted = scored.sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
        case .country:
            sorted = scored.sorted { lhs, rhs in
                let l = context.countryNames[lhs.0.countryCode ?? ""] ?? lhs.0.countryCode ?? "~"
                let r = context.countryNames[rhs.0.countryCode ?? ""] ?? rhs.0.countryCode ?? "~"
                if l != r { return l < r }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
        case .recentlyAdded:
            sorted = scored.sorted { ($0.0.firstSeen ?? .distantPast) > ($1.0.firstSeen ?? .distantPast) }
        }
        return sorted.map(\.0)
    }

    static func popularity(_ channel: Channel, _ context: SearchContext) -> Int {
        channel.popularity + (context.playCounts[channel.id] ?? 0) * 25
    }

    static func score(token: String, channel: Channel, context: SearchContext) -> Int {
        let name = channel.name.searchFolded
        if name == token { return 100 }
        if name.hasPrefix(token) { return 60 }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(token) }) { return 40 }
        if name.contains(token) { return 20 }
        if channel.altNames.contains(where: { $0.searchFolded.contains(token) }) { return 15 }

        if let code = channel.countryCode {
            if code.lowercased() == token { return 12 }
            if let countryName = context.countryNames[code]?.searchFolded, countryName.contains(token) { return 10 }
        }
        for language in channel.languages {
            if language.lowercased() == token { return 8 }
            let languageName = (context.languageNames[language] ?? language).searchFolded
            if languageName.hasPrefix(token) { return 8 }
        }
        for category in channel.categories {
            if category.hasPrefix(token) { return 8 }
            if let categoryName = context.categoryNames[category]?.searchFolded, categoryName.hasPrefix(token) { return 8 }
        }
        return 0
    }
}
