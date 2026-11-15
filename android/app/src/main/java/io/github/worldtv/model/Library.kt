package io.github.worldtv.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class HistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val channelId: String,
    val channelName: String,
    val startedAt: Long = System.currentTimeMillis(),
    /** Watched duration in milliseconds. */
    val duration: Long = 0,
)

@Serializable
data class ChannelGroup(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val channelIds: List<String> = emptyList(),
)

/** Favorites, groups and watch history. Immutable: every mutation returns a copy. */
@Serializable
data class UserLibrary(
    val favoriteIds: List<String> = emptyList(),
    val history: List<HistoryEntry> = emptyList(),
    val groups: List<ChannelGroup> = emptyList(),
    val playCounts: Map<String, Int> = emptyMap(),
) {
    fun isFavorite(id: String): Boolean = id in favoriteIds

    fun toggleFavorite(id: String): UserLibrary =
        if (id in favoriteIds) copy(favoriteIds = favoriteIds - id)
        else copy(favoriteIds = listOf(id) + favoriteIds)

    fun recordPlay(entry: HistoryEntry): UserLibrary = copy(
        history = (listOf(entry) + history).take(HISTORY_LIMIT),
        playCounts = playCounts + (entry.channelId to (playCounts[entry.channelId] ?: 0) + 1),
    )

    fun finishSession(id: String, at: Long = System.currentTimeMillis()): UserLibrary = copy(
        history = history.map { if (it.id == id) it.copy(duration = (at - it.startedAt).coerceAtLeast(0)) else it },
    )

    fun recentChannelIds(limit: Int = 20): List<String> =
        history.asSequence().map { it.channelId }.distinct().take(limit).toList()

    fun clearHistory(): UserLibrary = copy(history = emptyList())

    fun createGroup(name: String): UserLibrary = copy(groups = groups + ChannelGroup(name = name))

    fun renameGroup(id: String, name: String): UserLibrary =
        copy(groups = groups.map { if (it.id == id) it.copy(name = name) else it })

    fun deleteGroup(id: String): UserLibrary = copy(groups = groups.filterNot { it.id == id })

    fun toggle(channelId: String, groupId: String): UserLibrary = copy(
        groups = groups.map { group ->
            if (group.id != groupId) group
            else if (channelId in group.channelIds) group.copy(channelIds = group.channelIds - channelId)
            else group.copy(channelIds = group.channelIds + channelId)
        },
    )

    companion object {
        const val HISTORY_LIMIT = 500
    }
}

@Serializable
enum class ThemeMode { DARK, SYSTEM, LIGHT }

@Serializable
enum class VideoScale(val title: String) {
    FIT("Fit (letterbox)"),
    FILL("Fill (crop)"),
    STRETCH("Stretch"),
}

@Serializable
data class AppSettings(
    val theme: ThemeMode = ThemeMode.DARK,
    val autoplayOnSelect: Boolean = true,
    val startMuted: Boolean = false,
    val videoScale: VideoScale = VideoScale.FIT,
    val preferHighestQuality: Boolean = true,
    val hideGeoBlocked: Boolean = false,
    /** Seconds. */
    val requestTimeout: Int = 15,
    val maxRetries: Int = 3,
    val reconnectAttempts: Int = 3,
    val directoryRefreshHours: Int = 24,
    val directoryEnabled: Boolean = true,
    val directoryBaseUrl: String = "https://iptv-org.github.io/api/",
    /** Optional XMLTV URL used for the directory channels' guide. */
    val guideUrl: String = "",
    /** Keep playing in Picture-in-Picture when leaving the app. */
    val autoPictureInPicture: Boolean = true,
)

@Serializable
sealed interface StreamHealth {
    @Serializable
    data class Ok(val checkedAt: Long) : StreamHealth

    @Serializable
    data class Unreachable(val reason: String, val checkedAt: Long) : StreamHealth
}

@Serializable
data class Playlist(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    /** Remote URL, or null for a playlist imported from a local file. */
    val remoteUrl: String? = null,
    /** File name for local imports, shown in the UI. */
    val fileName: String? = null,
    val epgUrl: String? = null,
    val channels: List<Channel> = emptyList(),
    val addedAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val validation: Map<String, StreamHealth> = emptyMap(),
) {
    val sourceLabel: String get() = remoteUrl ?: fileName ?: "Local file"

    val invalidStreamCount: Int get() = validation.values.count { it is StreamHealth.Unreachable }
}
