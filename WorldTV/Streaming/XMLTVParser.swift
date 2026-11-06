import Foundation

enum XMLTVParserError: LocalizedError, Equatable {
    case malformed(String)
    case notXMLTV

    var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "The guide file is malformed: \(detail)"
        case .notXMLTV: return "This file is not an XMLTV programme guide."
        }
    }
}

/// Streaming SAX parser for XMLTV (`<tv>`, `<channel>`, `<programme>`).
/// Accepts plain XML or gzip-compressed (`.xml.gz`) data.
enum XMLTVParser {
    static func parse(data input: Data) throws -> ProgrammeGuide {
        let data = try Gzip.isGzipped(input) ? Gzip.decompress(input) : input
        let delegate = XMLTVParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let ok = parser.parse()
        if !ok {
            if !delegate.sawRoot { throw XMLTVParserError.notXMLTV }
            // Keep what we parsed if the file is merely truncated.
            if delegate.programmes.isEmpty {
                throw XMLTVParserError.malformed(parser.parserError?.localizedDescription ?? "unknown error")
            }
        }
        guard delegate.sawRoot else { throw XMLTVParserError.notXMLTV }
        return ProgrammeGuide(channels: delegate.channels, programmes: delegate.programmes)
    }

    /// Parses XMLTV timestamps: `YYYYMMDDhhmmss ±hhmm`. Missing time parts are
    /// treated as zero and a missing offset as UTC, per the XMLTV DTD.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let digits = String(trimmed.prefix { $0.isNumber })
        guard digits.count >= 8 else { return nil }
        let padded = (digits + "000000").prefix(14)
        func part(_ start: Int, _ length: Int) -> Int {
            let s = padded.index(padded.startIndex, offsetBy: start)
            let e = padded.index(s, offsetBy: length)
            return Int(padded[s..<e]) ?? 0
        }
        var components = DateComponents()
        components.year = part(0, 4)
        components.month = part(4, 2)
        components.day = part(6, 2)
        components.hour = part(8, 2)
        components.minute = part(10, 2)
        components.second = part(12, 2)

        var offsetSeconds = 0
        let rest = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        if let sign = rest.first, sign == "+" || sign == "-" {
            let offsetDigits = rest.dropFirst().prefix { $0.isNumber }
            if offsetDigits.count == 4, let value = Int(offsetDigits) {
                offsetSeconds = (value / 100) * 3600 + (value % 100) * 60
                if sign == "-" { offsetSeconds = -offsetSeconds }
            }
        }
        components.timeZone = TimeZone(secondsFromGMT: offsetSeconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: components)
    }
}

final class XMLTVParserDelegate: NSObject, XMLParserDelegate {
    private(set) var channels: [String: EPGChannel] = [:]
    private(set) var programmes: [Programme] = []
    private(set) var sawRoot = false

    private var currentChannel: EPGChannel?
    private var currentProgramme: (channel: String, start: Date, stop: Date?)?
    private var title: String?
    private var subtitle: String?
    private var desc: String?
    private var categories: [String] = []
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "tv":
            sawRoot = true
        case "channel":
            if let id = attributes["id"] {
                currentChannel = EPGChannel(id: id, displayNames: [], iconURL: nil)
            }
        case "icon":
            if currentChannel != nil, let src = attributes["src"] {
                currentChannel?.iconURL = URL(string: src)
            }
        case "programme":
            if let channel = attributes["channel"],
               let startRaw = attributes["start"], let start = XMLTVParser.parseDate(startRaw) {
                let stop = attributes["stop"].flatMap(XMLTVParser.parseDate)
                currentProgramme = (channel, start, stop)
                title = nil
                subtitle = nil
                desc = nil
                categories = []
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name":
            if !value.isEmpty { currentChannel?.displayNames.append(value) }
        case "channel":
            if let channel = currentChannel { channels[channel.id] = channel }
            currentChannel = nil
        case "title":
            if title == nil, !value.isEmpty { title = value }
        case "sub-title":
            if subtitle == nil, !value.isEmpty { subtitle = value }
        case "desc":
            if desc == nil, !value.isEmpty { desc = value }
        case "category":
            if currentProgramme != nil, !value.isEmpty { categories.append(value) }
        case "programme":
            if let current = currentProgramme {
                // Missing stop: assume 30 minutes; fixed up below by the next start.
                let stop = current.stop ?? current.start.addingTimeInterval(30 * 60)
                programmes.append(Programme(channelID: current.channel, start: current.start,
                                            stop: max(stop, current.start), title: title ?? "Untitled",
                                            subtitle: subtitle, description: desc, categories: categories))
            }
            currentProgramme = nil
        default:
            break
        }
        text = ""
    }
}
