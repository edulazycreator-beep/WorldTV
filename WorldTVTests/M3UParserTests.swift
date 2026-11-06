import XCTest
@testable import WorldTV

final class M3UParserTests: XCTestCase {
    private let sample = """
    #EXTM3U url-tvg="https://epg.example/guide.xml.gz" x-tvg-url="https://epg.example/alt.xml"
    #EXTINF:-1 tvg-id="Alpha.id" tvg-name="Alpha News" tvg-logo="https://logo.example/a.png" tvg-country="ID" tvg-language="Indonesian" group-title="News",Alpha News 1080p
    https://stream.example/alpha/1080.m3u8
    #EXTINF:-1 tvg-id="Beta.bn" group-title="Entertainment;Music",Beta, the "Fun" Channel
    #EXTVLCOPT:http-referrer=https://beta.example/
    #EXTVLCOPT:http-user-agent=Mozilla/5.0
    http://stream.example/beta.m3u8
    #EXTINF:0,Kodi Style
    https://stream.example/kodi.m3u8|User-Agent=Custom%20Agent&Referer=https://kodi.example
    #EXTINF:-1 tvg-id="Alpha.id",Alpha News Backup 720
    https://backup.example/alpha.m3u8
    #EXTINF:-1,Orphan without url
    #EXTINF:-1,Bad scheme
    ftp://nope.example/stream
    #EXTINF:-1,
    #EXTGRP:Sports
    https://stream.example/sports/live.m3u8
    """

    func testParsesHeaderGuideURLs() throws {
        let playlist = try M3UParser.parse(text: sample)
        XCTAssertEqual(playlist.epgURLs.map(\.absoluteString),
                       ["https://epg.example/guide.xml.gz", "https://epg.example/alt.xml"])
    }

    func testParsesEntriesAndAttributes() throws {
        let playlist = try M3UParser.parse(text: sample)
        XCTAssertEqual(playlist.entries.count, 5)

        let alpha = playlist.entries[0]
        XCTAssertEqual(alpha.name, "Alpha News 1080p")
        XCTAssertEqual(alpha.tvgID, "Alpha.id")
        XCTAssertEqual(alpha.tvgName, "Alpha News")
        XCTAssertEqual(alpha.logo?.absoluteString, "https://logo.example/a.png")
        XCTAssertEqual(alpha.country, "ID")
        XCTAssertEqual(alpha.groupTitle, "News")
        XCTAssertEqual(alpha.duration, -1)
    }

    func testTitleWithCommasAndQuotes() throws {
        let playlist = try M3UParser.parse(text: sample)
        XCTAssertEqual(playlist.entries[1].name, "Beta, the \"Fun\" Channel")
        XCTAssertEqual(playlist.entries[1].groupTitle, "Entertainment;Music")
    }

    func testVLCOptionsAndKodiHeaders() throws {
        let playlist = try M3UParser.parse(text: sample)
        XCTAssertEqual(playlist.entries[1].referrer, "https://beta.example/")
        XCTAssertEqual(playlist.entries[1].userAgent, "Mozilla/5.0")
        let kodi = playlist.entries[2]
        XCTAssertEqual(kodi.url.absoluteString, "https://stream.example/kodi.m3u8")
        XCTAssertEqual(kodi.userAgent, "Custom Agent")
        XCTAssertEqual(kodi.referrer, "https://kodi.example")
    }

    func testExtGrpAndFallbackName() throws {
        let playlist = try M3UParser.parse(text: sample)
        let sports = try XCTUnwrap(playlist.entries.last)
        XCTAssertEqual(sports.groupTitle, "Sports")
        XCTAssertEqual(sports.name, "live")
    }

    func testCountsSkippedLines() throws {
        let playlist = try M3UParser.parse(text: sample)
        // "Orphan without url" (no URL) and "Bad scheme" (ftp) are skipped.
        XCTAssertEqual(playlist.skippedLines, 2)
    }

    func testHandlesCRLFAndBOM() throws {
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,One\r\nhttps://a.example/1.m3u8\r\n"
        let playlist = try M3UParser.parse(text: text)
        XCTAssertEqual(playlist.entries.count, 1)
        XCTAssertEqual(playlist.entries[0].name, "One")
    }

    func testBareURLListWithoutHeader() throws {
        let playlist = try M3UParser.parse(text: "https://a.example/x.m3u8\nhttps://b.example/y.mp4")
        XCTAssertEqual(playlist.entries.count, 2)
        XCTAssertEqual(playlist.entries[1].name, "y")
    }

    func testRejectsEmptyAndNonPlaylist() {
        XCTAssertThrowsError(try M3UParser.parse(data: Data())) { error in
            XCTAssertEqual(error as? M3UParserError, .empty)
        }
        XCTAssertThrowsError(try M3UParser.parse(text: "<html><body>Not found</body></html>")) { error in
            XCTAssertEqual(error as? M3UParserError, .notAPlaylist)
        }
    }

    func testAttributeParserHandlesUnquotedAndSingleQuoted() {
        let attributes = M3UParser.parseAttributes(" tvg-id=abc tvg-name='Hello World' group-title=\"A, B\"")
        XCTAssertEqual(attributes["tvg-id"], "abc")
        XCTAssertEqual(attributes["tvg-name"], "Hello World")
        XCTAssertEqual(attributes["group-title"], "A, B")
    }

    func testConversionMergesStreamsByTvgIDAndMapsCategories() throws {
        let playlist = try M3UParser.parse(text: sample)
        let id = UUID()
        let channels = playlist.channels(playlistID: id, playlistName: "Mine",
                                         knownCategoryIDs: ["news", "entertainment", "music", "sports"])
        XCTAssertEqual(channels.count, 4)

        let alpha = try XCTUnwrap(channels.first { $0.epgID == "Alpha.id" })
        XCTAssertEqual(alpha.streams.count, 2, "entries sharing tvg-id become one channel")
        XCTAssertEqual(alpha.name, "Alpha News")
        XCTAssertEqual(alpha.countryCode, "ID")
        XCTAssertEqual(alpha.categories, ["news"])
        XCTAssertEqual(alpha.streams.first?.quality, "1080p")
        XCTAssertEqual(alpha.origin, .playlist(id))
        XCTAssertTrue(alpha.id.hasPrefix("pl:\(id.uuidString):"))

        let beta = try XCTUnwrap(channels.first { $0.epgID == "Beta.bn" })
        XCTAssertEqual(beta.categories, ["entertainment", "music"])
        XCTAssertEqual(beta.streams.first?.referrer, "https://beta.example/")
    }

    func testChannelIDsAreStableAcrossReparse() throws {
        let id = UUID()
        let first = try M3UParser.parse(text: sample).channels(playlistID: id, playlistName: "A", knownCategoryIDs: [])
        let second = try M3UParser.parse(text: sample).channels(playlistID: id, playlistName: "A", knownCategoryIDs: [])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }
}
