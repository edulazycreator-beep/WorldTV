package io.github.worldtv

import io.github.worldtv.data.M3UParseException
import io.github.worldtv.data.M3UParser
import io.github.worldtv.data.XmlTvParseException
import io.github.worldtv.data.XmlTvParser
import io.github.worldtv.data.toChannels
import io.github.worldtv.model.Channel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.GZIPOutputStream

class M3UParserTest {
    private val sample = """
        #EXTM3U url-tvg="https://example.com/epg.xml.gz,https://example.com/epg2.xml" x-tvg-url="https://example.com/epg.xml.gz"
        #EXTINF:-1 tvg-id="RTB1.bn" tvg-name="RTB Perdana" tvg-logo="https://example.com/rtb.png" tvg-country="BN" tvg-language="Malay" group-title="News;General",RTB Perdana HD
        https://example.com/rtb/index.m3u8
        #EXTINF:-1 tvg-id="RTB1.bn",RTB Perdana 720p
        #EXTVLCOPT:http-referrer=https://rtb.example/
        #EXTVLCOPT:http-user-agent=CustomAgent/1.0
        https://backup.example.com/rtb.m3u8
        #EXTINF:0 group-title="Music, Pop",Hits, the "best" channel
        #EXTGRP:Music
        http://music.example.com/live.m3u8|User-Agent=Kodi%2F20&Referer=https://music.example/
        #EXTINF:-1,Broken entry
        not a url
        https://bare.example.com/stream/channel5.m3u8
    """.trimIndent()

    @Test
    fun parsesHeaderEntriesAndOptions() {
        val playlist = M3UParser.parse(sample)
        assertEquals(listOf("https://example.com/epg.xml.gz", "https://example.com/epg2.xml"), playlist.epgUrls)
        assertEquals(4, playlist.entries.size)
        assertEquals(1, playlist.skippedLines)

        val first = playlist.entries[0]
        assertEquals("RTB Perdana HD", first.name)
        assertEquals("RTB1.bn", first.tvgId)
        assertEquals("https://example.com/rtb.png", first.logo)
        assertEquals("BN", first.country)
        assertEquals("News;General", first.groupTitle)

        val second = playlist.entries[1]
        assertEquals("https://rtb.example/", second.referrer)
        assertEquals("CustomAgent/1.0", second.userAgent)

        val third = playlist.entries[2]
        assertEquals("Hits, the \"best\" channel", third.name)
        assertEquals("Music", third.groupTitle)
        assertEquals("http://music.example.com/live.m3u8", third.url)
        assertEquals("Kodi/20", third.userAgent)
        assertEquals("https://music.example/", third.referrer)

        assertEquals("channel5", playlist.entries[3].name)
    }

    @Test
    fun mergesEntriesSharingTvgIdIntoOneChannel() {
        val playlist = M3UParser.parse(sample)
        val channels: List<Channel> = playlist.toChannels("p1", "Mine", setOf("news", "music"))
        assertEquals(3, channels.size)
        val rtb = channels.first()
        assertEquals("pl:p1:rtb1.bn", rtb.id)
        assertEquals("RTB Perdana", rtb.name)
        assertEquals(2, rtb.streams.size)
        assertEquals("BN", rtb.countryCode)
        assertEquals(listOf("news", "general"), rtb.categories)
        assertEquals("p1", rtb.playlistId)
        assertEquals("720p", rtb.streams[1].quality)
        assertEquals(listOf("music"), channels[1].categories)
    }

    @Test
    fun attributeParsingHandlesQuotesAndBareValues() {
        val attrs = M3UParser.parseAttributes(""" tvg-id="a b" tvg-name='c' radio=true GROUP-TITLE="x" """)
        assertEquals("a b", attrs["tvg-id"])
        assertEquals("c", attrs["tvg-name"])
        assertEquals("true", attrs["radio"])
        assertEquals("x", attrs["group-title"])
    }

    @Test
    fun rejectsEmptyAndNonPlaylists() {
        try {
            M3UParser.parse(ByteArray(0)); fail()
        } catch (e: M3UParseException) {
            assertTrue(e.message!!.contains("empty"))
        }
        try {
            M3UParser.parse("hello world\njust text"); fail()
        } catch (e: M3UParseException) {
            assertTrue(e.message!!.contains("M3U"))
        }
    }

    @Test
    fun decodesLatin1WhenNotUtf8() {
        val bytes = "#EXTM3U\n#EXTINF:-1,Café TV\nhttp://a.example/x.m3u8\n".toByteArray(Charsets.ISO_8859_1)
        assertEquals("Café TV", M3UParser.parse(bytes).entries.single().name)
    }

    @Test
    fun stripsBomAndHandlesCrLf() {
        val text = "﻿#EXTM3U\r\n#EXTINF:-1,One\r\nhttps://a.example/1.m3u8\r\n"
        assertEquals("One", M3UParser.parse(text).entries.single().name)
    }

    @Test
    fun qualityHints() {
        assertEquals("1080p", M3UParser.qualityHint("News FHD 1080"))
        assertEquals("2160p", M3UParser.qualityHint("Movies 4K"))
        assertNull(M3UParser.qualityHint("Plain"))
    }
}

class XmlTvParserTest {
    private val xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tv SYSTEM "xmltv.dtd">
        <tv generator-info-name="test">
          <channel id="RTB1.bn">
            <display-name>RTB Perdana</display-name>
            <display-name>RTB 1</display-name>
            <icon src="https://example.com/rtb.png"/>
          </channel>
          <programme start="20261115080000 +0800" stop="20261115090000 +0800" channel="RTB1.bn">
            <title lang="ms">Berita Pagi</title>
            <sub-title>Edisi Minggu</sub-title>
            <desc><![CDATA[Morning news & weather]]></desc>
            <category>News</category>
          </programme>
          <programme start="20261115090000 +0800" channel="RTB1.bn">
            <title>Drama</title>
          </programme>
        </tv>
    """.trimIndent()

    @Test
    fun parsesChannelsAndProgrammes() {
        val guide = XmlTvParser.parse(xml.toByteArray())
        val channel = guide.channels["RTB1.bn"]
        assertNotNull(channel)
        assertEquals(listOf("RTB Perdana", "RTB 1"), channel!!.displayNames)
        assertEquals("https://example.com/rtb.png", channel.iconUrl)

        val programmes = guide.programmes["RTB1.bn"]!!
        assertEquals(2, programmes.size)
        val first = programmes[0]
        assertEquals("Berita Pagi", first.title)
        assertEquals("Edisi Minggu", first.subtitle)
        assertEquals("Morning news & weather", first.description)
        assertEquals(listOf("News"), first.categories)
        // 08:00 +0800 == 00:00 UTC
        assertEquals(XmlTvParser.parseDate("20261115000000 +0000"), first.start)
        assertEquals(3_600_000L, first.stop - first.start)
        // Missing stop defaults to 30 minutes.
        assertEquals(30 * 60_000L, programmes[1].stop - programmes[1].start)

        val at = first.start + 10 * 60_000
        assertEquals("Berita Pagi", guide.current("RTB1.bn", at)?.title)
        assertEquals("Drama", guide.upcoming("RTB1.bn", at).single().title)
    }

    @Test
    fun parsesGzip() {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(xml.toByteArray()) }
        assertTrue(XmlTvParser.isGzipped(out.toByteArray()))
        assertEquals(2, XmlTvParser.parse(out.toByteArray()).programmeCount)
    }

    @Test
    fun matchesCatalogChannelsByIdOrName() {
        val guide = XmlTvParser.parse(xml.toByteArray())
        assertEquals("RTB1.bn", guide.guideId(Channel(id = "x", name = "Other", epgId = "RTB1.bn")))
        assertEquals("RTB1.bn", guide.guideId(Channel(id = "pl:1:rtb", name = "rtb 1")))
        assertNull(guide.guideId(Channel(id = "nope", name = "Nope")))
    }

    @Test
    fun dateParsing() {
        val utc = XmlTvParser.parseDate("20260101000000 +0000")!!
        assertEquals(utc, XmlTvParser.parseDate("20260101")!!)
        // 05:30 at +05:00 is 00:30 UTC; 19:00 at -05:00 the previous day is 00:00 UTC.
        assertEquals(utc + 30 * 60_000L, XmlTvParser.parseDate("20260101053000 +0500"))
        assertEquals(utc, XmlTvParser.parseDate("20251231190000 -0500"))
        assertNull(XmlTvParser.parseDate("2026"))
    }

    @Test
    fun rejectsNonXmltv() {
        try {
            XmlTvParser.parse("<html><body>nope</body></html>".toByteArray()); fail()
        } catch (e: XmlTvParseException) {
            assertTrue(e.message!!.contains("XMLTV"))
        }
    }

    @Test
    fun keepsProgrammesFromTruncatedFile() {
        val truncated = xml.substringBefore("<programme start=\"20261115090000")
        val guide = XmlTvParser.parse(truncated.toByteArray())
        assertEquals(1, guide.programmeCount)
    }
}
