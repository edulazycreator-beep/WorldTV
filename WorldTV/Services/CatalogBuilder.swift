import Foundation

/// The in-memory channel catalog shown in the UI.
struct Catalog: Sendable {
    var channels: [Channel]
    var countries: [Country]
    var categories: [ChannelCategory]
    var languages: [Language]
    var updatedAt: Date?

    static let empty = Catalog(channels: [], countries: [], categories: [], languages: [], updatedAt: nil)

    var isEmpty: Bool { channels.isEmpty }
}

/// Pure transformation from the raw directory files into catalog channels.
/// Kept free of I/O so it is fully unit-tested.
enum CatalogBuilder {
    static let attribution = "iptv-org public directory"
    static let usageNotes = "Publicly available stream listed by the iptv-org community database. "
        + "Availability and rights belong to the broadcaster; some streams are geo-blocked or not 24/7."

    static func build(from snapshot: DirectorySnapshot,
                      previousFirstSeen: [String: Date] = [:],
                      now: Date = Date()) -> Catalog {
        let blocked = Set(snapshot.blocklist.map(\.channel))

        var streamsByChannel: [String: [StreamSource]] = [:]
        for dto in snapshot.streams {
            guard let channelID = dto.channel,
                  case .success(let url) = StreamValidator.validate(dto.url) else { continue }
            let source = StreamSource(url: url, title: dto.title, quality: dto.quality,
                                      referrer: dto.referrer.nonEmpty, userAgent: dto.userAgent.nonEmpty,
                                      labels: dto.labels)
            if streamsByChannel[channelID]?.contains(where: { $0.url == url }) == true { continue }
            streamsByChannel[channelID, default: []].append(source)
        }

        var languagesByChannel: [String: [String]] = [:]
        for feed in snapshot.feeds where !feed.languages.isEmpty {
            if feed.isMain || languagesByChannel[feed.channel] == nil {
                languagesByChannel[feed.channel] = feed.languages
            }
        }

        var logoByChannel: [String: DirectoryDTO.Logo] = [:]
        for logo in snapshot.logos {
            guard let current = logoByChannel[logo.channel] else {
                logoByChannel[logo.channel] = logo
                continue
            }
            if logoScore(logo) > logoScore(current) { logoByChannel[logo.channel] = logo }
        }

        let countryCodes = Set(Country.featuredCodes)
        var channels: [Channel] = []
        channels.reserveCapacity(streamsByChannel.count)

        for dto in snapshot.channels {
            guard !dto.isNSFW, dto.closed == nil, !blocked.contains(dto.id),
                  !dto.categories.contains("xxx"),
                  let streams = streamsByChannel[dto.id], !streams.isEmpty else { continue }

            let country = dto.country?.uppercased()
            let logoURL = logoByChannel[dto.id].flatMap { URL(string: $0.url) }
            var channel = Channel(
                id: dto.id,
                name: dto.name,
                altNames: dto.altNames,
                countryCode: country,
                languages: languagesByChannel[dto.id] ?? [],
                categories: dto.categories.isEmpty ? ["general"] : dto.categories.map { $0.lowercased() },
                logoURL: logoURL,
                website: dto.website.flatMap(URL.init(string:)),
                streams: streams,
                origin: .directory,
                attribution: attribution,
                usageNotes: usageNotes,
                epgID: dto.id,
                popularity: 0,
                firstSeen: previousFirstSeen[dto.id] ?? now
            )
            channel.popularity = popularity(of: channel, featuredCountries: countryCodes)
            channels.append(channel)
        }

        channels.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let usedCountries = Set(channels.compactMap(\.countryCode))
        let countries = snapshot.countries
            .filter { usedCountries.contains($0.code.uppercased()) }
            .map { Country(code: $0.code.uppercased(), name: $0.name,
                           flag: $0.flag ?? Country.flagEmoji(for: $0.code), languages: $0.languages) }
            .sorted { $0.name < $1.name }

        let usedCategories = Set(channels.flatMap(\.categories))
        var categoryNames = Dictionary(snapshot.categories.map { ($0.id.lowercased(), $0.name) }) { a, _ in a }
        for id in usedCategories where categoryNames[id] == nil {
            categoryNames[id] = ChannelCategory.fallbackName(for: id)
        }
        let categories = usedCategories
            .map { ChannelCategory(id: $0, name: categoryNames[$0] ?? ChannelCategory.fallbackName(for: $0)) }
            .sorted { $0.name < $1.name }

        let usedLanguages = Set(channels.flatMap(\.languages))
        let languages = snapshot.languages
            .filter { usedLanguages.contains($0.code) }
            .map { Language(code: $0.code, name: $0.name) }
            .sorted { $0.name < $1.name }

        return Catalog(channels: channels, countries: countries, categories: categories,
                       languages: languages, updatedAt: snapshot.fetchedAt)
    }

    private static func logoScore(_ logo: DirectoryDTO.Logo) -> Double {
        var score = 0.0
        if logo.feed == nil { score += 10_000 }
        if logo.inUse { score += 5_000 }
        // Prefer reasonably sized logos; very large images waste memory.
        score += min(logo.width, 512)
        return score
    }

    /// A transparent heuristic: the directory has no viewing figures, so
    /// "popular" favours well-documented channels with several good streams.
    /// The user's own play counts are added on top in the view model.
    static func popularity(of channel: Channel, featuredCountries: Set<String>) -> Int {
        var score = min(channel.streams.count, 4) * 10
        let bestQuality = channel.streams.map(\.qualityRank).max() ?? 0
        if bestQuality >= 1080 { score += 15 } else if bestQuality >= 720 { score += 10 }
        if channel.streams.contains(where: { !$0.isGeoBlocked }) { score += 10 }
        if channel.logoURL != nil { score += 8 }
        if channel.website != nil { score += 4 }
        if let country = channel.countryCode, featuredCountries.contains(country) { score += 6 }
        if channel.categories.contains("news") || channel.categories.contains("general") { score += 3 }
        return score
    }
}
