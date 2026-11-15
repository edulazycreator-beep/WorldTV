package io.github.worldtv

import android.app.Application
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.disk.DiskCache
import coil.memory.MemoryCache
import io.github.worldtv.data.CatalogRepository
import io.github.worldtv.data.GuideRepository
import io.github.worldtv.data.HttpClient
import io.github.worldtv.data.JsonStore
import io.github.worldtv.data.LibraryRepository
import io.github.worldtv.data.PlaylistRepository
import io.github.worldtv.data.StreamValidator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

/** Manual dependency container; one instance per process. */
class AppContainer(app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val userAgent = "WorldTV/${BuildConfig.VERSION_NAME} (Android)"

    val okHttp: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .build()

    val http = HttpClient(okHttp, userAgent)
    val store = JsonStore(File(app.filesDir, "data"))
    val library = LibraryRepository(store, scope)
    val catalog = CatalogRepository(store, File(app.cacheDir, "directory"), http, library.settings)
    val playlists = PlaylistRepository(store, http, library.settings)
    val guide = GuideRepository(File(app.cacheDir, "guides"), http, library.settings)

    fun streamValidator() = StreamValidator(http, timeoutSeconds = library.settings.value.requestTimeout.coerceIn(5, 30))
}

class WorldTVApplication : Application(), ImageLoaderFactory {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .okHttpClient { container.okHttp }
        .memoryCache { MemoryCache.Builder(this).maxSizePercent(0.15).build() }
        .diskCache {
            DiskCache.Builder()
                .directory(cacheDir.resolve("logos"))
                .maxSizeBytes(64L * 1024 * 1024)
                .build()
        }
        .crossfade(true)
        .respectCacheHeaders(false)
        .build()
}
