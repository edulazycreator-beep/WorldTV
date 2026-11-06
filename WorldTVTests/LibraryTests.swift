import XCTest
@testable import WorldTV

final class UserLibraryTests: XCTestCase {
    func testToggleFavorite() {
        var library = UserLibrary()
        library.toggleFavorite("A")
        library.toggleFavorite("B")
        XCTAssertEqual(library.favoriteIDs, ["B", "A"], "newest favorite first")
        XCTAssertTrue(library.isFavorite("A"))
        library.toggleFavorite("A")
        XCTAssertFalse(library.isFavorite("A"))
        XCTAssertEqual(library.favoriteIDs, ["B"])
    }

    func testHistoryRecordsSessionsAndRecentIsUnique() {
        var library = UserLibrary()
        let start = Date(timeIntervalSince1970: 1_000)
        let first = library.recordPlay(channelID: "A", channelName: "Alpha", at: start)
        library.recordPlay(channelID: "B", channelName: "Beta", at: start.addingTimeInterval(10))
        library.recordPlay(channelID: "A", channelName: "Alpha", at: start.addingTimeInterval(20))

        XCTAssertEqual(library.history.count, 3)
        XCTAssertEqual(library.recentChannelIDs(), ["A", "B"])
        XCTAssertEqual(library.playCounts["A"], 2)

        library.finishSession(first, at: start.addingTimeInterval(95))
        XCTAssertEqual(library.history.last?.duration, 95)
    }

    func testHistoryIsCapped() {
        var library = UserLibrary()
        for index in 0..<(UserLibrary.historyLimit + 25) {
            library.recordPlay(channelID: "C\(index)", channelName: "C")
        }
        XCTAssertEqual(library.history.count, UserLibrary.historyLimit)
        XCTAssertEqual(library.history.first?.channelID, "C\(UserLibrary.historyLimit + 24)")
    }

    func testGroups() {
        var library = UserLibrary()
        let group = library.createGroup(named: "Morning")
        library.toggle(channelID: "A", inGroup: group.id)
        library.toggle(channelID: "B", inGroup: group.id)
        library.toggle(channelID: "A", inGroup: group.id)
        XCTAssertEqual(library.groups.first?.channelIDs, ["B"])
        library.renameGroup(group.id, to: "News")
        XCTAssertEqual(library.groups.first?.name, "News")
        library.deleteGroup(group.id)
        XCTAssertTrue(library.groups.isEmpty)
    }

    func testClearHistoryKeepsFavorites() {
        var library = UserLibrary()
        library.toggleFavorite("A")
        library.recordPlay(channelID: "A", channelName: "A")
        library.clearHistory()
        XCTAssertTrue(library.history.isEmpty)
        XCTAssertEqual(library.favoriteIDs, ["A"])
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    func testJSONFileStoreRoundTrip() async throws {
        let store = JSONFileStore(directory: TestData.temporaryDirectory())
        var library = UserLibrary()
        library.toggleFavorite("X")
        try await store.save(library, to: "lib.json")
        let loaded = try await store.load(UserLibrary.self, from: "lib.json")
        XCTAssertEqual(loaded, library)
        let missing = try await store.load(UserLibrary.self, from: "nope.json")
        XCTAssertNil(missing)
    }

    func testLibraryStorePersistsAcrossInstances() async throws {
        let directory = TestData.temporaryDirectory()
        let first = LibraryStore(store: JSONFileStore(directory: directory))
        await first.load()
        let channel = TestData.channel("RTB1.bn")
        first.toggleFavorite(channel)
        first.recordPlay(channel)
        first.createGroup(named: "Brunei")
        first.settings.theme = .light
        first.settings.reconnectAttempts = 5
        await first.flush()

        let second = LibraryStore(store: JSONFileStore(directory: directory))
        await second.load()
        XCTAssertTrue(second.isFavorite(channel))
        XCTAssertEqual(second.library.recentChannelIDs(), ["RTB1.bn"])
        XCTAssertEqual(second.library.groups.map(\.name), ["Brunei"])
        XCTAssertEqual(second.settings.theme, .light)
        XCTAssertEqual(second.settings.reconnectAttempts, 5)
    }

    func testSettingsDecodeLenientlyWithUnknownAndMissingKeys() throws {
        let json = Data(#"{"theme":"system","futureSetting":42,"maxRetries":"not a number"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.maxRetries, AppSettings().maxRetries)
        XCTAssertEqual(settings.videoGravity, .fit)
    }

    func testCorruptLibraryFileResetsWithError() async throws {
        let directory = TestData.temporaryDirectory()
        try Data("{ corrupt".utf8).write(to: directory.appendingPathComponent(LibraryStore.libraryFile))
        let store = LibraryStore(store: JSONFileStore(directory: directory))
        await store.load()
        XCTAssertTrue(store.library.favoriteIDs.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testImportedContentRoundTripPreservesPlaylists() async throws {
        let store = JSONFileStore(directory: TestData.temporaryDirectory())
        let data = Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"a\",A\nhttps://a.example/a.m3u8\n".utf8)
        let playlist = try PlaylistService.makePlaylist(from: data, existing: nil, name: "Mine",
                                                        source: .remote(URL(string: "https://p.example/list.m3u")!),
                                                        knownCategoryIDs: [])
        try await store.save(ImportedContent(playlists: [playlist]), to: "imported.json")
        let loaded = try await store.load(ImportedContent.self, from: "imported.json")
        XCTAssertEqual(loaded?.playlists.first?.channels.map(\.id), playlist.channels.map(\.id))
        XCTAssertEqual(loaded?.playlists.first?.source, playlist.source)
    }

    func testPlaylistUpdateKeepsIdentityAndFirstSeen() throws {
        let source = Playlist.Source.remote(URL(string: "https://p.example/list.m3u")!)
        let v1 = Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"a\",A\nhttps://a.example/a.m3u8\n".utf8)
        let v2 = Data("#EXTM3U\n#EXTINF:-1 tvg-id=\"a\",A\nhttps://a.example/a2.m3u8\n#EXTINF:-1 tvg-id=\"b\",B\nhttps://b.example/b.m3u8\n".utf8)
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 9_000)
        let first = try PlaylistService.makePlaylist(from: v1, existing: nil, name: "P", source: source,
                                                     knownCategoryIDs: [], now: t1)
        let second = try PlaylistService.makePlaylist(from: v2, existing: first, name: "P", source: source,
                                                      knownCategoryIDs: [], now: t2)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.addedAt, t1)
        XCTAssertEqual(second.updatedAt, t2)
        XCTAssertEqual(second.channels.count, 2)
        XCTAssertEqual(second.channels.first { $0.epgID == "a" }?.firstSeen, t1)
        XCTAssertEqual(second.channels.first { $0.epgID == "b" }?.firstSeen, t2)
    }

    func testPlaylistWithoutChannelsIsRejected() {
        XCTAssertThrowsError(try PlaylistService.makePlaylist(
            from: Data("#EXTM3U\n#EXTINF:-1,Nothing\n".utf8), existing: nil, name: "Empty",
            source: .remote(URL(string: "https://p.example")!), knownCategoryIDs: []))
    }
}
