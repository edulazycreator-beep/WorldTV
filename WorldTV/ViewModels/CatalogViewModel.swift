import Combine
import Foundation

/// Owns everything the user can browse: the public directory, imported
/// playlists and programme guides. All heavy work (download, parse, join,
/// validation) runs off the main actor.
@MainActor
final class CatalogViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var countries: [Country] = []
    @Published private(set) var categories: [ChannelCategory] = []
    @Published private(set) var languages: [Language] = []
    @Published private(set) var directoryState: LoadState = .idle
    @Published private(set) var directoryUpdatedAt: Date?
    @Published private(set) var imported = ImportedContent()
    @Published private(set) var guide = ProgrammeGuide()
    @Published private(set) var guideState: LoadState = .idle
    @Published private(set) var busyPlaylists: Set<UUID> = []
    @Published private(set) var validationProgress: [UUID: Double] = [:]
    /// One-line, user-facing result of the last playlist/guide operation.
    @Published var notice: String?

    private(set) var directory: Catalog = .empty
    private var byID: [String: Channel] = [:]

    private let repository: CatalogRepository
    private let store: JSONFileStore
    private var playlistService: PlaylistService
    private let validator: StreamValidator
    private let library: LibraryStore
    private let networkEnabled: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    static let importedFile = "imported.json"

    init(repository: CatalogRepository, store: JSONFileStore, playlistService: PlaylistService,
         validator: StreamValidator, library: LibraryStore, networkEnabled: Bool = true) {
        self.repository = repository
        self.store = store
        self.playlistService = playlistService
        self.validator = validator
        self.library = library
        self.networkEnabled = networkEnabled

        library.$settings
            .map { ($0.hideGeoBlocked, $0.directoryEnabled) }
            .removeDuplicates { $0 == $1 }
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                self.rebuild()
                // Directory just switched on and nothing is loaded yet: fetch it.
                if value.1, self.started, self.directory.isEmpty {
                    Task { await self.refreshDirectory() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Startup

    func start() async {
        guard !started else { return }
        started = true

        if let saved = try? await store.load(ImportedContent.self, from: Self.importedFile) {
            imported = saved
        }
        if let cached = await repository.loadCached() {
            directory = cached
            directoryUpdatedAt = cached.updatedAt
            directoryState = .loaded
        }
        rebuild()
        if directory.isEmpty && (!networkEnabled || !library.settings.directoryEnabled) {
            directoryState = .loaded // nothing to fetch; show the empty state instead of a spinner
        }

        let maxAge = library.settings.directoryRefreshHours
        if networkEnabled, library.settings.directoryEnabled {
            if directory.isEmpty {
                await refreshDirectory()
            } else if await repository.isStale(maxAgeHours: maxAge) {
                Task { await self.refreshDirectory() } // background refresh; cached data stays visible
            }
        }
        await refreshGuides(useNetwork: networkEnabled)
    }

    func refreshDirectory() async {
        guard networkEnabled else { return }
        guard directoryState != .loading else { return }
        let hadData = !directory.isEmpty
        directoryState = .loading
        applyNetworkSettings()
        await repository.setNetworkOptions(timeout: library.settings.requestTimeout, retry: retryPolicy)
        do {
            let catalog = try await repository.refresh()
            directory = catalog
            directoryUpdatedAt = catalog.updatedAt
            directoryState = .loaded
            rebuild()
        } catch {
            let message = NetworkError.from(error).localizedDescription
            directoryState = hadData ? .loaded : .failed(message)
            notice = hadData ? "Couldn't refresh the channel directory: \(message) Showing saved data." : nil
        }
    }

    // MARK: Lookups

    func channel(id: String) -> Channel? { byID[id] }

    func channels(ids: [String]) -> [Channel] { ids.compactMap { byID[$0] } }

    func countryName(_ code: String?) -> String {
        guard let code else { return "International" }
        return countries.first { $0.code == code }?.name ?? Locale.countryName(for: code)
    }

    func country(_ code: String?) -> Country? {
        guard let code else { return nil }
        return countries.first { $0.code == code }
    }

    func categoryName(_ id: String) -> String {
        categories.first { $0.id == id }?.name ?? ChannelCategory.fallbackName(for: id)
    }

    func languageName(_ code: String) -> String {
        languages.first { $0.code == code }?.name ?? Locale.languageName(for: code)
    }

    func searchContext() -> SearchContext {
        SearchContext(
            countryNames: Dictionary(countries.map { ($0.code, $0.name) }) { a, _ in a },
            languageNames: Dictionary(languages.map { ($0.code, $0.name) }) { a, _ in a },
            categoryNames: Dictionary(categories.map { ($0.id, $0.name) }) { a, _ in a },
            playCounts: library.library.playCounts,
            favoriteIDs: Set(library.library.favoriteIDs)
        )
    }

    func popular(limit: Int = 24) -> [Channel] {
        var query = SearchQuery()
        query.sort = .popularity
        return Array(SearchService.search(channels, query: query, context: searchContext()).prefix(limit))
    }

    func recentlyAdded(limit: Int = 24) -> [Channel] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return Array(channels
            .filter { ($0.firstSeen ?? .distantPast) > cutoff }
            .sorted { ($0.firstSeen ?? .distantPast) > ($1.firstSeen ?? .distantPast) }
            .prefix(limit))
    }

    /// A stable daily pick from well-documented channels in the featured countries.
    func featured(limit: Int = 8) -> [Channel] {
        let featuredCodes = Set(Country.featuredCodes)
        let pool = channels
            .filter { $0.logoURL != nil && featuredCodes.contains($0.countryCode ?? "") }
            .sorted { $0.popularity > $1.popularity }
            .prefix(120)
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var picked: [Channel] = []
        var usedCountries = Set<String>()
        let rotated = Array(pool)
        guard !rotated.isEmpty else { return [] }
        for offset in 0..<rotated.count {
            let candidate = rotated[(offset + day * 7) % rotated.count]
            guard usedCountries.insert(candidate.countryCode ?? "").inserted else { continue }
            picked.append(candidate)
            if picked.count == limit { break }
        }
        return picked
    }

    func channelCount(country code: String) -> Int {
        channels.filter { $0.countryCode == code }.count
    }

    func channelCount(category id: String) -> Int {
        channels.filter { $0.categories.contains(id) }.count
    }

    func channelCount(continent: Continent) -> Int {
        channels.filter { Continent.of(countryCode: $0.countryCode) == continent }.count
    }

    // MARK: Playlists

    func importPlaylist(fileURL: URL) async {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let bookmark = PlaylistService.bookmark(for: fileURL)
        do {
            let data = try PlaylistService.readSecurityScoped(fileURL)
            try await addPlaylist(data: data, name: name, source: .file(name: fileURL.lastPathComponent, bookmark: bookmark))
        } catch {
            notice = "Import failed: \(error.localizedDescription)"
        }
    }

    func addPlaylist(urlString: String, name: String) async {
        switch StreamValidator.validate(urlString) {
        case .failure(let issue):
            notice = "Import failed: \(issue.localizedDescription)"
        case .success(let url):
            applyNetworkSettings()
            do {
                let data = try await playlistService.read(.remote(url))
                let title = name.trimmingCharacters(in: .whitespaces).nonEmpty ?? url.host ?? "Playlist"
                try await addPlaylist(data: data, name: title, source: .remote(url))
            } catch {
                notice = "Import failed: \(NetworkError.from(error).localizedDescription)"
            }
        }
    }

    private func addPlaylist(data: Data, name: String, source: Playlist.Source) async throws {
        let knownCategories = Set(categories.map(\.id)).union(ChannelCategory.featuredIDs)
        let playlist = try await Task.detached(priority: .userInitiated) {
            try PlaylistService.makePlaylist(from: data, existing: nil, name: name, source: source,
                                             knownCategoryIDs: knownCategories)
        }.value
        imported.playlists.append(playlist)
        await persistImported()
        rebuild()
        notice = "Imported “\(playlist.name)” with \(playlist.channels.count) channels."
        if playlist.epgURL != nil { await refreshGuides(useNetwork: networkEnabled) }
    }

    func updatePlaylist(_ id: UUID) async {
        guard let existing = imported.playlists.first(where: { $0.id == id }) else { return }
        busyPlaylists.insert(id)
        defer { busyPlaylists.remove(id) }
        applyNetworkSettings()
        do {
            let data = try await playlistService.read(existing.source)
            let knownCategories = Set(categories.map(\.id)).union(ChannelCategory.featuredIDs)
            let updated = try await Task.detached(priority: .userInitiated) {
                try PlaylistService.makePlaylist(from: data, existing: existing, name: existing.name,
                                                 source: existing.source, knownCategoryIDs: knownCategories)
            }.value
            if let index = imported.playlists.firstIndex(where: { $0.id == id }) {
                imported.playlists[index] = updated
            }
            await persistImported()
            rebuild()
            notice = "Updated “\(updated.name)”: \(updated.channels.count) channels."
        } catch {
            notice = "Update failed: \(NetworkError.from(error).localizedDescription)"
        }
    }

    func removePlaylist(_ id: UUID) async {
        imported.playlists.removeAll { $0.id == id }
        await persistImported()
        rebuild()
    }

    func renamePlaylist(_ id: UUID, to name: String) async {
        guard let index = imported.playlists.firstIndex(where: { $0.id == id }),
              let trimmed = name.trimmingCharacters(in: .whitespaces).nonEmpty else { return }
        imported.playlists[index].name = trimmed
        await persistImported()
    }

    func setGuideURL(_ urlString: String, for id: UUID) async {
        guard let index = imported.playlists.firstIndex(where: { $0.id == id }) else { return }
        if urlString.trimmingCharacters(in: .whitespaces).isEmpty {
            imported.playlists[index].epgURL = nil
        } else if case .success(let url) = StreamValidator.validate(urlString) {
            imported.playlists[index].epgURL = url
        } else {
            notice = "That guide address is not a valid HTTP(S) URL."
            return
        }
        await persistImported()
        await refreshGuides(useNetwork: networkEnabled)
    }

    /// Checks every stream in a playlist and records which ones are unreachable.
    func validatePlaylist(_ id: UUID) async {
        guard let playlist = imported.playlists.first(where: { $0.id == id }) else { return }
        busyPlaylists.insert(id)
        validationProgress[id] = 0
        defer {
            busyPlaylists.remove(id)
            validationProgress[id] = nil
        }
        let streams = playlist.channels.flatMap(\.streams)
        let results = await validator.checkAll(streams) { done, total in
            Task { @MainActor [weak self] in
                self?.validationProgress[id] = total == 0 ? 1 : Double(done) / Double(total)
            }
        }
        guard let index = imported.playlists.firstIndex(where: { $0.id == id }) else { return }
        imported.playlists[index].validation = results
        await persistImported()
        let bad = results.values.filter(\.isUnreachable).count
        notice = bad == 0
            ? "All \(results.count) streams in “\(playlist.name)” responded."
            : "\(bad) of \(results.count) streams in “\(playlist.name)” are unreachable right now."
    }

    func health(of stream: StreamSource, in channel: Channel) -> StreamHealth {
        guard case .playlist(let playlistID) = channel.origin,
              let playlist = imported.playlists.first(where: { $0.id == playlistID }) else { return .unknown }
        return playlist.validation[stream.url.absoluteString] ?? .unknown
    }

    // MARK: Guides

    func addGuide(urlString: String) async {
        switch StreamValidator.validate(urlString) {
        case .failure(let issue):
            notice = "Guide not added: \(issue.localizedDescription)"
        case .success(let url):
            imported.guides.append(GuideSource(name: url.host ?? "XMLTV guide", source: .remote(url)))
            await persistImported()
            await refreshGuides(useNetwork: networkEnabled)
        }
    }

    func importGuide(fileURL: URL) async {
        let bookmark = PlaylistService.bookmark(for: fileURL)
        imported.guides.append(GuideSource(name: fileURL.lastPathComponent,
                                           source: .file(name: fileURL.lastPathComponent, bookmark: bookmark)))
        await persistImported()
        await refreshGuides(useNetwork: networkEnabled)
    }

    func removeGuide(_ id: UUID) async {
        imported.guides.removeAll { $0.id == id }
        await store.remove(Self.guideCacheName(id.uuidString))
        await persistImported()
        await refreshGuides(useNetwork: false)
    }

    /// Loads every guide source (playlist-declared and standalone), caching
    /// raw XMLTV on disk so the guide is available offline and at startup.
    func refreshGuides(useNetwork: Bool = true) async {
        var sources: [(key: String, source: Playlist.Source)] = []
        for guideSource in imported.guides {
            sources.append((key: guideSource.id.uuidString, source: guideSource.source))
        }
        for playlist in imported.playlists {
            if let url = playlist.epgURL {
                sources.append((key: "pl-" + playlist.id.uuidString, source: Playlist.Source.remote(url)))
            }
        }
        guard !sources.isEmpty else {
            guide = ProgrammeGuide()
            rebuildGuideMap()
            guideState = .idle
            return
        }
        guideState = .loading
        applyNetworkSettings()
        var merged = ProgrammeGuide()
        var failures: [String] = []
        for entry in sources {
            let cacheName = Self.guideCacheName(entry.key)
            var data: Data?
            let isRemote: Bool
            if case .remote = entry.source { isRemote = true } else { isRemote = false }
            if !isRemote || useNetwork {
                data = try? await playlistService.read(entry.source)
                if let data { try? await store.writeData(data, to: cacheName) }
            }
            if data == nil { data = await store.loadData(cacheName) }
            guard let payload = data else {
                failures.append(entry.source.displayValue)
                continue
            }
            do {
                let parsed = try await Task.detached(priority: .utility) { try XMLTVParser.parse(data: payload) }.value
                merged.merge(parsed)
            } catch {
                failures.append(entry.source.displayValue)
            }
        }
        guide = merged
        rebuildGuideMap()
        guideState = failures.isEmpty ? .loaded : .failed("\(failures.count) guide source(s) could not be loaded.")
        for index in imported.guides.indices where !failures.contains(imported.guides[index].source.displayValue) {
            imported.guides[index].updatedAt = Date()
        }
    }

    private static func guideCacheName(_ key: String) -> String { "guide-\(key).xml" }

    /// Catalog channel ID -> XMLTV channel ID, rebuilt when channels or guide change.
    private var guideMap: [String: String] = [:]
    @Published private(set) var channelsWithGuide: [Channel] = []

    private func rebuildGuideMap() {
        guard !guide.isEmpty else {
            guideMap = [:]
            channelsWithGuide = []
            return
        }
        var map: [String: String] = [:]
        var matched: [Channel] = []
        for channel in channels {
            if let id = guide.guideID(for: channel) {
                map[channel.id] = id
                matched.append(channel)
            }
        }
        guideMap = map
        channelsWithGuide = matched
    }

    func guideID(for channel: Channel) -> String? { guideMap[channel.id] }

    func currentProgramme(for channel: Channel, at date: Date = Date()) -> Programme? {
        guard let id = guideMap[channel.id] else { return nil }
        return guide.current(for: id, at: date)
    }

    func upcoming(for channel: Channel, limit: Int = 8) -> [Programme] {
        guard let id = guideMap[channel.id] else { return [] }
        return guide.upcoming(for: id, limit: limit)
    }

    func schedule(for channel: Channel, from: Date, to: Date) -> [Programme] {
        guard let id = guideMap[channel.id] else { return [] }
        return guide.schedule(for: id, from: from, to: to)
    }

    // MARK: Internals

    private var retryPolicy: RetryPolicy {
        RetryPolicy(maxAttempts: max(1, library.settings.maxRetries + 1), baseDelay: 0.5, maxDelay: 8)
    }

    /// Applies the user's timeout/retry preferences before network work.
    private func applyNetworkSettings() {
        playlistService.timeout = max(5, library.settings.requestTimeout * 2)
        playlistService.retry = retryPolicy
    }

    private func persistImported() async {
        do {
            try await store.save(imported, to: Self.importedFile)
        } catch {
            notice = "Couldn't save playlists: \(error.localizedDescription)"
        }
    }

    private func rebuild() {
        let settings = library.settings
        var combined: [Channel] = settings.directoryEnabled ? directory.channels : []
        for playlist in imported.playlists { combined.append(contentsOf: playlist.channels) }
        if settings.hideGeoBlocked {
            combined = combined.filter { $0.streams.contains { !$0.isGeoBlocked } }
        }
        channels = combined
        byID = Dictionary(combined.map { ($0.id, $0) }) { first, _ in first }

        var countryMap = Dictionary(directory.countries.map { ($0.code, $0) }) { a, _ in a }
        var categoryMap = Dictionary(directory.categories.map { ($0.id, $0) }) { a, _ in a }
        var languageMap = Dictionary(directory.languages.map { ($0.code, $0) }) { a, _ in a }
        for channel in combined where !channel.origin.isDirectory {
            if let code = channel.countryCode, countryMap[code] == nil {
                countryMap[code] = Country(code: code, name: Locale.countryName(for: code),
                                           flag: Country.flagEmoji(for: code), languages: [])
            }
            for category in channel.categories where categoryMap[category] == nil {
                categoryMap[category] = ChannelCategory(id: category, name: ChannelCategory.fallbackName(for: category))
            }
            for language in channel.languages where languageMap[language] == nil {
                languageMap[language] = Language(code: language, name: Locale.languageName(for: language))
            }
        }
        let usedCountries = Set(combined.compactMap(\.countryCode))
        let usedCategories = Set(combined.flatMap(\.categories))
        let usedLanguages = Set(combined.flatMap(\.languages))
        countries = countryMap.values.filter { usedCountries.contains($0.code) }.sorted { $0.name < $1.name }
        categories = categoryMap.values.filter { usedCategories.contains($0.id) }.sorted { $0.name < $1.name }
        languages = languageMap.values.filter { usedLanguages.contains($0.code) }.sorted { $0.name < $1.name }
        rebuildGuideMap()
    }
}
