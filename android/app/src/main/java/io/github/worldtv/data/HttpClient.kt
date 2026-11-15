package io.github.worldtv.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Errors surfaced to the UI with readable messages. */
sealed class NetworkException(message: String, cause: Throwable? = null) : IOException(message, cause) {
    class Offline(cause: Throwable? = null) :
        NetworkException("You appear to be offline. Check your internet connection.", cause)

    class Timeout(cause: Throwable? = null) :
        NetworkException("The server took too long to respond.", cause)

    class HttpStatus(val code: Int) : NetworkException(describe(code))

    class Decoding(detail: String, cause: Throwable? = null) :
        NetworkException("The data could not be read: $detail", cause)

    class Other(cause: Throwable) : NetworkException(cause.message ?: "Network error", cause)

    /** Whether trying again could plausibly succeed. */
    val isRetryable: Boolean
        get() = when (this) {
            is Offline, is Timeout, is Other -> true
            is HttpStatus -> code == 408 || code == 429 || code >= 500
            is Decoding -> false
        }

    companion object {
        fun describe(code: Int): String = when (code) {
            401, 403 -> "Access denied (HTTP $code). The content may be geo-blocked."
            404, 410 -> "Not found (HTTP $code)."
            429 -> "Too many requests (HTTP 429). Try again shortly."
            in 500..599 -> "The server had a problem (HTTP $code)."
            else -> "Unexpected server response (HTTP $code)."
        }

        fun from(error: Throwable): NetworkException = when (error) {
            is NetworkException -> error
            is UnknownHostException -> Offline(error)
            is SocketTimeoutException -> Timeout(error)
            else -> Other(error)
        }
    }
}

data class RetryPolicy(val maxRetries: Int = 3, val baseDelayMs: Long = 500, val maxDelayMs: Long = 8_000) {
    fun delayFor(attempt: Int): Long = (baseDelayMs shl attempt.coerceAtMost(10)).coerceAtMost(maxDelayMs)
}

/** Thin coroutine wrapper over OkHttp with retries and readable errors. */
class HttpClient(
    val okHttp: OkHttpClient,
    private val userAgent: String,
) {
    suspend fun getBytes(url: String, timeoutSeconds: Int = 30, retry: RetryPolicy = RetryPolicy()): ByteArray =
        withRetry(retry) { execute(url, timeoutSeconds) { it.body!!.bytes() } }

    suspend fun getText(url: String, timeoutSeconds: Int = 30, retry: RetryPolicy = RetryPolicy()): String =
        getBytes(url, timeoutSeconds, retry).toString(Charsets.UTF_8)

    /** Streams the body into [target] (atomically replaced on success). */
    suspend fun download(url: String, target: File, timeoutSeconds: Int = 60, retry: RetryPolicy = RetryPolicy()) {
        withRetry(retry) {
            execute(url, timeoutSeconds) { response ->
                target.parentFile?.mkdirs()
                val tmp = File(target.parentFile, target.name + ".part")
                response.body!!.byteStream().use { input -> tmp.outputStream().use { input.copyTo(it) } }
                if (!tmp.renameTo(target)) {
                    tmp.copyTo(target, overwrite = true)
                    tmp.delete()
                }
            }
        }
    }

    /**
     * Fetches at most [maxBytes] of the response (used for stream health checks).
     * Returns the HTTP status and the bytes read.
     */
    suspend fun probe(request: Request, maxBytes: Int, timeoutSeconds: Int): Pair<Int, ByteArray> =
        withContext(Dispatchers.IO) {
            val client = okHttp.newBuilder()
                .callTimeout(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                .build()
            client.newCall(request).await().use { response ->
                val body = response.body ?: return@use response.code to ByteArray(0)
                val buffer = ByteArray(maxBytes)
                var read = 0
                body.byteStream().use { input ->
                    while (read < maxBytes) {
                        val n = input.read(buffer, read, maxBytes - read)
                        if (n < 0) break
                        read += n
                    }
                }
                response.code to buffer.copyOf(read)
            }
        }

    private suspend fun <T> execute(url: String, timeoutSeconds: Int, block: (Response) -> T): T =
        withContext(Dispatchers.IO) {
            val client = okHttp.newBuilder()
                .callTimeout(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                .readTimeout(timeoutSeconds.toLong(), TimeUnit.SECONDS)
                .build()
            val request = Request.Builder().url(url).header("User-Agent", userAgent).build()
            try {
                client.newCall(request).await().use { response ->
                    if (!response.isSuccessful) throw NetworkException.HttpStatus(response.code)
                    block(response)
                }
            } catch (e: IllegalArgumentException) {
                throw NetworkException.Other(e)
            }
        }

    private suspend fun <T> withRetry(policy: RetryPolicy, block: suspend () -> T): T {
        var attempt = 0
        while (true) {
            try {
                return block()
            } catch (e: Throwable) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                val error = NetworkException.from(e)
                if (!error.isRetryable || attempt >= policy.maxRetries) throw error
                delay(policy.delayFor(attempt))
                attempt++
            }
        }
    }
}

suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    enqueue(object : Callback {
        override fun onResponse(call: Call, response: Response) = cont.resume(response)
        override fun onFailure(call: Call, e: IOException) {
            if (!cont.isCancelled) cont.resumeWithException(e)
        }
    })
    cont.invokeOnCancellation { runCatching { cancel() } }
}
