import Foundation

struct Country: Codable, Hashable, Sendable, Identifiable {
    var id: String { code }
    /// ISO 3166-1 alpha-2, upper-case.
    var code: String
    var name: String
    var flag: String
    /// Official languages, ISO 639-3.
    var languages: [String]

    var continent: Continent { Continent.of(countryCode: code) }

    /// Builds a flag emoji from a two-letter code when the source has none.
    static func flagEmoji(for code: String) -> String {
        let base: UInt32 = 0x1F1E6 - 65
        var result = ""
        for scalar in code.uppercased().unicodeScalars where (65...90).contains(scalar.value) {
            if let flagScalar = Unicode.Scalar(base + scalar.value) {
                result.unicodeScalars.append(flagScalar)
            }
        }
        return result
    }

    /// Countries highlighted in Explore, in display order.
    static let featuredCodes = ["ID", "BN", "MY", "SG", "US", "GB", "JP", "KR",
                                "CN", "IN", "AU", "DE", "FR", "SA"]
}

enum Continent: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case asia, europe, africa, northAmerica, southAmerica, oceania, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asia: return "Asia"
        case .europe: return "Europe"
        case .africa: return "Africa"
        case .northAmerica: return "North America"
        case .southAmerica: return "South America"
        case .oceania: return "Oceania"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .asia, .oceania: return "globe.asia.australia.fill"
        case .europe, .africa: return "globe.europe.africa.fill"
        case .northAmerica, .southAmerica: return "globe.americas.fill"
        case .other: return "globe"
        }
    }

    static func of(countryCode: String?) -> Continent {
        guard let code = countryCode?.uppercased() else { return .other }
        return lookup[code] ?? .other
    }

    private static let lookup: [String: Continent] = {
        let table: [(Continent, String)] = [
            (.africa, "DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU YT MA MZ NA NE NG RE RW SH ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW"),
            (.asia, "AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KW KG LA LB MO MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE"),
            (.europe, "AX AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG HU IS IE IM IT JE XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SJ SE CH UA GB VA"),
            (.northAmerica, "AI AG AW BS BB BZ BM BQ VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI UM"),
            (.southAmerica, "AR BO BR CL CO EC FK GF GY PY PE SR UY VE"),
            (.oceania, "AS AU CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV VU WF"),
        ]
        var map: [String: Continent] = [:]
        for (continent, codes) in table {
            for code in codes.split(separator: " ") { map[String(code)] = continent }
        }
        return map
    }()
}

struct ChannelCategory: Codable, Hashable, Sendable, Identifiable {
    /// Lower-case identifier, e.g. "news".
    var id: String
    var name: String

    var symbol: String { Self.symbols[id] ?? "tv" }

    /// The categories surfaced on Home and Explore, in display order.
    static let featuredIDs = ["news", "sports", "entertainment", "movies", "music",
                              "documentary", "kids", "education", "religious", "general"]

    private static let symbols: [String: String] = [
        "news": "newspaper.fill", "sports": "sportscourt.fill",
        "entertainment": "sparkles.tv.fill", "movies": "film.fill",
        "music": "music.note", "documentary": "camera.macro",
        "kids": "teddybear.fill", "education": "graduationcap.fill",
        "religious": "building.columns.fill", "general": "tv.fill",
        "business": "chart.line.uptrend.xyaxis", "weather": "cloud.sun.fill",
        "cooking": "fork.knife", "travel": "airplane", "science": "atom",
        "series": "play.rectangle.on.rectangle.fill", "animation": "wand.and.stars",
        "comedy": "theatermasks.fill", "culture": "paintpalette.fill",
        "lifestyle": "leaf.fill", "shop": "bag.fill", "auto": "car.fill",
        "outdoor": "mountain.2.fill", "family": "figure.2.and.child.holdinghands",
        "legislative": "building.2.fill", "classic": "clock.fill", "relax": "moon.stars.fill",
    ]

    /// Display name for an ID when the directory hasn't supplied one.
    static func fallbackName(for id: String) -> String {
        id.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

struct Language: Codable, Hashable, Sendable, Identifiable {
    var id: String { code }
    var code: String
    var name: String
}
