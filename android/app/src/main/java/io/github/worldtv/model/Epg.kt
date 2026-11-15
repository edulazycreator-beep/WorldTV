package io.github.worldtv.model

/** A single XMLTV `<programme>` entry. Times are epoch millis (UTC). */
data class Programme(
    val channelId: String,
    val start: Long,
    val stop: Long,
    val title: String,
    val subtitle: String? = null,
    val description: String? = null,
    val categories: List<String> = emptyList(),
) {
    val key: String get() = "$channelId|$start"

    fun isAiring(at: Long): Boolean = at in start until stop

    /** 0…1 progress through the programme at [at]. */
    fun progress(at: Long): Float {
        val total = stop - start
        if (total <= 0) return 0f
        return ((at - start).toFloat() / total).coerceIn(0f, 1f)
    }
}

data class EpgChannel(
    val id: String,
    val displayNames: List<String> = emptyList(),
    val iconUrl: String? = null,
)

/** Parsed XMLTV document, indexed for fast "now / next" lookups. */
class ProgrammeGuide(
    channels: Map<String, EpgChannel> = emptyMap(),
    programmes: List<Programme> = emptyList(),
) {
    val channels: Map<String, EpgChannel> = channels
    /** Programmes per XMLTV channel ID, sorted by start time. */
    val programmes: Map<String, List<Programme>> =
        programmes.groupBy { it.channelId }.mapValues { (_, list) -> list.sortedBy { it.start } }

    private val nameIndex: Map<String, String> = buildMap {
        for (channel in channels.values.sortedBy { it.id }) {
            for (name in channel.displayNames) putIfAbsent(name.lowercase(), channel.id)
        }
    }

    val isEmpty: Boolean get() = programmes.isEmpty()
    val programmeCount: Int get() = programmes.values.sumOf { it.size }

    fun current(channelId: String, at: Long = System.currentTimeMillis()): Programme? =
        programmes[channelId]?.firstOrNull { it.isAiring(at) }

    fun upcoming(channelId: String, after: Long = System.currentTimeMillis(), limit: Int = 10): List<Programme> =
        programmes[channelId].orEmpty().filter { it.start >= after }.take(limit)

    fun schedule(channelId: String, from: Long, to: Long): List<Programme> =
        programmes[channelId].orEmpty().filter { it.stop > from && it.start < to }

    /** Merge another guide in; later data wins for duplicate programme starts. */
    fun merge(other: ProgrammeGuide): ProgrammeGuide {
        val mergedChannels = channels + other.channels
        val byChannel = programmes.toMutableMap()
        for ((key, list) in other.programmes) {
            val combined = LinkedHashMap<Long, Programme>()
            byChannel[key].orEmpty().forEach { combined[it.start] = it }
            list.forEach { combined[it.start] = it }
            byChannel[key] = combined.values.toList()
        }
        return ProgrammeGuide(mergedChannels, byChannel.values.flatten())
    }

    /** Resolve which XMLTV channel ID belongs to a catalog channel. */
    fun guideId(channel: Channel): String? {
        channel.epgId?.let { if (programmes.containsKey(it)) return it }
        if (programmes.containsKey(channel.id)) return channel.id
        for (name in listOf(channel.name) + channel.altNames) {
            val id = nameIndex[name.lowercase()]
            if (id != null && programmes.containsKey(id)) return id
        }
        return null
    }

    companion object {
        val EMPTY = ProgrammeGuide()
    }
}
