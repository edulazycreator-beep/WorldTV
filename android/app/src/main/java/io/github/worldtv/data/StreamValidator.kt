package io.github.worldtv.data

import io.github.worldtv.model.StreamHealth
import io.github.worldtv.model.StreamSource
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.Request
import java.net.URI
import java.net.URL
import java.util.concurrent.atomic.AtomicInteger

sealed class StreamUrlIssue(val message: String) {
    data object Empty : StreamUrlIssue("No stream address was provided.")
    data object Malformed : StreamUrlIssue("The stream address is not a valid URL.")
    data object MissingHost : StreamUrlIssue("The stream address has no server name.")
    data class UnsupportedScheme(val scheme: String) :
        StreamUrlIssue("\"$scheme\" streams are not supported. World TV plays HTTP(S) HLS, DASH and MP4 streams.")
}

enum class StreamKind { HLS, DASH, MP4, OTHER }

/**
 * Validates stream URLs and performs lightweight availability checks.
 * A check downloads at most a few kilobytes — never the stream itself.
 */
class StreamValidator(
    private val http: HttpClient,
    private val timeoutSeconds: Int = 10,
    private val maxProbeBytes: Int = 64 * 1024,
    private val maxConcurrentChecks: Int = 8,
) {
    suspend fun check(stream: StreamSource, now: Long = System.currentTimeMillis()): StreamHealth {
        val url = when (val result = validate(stream.url)) {
            is ValidationResult.Invalid -> return StreamHealth.Unreachable(result.issue.message, now)
            is ValidationResult.Valid -> result.url
        }
        val builder = try {
            Request.Builder().url(url)
        } catch (e: IllegalArgumentException) {
            return StreamHealth.Unreachable(StreamUrlIssue.Malformed.message, now)
        }
        if (kind(url) != StreamKind.HLS) builder.header("Range", "bytes=0-${maxProbeBytes - 1}")
        stream.referrer?.let { builder.header("Referer", it) }
        stream.userAgent?.let { builder.header("User-Agent", it) }
        return try {
            val (status, body) = http.probe(builder.build(), maxProbeBytes, timeoutSeconds)
            evaluate(url, status, body, now)
        } catch (e: Throwable) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            StreamHealth.Unreachable(NetworkException.from(e).message ?: "Unreachable", now)
        }
    }

    /** Checks many streams with bounded concurrency. */
    suspend fun checkAll(
        streams: List<StreamSource>,
        progress: (done: Int, total: Int) -> Unit = { _, _ -> },
    ): Map<String, StreamHealth> = coroutineScope {
        val semaphore = Semaphore(maxConcurrentChecks.coerceAtLeast(1))
        val done = AtomicInteger(0)
        streams.distinctBy { it.url }.map { stream ->
            async {
                semaphore.withPermit {
                    val health = check(stream)
                    progress(done.incrementAndGet(), streams.size)
                    stream.url to health
                }
            }
        }.associate { it.await() }
    }

    sealed interface ValidationResult {
        data class Valid(val url: String) : ValidationResult
        data class Invalid(val issue: StreamUrlIssue) : ValidationResult
    }

    companion object {
        val supportedSchemes = setOf("http", "https")

        /** Static validation: parses and checks scheme and host. */
        fun validate(raw: String?): ValidationResult {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return ValidationResult.Invalid(StreamUrlIssue.Empty)
            val (scheme, host) = try {
                val uri = URI(trimmed)
                (uri.scheme?.lowercase()) to (uri.host ?: uri.rawAuthority?.substringAfter('@')?.substringBefore(':'))
            } catch (e: Exception) {
                try {
                    val url = URL(trimmed)
                    url.protocol?.lowercase() to url.host
                } catch (e2: Exception) {
                    return ValidationResult.Invalid(StreamUrlIssue.Malformed)
                }
            }
            if (scheme == null) return ValidationResult.Invalid(StreamUrlIssue.Malformed)
            if (scheme !in supportedSchemes) return ValidationResult.Invalid(StreamUrlIssue.UnsupportedScheme(scheme))
            if (host.isNullOrEmpty()) return ValidationResult.Invalid(StreamUrlIssue.MissingHost)
            return ValidationResult.Valid(trimmed)
        }

        fun isValid(raw: String?): Boolean = validate(raw) is ValidationResult.Valid

        fun kind(url: String): StreamKind {
            val lower = url.lowercase()
            val path = lower.substringBefore('?').substringBefore('#')
            return when {
                path.endsWith(".m3u8") || path.endsWith(".m3u") || lower.contains("m3u8") -> StreamKind.HLS
                path.endsWith(".mpd") -> StreamKind.DASH
                path.endsWith(".mp4") || path.endsWith(".m4v") || path.endsWith(".mov") -> StreamKind.MP4
                else -> StreamKind.OTHER
            }
        }

        fun evaluate(url: String, status: Int, body: ByteArray, now: Long): StreamHealth = when (status) {
            in 200..299 -> {
                if (kind(url) == StreamKind.HLS) {
                    val head = String(body, 0, minOf(body.size, 1024), Charsets.UTF_8)
                        .trim().trimStart('﻿')
                    if (!head.startsWith("#EXTM3U")) {
                        StreamHealth.Unreachable("The server did not return an HLS playlist.", now)
                    } else StreamHealth.Ok(now)
                } else StreamHealth.Ok(now)
            }
            401, 403 -> StreamHealth.Unreachable("Access denied (HTTP $status). The stream may be geo-blocked.", now)
            404, 410 -> StreamHealth.Unreachable("The stream no longer exists (HTTP $status).", now)
            else -> StreamHealth.Unreachable(NetworkException.describe(status), now)
        }
    }
}
