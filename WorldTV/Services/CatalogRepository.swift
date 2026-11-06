import Foundation

/// Loads the public channel directory from the on-disk cache (fast startup)
/// and refreshes it from the network in the background. Channel metadata and
/// stream URLs live in these downloaded files, not in the app binary, so the
/// directory updates without a new release.
actor CatalogRepository {
    private var api: DirectoryAPI
    private let store: JSONFileStore
    private static let cachePrefix = "directory-"
    private static let firstSeenFile = "directory-first-seen.json"
    private static let fetchedAtFile = "directory-fetched-at.json"

    init(api: DirectoryAPI, store: JSONFileStore) {
        self.api = api
        self.store = store
    }

    func setNetworkOptions(timeout: TimeInterval, retry: RetryPolicy) {
        api.timeout = max(timeout, 20) // directory files are large; never go below 20 s
        api.retry = retry
    }

    /// Builds the catalog from cached files, or nil if nothing is cached.
    func loadCached() async -> Catalog? {
        var raw: [DirectoryAPI.Resource: Data] = [:]
        for resource in DirectoryAPI.Resource.allCases {
            if let data = await store.loadData(Self.cachePrefix + resource.fileName) { raw[resource] = data }
        }
        guard raw[.channels] != nil, raw[.streams] != nil else { return nil }
        let fetchedAt = (try? await store.load(Date.self, from: Self.fetchedAtFile)) ?? nil
        guard let snapshot = try? DirectoryAPI.decode(raw, fetchedAt: fetchedAt ?? Date.distantPast) else {
            return nil
        }
        let firstSeen = (try? await store.load([String: Date].self, from: Self.firstSeenFile)) ?? nil
        return CatalogBuilder.build(from: snapshot, previousFirstSeen: firstSeen ?? [:])
    }

    func lastFetchDate() async -> Date? {
        (try? await store.load(Date.self, from: Self.fetchedAtFile)) ?? nil
    }

    func isStale(maxAgeHours: Int, now: Date = Date()) async -> Bool {
        guard let last = await lastFetchDate() else { return true }
        return now.timeIntervalSince(last) > TimeInterval(maxAgeHours) * 3600
    }

    /// Downloads the directory, caches the raw files and rebuilds the catalog.
    func refresh(now: Date = Date()) async throws -> Catalog {
        let raw = try await api.fetchRaw()
        let snapshot = try DirectoryAPI.decode(raw, fetchedAt: now)

        // Only persist after a successful decode so a bad download never
        // replaces a good cache.
        for (resource, data) in raw {
            try? await store.writeData(data, to: Self.cachePrefix + resource.fileName)
        }
        try? await store.save(now, to: Self.fetchedAtFile)

        let previous = ((try? await store.load([String: Date].self, from: Self.firstSeenFile)) ?? nil) ?? [:]
        let isFirstFetch = previous.isEmpty
        // On the very first fetch nothing is "recently added"; mark everything as old.
        let baseline = isFirstFetch ? now.addingTimeInterval(-90 * 24 * 3600) : now
        let catalog = CatalogBuilder.build(from: snapshot, previousFirstSeen: previous, now: baseline)

        var firstSeen = previous
        for channel in catalog.channels where firstSeen[channel.id] == nil {
            firstSeen[channel.id] = channel.firstSeen ?? baseline
        }
        try? await store.save(firstSeen, to: Self.firstSeenFile)
        return catalog
    }
}
