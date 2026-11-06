import XCTest
@testable import WorldTV

final class SearchServiceTests: XCTestCase {
    private let channels: [Channel] = [
        TestData.channel("RTB1.bn", name: "RTB Perdana", country: "BN", languages: ["msa"], categories: ["general"], popularity: 30,
                         firstSeen: Date(timeIntervalSince1970: 100)),
        TestData.channel("TVRI.id", name: "TVRI Nasional", country: "ID", languages: ["ind"], categories: ["general"], popularity: 50,
                         firstSeen: Date(timeIntervalSince1970: 300)),
        TestData.channel("NHK.jp", name: "NHK World-Japan", country: "JP", languages: ["eng"], categories: ["news"], popularity: 80,
                         firstSeen: Date(timeIntervalSince1970: 200)),
        TestData.channel("Kids.us", name: "Café Kids", country: "US", languages: ["eng"], categories: ["kids"], popularity: 10),
        TestData.channel("Geo.gb", name: "Geo Only", country: "GB", languages: ["eng"], categories: ["news"],
                         streams: [StreamSource(url: URL(string: "https://g.example/a.m3u8")!, labels: ["Geo-blocked"])]),
    ]

    private let context = SearchContext(
        countryNames: ["BN": "Brunei", "ID": "Indonesia", "JP": "Japan", "US": "United States", "GB": "United Kingdom"],
        languageNames: ["msa": "Malay", "ind": "Indonesian", "eng": "English"],
        categoryNames: ["general": "General", "news": "News", "kids": "Kids"])

    private func ids(_ query: SearchQuery) -> [String] {
        SearchService.search(channels, query: query, context: context).map(\.id)
    }

    func testNameSearchRanksExactAndPrefixFirst() {
        var query = SearchQuery()
        query.text = "nhk"
        XCTAssertEqual(ids(query), ["NHK.jp"])
        query.text = "tv"
        XCTAssertEqual(ids(query).first, "TVRI.id")
    }

    func testDiacriticAndCaseInsensitive() {
        var query = SearchQuery()
        query.text = "CAFE"
        XCTAssertEqual(ids(query), ["Kids.us"])
    }

    func testSearchByCountryNameLanguageAndCategory() {
        var query = SearchQuery()
        query.text = "brunei"
        XCTAssertEqual(ids(query), ["RTB1.bn"])
        query.text = "malay"
        XCTAssertEqual(ids(query), ["RTB1.bn"])
        query.text = "indonesia"
        XCTAssertEqual(ids(query), ["TVRI.id"])
        query.text = "news"
        XCTAssertEqual(Set(ids(query)), ["NHK.jp", "Geo.gb"])
    }

    func testAllTokensMustMatch() {
        var query = SearchQuery()
        query.text = "news japan"
        XCTAssertEqual(ids(query), ["NHK.jp"])
        query.text = "news brunei"
        XCTAssertEqual(ids(query), [])
    }

    func testFilters() {
        var query = SearchQuery()
        query.countryCode = "ID"
        XCTAssertEqual(ids(query), ["TVRI.id"])

        query = SearchQuery()
        query.continent = .asia
        XCTAssertEqual(Set(ids(query)), ["RTB1.bn", "TVRI.id", "NHK.jp"])

        query = SearchQuery()
        query.languageCode = "ENG"
        XCTAssertEqual(Set(ids(query)), ["NHK.jp", "Kids.us", "Geo.gb"])

        query = SearchQuery()
        query.categoryID = "kids"
        XCTAssertEqual(ids(query), ["Kids.us"])

        query = SearchQuery()
        query.hideGeoBlocked = true
        XCTAssertFalse(ids(query).contains("Geo.gb"))
    }

    func testFavoritesOnlyFilter() {
        var query = SearchQuery()
        query.onlyFavorites = true
        var favoriteContext = context
        favoriteContext.favoriteIDs = ["RTB1.bn"]
        XCTAssertEqual(SearchService.search(channels, query: query, context: favoriteContext).map(\.id), ["RTB1.bn"])
    }

    func testSorting() {
        var query = SearchQuery()
        query.sort = .name
        XCTAssertEqual(ids(query).first, "Kids.us") // "Café Kids"
        query.sort = .popularity
        XCTAssertEqual(ids(query).first, "NHK.jp")
        query.sort = .recentlyAdded
        XCTAssertEqual(Array(ids(query).prefix(3)), ["TVRI.id", "NHK.jp", "RTB1.bn"])
        query.sort = .country
        XCTAssertEqual(ids(query).first, "RTB1.bn") // Brunei
    }

    func testPlayCountsBoostPopularity() {
        var query = SearchQuery()
        query.sort = .popularity
        var boosted = context
        boosted.playCounts = ["Kids.us": 10]
        XCTAssertEqual(SearchService.search(channels, query: query, context: boosted).first?.id, "Kids.us")
    }

    func testEmptyQueryState() {
        XCTAssertTrue(SearchQuery().isEmpty)
        var query = SearchQuery()
        query.categoryID = "news"
        XCTAssertFalse(query.isEmpty)
        XCTAssertTrue(query.hasFilters)
    }
}
