package io.github.worldtv.data

import io.github.worldtv.model.Channel
import io.github.worldtv.model.Continent
import java.text.Normalizer

/** Filters that can be combined with a text query. */
data class SearchFilters(
    val countryCode: String? = null,
    val continent: Continent? = null,
    val categoryId: String? = null,
    val languageCode: String? = null,
    val favoritesOnly: Boolean = false,
    val hideGeoBlocked: Boolean = false,
) {
    val isActive: Boolean
        get() = countryCode != null || continent != null || categoryId != null ||
            languageCode != null || favoritesOnly || hideGeoBlocked
}

/** Ranked, accent- and case-insensitive channel search. */
object SearchService {
    private val diacritics = "\\p{Mn}+".toRegex()

    fun normalize(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(diacritics, "").lowercase().trim()

    fun matchesFilters(channel: Channel, filters: SearchFilters, favorites: Set<String>): Boolean {
        filters.countryCode?.let { if (channel.countryCode != it) return false }
        filters.continent?.let { if (Continent.of(channel.countryCode) != it) return false }
        filters.categoryId?.let { if (it !in channel.categories) return false }
        filters.languageCode?.let { if (it !in channel.languages) return false }
        if (filters.favoritesOnly && channel.id !in favorites) return false
        if (filters.hideGeoBlocked && channel.isGeoBlocked) return false
        return true
    }

    /**
     * Scores: exact name 100, prefix 80, word prefix 60, contains 40, alt name 30,
     * country/category/language code 20. Ties break on popularity, then name.
     */
    fun search(
        channels: List<Channel>,
        query: String,
        filters: SearchFilters = SearchFilters(),
        favorites: Set<String> = emptySet(),
        countryNames: Map<String, String> = emptyMap(),
        limit: Int = 500,
    ): List<Channel> {
        val q = normalize(query)
        val filtered = channels.asSequence().filter { matchesFilters(it, filters, favorites) }
        if (q.isEmpty()) {
            return filtered.sortedByDescending { it.popularity }.take(limit).toList()
        }
        return filtered
            .mapNotNull { channel -> score(channel, q, countryNames).takeIf { it > 0 }?.let { channel to it } }
            .sortedWith(
                compareByDescending<Pair<Channel, Int>> { it.second }
                    .thenByDescending { it.first.popularity }
                    .thenBy { it.first.name.lowercase() }
            )
            .take(limit)
            .map { it.first }
            .toList()
    }

    fun score(channel: Channel, q: String, countryNames: Map<String, String> = emptyMap()): Int {
        val name = normalize(channel.name)
        var best = when {
            name == q -> 100
            name.startsWith(q) -> 80
            name.split(' ', '-', '_', '.').any { it.startsWith(q) } -> 60
            name.contains(q) -> 40
            else -> 0
        }
        if (best < 30 && channel.altNames.any { normalize(it).contains(q) }) best = 30
        if (best < 20) {
            val code = channel.countryCode?.lowercase()
            val countryName = channel.countryCode?.let { countryNames[it] }?.let(::normalize)
            if (code == q || (countryName != null && countryName.startsWith(q)) ||
                channel.categories.any { it == q || it.startsWith(q) } ||
                channel.languages.any { it.lowercase() == q }
            ) best = 20
        }
        return best
    }
}
