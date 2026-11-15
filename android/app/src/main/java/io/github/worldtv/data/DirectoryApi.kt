package io.github.worldtv.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.decodeFromStream
import java.io.File

/**
 * Data transfer objects for the public iptv-org API (https://github.com/iptv-org/api).
 * Every field is optional so upstream schema additions or omissions never break the app;
 * records missing essential fields are dropped by [CatalogBuilder].
 */
object DirectoryDto {
    @Serializable
    data class Channel(
        val id: String? = null,
        val name: String? = null,
        @SerialName("alt_names") val altNames: List<String> = emptyList(),
        val country: String? = null,
        val categories: List<String> = emptyList(),
        @SerialName("is_nsfw") val isNsfw: Boolean = false,
        val closed: String? = null,
        @SerialName("replaced_by") val replacedBy: String? = null,
        val website: String? = null,
        val launched: String? = null,
    )

    @Serializable
    data class Feed(
        val channel: String? = null,
        val id: String? = null,
        @SerialName("is_main") val isMain: Boolean = false,
        val languages: List<String> = emptyList(),
    )

    @Serializable
    data class Logo(
        val channel: String? = null,
        val feed: String? = null,
        @SerialName("in_use") val inUse: Boolean = true,
        val width: Double = 0.0,
        val url: String? = null,
    )

    @Serializable
    data class Stream(
        val channel: String? = null,
        val feed: String? = null,
        val title: String? = null,
        val url: String? = null,
        val referrer: String? = null,
        @SerialName("user_agent") val userAgent: String? = null,
        val quality: String? = null,
        val labels: List<String> = emptyList(),
    )

    @Serializable
    data class Category(val id: String? = null, val name: String? = null)

    @Serializable
    data class Language(val code: String? = null, val name: String? = null)

    @Serializable
    data class Country(
        val code: String? = null,
        val name: String? = null,
        val flag: String? = null,
        val languages: List<String> = emptyList(),
    )

    @Serializable
    data class BlocklistEntry(val channel: String? = null, val reason: String? = null)
}

/** The raw directory files decoded together. */
data class DirectorySnapshot(
    val channels: List<DirectoryDto.Channel> = emptyList(),
    val feeds: List<DirectoryDto.Feed> = emptyList(),
    val logos: List<DirectoryDto.Logo> = emptyList(),
    val streams: List<DirectoryDto.Stream> = emptyList(),
    val categories: List<DirectoryDto.Category> = emptyList(),
    val languages: List<DirectoryDto.Language> = emptyList(),
    val countries: List<DirectoryDto.Country> = emptyList(),
    val blocklist: List<DirectoryDto.BlocklistEntry> = emptyList(),
    val fetchedAt: Long = System.currentTimeMillis(),
)

enum class DirectoryResource(val fileName: String, val isRequired: Boolean = false) {
    CHANNELS("channels.json", isRequired = true),
    FEEDS("feeds.json"),
    LOGOS("logos.json"),
    STREAMS("streams.json", isRequired = true),
    CATEGORIES("categories.json"),
    LANGUAGES("languages.json"),
    COUNTRIES("countries.json"),
    BLOCKLIST("blocklist.json"),
}

/** Downloads the public directory. The base URL is configurable (mirror / self-hosted). */
class DirectoryApi(
    private val http: HttpClient,
    private val baseUrl: String = DEFAULT_BASE_URL,
    private val timeoutSeconds: Int = 60,
    private val retry: RetryPolicy = RetryPolicy(),
) {
    fun url(resource: DirectoryResource): String = baseUrl.trimEnd('/') + "/" + resource.fileName

    /** Downloads every resource concurrently into [dir]. Optional resources may be missing. */
    suspend fun download(dir: File): Map<DirectoryResource, File> = coroutineScope {
        dir.mkdirs()
        DirectoryResource.entries.map { resource ->
            async {
                val target = File(dir, resource.fileName)
                try {
                    http.download(url(resource), target, timeoutSeconds, retry)
                    resource to target
                } catch (e: Throwable) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    if (resource.isRequired) throw e
                    null
                }
            }
        }.mapNotNull { it.await() }.toMap()
    }

    companion object {
        const val DEFAULT_BASE_URL = "https://iptv-org.github.io/api/"

        val json = Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
            isLenient = true
            explicitNulls = false
        }

        fun decode(files: Map<DirectoryResource, File>, fetchedAt: Long): DirectorySnapshot {
            fun <T> list(serializer: KSerializer<T>, resource: DirectoryResource): List<T> {
                val file = files[resource]
                if (file == null || !file.exists()) {
                    if (resource.isRequired) throw NetworkException.Decoding("${resource.fileName} is missing")
                    return emptyList()
                }
                return try {
                    decodeLenient(serializer, file)
                } catch (e: Exception) {
                    if (resource.isRequired) throw NetworkException.Decoding("${resource.fileName}: ${e.message}", e)
                    emptyList()
                }
            }
            return DirectorySnapshot(
                channels = list(DirectoryDto.Channel.serializer(), DirectoryResource.CHANNELS),
                feeds = list(DirectoryDto.Feed.serializer(), DirectoryResource.FEEDS),
                logos = list(DirectoryDto.Logo.serializer(), DirectoryResource.LOGOS),
                streams = list(DirectoryDto.Stream.serializer(), DirectoryResource.STREAMS),
                categories = list(DirectoryDto.Category.serializer(), DirectoryResource.CATEGORIES),
                languages = list(DirectoryDto.Language.serializer(), DirectoryResource.LANGUAGES),
                countries = list(DirectoryDto.Country.serializer(), DirectoryResource.COUNTRIES),
                blocklist = list(DirectoryDto.BlocklistEntry.serializer(), DirectoryResource.BLOCKLIST),
                fetchedAt = fetchedAt,
            )
        }

        /**
         * Streams the array straight from disk; if any element has an unexpected shape the
         * file is re-read element by element and only the bad elements are skipped.
         */
        @OptIn(ExperimentalSerializationApi::class)
        fun <T> decodeLenient(serializer: KSerializer<T>, file: File): List<T> =
            try {
                file.inputStream().buffered().use { json.decodeFromStream(ListSerializer(serializer), it) }
            } catch (e: Exception) {
                val array = file.inputStream().buffered().use { json.decodeFromStream(JsonArray.serializer(), it) }
                array.mapNotNull { runCatching { json.decodeFromJsonElement(serializer, it) }.getOrNull() }
            }

        fun <T> decodeLenient(serializer: KSerializer<T>, text: String): List<T> =
            try {
                json.decodeFromString(ListSerializer(serializer), text)
            } catch (e: Exception) {
                json.parseToJsonElement(text).let { it as? JsonArray ?: JsonArray(emptyList()) }
                    .mapNotNull { runCatching { json.decodeFromJsonElement(serializer, it) }.getOrNull() }
            }
    }
}
