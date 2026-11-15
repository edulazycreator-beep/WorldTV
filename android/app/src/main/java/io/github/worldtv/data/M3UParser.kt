package io.github.worldtv.data

import io.github.worldtv.model.Channel
import io.github.worldtv.model.StreamSource
import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** One `#EXTINF` entry (or bare URL line) from an M3U / M3U8 playlist. */
data class M3UEntry(
    val name: String,
    val url: String,
    val duration: Int = -1,
    val attributes: Map<String, String> = emptyMap(),
    val groupTitle: String? = null,
    val referrer: String? = null,
    val userAgent: String? = null,
) {
    val tvgId: String? get() = attributes["tvg-id"].nonEmpty()
    val tvgName: String? get() = attributes["tvg-name"].nonEmpty()
    val logo: String? get() = attributes["tvg-logo"].nonEmpty()
    val country: String? get() = attributes["tvg-country"].nonEmpty()
    val language: String? get() = attributes["tvg-language"].nonEmpty()
}

data class M3UPlaylist(
    val epgUrls: List<String>,
    val entries: List<M3UEntry>,
    /** Lines that looked like stream entries but could not be parsed. */
    val skippedLines: Int,
)

class M3UParseException(message: String) : Exception(message) {
    companion object {
        val EMPTY get() = M3UParseException("The playlist is empty.")
        val NOT_A_PLAYLIST get() = M3UParseException("This file doesn't look like an M3U playlist.")
    }
}

/**
 * Parser for extended M3U playlists as used by IPTV providers.
 *
 * Supports `#EXTM3U` header attributes (`url-tvg`, `x-tvg-url`), `#EXTINF` attributes
 * (`tvg-id`, `tvg-name`, `tvg-logo`, `tvg-country`, `tvg-language`, `group-title`),
 * `#EXTGRP`, `#EXTVLCOPT` HTTP options and Kodi-style `url|User-Agent=…&Referer=…` suffixes.
 */
object M3UParser {
    private val streamSchemes = setOf("http", "https", "rtmp", "rtsp", "file")

    fun parse(bytes: ByteArray): M3UPlaylist {
        if (bytes.isEmpty()) throw M3UParseException.EMPTY
        return parse(decodeText(bytes))
    }

    /** UTF-8 when valid, otherwise ISO-8859-1 (never fails). */
    fun decodeText(bytes: ByteArray): String = try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
    } catch (e: CharacterCodingException) {
        String(bytes, Charsets.ISO_8859_1)
    }

    fun parse(rawText: String): M3UPlaylist {
        val text = rawText.removePrefix("﻿")
        val lines = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        if (lines.isEmpty()) throw M3UParseException.EMPTY

        val hasHeader = lines[0].uppercase().startsWith("#EXTM3U")
        val hasEntries = lines.any { it.uppercase().startsWith("#EXTINF") }
        val hasUrls = lines.any { isStreamLine(it) }
        if (!hasHeader && !hasEntries && !hasUrls) throw M3UParseException.NOT_A_PLAYLIST

        val epgUrls = mutableListOf<String>()
        val entries = mutableListOf<M3UEntry>()
        var skipped = 0

        var pendingName: String? = null
        var pendingDuration = -1
        var pendingAttributes: Map<String, String> = emptyMap()
        var pendingGroup: String? = null
        var pendingReferrer: String? = null
        var pendingUserAgent: String? = null

        fun resetPending() {
            pendingName = null
            pendingDuration = -1
            pendingAttributes = emptyMap()
            pendingGroup = null
            pendingReferrer = null
            pendingUserAgent = null
        }

        for (line in lines) {
            val upper = line.uppercase()
            when {
                upper.startsWith("#EXTM3U") -> {
                    val attributes = parseAttributes(line.substring("#EXTM3U".length))
                    for (key in listOf("url-tvg", "x-tvg-url", "tvg-url")) {
                        val value = attributes[key] ?: continue
                        for (part in value.split(',')) {
                            val url = part.trim()
                            if (url.contains("://") && url !in epgUrls) epgUrls += url
                        }
                    }
                }
                upper.startsWith("#EXTINF:") -> {
                    if (pendingName != null) skipped++ // previous EXTINF had no URL
                    resetPending()
                    val body = line.substring("#EXTINF:".length)
                    val (meta, title) = splitTitle(body)
                    val durationText = meta.takeWhile { it == '-' || it.isDigit() }
                    pendingDuration = durationText.toIntOrNull() ?: -1
                    pendingAttributes = parseAttributes(meta.substring(durationText.length))
                    pendingName = title
                    pendingGroup = pendingAttributes["group-title"].nonEmpty()
                }
                upper.startsWith("#EXTGRP:") -> {
                    pendingGroup = line.substring("#EXTGRP:".length).trim().nonEmpty()
                }
                upper.startsWith("#EXTVLCOPT:") -> {
                    val option = line.substring("#EXTVLCOPT:".length)
                    optionValue(option, "http-referrer")?.let { pendingReferrer = it }
                    optionValue(option, "http-user-agent")?.let { pendingUserAgent = it }
                }
                line.startsWith("#") -> Unit
                else -> {
                    val (url, headers) = splitKodiHeaders(line)
                    val scheme = url.substringBefore("://", "").lowercase()
                    if (!url.contains("://") || scheme !in streamSchemes) {
                        skipped++
                        resetPending()
                        continue
                    }
                    val path = url.substringAfter("://").substringBefore('?').substringBefore('#')
                    val host = path.substringBefore('/')
                    val lastComponent = path.substringAfterLast('/', "").substringBeforeLast('.')
                    val name = pendingName.nonEmpty()
                        ?: pendingAttributes["tvg-name"].nonEmpty()
                        ?: lastComponent.ifEmpty { host.ifEmpty { url } }
                    entries += M3UEntry(
                        name = name,
                        url = url,
                        duration = pendingDuration,
                        attributes = pendingAttributes,
                        groupTitle = pendingGroup,
                        referrer = pendingReferrer ?: headers["referer"] ?: headers["referrer"],
                        userAgent = pendingUserAgent ?: headers["user-agent"],
                    )
                    resetPending()
                }
            }
        }
        if (pendingName != null) skipped++

        return M3UPlaylist(epgUrls, entries, skipped)
    }

    private fun isStreamLine(line: String): Boolean {
        val lower = line.lowercase()
        return lower.startsWith("http://") || lower.startsWith("https://") ||
            lower.startsWith("rtmp://") || lower.startsWith("rtsp://")
    }

    /** Splits `-1 tvg-id="x",Channel Name`, ignoring commas inside quoted values. */
    fun splitTitle(body: String): Pair<String, String> {
        var inQuotes = false
        for ((index, char) in body.withIndex()) {
            if (char == '"') inQuotes = !inQuotes
            if (char == ',' && !inQuotes) {
                return body.substring(0, index) to body.substring(index + 1).trim()
            }
        }
        return body to ""
    }

    /** Parses `key="value" key2=value2` pairs. Keys are lower-cased. */
    fun parseAttributes(text: String): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        val chars = text
        var i = 0
        while (i < chars.length) {
            while (i < chars.length && chars[i].isWhitespace()) i++
            val keyStart = i
            while (i < chars.length && chars[i] != '=' && !chars[i].isWhitespace()) i++
            val key = chars.substring(keyStart, i).lowercase()
            if (i >= chars.length || chars[i] != '=') {
                i++
                continue
            }
            i++ // skip '='
            val value: String
            if (i < chars.length && (chars[i] == '"' || chars[i] == '\'')) {
                val quote = chars[i]
                i++
                val valueStart = i
                while (i < chars.length && chars[i] != quote) i++
                value = chars.substring(valueStart, minOf(i, chars.length))
                i++
            } else {
                val valueStart = i
                while (i < chars.length && !chars[i].isWhitespace()) i++
                value = chars.substring(valueStart, i)
            }
            if (key.isNotEmpty()) result[key] = value.trim()
        }
        return result
    }

    private fun optionValue(option: String, key: String): String? {
        val parts = option.split('=', limit = 2)
        if (parts.size != 2 || parts[0].trim().lowercase() != key) return null
        return parts[1].trim().nonEmpty()
    }

    private fun splitKodiHeaders(line: String): Pair<String, Map<String, String>> {
        val pipe = line.indexOf('|')
        if (pipe < 0) return line to emptyMap()
        val headers = HashMap<String, String>()
        for (pair in line.substring(pipe + 1).split('&')) {
            val kv = pair.split('=', limit = 2)
            if (kv.size != 2) continue
            val value = runCatching { URLDecoder.decode(kv[1], "UTF-8") }.getOrDefault(kv[1])
            headers[kv[0].trim().lowercase()] = value
        }
        return line.substring(0, pipe) to headers
    }

    fun qualityHint(name: String): String? {
        val lower = name.lowercase()
        val table = listOf(
            "2160" to "2160p", "4k" to "2160p", "1080" to "1080p", "720" to "720p",
            "576" to "576p", "480" to "480p", "360" to "360p",
        )
        return table.firstOrNull { lower.contains(it.first) }?.second
    }
}

/**
 * Converts entries into catalog channels for a playlist. Entries that share a `tvg-id`
 * (or name, when there is no ID) become one channel with several stream sources.
 * IDs are stable across playlist updates so favorites survive a refresh.
 */
fun M3UPlaylist.toChannels(
    playlistId: String,
    playlistName: String,
    knownCategoryIds: Set<String>,
    now: Long = System.currentTimeMillis(),
): List<Channel> {
    val byKey = LinkedHashMap<String, Channel>()
    for (entry in entries) {
        val rawKey = (entry.tvgId ?: entry.name).lowercase()
        val key = "pl:$playlistId:$rawKey"
        val stream = StreamSource(
            url = entry.url,
            title = entry.name,
            quality = M3UParser.qualityHint(entry.name),
            referrer = entry.referrer,
            userAgent = entry.userAgent,
        )
        val existing = byKey[key]
        if (existing != null) {
            if (existing.streams.none { it.url == stream.url }) {
                byKey[key] = existing.copy(streams = existing.streams + stream)
            }
            continue
        }
        val groups = (entry.groupTitle ?: "")
            .split(';', '|')
            .map { it.trim().lowercase() }
            .filter { it.isNotEmpty() }
        val categories = groups.map { group ->
            when {
                group in knownCategoryIds -> group
                else -> knownCategoryIds.firstOrNull { group.contains(it) } ?: group
            }
        }.distinct()
        val country = entry.country
            ?.split(';', ',')
            ?.firstOrNull()
            ?.trim()?.uppercase()
            ?.takeIf { it.length == 2 }
        val languages = (entry.language ?: "")
            .split(';', ',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val tvgName = entry.tvgName
        byKey[key] = Channel(
            id = key,
            name = tvgName ?: entry.name,
            altNames = if (tvgName != null && tvgName != entry.name) listOf(entry.name) else emptyList(),
            countryCode = country,
            languages = languages,
            categories = categories,
            logoUrl = entry.logo,
            streams = listOf(stream),
            playlistId = playlistId,
            attribution = "Imported playlist “$playlistName”",
            usageNotes = "Provided by the user. Make sure you are authorized to use this playlist.",
            epgId = entry.tvgId,
            firstSeen = now,
        )
    }
    return byKey.values.toList()
}

/** Null for null, empty or whitespace-only strings. */
fun String?.nonEmpty(): String? = this?.trim()?.takeIf { it.isNotEmpty() }
