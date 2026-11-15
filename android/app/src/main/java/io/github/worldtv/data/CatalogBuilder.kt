package io.github.worldtv.data

import io.github.worldtv.model.Catalog
import io.github.worldtv.model.Channel
import io.github.worldtv.model.ChannelCategory
import io.github.worldtv.model.Country
import io.github.worldtv.model.Language
import io.github.worldtv.model.StreamSource

/** Pure transformation from the raw directory files into catalog channels. */
object CatalogBuilder {
    const val ATTRIBUTION = "iptv-org public directory"
    const val USAGE_NOTES = "Publicly available stream listed by the iptv-org community database. " +
        "Availability and rights belong to the broadcaster; some streams are geo-blocked or not 24/7."

    fun build(
        snapshot: DirectorySnapshot,
        previousFirstSeen: Map<String, Long> = emptyMap(),
        now: Long = System.currentTimeMillis(),
    ): Catalog {
        val blocked = snapshot.blocklist.mapNotNull { it.channel }.toHashSet()

        val streamsByChannel = HashMap<String, MutableList<StreamSource>>()
        for (dto in snapshot.streams) {
            val channelId = dto.channel ?: continue
            val valid = StreamValidator.validate(dto.url) as? StreamValidator.ValidationResult.Valid ?: continue
            val list = streamsByChannel.getOrPut(channelId) { mutableListOf() }
            if (list.any { it.url == valid.url }) continue
            list += StreamSource(
                url = valid.url,
                title = dto.title,
                quality = dto.quality,
                referrer = dto.referrer?.takeIf { it.isNotBlank() },
                userAgent = dto.userAgent?.takeIf { it.isNotBlank() },
                labels = dto.labels,
            )
        }

        val languagesByChannel = HashMap<String, List<String>>()
        for (feed in snapshot.feeds) {
            val channel = feed.channel ?: continue
            if (feed.languages.isEmpty()) continue
            if (feed.isMain || channel !in languagesByChannel) languagesByChannel[channel] = feed.languages
        }

        val logoByChannel = HashMap<String, io.github.worldtv.data.DirectoryDto.Logo>()
        for (logo in snapshot.logos) {
            val channel = logo.channel ?: continue
            if (logo.url.isNullOrBlank()) continue
            val current = logoByChannel[channel]
            if (current == null || logoScore(logo) > logoScore(current)) logoByChannel[channel] = logo
        }

        val featured = Country.featuredCodes.toSet()
        val channels = ArrayList<Channel>(streamsByChannel.size)
        for (dto in snapshot.channels) {
            val id = dto.id ?: continue
            if (dto.isNsfw || dto.closed != null || id in blocked || "xxx" in dto.categories) continue
            val streams = streamsByChannel[id]
            if (streams.isNullOrEmpty()) continue
            val base = Channel(
                id = id,
                name = dto.name?.takeIf { it.isNotBlank() } ?: id,
                altNames = dto.altNames,
                countryCode = dto.country?.uppercase(),
                languages = languagesByChannel[id].orEmpty(),
                categories = if (dto.categories.isEmpty()) listOf("general") else dto.categories.map { it.lowercase() },
                logoUrl = logoByChannel[id]?.url,
                website = dto.website?.takeIf { it.isNotBlank() },
                streams = streams,
                attribution = ATTRIBUTION,
                usageNotes = USAGE_NOTES,
                epgId = id,
                firstSeen = previousFirstSeen[id] ?: now,
            )
            channels += base.copy(popularity = popularity(base, featured))
        }
        channels.sortWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

        val usedCountries = channels.mapNotNullTo(HashSet()) { it.countryCode }
        val countries = snapshot.countries
            .filter { it.code != null && it.code.uppercase() in usedCountries }
            .map {
                val code = it.code!!.uppercase()
                Country(code, it.name ?: code, it.flag ?: Country.flagEmoji(code), it.languages)
            }
            .distinctBy { it.code }
            .sortedBy { it.name }

        val usedCategories = channels.flatMapTo(HashSet()) { it.categories }
        val categoryNames = HashMap<String, String>()
        for (c in snapshot.categories) {
            val id = c.id?.lowercase() ?: continue
            categoryNames.putIfAbsent(id, c.name ?: ChannelCategory.fallbackName(id))
        }
        val categories = usedCategories
            .map { ChannelCategory(it, categoryNames[it] ?: ChannelCategory.fallbackName(it)) }
            .sortedBy { it.name }

        val usedLanguages = channels.flatMapTo(HashSet()) { it.languages }
        val languages = snapshot.languages
            .filter { it.code != null && it.code in usedLanguages }
            .map { val code = it.code!!; Language(code, it.name ?: code) }
            .distinctBy { it.code }
            .sortedBy { it.name }

        return Catalog(channels, countries, categories, languages, snapshot.fetchedAt)
    }

    private fun logoScore(logo: DirectoryDto.Logo): Double {
        var score = 0.0
        if (logo.feed == null) score += 10_000
        if (logo.inUse) score += 5_000
        // Prefer reasonably sized logos; very large images waste memory.
        score += minOf(logo.width, 512.0)
        return score
    }

    /**
     * A transparent heuristic: the directory has no viewing figures, so "popular" favours
     * well-documented channels with several good streams. The user's play counts are added on top.
     */
    fun popularity(channel: Channel, featuredCountries: Set<String>): Int {
        var score = minOf(channel.streams.size, 4) * 10
        val best = channel.streams.maxOfOrNull { it.qualityRank } ?: 0
        if (best >= 1080) score += 15 else if (best >= 720) score += 10
        if (channel.streams.any { !it.isGeoBlocked }) score += 10
        if (channel.logoUrl != null) score += 8
        if (channel.website != null) score += 4
        if (channel.countryCode != null && channel.countryCode in featuredCountries) score += 6
        if ("news" in channel.categories || "general" in channel.categories) score += 3
        return score
    }
}
