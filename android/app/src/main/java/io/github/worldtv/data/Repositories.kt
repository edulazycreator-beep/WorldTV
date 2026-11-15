package io.github.worldtv.data

import io.github.worldtv.model.AppSettings
import io.github.worldtv.model.Catalog
import io.github.worldtv.model.Channel
import io.github.worldtv.model.HistoryEntry
import io.github.worldtv.model.Playlist
import io.github.worldtv.model.ProgrammeGuide
import io.github.worldtv.model.StreamHealth
import io.github.worldtv.model.UserLibrary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/** Favorites, groups, history and settings, persisted as JSON. */
class LibraryRepository(private val store: JsonStore, private val scope: CoroutineScope) {
    private val _library = MutableStateFlow(store.read(LIBRARY_FILE, UserLibrary.serializer()) ?: UserLibrary())
    val library: StateFlow<UserLibrary> = _library.asStateFlow()

    private val _settings = MutableStateFlow(store.read(SETTINGS_FILE, AppSettings.serializer()) ?: AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private var saveLibraryJob: Job? = null

    fun updateLibrary(transform: (UserLibrary) -> UserLibrary) {
        _library.update(transform)
        saveLibraryJob?.cancel()
        saveLibraryJob = scope.launch(Dispatchers.IO) {
            kotlinx.coroutines.delay(300)
            store.write(LIBRARY_FILE, UserLibrary.serializer(), _library.value)
        }
    }

    fun updateSettings(transform: (AppSettings) -> AppSettings) {
        _settings.update(transform)
        scope.launch(Dispatchers.IO) { store.write(SETTINGS_FILE, AppSettings.serializer(), _settings.value) }
    }

    fun toggleFavorite(id: String) = updateLibrary { it.toggleFavorite(id) }

    /** Records the start of a viewing session and returns its ID. */
    fun recordPlay(channel: Channel): String {
        val entry = HistoryEntry(channelId = channel.id, channelName = channel.name)
        updateLibrary { it.recordPlay(entry) }
        return entry.id
    }

    fun finishSession(id: String) = updateLibrary { it.finishSession(id) }

    companion object {
        const val LIBRARY_FILE = "library.json"
        const val SETTINGS_FILE = "settings.json"
    }
}

data class CatalogState(
    val catalog: Catalog = Catalog.EMPTY,
    val isLoading: Boolean = false,
    val error: String? = null,
)

/** Loads the cached catalog instantly and refreshes it from the public directory. */
class CatalogRepository(
    private val store: JsonStore,
    private val rawDir: File,
    private val http: HttpClient,
    private val settings: StateFlow<AppSettings>,
) {
    private val _state = MutableStateFlow(CatalogState())
    val state: StateFlow<CatalogState> = _state.asStateFlow()
    private val mutex = Mutex()

    suspend fun loadCached() = withContext(Dispatchers.IO) {
        if (!_state.value.catalog.isEmpty) return@withContext
        val cached = store.read(CATALOG_FILE, Catalog.serializer())
        if (cached != null) _state.update { it.copy(catalog = cached) }
    }

    fun isStale(now: Long = System.currentTimeMillis()): Boolean {
        val updated = _state.value.catalog.updatedAt ?: return true
        val hours = settings.value.directoryRefreshHours.coerceAtLeast(1)
        return now - updated > hours * 3_600_000L
    }

    /** Loads the cache, then refreshes when stale (or always when [force]). */
    suspend fun load(force: Boolean = false) {
        loadCached()
        if (!settings.value.directoryEnabled) return
        if (force || isStale() || _state.value.catalog.isEmpty) refresh()
    }

    suspend fun refresh() = mutex.withLock {
        val config = settings.value
        if (!config.directoryEnabled) return@withLock
        _state.update { it.copy(isLoading = true, error = null) }
        try {
            val catalog = withContext(Dispatchers.IO) {
                val api = DirectoryApi(
                    http,
                    config.directoryBaseUrl.ifBlank { DirectoryApi.DEFAULT_BASE_URL },
                    timeoutSeconds = maxOf(config.requestTimeout, 60),
                    retry = RetryPolicy(maxRetries = config.maxRetries),
                )
                val files = api.download(rawDir)
                val snapshot = DirectoryApi.decode(files, System.currentTimeMillis())
                files.values.forEach { it.delete() }
                val previous = _state.value.catalog.channels.mapNotNull { c -> c.firstSeen?.let { c.id to it } }.toMap()
                val built = CatalogBuilder.build(snapshot, previous)
                store.write(CATALOG_FILE, Catalog.serializer(), built)
                built
            }
            _state.update { CatalogState(catalog = catalog) }
        } catch (e: Throwable) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            val message = NetworkException.from(e).message
            _state.update { it.copy(isLoading = false, error = message) }
        }
    }

    fun clearCache() {
        store.delete(CATALOG_FILE)
        rawDir.deleteRecursively()
        _state.value = CatalogState()
    }

    companion object {
        const val CATALOG_FILE = "catalog.json"
    }
}

/** User-imported M3U / M3U8 playlists. */
class PlaylistRepository(
    private val store: JsonStore,
    private val http: HttpClient,
    private val settings: StateFlow<AppSettings>,
) {
    private val _playlists = MutableStateFlow(
        store.read(PLAYLISTS_FILE, ListSerializer(Playlist.serializer())) ?: emptyList()
    )
    val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

    private fun save() = store.write(PLAYLISTS_FILE, ListSerializer(Playlist.serializer()), _playlists.value)

    /** Imports a playlist from raw bytes (e.g. a file chosen by the user). */
    suspend fun importBytes(name: String, fileName: String?, bytes: ByteArray, knownCategories: Set<String>): Playlist =
        withContext(Dispatchers.Default) {
            val parsed = M3UParser.parse(bytes)
            if (parsed.entries.isEmpty()) throw M3UParseException("No playable channels were found in this playlist.")
            val playlist = Playlist(name = name, fileName = fileName, epgUrl = parsed.epgUrls.firstOrNull())
            val withChannels = playlist.copy(channels = parsed.toChannels(playlist.id, name, knownCategories))
            _playlists.update { it + withChannels }
            withContext(Dispatchers.IO) { save() }
            withChannels
        }

    /** Imports a playlist from an HTTP(S) URL. */
    suspend fun importUrl(name: String, url: String, knownCategories: Set<String>): Playlist {
        if (!StreamValidator.isValid(url)) throw M3UParseException("Enter a valid http:// or https:// address.")
        val config = settings.value
        val bytes = http.getBytes(url, config.requestTimeout.coerceAtLeast(15), RetryPolicy(config.maxRetries))
        val parsed = withContext(Dispatchers.Default) { M3UParser.parse(bytes) }
        if (parsed.entries.isEmpty()) throw M3UParseException("No playable channels were found in this playlist.")
        val displayName = name.ifBlank { url.substringAfterLast('/').substringBefore('?').ifBlank { "Playlist" } }
        val playlist = Playlist(name = displayName, remoteUrl = url, epgUrl = parsed.epgUrls.firstOrNull())
        val withChannels = playlist.copy(channels = parsed.toChannels(playlist.id, displayName, knownCategories))
        _playlists.update { it + withChannels }
        withContext(Dispatchers.IO) { save() }
        return withChannels
    }

    /** Re-downloads a remote playlist. Channel IDs are stable, so favorites survive. */
    suspend fun refresh(id: String, knownCategories: Set<String>) {
        val playlist = _playlists.value.firstOrNull { it.id == id } ?: return
        val url = playlist.remoteUrl ?: return
        val config = settings.value
        val bytes = http.getBytes(url, config.requestTimeout.coerceAtLeast(15), RetryPolicy(config.maxRetries))
        val parsed = withContext(Dispatchers.Default) { M3UParser.parse(bytes) }
        val channels = parsed.toChannels(playlist.id, playlist.name, knownCategories)
        update(id) {
            it.copy(
                channels = channels,
                epgUrl = it.epgUrl ?: parsed.epgUrls.firstOrNull(),
                updatedAt = System.currentTimeMillis(),
                validation = emptyMap(),
            )
        }
    }

    fun rename(id: String, name: String) = update(id) { it.copy(name = name) }

    fun setEpgUrl(id: String, url: String?) = update(id) { it.copy(epgUrl = url?.takeIf { u -> u.isNotBlank() }) }

    fun delete(id: String) {
        _playlists.update { list -> list.filterNot { it.id == id } }
        save()
    }

    fun setValidation(id: String, results: Map<String, StreamHealth>) = update(id) { it.copy(validation = results) }

    /** Removes streams that failed validation; channels left without streams are dropped. */
    fun removeInvalid(id: String) = update { playlist ->
        if (playlist.id != id) return@update playlist
        val bad = playlist.validation.filterValues { it is StreamHealth.Unreachable }.keys
        val channels = playlist.channels.mapNotNull { channel ->
            val streams = channel.streams.filterNot { it.url in bad }
            if (streams.isEmpty()) null else channel.copy(streams = streams)
        }
        playlist.copy(channels = channels, validation = playlist.validation - bad)
    }

    private fun update(id: String, transform: (Playlist) -> Playlist) = update { if (it.id == id) transform(it) else it }

    private fun update(transform: (Playlist) -> Playlist) {
        _playlists.update { list -> list.map(transform) }
        save()
    }

    companion object {
        const val PLAYLISTS_FILE = "playlists.json"
    }
}

data class GuideState(
    val guide: ProgrammeGuide = ProgrammeGuide.EMPTY,
    val isLoading: Boolean = false,
    val error: String? = null,
    val sources: List<String> = emptyList(),
)

/** XMLTV programme guides from settings and imported playlists. */
class GuideRepository(
    private val cacheDir: File,
    private val http: HttpClient,
    private val settings: StateFlow<AppSettings>,
) {
    private val _state = MutableStateFlow(GuideState())
    val state: StateFlow<GuideState> = _state.asStateFlow()
    private val mutex = Mutex()

    private fun cacheFile(url: String) = File(cacheDir, "guide-${url.hashCode().toUInt()}.xml")

    /** Loads every source: from the on-disk cache when fresh (< 6 h), otherwise from the network. */
    suspend fun load(urls: List<String>, force: Boolean = false) = mutex.withLock {
        val sources = urls.filter { StreamValidator.isValid(it) }.distinct()
        if (sources.isEmpty()) {
            _state.value = GuideState()
            return@withLock
        }
        _state.update { it.copy(isLoading = true, error = null, sources = sources) }
        var guide = ProgrammeGuide.EMPTY
        val errors = mutableListOf<String>()
        withContext(Dispatchers.IO) {
            cacheDir.mkdirs()
            for (url in sources) {
                try {
                    val file = cacheFile(url)
                    val fresh = file.exists() && System.currentTimeMillis() - file.lastModified() < 6 * 3_600_000L
                    val bytes = if (!force && fresh) file.readBytes() else {
                        val config = settings.value
                        http.getBytes(url, maxOf(config.requestTimeout, 60), RetryPolicy(config.maxRetries))
                            .also { file.writeBytes(it) }
                    }
                    guide = guide.merge(XmlTvParser.parse(bytes))
                } catch (e: Throwable) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    errors += "${url.substringAfter("://").substringBefore('/')}: ${e.message}"
                }
            }
        }
        _state.value = GuideState(guide, false, errors.takeIf { it.isNotEmpty() }?.joinToString("\n"), sources)
    }

    fun clearCache() {
        cacheDir.listFiles()?.forEach { it.delete() }
    }
}
