package io.github.worldtv

import io.github.worldtv.data.CatalogBuilder
import io.github.worldtv.data.DirectoryApi
import io.github.worldtv.data.DirectoryDto
import io.github.worldtv.data.DirectoryResource
import io.github.worldtv.data.DirectorySnapshot
import io.github.worldtv.data.SearchFilters
import io.github.worldtv.data.SearchService
import io.github.worldtv.data.StreamValidator
import io.github.worldtv.data.StreamKind
import io.github.worldtv.data.StreamUrlIssue
import io.github.worldtv.model.Channel
import io.github.worldtv.model.Continent
import io.github.worldtv.model.Country
import io.github.worldtv.model.HistoryEntry
import io.github.worldtv.model.StreamHealth
import io.github.worldtv.model.StreamSource
import io.github.worldtv.model.UserLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CatalogBuilderTest {
    private fun snapshot() = DirectorySnapshot(
        channels = listOf(
            DirectoryDto.Channel(id = "RTB1.bn", name = "RTB Perdana", country = "bn", categories = listOf("General"), website = "https://rtb.gov.bn"),
            DirectoryDto.Channel(id = "Adult.us", name = "Adult", country = "US", isNsfw = true),
            DirectoryDto.Channel(id = "Closed.uk", name = "Closed", country = "GB", closed = "2020-01-01"),
            DirectoryDto.Channel(id = "Blocked.fr", name = "Blocked", country = "FR"),
            DirectoryDto.Channel(id = "NoStream.jp", name = "No Stream", country = "JP"),
            DirectoryDto.Channel(id = "NHK.jp", name = "NHK World", country = "JP", categories = listOf("news")),
            DirectoryDto.Channel(id = null, name = "Missing id"),
        ),
        feeds = listOf(
            DirectoryDto.Feed(channel = "RTB1.bn", id = "SD", isMain = false, languages = listOf("eng")),
            DirectoryDto.Feed(channel = "RTB1.bn", id = "HD", isMain = true, languages = listOf("msa")),
        ),
        logos = listOf(
            DirectoryDto.Logo(channel = "RTB1.bn", feed = "HD", url = "https://a/feed.png", width = 512.0),
            DirectoryDto.Logo(channel = "RTB1.bn", url = "https://a/main.png", width = 256.0),
        ),
        streams = listOf(
            DirectoryDto.Stream(channel = "RTB1.bn", url = "https://rtb.example/live.m3u8", quality = "720p"),
            DirectoryDto.Stream(channel = "RTB1.bn", url = "https://rtb.example/live.m3u8", quality = "720p"),
            DirectoryDto.Stream(channel = "RTB1.bn", url = "rtmp://rtb.example/live", quality = "1080p"),
            DirectoryDto.Stream(channel = "Adult.us", url = "https://x/1.m3u8"),
            DirectoryDto.Stream(channel = "Closed.uk", url = "https://x/2.m3u8"),
            DirectoryDto.Stream(channel = "Blocked.fr", url = "https://x/3.m3u8"),
            DirectoryDto.Stream(channel = "NHK.jp", url = "https://nhk.example/1080.m3u8", quality = "1080p", labels = listOf("Geo-blocked")),
            DirectoryDto.Stream(channel = null, url = "https://orphan/1.m3u8"),
        ),
        categories = listOf(DirectoryDto.Category("general", "General"), DirectoryDto.Category("news", "News")),
        languages = listOf(DirectoryDto.Language("msa", "Malay"), DirectoryDto.Language("eng", "English")),
        countries = listOf(
            DirectoryDto.Country("BN", "Brunei", "🇧🇳"),
            DirectoryDto.Country("JP", "Japan", null),
            DirectoryDto.Country("FR", "France", "🇫🇷"),
        ),
        blocklist = listOf(DirectoryDto.BlocklistEntry("Blocked.fr", "dmca")),
        fetchedAt = 1_000L,
    )

    @Test
    fun filtersAndBuildsChannels() {
        val catalog = CatalogBuilder.build(snapshot(), now = 5L)
        assertEquals(listOf("NHK World", "RTB Perdana"), catalog.channels.map { it.name })
        val rtb = catalog.channels.first { it.id == "RTB1.bn" }
        assertEquals("BN", rtb.countryCode)
        assertEquals(1, rtb.streams.size) // duplicate + rtmp dropped
        assertEquals(listOf("msa"), rtb.languages) // main feed wins
        assertEquals("https://a/main.png", rtb.logoUrl) // channel-level logo preferred
        assertEquals(listOf("general"), rtb.categories)
        assertEquals(5L, rtb.firstSeen)
        assertEquals(1_000L, catalog.updatedAt)

        assertEquals(listOf("BN", "JP"), catalog.countries.map { it.code }.sorted())
        assertEquals(Country.flagEmoji("JP"), catalog.countries.first { it.code == "JP" }.flag)
        assertEquals(listOf("General", "News"), catalog.categories.map { it.name })
        assertEquals(listOf("Malay"), catalog.languages.map { it.name })
    }

    @Test
    fun keepsFirstSeenAcrossRefreshes() {
        val catalog = CatalogBuilder.build(snapshot(), previousFirstSeen = mapOf("RTB1.bn" to 42L), now = 99L)
        assertEquals(42L, catalog.channels.first { it.id == "RTB1.bn" }.firstSeen)
        assertEquals(99L, catalog.channels.first { it.id == "NHK.jp" }.firstSeen)
    }

    @Test
    fun popularityRewardsGoodMetadata() {
        val rich = Channel(
            id = "a", name = "A", countryCode = "ID", categories = listOf("news"), logoUrl = "x", website = "y",
            streams = listOf(StreamSource("https://a/1.m3u8", quality = "1080p"), StreamSource("https://a/2.m3u8")),
        )
        val poor = Channel(id = "b", name = "B", streams = listOf(StreamSource("https://b/1.m3u8", labels = listOf("Geo-blocked"))))
        val featured = Country.featuredCodes.toSet()
        assertTrue(CatalogBuilder.popularity(rich, featured) > CatalogBuilder.popularity(poor, featured))
    }

    @Test
    fun lenientDecodingSkipsMalformedElements() {
        val dir = createTempDir()
        try {
            File(dir, "channels.json").writeText(
                """[{"id":"A.us","name":"A","categories":["news"],"is_nsfw":false,"extra":{"x":1}},
                   {"id":"B.us","name":"B","categories":"not-a-list"},
                   {"id":"C.us","name":null}]"""
            )
            File(dir, "streams.json").writeText("""[{"channel":"A.us","url":"https://a/1.m3u8","user_agent":null}]""")
            val files = mapOf(
                DirectoryResource.CHANNELS to File(dir, "channels.json"),
                DirectoryResource.STREAMS to File(dir, "streams.json"),
            )
            val snapshot = DirectoryApi.decode(files, 7L)
            assertEquals(listOf("A.us", "C.us"), snapshot.channels.map { it.id })
            assertEquals(1, snapshot.streams.size)
            assertTrue(snapshot.countries.isEmpty())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Suppress("DEPRECATION")
    private fun createTempDir(): File = kotlin.io.createTempDir("wtv")
}

class StreamValidatorTest {
    @Test
    fun validatesUrls() {
        assertTrue(StreamValidator.isValid("https://a.example/live.m3u8"))
        assertTrue(StreamValidator.isValid("  http://1.2.3.4:8080/x  "))
        assertEquals(
            StreamValidator.ValidationResult.Invalid(StreamUrlIssue.Empty),
            StreamValidator.validate("  "),
        )
        assertEquals(
            StreamValidator.ValidationResult.Invalid(StreamUrlIssue.UnsupportedScheme("rtmp")),
            StreamValidator.validate("rtmp://a.example/live"),
        )
        assertFalse(StreamValidator.isValid("not a url"))
        assertFalse(StreamValidator.isValid("https:///path-only"))
    }

    @Test
    fun detectsKind() {
        assertEquals(StreamKind.HLS, StreamValidator.kind("https://a/b/index.m3u8?token=1"))
        assertEquals(StreamKind.DASH, StreamValidator.kind("https://a/manifest.mpd"))
        assertEquals(StreamKind.MP4, StreamValidator.kind("https://a/video.MP4"))
        assertEquals(StreamKind.OTHER, StreamValidator.kind("https://a/live"))
    }

    @Test
    fun evaluatesResponses() {
        val hls = "https://a/live.m3u8"
        assertTrue(StreamValidator.evaluate(hls, 200, "#EXTM3U\n#EXT-X-VERSION:3".toByteArray(), 0) is StreamHealth.Ok)
        assertTrue(StreamValidator.evaluate(hls, 200, "<html>".toByteArray(), 0) is StreamHealth.Unreachable)
        val denied = StreamValidator.evaluate(hls, 403, ByteArray(0), 0) as StreamHealth.Unreachable
        assertTrue(denied.reason.contains("geo-blocked"))
        assertTrue(StreamValidator.evaluate("https://a/v.mp4", 206, ByteArray(10), 0) is StreamHealth.Ok)
    }
}

class SearchServiceTest {
    private val channels = listOf(
        Channel(id = "1", name = "RTB Perdana", countryCode = "BN", categories = listOf("general"), popularity = 10),
        Channel(id = "2", name = "Télé Québec", countryCode = "CA", categories = listOf("education"), popularity = 5),
        Channel(id = "3", name = "Sport RTB", countryCode = "BN", categories = listOf("sports"), popularity = 50),
        Channel(id = "4", name = "NHK World", countryCode = "JP", categories = listOf("news"), altNames = listOf("NHK Japan")),
        Channel(id = "5", name = "Geo TV", countryCode = "PK", streams = listOf(StreamSource("https://g/1.m3u8", labels = listOf("Geo-blocked")))),
    )

    @Test
    fun ranksExactThenPrefixThenWord() {
        val results = SearchService.search(channels, "rtb")
        assertEquals(listOf("1", "3"), results.map { it.id })
    }

    @Test
    fun ignoresAccentsAndCase() {
        assertEquals("2", SearchService.search(channels, "tele quebec").single().id)
    }

    @Test
    fun matchesAltNamesCountriesAndCategories() {
        assertEquals("4", SearchService.search(channels, "japan").first().id)
        assertEquals(setOf("1", "3"), SearchService.search(channels, "brunei", countryNames = mapOf("BN" to "Brunei")).map { it.id }.toSet())
        assertEquals("3", SearchService.search(channels, "sports").single().id)
    }

    @Test
    fun appliesFilters() {
        assertEquals(listOf("3", "1"), SearchService.search(channels, "", SearchFilters(countryCode = "BN")).map { it.id })
        assertEquals(listOf("4"), SearchService.search(channels, "", SearchFilters(continent = Continent.ASIA, categoryId = "news")).map { it.id })
        assertEquals(listOf("2"), SearchService.search(channels, "", SearchFilters(favoritesOnly = true), favorites = setOf("2")).map { it.id })
        assertFalse(SearchService.search(channels, "", SearchFilters(hideGeoBlocked = true)).any { it.id == "5" })
    }
}

class UserLibraryTest {
    @Test
    fun favoritesToggleAndOrder() {
        var lib = UserLibrary()
        lib = lib.toggleFavorite("a").toggleFavorite("b")
        assertEquals(listOf("b", "a"), lib.favoriteIds)
        lib = lib.toggleFavorite("a")
        assertEquals(listOf("b"), lib.favoriteIds)
    }

    @Test
    fun historyIsCappedAndCountsPlays() {
        var lib = UserLibrary()
        repeat(UserLibrary.HISTORY_LIMIT + 10) { i -> lib = lib.recordPlay(HistoryEntry(channelId = "c${i % 3}", channelName = "C")) }
        assertEquals(UserLibrary.HISTORY_LIMIT, lib.history.size)
        assertEquals(UserLibrary.HISTORY_LIMIT + 10, lib.playCounts.values.sum())
        assertEquals(3, lib.recentChannelIds().size)
    }

    @Test
    fun finishSessionRecordsDuration() {
        val entry = HistoryEntry(channelId = "a", channelName = "A", startedAt = 1_000)
        val lib = UserLibrary().recordPlay(entry).finishSession(entry.id, at = 61_000)
        assertEquals(60_000L, lib.history.single().duration)
    }

    @Test
    fun groups() {
        var lib = UserLibrary().createGroup("News")
        val id = lib.groups.single().id
        lib = lib.toggle("x", id).toggle("y", id).toggle("x", id).renameGroup(id, "Morning")
        assertEquals(listOf("y"), lib.groups.single().channelIds)
        assertEquals("Morning", lib.groups.single().name)
        assertTrue(lib.deleteGroup(id).groups.isEmpty())
    }

    @Test
    fun continents() {
        assertEquals(Continent.ASIA, Continent.of("bn"))
        assertEquals(Continent.EUROPE, Continent.of("GB"))
        assertEquals(Continent.OTHER, Continent.of(null))
        assertEquals("🇧🇳", Country.flagEmoji("bn"))
    }
}
