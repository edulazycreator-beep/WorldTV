import XCTest
@testable import WorldTV

final class XMLTVParserTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE tv SYSTEM "xmltv.dtd">
    <tv generator-info-name="test">
      <channel id="Alpha.id">
        <display-name lang="id">Alpha News</display-name>
        <display-name>Alpha</display-name>
        <icon src="https://logo.example/alpha.png"/>
      </channel>
      <programme start="20261107080000 +0700" stop="20261107090000 +0700" channel="Alpha.id">
        <title lang="id">Berita Pagi</title>
        <title lang="en">Morning News</title>
        <sub-title>Episode 12</sub-title>
        <desc><![CDATA[Headlines & weather.]]></desc>
        <category>News</category>
      </programme>
      <programme start="20261107090000 +0700" stop="20261107100000 +0700" channel="Alpha.id">
        <title>Talk Show</title>
      </programme>
      <programme start="20261107010000" channel="Beta.bn">
        <title>No Stop Time</title>
      </programme>
      <programme stop="20261107010000" channel="Broken">
        <title>Missing start is ignored</title>
      </programme>
    </tv>
    """

    func testParsesChannelsAndProgrammes() throws {
        let guide = try XMLTVParser.parse(data: Data(sample.utf8))
        XCTAssertEqual(guide.channels["Alpha.id"]?.displayNames, ["Alpha News", "Alpha"])
        XCTAssertEqual(guide.channels["Alpha.id"]?.iconURL?.absoluteString, "https://logo.example/alpha.png")
        XCTAssertEqual(guide.programmes["Alpha.id"]?.count, 2)
        XCTAssertNil(guide.programmes["Broken"])

        let first = try XCTUnwrap(guide.programmes["Alpha.id"]?.first)
        XCTAssertEqual(first.title, "Berita Pagi", "first title wins")
        XCTAssertEqual(first.subtitle, "Episode 12")
        XCTAssertEqual(first.description, "Headlines & weather.")
        XCTAssertEqual(first.categories, ["News"])
    }

    func testTimezoneOffsetsAreApplied() throws {
        let guide = try XMLTVParser.parse(data: Data(sample.utf8))
        let first = try XCTUnwrap(guide.programmes["Alpha.id"]?.first)
        // 08:00 +07:00 == 01:00 UTC
        XCTAssertEqual(first.start, utc(2026, 11, 7, 1, 0))
        XCTAssertEqual(first.stop.timeIntervalSince(first.start), 3600)
    }

    func testMissingOffsetIsUTCAndMissingStopDefaults() throws {
        let guide = try XMLTVParser.parse(data: Data(sample.utf8))
        let programme = try XCTUnwrap(guide.programmes["Beta.bn"]?.first)
        XCTAssertEqual(programme.start, utc(2026, 11, 7, 1, 0))
        XCTAssertEqual(programme.stop.timeIntervalSince(programme.start), 1800)
    }

    func testDateParsingVariants() {
        XCTAssertEqual(XMLTVParser.parseDate("20261107083000 +0000"), utc(2026, 11, 7, 8, 30))
        XCTAssertEqual(XMLTVParser.parseDate("202611070830 -0500"), utc(2026, 11, 7, 13, 30))
        XCTAssertEqual(XMLTVParser.parseDate("20261107"), utc(2026, 11, 7, 0, 0))
        XCTAssertNil(XMLTVParser.parseDate("not a date"))
    }

    func testGzipCompressedGuide() throws {
        let guide = try XMLTVParser.parse(data: TestData.gzippedGuide)
        XCTAssertEqual(guide.programmes["Gz.tv"]?.first?.title, "Compressed Hour")
        XCTAssertEqual(guide.channels["Gz.tv"]?.displayNames, ["Gzip TV"])
    }

    func testRejectsNonXMLTV() {
        XCTAssertThrowsError(try XMLTVParser.parse(data: Data("<html><body/></html>".utf8)))
        XCTAssertThrowsError(try XMLTVParser.parse(data: Data("garbage".utf8)))
    }

    func testNowNextAndProgress() throws {
        let guide = try XMLTVParser.parse(data: Data(sample.utf8))
        let halfway = utc(2026, 11, 7, 1, 30)
        let now = try XCTUnwrap(guide.current(for: "Alpha.id", at: halfway))
        XCTAssertEqual(now.title, "Berita Pagi")
        XCTAssertEqual(now.progress(at: halfway), 0.5, accuracy: 0.001)
        XCTAssertEqual(guide.upcoming(for: "Alpha.id", after: halfway).map(\.title), ["Talk Show"])
        XCTAssertNil(guide.current(for: "Alpha.id", at: utc(2026, 11, 8, 0, 0)))
    }

    func testGuideMatchesChannelsByIDOrDisplayName() throws {
        let guide = try XMLTVParser.parse(data: Data(sample.utf8))
        let byID = TestData.channel("Alpha.id", name: "Something Else")
        XCTAssertEqual(guide.guideID(for: byID), "Alpha.id")

        var byName = TestData.channel("pl:x:alpha", name: "ALPHA NEWS")
        byName.epgID = nil
        XCTAssertEqual(guide.guideID(for: byName), "Alpha.id")

        let unknown = TestData.channel("Nope", name: "Unknown")
        XCTAssertNil(guide.guideID(for: unknown))
    }

    func testMergeReplacesDuplicateStarts() throws {
        var guide = try XMLTVParser.parse(data: Data(sample.utf8))
        let replacement = Programme(channelID: "Alpha.id", start: utc(2026, 11, 7, 1, 0),
                                    stop: utc(2026, 11, 7, 2, 0), title: "Updated")
        guide.merge(ProgrammeGuide(programmes: [replacement]))
        XCTAssertEqual(guide.programmes["Alpha.id"]?.count, 2)
        XCTAssertEqual(guide.programmes["Alpha.id"]?.first?.title, "Updated")
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}
