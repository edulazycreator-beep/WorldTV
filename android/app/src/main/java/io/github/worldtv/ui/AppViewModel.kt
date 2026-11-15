package io.github.worldtv.ui

import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import io.github.worldtv.WorldTVApplication
import io.github.worldtv.data.CatalogState
import io.github.worldtv.data.GuideState
import io.github.worldtv.data.NetworkException
import io.github.worldtv.data.SearchFilters
import io.github.worldtv.data.SearchService
import io.github.worldtv.model.AppSettings
import io.github.worldtv.model.Channel
import io.github.worldtv.model.ChannelCategory
import io.github.worldtv.model.Country
import io.github.worldtv.model.Playlist
import io.github.worldtv.model.UserLibrary
import io.github.worldtv.player.PlayerController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Everything the screens show, derived from the repositories. */
data class CatalogIndex(
    val channels: List<Channel> = emptyList(),
    val byId: Map<String, Channel> = emptyMap(),
    val countries: List<Country> = emptyList(),
    val countryByCode: Map<String, Country> = emptyMap(),
    val categories: List<ChannelCategory> = emptyList(),
    val categoryById: Map<String, ChannelCategory> = emptyMap(),
    val languages: List<io.github.worldtv.model.Language> = emptyList(),
    val channelCountByCountry: Map<String, Int> = emptyMap(),
    val channelCountByCategory: Map<String, Int> = emptyMap(),
)

data class HomeSections(
    val featured: List<Channel> = emptyList(),
    val recent: List<Channel> = emptyList(),
    val favorites: List<Channel> = emptyList(),
    val popular: List<Channel> = emptyList(),
    val recentlyAdded: List<Channel> = emptyList(),
    val categories: List<Pair<ChannelCategory, Int>> = emptyList(),
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val container = (application as WorldTVApplication).container
    private val libraryRepo = container.library
    private val catalogRepo = container.catalog
    private val playlistRepo = container.playlists
    private val guideRepo = container.guide

    val settings: StateFlow<AppSettings> = libraryRepo.settings
    val library: StateFlow<UserLibrary> = libraryRepo.library
    val catalogState: StateFlow<CatalogState> = catalogRepo.state
    val playlists: StateFlow<List<Playlist>> = playlistRepo.playlists
    val guideState: StateFlow<GuideState> = guideRepo.state

    val player = PlayerController(application, container.okHttp, container.userAgent)

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages: SharedFlow<String> = _messages.asSharedFlow()

    /** Directory + playlist channels, with the user's popularity and geo filters applied. */
    val index: StateFlow<CatalogIndex> = combine(
        catalogRepo.state.map { it.catalog }.distinctUntilChanged(),
        playlistRepo.playlists,
        settings.map { it.hideGeoBlocked }.distinctUntilChanged(),
        library.map { it.playCounts }.distinctUntilChanged(),
    ) { catalog, playlists, hideGeo, playCounts ->
        val all = (catalog.channels + playlists.flatMap { it.channels })
            .asSequence()
            .filter { !hideGeo || !it.isGeoBlocked }
            .map { c -> playCounts[c.id]?.let { c.copy(popularity = c.popularity + it * 5) } ?: c }
            .toList()
        val countryCounts = all.groupingBy { it.countryCode ?: "" }.eachCount()
        val categoryCounts = HashMap<String, Int>()
        all.forEach { c -> c.categories.forEach { categoryCounts[it] = (categoryCounts[it] ?: 0) + 1 } }
        val categories = (catalog.categories + categoryCounts.keys
            .filter { id -> catalog.categories.none { it.id == id } }
            .map { ChannelCategory(it, ChannelCategory.fallbackName(it)) })
            .filter { (categoryCounts[it.id] ?: 0) > 0 }
            .sortedBy { it.name }
        CatalogIndex(
            channels = all,
            byId = all.associateBy { it.id },
            countries = catalog.countries.filter { (countryCounts[it.code] ?: 0) > 0 },
            countryByCode = catalog.countries.associateBy { it.code },
            categories = categories,
            categoryById = categories.associateBy { it.id },
            languages = catalog.languages,
            channelCountByCountry = countryCounts,
            channelCountByCategory = categoryCounts,
        )
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, CatalogIndex())

    val home: StateFlow<HomeSections> = combine(index, library) { index, library ->
        val channels = index.channels
        val withLogos = channels.filter { it.logoUrl != null }
        // Stable daily pick so Featured changes once a day, not on every launch.
        val day = System.currentTimeMillis() / 86_400_000L
        val featured = withLogos
            .sortedByDescending { it.popularity }
            .take(200)
            .sortedBy { (it.id.hashCode().toLong() * 31 + day).hashCode() }
            .take(10)
        HomeSections(
            featured = featured,
            recent = library.recentChannelIds(20).mapNotNull { index.byId[it] },
            favorites = library.favoriteIds.mapNotNull { index.byId[it] }.take(20),
            popular = channels.sortedByDescending { it.popularity }.take(24),
            recentlyAdded = channels.filter { it.firstSeen != null }.sortedByDescending { it.firstSeen }.take(24),
            categories = ChannelCategory.featuredIds.mapNotNull { id ->
                index.categoryById[id]?.let { it to (index.channelCountByCategory[id] ?: 0) }
            },
        )
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Eagerly, HomeSections())

    // ---- Search ----------------------------------------------------------------------------

    val searchQuery = MutableStateFlow("")
    val searchFilters = MutableStateFlow(SearchFilters())

    @OptIn(FlowPreview::class)
    val searchResults: StateFlow<List<Channel>> = combine(
        searchQuery.debounce(200), searchFilters, index, library,
    ) { query, filters, index, library ->
        if (query.isBlank() && !filters.isActive) emptyList()
        else SearchService.search(
            index.channels, query, filters, library.favoriteIds.toSet(),
            index.countries.associate { it.code to it.name },
        )
    }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    // ---- Playback --------------------------------------------------------------------------

    private val _queue = MutableStateFlow<List<Channel>>(emptyList())
    val queue: StateFlow<List<Channel>> = _queue.asStateFlow()
    private var sessionId: String? = null

    fun play(channel: Channel, queue: List<Channel> = emptyList()) {
        finishSession()
        _queue.value = queue.ifEmpty { listOf(channel) }
        val config = settings.value
        player.reconnectAttempts = config.reconnectAttempts
        player.play(channel, config.preferHighestQuality, config.startMuted)
        sessionId = libraryRepo.recordPlay(channel)
    }

    fun playAdjacent(offset: Int) {
        val current = player.state.value.channel ?: return
        val list = _queue.value
        if (list.size < 2) return
        val index = list.indexOfFirst { it.id == current.id }.takeIf { it >= 0 } ?: return
        val next = list[(index + offset).mod(list.size)]
        play(next, list)
    }

    fun stopPlayback() {
        finishSession()
        player.stop()
    }

    private fun finishSession() {
        sessionId?.let { libraryRepo.finishSession(it) }
        sessionId = null
    }

    // ---- Library ---------------------------------------------------------------------------

    fun toggleFavorite(id: String) = libraryRepo.toggleFavorite(id)
    fun clearHistory() = libraryRepo.updateLibrary { it.clearHistory() }
    fun createGroup(name: String) = libraryRepo.updateLibrary { it.createGroup(name.trim()) }
    fun renameGroup(id: String, name: String) = libraryRepo.updateLibrary { it.renameGroup(id, name.trim()) }
    fun deleteGroup(id: String) = libraryRepo.updateLibrary { it.deleteGroup(id) }
    fun toggleInGroup(channelId: String, groupId: String) = libraryRepo.updateLibrary { it.toggle(channelId, groupId) }
    fun updateSettings(transform: (AppSettings) -> AppSettings) = libraryRepo.updateSettings(transform)

    // ---- Catalog & guide -------------------------------------------------------------------

    init {
        viewModelScope.launch {
            catalogRepo.load()
            loadGuide(force = false)
        }
    }

    fun refreshCatalog() = viewModelScope.launch { catalogRepo.load(force = true) }

    fun clearCaches() = viewModelScope.launch {
        catalogRepo.clearCache()
        guideRepo.clearCache()
        _messages.tryEmit("Cache cleared. Reloading the directory…")
        catalogRepo.load(force = true)
    }

    private fun guideSources(): List<String> =
        listOfNotNull(settings.value.guideUrl.takeIf { it.isNotBlank() }) + playlists.value.mapNotNull { it.epgUrl }

    fun loadGuide(force: Boolean = true) = viewModelScope.launch { guideRepo.load(guideSources(), force) }

    // ---- Playlists -------------------------------------------------------------------------

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    val validationProgress = MutableStateFlow<Pair<Int, Int>?>(null)

    private fun knownCategories() = index.value.categories.map { it.id }.toSet() + ChannelCategory.featuredIds

    fun importPlaylistUrl(name: String, url: String) = runBusy {
        val playlist = playlistRepo.importUrl(name, url.trim(), knownCategories())
        _messages.tryEmit("Imported ${playlist.channels.size} channels from “${playlist.name}”.")
        if (playlist.epgUrl != null) loadGuide(force = false)
    }

    fun importPlaylistFile(uri: Uri) = runBusy {
        val resolver = getApplication<Application>().contentResolver
        val (bytes, fileName) = withContext(Dispatchers.IO) {
            val name = runCatching {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(0) else null
                }
            }.getOrNull() ?: uri.lastPathSegment ?: "Playlist"
            val data = resolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("The file could not be opened.")
            data to name
        }
        val displayName = fileName.substringBeforeLast('.').ifBlank { "Playlist" }
        val playlist = playlistRepo.importBytes(displayName, fileName, bytes, knownCategories())
        _messages.tryEmit("Imported ${playlist.channels.size} channels from “${playlist.name}”.")
        if (playlist.epgUrl != null) loadGuide(force = false)
    }

    fun refreshPlaylist(id: String) = runBusy {
        playlistRepo.refresh(id, knownCategories())
        _messages.tryEmit("Playlist updated.")
    }

    fun renamePlaylist(id: String, name: String) = playlistRepo.rename(id, name.trim())
    fun setPlaylistEpg(id: String, url: String) {
        playlistRepo.setEpgUrl(id, url.trim())
        loadGuide(force = false)
    }

    fun deletePlaylist(id: String) {
        playlistRepo.delete(id)
        loadGuide(force = false)
    }

    fun validatePlaylist(id: String) = runBusy {
        val playlist = playlists.value.firstOrNull { it.id == id } ?: return@runBusy
        val streams = playlist.channels.flatMap { it.streams }
        validationProgress.value = 0 to streams.size
        val results = container.streamValidator().checkAll(streams) { done, total ->
            validationProgress.value = done to total
        }
        validationProgress.value = null
        playlistRepo.setValidation(id, results)
        val bad = results.values.count { it is io.github.worldtv.model.StreamHealth.Unreachable }
        _messages.tryEmit("Checked ${results.size} streams: ${results.size - bad} reachable, $bad unreachable.")
    }

    fun removeInvalidStreams(id: String) = playlistRepo.removeInvalid(id)

    private fun runBusy(block: suspend () -> Unit) = viewModelScope.launch {
        _busy.value = true
        try {
            block()
        } catch (e: Throwable) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            validationProgress.value = null
            val message = when (e) {
                is NetworkException -> e.message
                else -> e.message ?: "Something went wrong."
            }
            _messages.tryEmit(message ?: "Something went wrong.")
        } finally {
            _busy.value = false
        }
    }

    fun showMessage(text: String) {
        _messages.tryEmit(text)
    }

    override fun onCleared() {
        finishSession()
        player.release()
        super.onCleared()
    }
}
