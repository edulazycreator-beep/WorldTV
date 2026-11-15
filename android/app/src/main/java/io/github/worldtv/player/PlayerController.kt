@file:androidx.annotation.OptIn(markerClass = [UnstableApi::class])

package io.github.worldtv.player

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.github.worldtv.data.StreamKind
import io.github.worldtv.data.StreamValidator
import io.github.worldtv.model.Channel
import io.github.worldtv.model.StreamSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import okhttp3.OkHttpClient

sealed interface PlaybackStatus {
    data object Idle : PlaybackStatus
    data object Loading : PlaybackStatus
    data object Buffering : PlaybackStatus
    data object Playing : PlaybackStatus
    data object Paused : PlaybackStatus
    data class Reconnecting(val attempt: Int, val maxAttempts: Int) : PlaybackStatus
    data class Failed(val message: String, val geoBlockHint: Boolean) : PlaybackStatus
}

data class PlayerUiState(
    val channel: Channel? = null,
    val streams: List<StreamSource> = emptyList(),
    val streamIndex: Int = 0,
    val status: PlaybackStatus = PlaybackStatus.Idle,
    val isMuted: Boolean = false,
    val videoHeight: Int = 0,
) {
    val currentStream: StreamSource? get() = streams.getOrNull(streamIndex)
}

/**
 * Live-TV playback on top of ExoPlayer: automatic fallback to the channel's next stream,
 * reconnect with exponential backoff, stall detection and a return to the live edge.
 * Must be used from the main thread.
 */
class PlayerController(
    context: Context,
    private val okHttp: OkHttpClient,
    private val userAgent: String,
) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    val player: ExoPlayer = ExoPlayer.Builder(appContext)
        .setLoadControl(
            DefaultLoadControl.Builder()
                .setBufferDurationsMs(15_000, 50_000, 2_000, 4_000)
                .build()
        )
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            /* handleAudioFocus = */ true,
        )
        .setHandleAudioBecomingNoisy(true)
        .build()

    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    var reconnectAttempts = 3
    var stallTimeoutMs = 20_000L

    private var reconnectCount = 0
    private var forceHls = false
    private val stallCheck = Runnable { onStalled() }
    private val reconnectRunnable = Runnable { prepareCurrent() }

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        if (_state.value.status !is PlaybackStatus.Reconnecting) setStatus(
                            if (_state.value.status == PlaybackStatus.Loading) PlaybackStatus.Loading else PlaybackStatus.Buffering
                        )
                        scheduleStallCheck()
                    }
                    Player.STATE_READY -> {
                        cancelStallCheck()
                        reconnectCount = 0
                        setStatus(if (player.playWhenReady) PlaybackStatus.Playing else PlaybackStatus.Paused)
                    }
                    Player.STATE_ENDED -> {
                        // A live stream should never end; treat it as a dropped connection.
                        handleFailure(null)
                    }
                    Player.STATE_IDLE -> cancelStallCheck()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) setStatus(PlaybackStatus.Playing)
                else if (player.playbackState == Player.STATE_READY) setStatus(PlaybackStatus.Paused)
            }

            override fun onPlayerError(error: PlaybackException) {
                handleFailure(error)
            }

            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                _state.update { it.copy(videoHeight = videoSize.height) }
            }
        })
    }

    /** Starts [channel]. Streams are tried best-first. */
    fun play(channel: Channel, preferHighestQuality: Boolean, startMuted: Boolean) {
        val streams = if (preferHighestQuality) channel.rankedStreams
        else channel.streams.sortedBy { it.isGeoBlocked }
        reconnectCount = 0
        forceHls = false
        handler.removeCallbacks(reconnectRunnable)
        player.volume = if (startMuted) 0f else 1f
        _state.value = PlayerUiState(
            channel = channel,
            streams = streams,
            streamIndex = 0,
            status = PlaybackStatus.Loading,
            isMuted = startMuted,
        )
        if (streams.isEmpty()) {
            setStatus(PlaybackStatus.Failed("This channel has no playable streams.", false))
            return
        }
        prepareCurrent()
    }

    /** Switches to a specific stream of the current channel. */
    fun selectStream(index: Int) {
        if (index !in _state.value.streams.indices) return
        reconnectCount = 0
        forceHls = false
        _state.update { it.copy(streamIndex = index, status = PlaybackStatus.Loading) }
        prepareCurrent()
    }

    fun retry() {
        reconnectCount = 0
        forceHls = false
        _state.update { it.copy(streamIndex = 0, status = PlaybackStatus.Loading) }
        prepareCurrent()
    }

    fun togglePlayPause() {
        if (player.isPlaying) {
            player.pause()
        } else {
            // Live TV: resuming jumps back to the live edge.
            if (player.isCurrentMediaItemLive) player.seekToDefaultPosition()
            if (player.playbackState == Player.STATE_IDLE) player.prepare()
            player.play()
        }
    }

    fun setMuted(muted: Boolean) {
        player.volume = if (muted) 0f else 1f
        _state.update { it.copy(isMuted = muted) }
    }

    fun stop() {
        cancelStallCheck()
        handler.removeCallbacks(reconnectRunnable)
        player.stop()
        player.clearMediaItems()
        _state.value = PlayerUiState()
    }

    fun release() {
        stop()
        player.release()
    }

    private fun prepareCurrent() {
        val current = _state.value
        val stream = current.currentStream ?: return
        val headers = buildMap {
            stream.referrer?.let {
                put("Referer", it)
                put("Origin", it.substringBefore("://") + "://" + it.substringAfter("://").substringBefore('/'))
            }
        }
        val dataSource = OkHttpDataSource.Factory(okHttp)
            .setUserAgent(stream.userAgent ?: userAgent)
            .setDefaultRequestProperties(headers)
        val itemBuilder = MediaItem.Builder()
            .setUri(stream.url)
            .setMediaMetadata(MediaMetadata.Builder().setTitle(current.channel?.name).build())
            .setLiveConfiguration(MediaItem.LiveConfiguration.Builder().setTargetOffsetMs(10_000).build())
        when (StreamValidator.kind(stream.url)) {
            StreamKind.HLS -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            StreamKind.DASH -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
            else -> if (forceHls) itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
        }
        val source = DefaultMediaSourceFactory(dataSource).createMediaSource(itemBuilder.build())
        player.setMediaSource(source)
        player.prepare()
        player.playWhenReady = true
        scheduleStallCheck()
    }

    private fun handleFailure(error: PlaybackException?) {
        cancelStallCheck()
        val current = _state.value
        if (current.channel == null) return

        if (error?.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            player.seekToDefaultPosition()
            player.prepare()
            return
        }
        // Many IPTV URLs hide HLS behind extension-less paths: retry once as HLS.
        val parsingFailed = error?.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED ||
            error?.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED
        val stream = current.currentStream
        if (parsingFailed && !forceHls && stream != null && StreamValidator.kind(stream.url) == StreamKind.OTHER) {
            forceHls = true
            prepareCurrent()
            return
        }

        val httpCode = (error?.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode
        val permanent = (httpCode != null && httpCode in PERMANENT_HTTP_CODES) || parsingFailed ||
            error?.errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED

        if (!permanent && reconnectCount < reconnectAttempts) {
            reconnectCount++
            setStatus(PlaybackStatus.Reconnecting(reconnectCount, reconnectAttempts))
            val delay = (1_000L shl (reconnectCount - 1)).coerceAtMost(8_000L)
            handler.removeCallbacks(reconnectRunnable)
            handler.postDelayed(reconnectRunnable, delay)
            return
        }

        // Fall back to the channel's next stream.
        if (current.streamIndex + 1 < current.streams.size) {
            reconnectCount = 0
            forceHls = false
            _state.update { it.copy(streamIndex = it.streamIndex + 1, status = PlaybackStatus.Loading) }
            prepareCurrent()
            return
        }

        val geo = httpCode == 401 || httpCode == 403 || current.streams.any { it.isGeoBlocked }
        val message = when {
            httpCode == 401 || httpCode == 403 ->
                "The broadcaster refused the connection (HTTP $httpCode). This channel is probably not available in your region."
            httpCode == 404 || httpCode == 410 -> "The stream is no longer available (HTTP $httpCode)."
            parsingFailed -> "The stream format is not supported."
            error?.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ->
                "Could not connect to the stream. Check your internet connection."
            error?.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ->
                "The stream took too long to respond."
            else -> "The channel is offline or not broadcasting right now."
        }
        player.stop()
        setStatus(PlaybackStatus.Failed(message, geo))
    }

    private fun onStalled() {
        if (player.playbackState == Player.STATE_BUFFERING && _state.value.channel != null) handleFailure(null)
    }

    private fun scheduleStallCheck() {
        handler.removeCallbacks(stallCheck)
        handler.postDelayed(stallCheck, stallTimeoutMs)
    }

    private fun cancelStallCheck() = handler.removeCallbacks(stallCheck)

    private fun setStatus(status: PlaybackStatus) = _state.update { it.copy(status = status) }

    private companion object {
        val PERMANENT_HTTP_CODES = setOf(401, 403, 404, 410)
    }
}
