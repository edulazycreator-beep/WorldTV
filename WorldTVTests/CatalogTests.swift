import XCTest
@testable import WorldTV

final class CatalogBuilderTests: XCTestCase {
    private func snapshot() throws -> DirectorySnapshot {
        try DirectoryAPI.decode(TestData.directoryRaw(), fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testLenientDecodingSkipsBrokenElements() throws {
        let snapshot = try snapshot()
        XCTAssertEqual(snapshot.channels.count, 6, "the malformed element is skipped, not fatal")
        XCTAssertEqual(snapshot.streams.count, 9)
    }

    func testMissingRequiredResourceFails() {
        var raw = TestData.directoryRaw()
        raw[.streams] = nil
        XCTAssertThrowsError(try DirectoryAPI.decode(raw, fetchedAt: Date()))
    }

    func testMissingOptionalResourceIsTolerated() throws {
        var raw = TestData.directoryRaw()
        raw[.logos] = nil
        raw[.blocklist] = Data("not json".utf8)
        let snapshot = try DirectoryAPI.decode(raw, fetchedAt: Date())
        XCTAssertTrue(snapshot.logos.isEmpty)
        XCTAssertTrue(snapshot.blocklist.isEmpty)
    }

    func testFiltersClosedNSFWBlockedAndStreamlessChannels() throws {
        let catalog = CatalogBuilder.build(from: try snapshot())
        XCTAssertEqual(catalog.channels.map(\.id).sorted(), ["Alpha.id", "Beta.bn"])
    }

    func testJoinsStreamsLogosLanguagesAndMetadata() throws {
        let catalog = CatalogBuilder.build(from: try snapshot())
        let alpha = try XCTUnwrap(catalog.channels.first { $0.id == "Alpha.id" })
        XCTAssertEqual(alpha.streams.count, 2, "duplicate stream URL is dropped")
        XCTAssertEqual(alpha.logoURL?.absoluteString, "https://logos.example/alpha.png", "channel-level logo preferred over feed logo")
        XCTAssertEqual(alpha.languages, ["ind"])
        XCTAssertEqual(alpha.website?.absoluteString, "https://alpha.example")
        XCTAssertEqual(alpha.countryCode, "ID")
        XCTAssertEqual(alpha.epgID, "Alpha.id")
        XCTAssertEqual(alpha.origin, .directory)
        XCTAssertFalse(alpha.attribution.isEmpty)

        let beta = try XCTUnwrap(catalog.channels.first { $0.id == "Beta.bn" })
        XCTAssertEqual(beta.streams.count, 1, "rtmp stream is rejected")
        XCTAssertEqual(beta.languages, ["msa", "eng"])
        XCTAssertNil(beta.logoURL)
    }

    func testRankedStreamsPreferNonGeoBlockedThenQuality() throws {
        let catalog = CatalogBuilder.build(from: try snapshot())
        let alpha = try XCTUnwrap(catalog.channels.first { $0.id == "Alpha.id" })
        XCTAssertEqual(alpha.primaryStream?.quality, "720p", "the 1080p stream is geo-blocked")
        XCTAssertEqual(alpha.bestQualityLabel, "720p")
    }

    func testBuildsCountriesCategoriesLanguagesInUse() throws {
        let catalog = CatalogBuilder.build(from: try snapshot())
        XCTAssertEqual(catalog.countries.map(\.code), ["BN", "ID"])
        XCTAssertEqual(catalog.countries.first?.flag, "🇧🇳")
        XCTAssertEqual(Set(catalog.categories.map(\.id)), ["news", "general"])
        XCTAssertEqual(Set(catalog.languages.map(\.code)), ["ind", "msa", "eng"])
    }

    func testFirstSeenIsPreserved() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 2_000)
        let catalog = CatalogBuilder.build(from: try snapshot(), previousFirstSeen: ["Alpha.id": old], now: now)
        XCTAssertEqual(catalog.channels.first { $0.id == "Alpha.id" }?.firstSeen, old)
        XCTAssertEqual(catalog.channels.first { $0.id == "Beta.bn" }?.firstSeen, now)
    }

    func testPopularityRewardsCompleteChannels() throws {
        let catalog = CatalogBuilder.build(from: try snapshot())
        let alpha = try XCTUnwrap(catalog.channels.first { $0.id == "Alpha.id" })
        let beta = try XCTUnwrap(catalog.channels.first { $0.id == "Beta.bn" })
        XCTAssertGreaterThan(alpha.popularity, beta.popularity)
    }

    func testContinentMapping() {
        XCTAssertEqual(Continent.of(countryCode: "BN"), .asia)
        XCTAssertEqual(Continent.of(countryCode: "id"), .asia)
        XCTAssertEqual(Continent.of(countryCode: "GB"), .europe)
        XCTAssertEqual(Continent.of(countryCode: "US"), .northAmerica)
        XCTAssertEqual(Continent.of(countryCode: "BR"), .southAmerica)
        XCTAssertEqual(Continent.of(countryCode: "AU"), .oceania)
        XCTAssertEqual(Continent.of(countryCode: "NG"), .africa)
        XCTAssertEqual(Continent.of(countryCode: nil), .other)
        XCTAssertEqual(Continent.of(countryCode: "ZZ"), .other)
    }

    func testFlagEmoji() {
        XCTAssertEqual(Country.flagEmoji(for: "id"), "🇮🇩")
        XCTAssertEqual(Country.flagEmoji(for: "SA"), "🇸🇦")
    }
}

final class CatalogRepositoryTests: XCTestCase {
    func testRefreshCachesAndReloadsOffline() async throws {
        let raw = TestData.directoryRaw()
        let client = MockHTTPClient { request in
            let name = request.url!.lastPathComponent
            guard let resource = DirectoryAPI.Resource.allCases.first(where: { $0.fileName == name }),
                  let data = raw[resource] else { return (404, Data()) }
            return (200, data)
        }
        let store = JSONFileStore(directory: TestData.temporaryDirectory())
        let repository = CatalogRepository(api: DirectoryAPI(client: client, retry: .none), store: store)

        let cachedBefore = await repository.loadCached()
        XCTAssertNil(cachedBefore)
        let staleBefore = await repository.isStale(maxAgeHours: 24)
        XCTAssertTrue(staleBefore)

        let fresh = try await repository.refresh()
        XCTAssertEqual(fresh.channels.count, 2)
        XCTAssertEqual(client.requests.count, DirectoryAPI.Resource.allCases.count)

        // Simulate going offline: every request now fails.
        client.setHandler { _ in throw URLError(.notConnectedToInternet) }
        let cached = await repository.loadCached()
        XCTAssertEqual(cached?.channels.map(\.id).sorted(), ["Alpha.id", "Beta.bn"])
        let staleAfter = await repository.isStale(maxAgeHours: 24)
        XCTAssertFalse(staleAfter)

        do {
            _ = try await repository.refresh()
            XCTFail("refresh should fail offline")
        } catch {
            XCTAssertEqual(NetworkError.from(error), .offline)
        }
        let stillCached = await repository.loadCached()
        XCTAssertNotNil(stillCached, "a failed refresh must not destroy the cache")
    }

    func testOptionalResourceFailureDoesNotBreakRefresh() async throws {
        let raw = TestData.directoryRaw()
        let client = MockHTTPClient { request in
            let name = request.url!.lastPathComponent
            if name == "logos.json" { return (500, Data()) }
            guard let resource = DirectoryAPI.Resource.allCases.first(where: { $0.fileName == name }) else { return (404, Data()) }
            return (200, raw[resource] ?? Data())
        }
        let repository = CatalogRepository(api: DirectoryAPI(client: client, retry: .none),
                                           store: JSONFileStore(directory: TestData.temporaryDirectory()))
        let catalog = try await repository.refresh()
        XCTAssertEqual(catalog.channels.count, 2)
        XCTAssertTrue(catalog.channels.allSatisfy { $0.logoURL == nil })
    }
}
