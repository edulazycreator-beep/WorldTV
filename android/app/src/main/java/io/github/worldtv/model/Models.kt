package io.github.worldtv.model

import kotlinx.serialization.Serializable

/** A single playable source for a channel. */
@Serializable
data class StreamSource(
    val url: String,
    val title: String? = null,
    /** e.g. "1080p", "720p" — reported by the source when known. */
    val quality: String? = null,
    /** Optional HTTP headers some broadcasters require. */
    val referrer: String? = null,
    val userAgent: String? = null,
    /** Known caveats from the source, e.g. "Geo-blocked", "Not 24/7". */
    val labels: List<String> = emptyList(),
) {
    /** Numeric vertical resolution parsed from [quality] ("720p" -> 720). */
    val qualityRank: Int
        get() = quality?.takeWhile { it.isDigit() }?.toIntOrNull() ?: 0

    val isGeoBlocked: Boolean
        get() = labels.any { it.contains("geo", ignoreCase = true) }
}

/**
 * A television channel, independent of how it is streamed.
 * Directory channels use the iptv-org ID (e.g. "RTB1.bn");
 * playlist channels use "pl:<playlistId>:<tvg-id or name>".
 */
@Serializable
data class Channel(
    val id: String,
    val name: String,
    val altNames: List<String> = emptyList(),
    /** ISO 3166-1 alpha-2, upper-case. Null when unknown. */
    val countryCode: String? = null,
    /** ISO 639-3 codes (directory) or free-text language names (playlists). */
    val languages: List<String> = emptyList(),
    /** Category IDs, lower-case ("news", "sports", …). */
    val categories: List<String> = emptyList(),
    val logoUrl: String? = null,
    val website: String? = null,
    val streams: List<StreamSource> = emptyList(),
    /** Null for the public directory, otherwise the ID of the imported playlist. */
    val playlistId: String? = null,
    val attribution: String = "",
    val usageNotes: String? = null,
    /** XMLTV channel ID used to match programme data. */
    val epgId: String? = null,
    val popularity: Int = 0,
    /** Epoch millis when the channel first appeared in the local catalog. */
    val firstSeen: Long? = null,
) {
    val isFromDirectory: Boolean get() = playlistId == null

    /** Streams ordered best-first: not geo-blocked, then highest quality. */
    val rankedStreams: List<StreamSource>
        get() = streams.sortedWith(
            compareBy<StreamSource> { it.isGeoBlocked }.thenByDescending { it.qualityRank }
        )

    val bestQualityLabel: String? get() = rankedStreams.firstOrNull { it.quality != null }?.quality

    val primaryCategory: String? get() = categories.firstOrNull()

    val isGeoBlocked: Boolean get() = streams.isNotEmpty() && streams.all { it.isGeoBlocked }
}

@Serializable
data class Country(
    val code: String,
    val name: String,
    val flag: String,
    val languages: List<String> = emptyList(),
) {
    val continent: Continent get() = Continent.of(code)

    companion object {
        /** Countries highlighted in Explore, in display order. */
        val featuredCodes = listOf(
            "ID", "BN", "MY", "SG", "US", "GB", "JP", "KR", "CN", "IN", "AU", "DE", "FR", "SA",
        )

        /** Builds a flag emoji from a two-letter code. */
        fun flagEmoji(code: String): String {
            val sb = StringBuilder()
            for (ch in code.uppercase()) {
                if (ch in 'A'..'Z') sb.appendCodePoint(0x1F1E6 + (ch - 'A'))
            }
            return sb.toString()
        }
    }
}

enum class Continent(val displayName: String) {
    ASIA("Asia"),
    EUROPE("Europe"),
    AFRICA("Africa"),
    NORTH_AMERICA("North America"),
    SOUTH_AMERICA("South America"),
    OCEANIA("Oceania"),
    OTHER("Other");

    companion object {
        fun of(countryCode: String?): Continent =
            countryCode?.uppercase()?.let { lookup[it] } ?: OTHER

        private val lookup: Map<String, Continent> by lazy {
            val table = listOf(
                AFRICA to "DZ AO BJ BW BF BI CV CM CF TD KM CG CD CI DJ EG GQ ER SZ ET GA GM GH GN GW KE LS LR LY MG MW ML MR MU YT MA MZ NA NE NG RE RW SH ST SN SC SL SO ZA SS SD TZ TG TN UG EH ZM ZW",
                ASIA to "AF AM AZ BH BD BT BN KH CN CY GE HK IN ID IR IQ IL JP JO KZ KW KG LA LB MO MY MV MN MM NP KP OM PK PS PH QA SA SG KR LK SY TW TJ TH TL TR TM AE UZ VN YE",
                EUROPE to "AX AL AD AT BY BE BA BG HR CZ DK EE FO FI FR DE GI GR GG HU IS IE IM IT JE XK LV LI LT LU MT MD MC ME NL MK NO PL PT RO RU SM RS SK SI ES SJ SE CH UA GB VA",
                NORTH_AMERICA to "AI AG AW BS BB BZ BM BQ VG CA KY CR CU CW DM DO SV GL GD GP GT HT HN JM MQ MX MS NI PA PR BL KN LC MF PM VC SX TT TC US VI UM",
                SOUTH_AMERICA to "AR BO BR CL CO EC FK GF GY PY PE SR UY VE",
                OCEANIA to "AS AU CK FJ PF GU KI MH FM NR NC NZ NU NF MP PW PG PN WS SB TK TO TV VU WF",
            )
            buildMap { for ((c, codes) in table) codes.split(" ").forEach { put(it, c) } }
        }
    }
}

@Serializable
data class ChannelCategory(val id: String, val name: String) {
    companion object {
        /** The categories surfaced on Home and Explore, in display order. */
        val featuredIds = listOf(
            "news", "sports", "entertainment", "movies", "music",
            "documentary", "kids", "education", "religious", "general",
        )

        fun fallbackName(id: String): String =
            id.split('_').joinToString(" ") { part -> part.replaceFirstChar { it.uppercase() } }
    }
}

@Serializable
data class Language(val code: String, val name: String)

/** The in-memory channel catalog shown in the UI. */
@Serializable
data class Catalog(
    val channels: List<Channel> = emptyList(),
    val countries: List<Country> = emptyList(),
    val categories: List<ChannelCategory> = emptyList(),
    val languages: List<Language> = emptyList(),
    /** Epoch millis of the directory download this catalog was built from. */
    val updatedAt: Long? = null,
) {
    val isEmpty: Boolean get() = channels.isEmpty()

    companion object {
        val EMPTY = Catalog()
    }
}
