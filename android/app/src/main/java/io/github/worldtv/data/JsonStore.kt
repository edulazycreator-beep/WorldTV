package io.github.worldtv.data

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream
import kotlinx.serialization.json.encodeToStream
import java.io.File

/** Atomic JSON file persistence. Corrupt files are moved aside instead of crashing the app. */
class JsonStore(private val dir: File) {
    init {
        dir.mkdirs()
    }

    @OptIn(ExperimentalSerializationApi::class)
    fun <T> read(name: String, serializer: KSerializer<T>): T? {
        val file = File(dir, name)
        if (!file.exists()) return null
        return try {
            file.inputStream().buffered().use { json.decodeFromStream(serializer, it) }
        } catch (e: Exception) {
            file.renameTo(File(dir, "$name.corrupt-${System.currentTimeMillis()}"))
            null
        }
    }

    @OptIn(ExperimentalSerializationApi::class)
    @Synchronized
    fun <T> write(name: String, serializer: KSerializer<T>, value: T) {
        val target = File(dir, name)
        val tmp = File(dir, "$name.tmp")
        tmp.outputStream().buffered().use { json.encodeToStream(serializer, value, it) }
        if (!tmp.renameTo(target)) {
            tmp.copyTo(target, overwrite = true)
            tmp.delete()
        }
    }

    fun delete(name: String) {
        File(dir, name).delete()
    }

    fun file(name: String): File = File(dir, name)

    companion object {
        val json = Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
            encodeDefaults = true
            explicitNulls = false
        }
    }
}
