@file:androidx.annotation.OptIn(markerClass = [UnstableApi::class])

package io.github.worldtv.ui.screens

import android.app.Activity
import android.view.KeyEvent as AndroidKeyEvent
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.AspectRatio
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SettingsInputAntenna
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.github.worldtv.MainActivity
import io.github.worldtv.model.VideoScale
import io.github.worldtv.player.PlaybackStatus
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelLogo
import io.github.worldtv.ui.components.ChannelRow
import io.github.worldtv.ui.components.LiveBadge
import io.github.worldtv.ui.components.Pill
import io.github.worldtv.ui.components.formatTime
import io.github.worldtv.ui.theme.WtvColors
import kotlinx.coroutines.delay

@Composable
fun PlayerScreen(
    viewModel: AppViewModel,
    actions: ChannelActions,
    isInPictureInPicture: Boolean,
    onClose: () -> Unit,
) {
    val state by viewModel.player.state.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val queue by viewModel.queue.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    val guideState by viewModel.guideState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = context as? Activity

    var controlsVisible by remember { mutableStateOf(true) }
    var drawerOpen by remember { mutableStateOf(false) }
    var streamMenu by remember { mutableStateOf(false) }
    var interactionTick by remember { mutableIntStateOf(0) }
    val focus = remember { FocusRequester() }
    val channel = state.channel

    fun poke() {
        controlsVisible = true
        interactionTick++
    }

    // Immersive full screen while the player is shown.
    DisposableEffect(activity) {
        val window = activity?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, it.decorView) }
        controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { controller?.show(WindowInsetsCompat.Type.systemBars()) }
    }

    // Auto-hide controls while playing.
    LaunchedEffect(interactionTick, state.status, drawerOpen, streamMenu) {
        if (state.status is PlaybackStatus.Playing && !drawerOpen && !streamMenu) {
            delay(4_000)
            controlsVisible = false
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    BackHandler {
        when {
            drawerOpen -> drawerOpen = false
            else -> onClose()
        }
    }

    if (channel == null) {
        LaunchedEffect(Unit) { onClose() }
        return
    }

    val guideId = guideState.guide.guideId(channel)
    val now = guideId?.let { guideState.guide.current(it) }
    val next = guideId?.let { guideState.guide.upcoming(it, limit = 1).firstOrNull() }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (event.key.nativeKeyCode) {
                    AndroidKeyEvent.KEYCODE_CHANNEL_UP -> { viewModel.playAdjacent(-1); true }
                    AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> { viewModel.playAdjacent(1); true }
                    AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, AndroidKeyEvent.KEYCODE_MEDIA_PLAY,
                    AndroidKeyEvent.KEYCODE_MEDIA_PAUSE -> { viewModel.player.togglePlayPause(); poke(); true }
                    AndroidKeyEvent.KEYCODE_DPAD_UP -> if (!controlsVisible && !drawerOpen) { viewModel.playAdjacent(-1); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_DOWN -> if (!controlsVisible && !drawerOpen) { viewModel.playAdjacent(1); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER ->
                        if (!controlsVisible) { poke(); true } else { poke(); false }
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT, AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> { poke(); false }
                    else -> false
                }
            }
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                if (controlsVisible) controlsVisible = false else poke()
            },
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    useController = false
                    keepScreenOn = true
                    setShutterBackgroundColor(android.graphics.Color.BLACK)
                    player = viewModel.player.player
                }
            },
            update = { view ->
                view.player = viewModel.player.player
                view.resizeMode = when (settings.videoScale) {
                    VideoScale.FIT -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    VideoScale.FILL -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    VideoScale.STRETCH -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                }
            },
            onRelease = { it.player = null },
            modifier = Modifier.fillMaxSize(),
        )

        if (isInPictureInPicture) return@Box

        StatusOverlay(
            status = state.status,
            onRetry = { viewModel.player.retry() },
            onNext = { viewModel.playAdjacent(1) },
            hasNext = queue.size > 1,
            modifier = Modifier.align(Alignment.Center),
        )

        AnimatedVisibility(controlsVisible, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize()) {
                // Top gradient + bar
                Box(
                    Modifier.fillMaxWidth().align(Alignment.TopCenter)
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.8f), Color.Transparent)))
                        .safeDrawingPadding()
                        .padding(8.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Color.White) }
                        ChannelLogo(channel, size = 40.dp)
                        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                            Text(channel.name, style = MaterialTheme.typography.titleMedium, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                now?.let { "${it.title} · until ${formatTime(it.stop)}" }
                                    ?: channel.countryCode?.let { index.countryByCode[it]?.let { c -> "${c.flag} ${c.name}" } }
                                    ?: channel.attribution,
                                style = MaterialTheme.typography.bodySmall,
                                color = Color.White.copy(alpha = 0.75f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        IconButton(onClick = { viewModel.toggleFavorite(channel.id); poke() }) {
                            val fav = library.isFavorite(channel.id)
                            Icon(
                                if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, "Favorite",
                                tint = if (fav) WtvColors.Live else Color.White,
                            )
                        }
                        Box {
                            IconButton(onClick = { streamMenu = true }) {
                                Icon(Icons.Filled.SettingsInputAntenna, "Streams", tint = Color.White)
                            }
                            DropdownMenu(expanded = streamMenu, onDismissRequest = { streamMenu = false }) {
                                state.streams.forEachIndexed { i, stream ->
                                    DropdownMenuItem(
                                        text = {
                                            Text(
                                                (if (i == state.streamIndex) "● " else "") +
                                                    listOfNotNull(stream.title?.takeIf { it != channel.name } ?: "Stream ${i + 1}", stream.quality,
                                                        if (stream.isGeoBlocked) "geo-blocked" else null).joinToString(" · ")
                                            )
                                        },
                                        onClick = {
                                            streamMenu = false
                                            viewModel.player.selectStream(i)
                                        },
                                    )
                                }
                            }
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            IconButton(onClick = { (activity as? MainActivity)?.enterPip() }) {
                                Icon(Icons.Filled.PictureInPictureAlt, "Picture in Picture", tint = Color.White)
                            }
                        }
                        IconButton(onClick = { drawerOpen = !drawerOpen; poke() }) {
                            Icon(Icons.AutoMirrored.Filled.List, "Channels", tint = Color.White)
                        }
                    }
                }

                // Centre transport
                Row(
                    Modifier.align(Alignment.Center),
                    horizontalArrangement = Arrangement.spacedBy(32.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (queue.size > 1) {
                        RoundButton(onClick = { viewModel.playAdjacent(-1); poke() }) { Icon(Icons.Filled.SkipPrevious, "Previous channel", tint = Color.White, modifier = Modifier.size(32.dp)) }
                    }
                    if (state.status is PlaybackStatus.Playing || state.status is PlaybackStatus.Paused) {
                        RoundButton(onClick = { viewModel.player.togglePlayPause(); poke() }, big = true) {
                            Icon(
                                if (state.status is PlaybackStatus.Playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                                "Play/Pause", tint = Color.White, modifier = Modifier.size(44.dp),
                            )
                        }
                    }
                    if (queue.size > 1) {
                        RoundButton(onClick = { viewModel.playAdjacent(1); poke() }) { Icon(Icons.Filled.SkipNext, "Next channel", tint = Color.White, modifier = Modifier.size(32.dp)) }
                    }
                }

                // Bottom bar
                Box(
                    Modifier.fillMaxWidth().align(Alignment.BottomCenter)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.8f))))
                        .safeDrawingPadding()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        LiveBadge()
                        Spacer(Modifier.width(8.dp))
                        state.currentStream?.quality?.let { Pill(it) }
                        if (state.videoHeight > 0) {
                            Spacer(Modifier.width(6.dp))
                            Pill("${state.videoHeight}p")
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(
                            next?.let { "Next: ${it.title} at ${formatTime(it.start)}" } ?: "",
                            color = Color.White.copy(alpha = 0.7f),
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(onClick = { viewModel.player.setMuted(!state.isMuted); poke() }) {
                            Icon(
                                if (state.isMuted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                                "Mute", tint = Color.White,
                            )
                        }
                        IconButton(onClick = {
                            val scales = VideoScale.entries
                            val nextScale = scales[(scales.indexOf(settings.videoScale) + 1) % scales.size]
                            viewModel.updateSettings { it.copy(videoScale = nextScale) }
                            viewModel.showMessage("Aspect ratio: ${nextScale.title}")
                            poke()
                        }) { Icon(Icons.Filled.AspectRatio, "Aspect ratio", tint = Color.White) }
                    }
                }
            }
        }

        // Channel drawer
        AnimatedVisibility(
            drawerOpen,
            enter = slideInHorizontally { it },
            exit = slideOutHorizontally { it },
            modifier = Modifier.align(Alignment.CenterEnd).fillMaxHeight(),
        ) {
            val listState = rememberLazyListState(
                initialFirstVisibleItemIndex = queue.indexOfFirst { it.id == channel.id }.coerceAtLeast(0)
            )
            Column(
                Modifier.fillMaxHeight().width(340.dp)
                    .background(Color(0xF00E0F12))
                    .safeDrawingPadding()
            ) {
                Text(
                    "Channels (${queue.size})",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    modifier = Modifier.padding(16.dp),
                )
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(queue, key = { it.id }) { item ->
                        ChannelRow(
                            channel = item,
                            country = item.countryCode?.let { index.countryByCode[it] },
                            isFavorite = library.isFavorite(item.id),
                            isPlaying = item.id == channel.id,
                            onClick = { viewModel.play(item, queue) },
                            onLongClick = { actions.showDetails(item) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RoundButton(onClick: () -> Unit, big: Boolean = false, content: @Composable () -> Unit) {
    Box(
        Modifier
            .size(if (big) 80.dp else 60.dp)
            .background(Color.Black.copy(alpha = 0.45f), androidx.compose.foundation.shape.CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun StatusOverlay(
    status: PlaybackStatus,
    onRetry: () -> Unit,
    onNext: () -> Unit,
    hasNext: Boolean,
    modifier: Modifier = Modifier,
) {
    when (status) {
        PlaybackStatus.Loading, PlaybackStatus.Buffering -> Column(
            modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(color = WtvColors.Accent)
            Text(if (status == PlaybackStatus.Loading) "Tuning in…" else "Buffering…", color = Color.White)
        }
        is PlaybackStatus.Reconnecting -> Column(
            modifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(color = WtvColors.AccentSecondary)
            Text("Connection lost — reconnecting (${status.attempt}/${status.maxAttempts})…", color = Color.White)
        }
        is PlaybackStatus.Failed -> Column(
            modifier.padding(32.dp).background(Color.Black.copy(alpha = 0.7f), androidx.compose.foundation.shape.RoundedCornerShape(16.dp)).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Can't play this channel", style = MaterialTheme.typography.titleLarge, color = Color.White)
            Text(status.message, color = Color.White.copy(alpha = 0.8f), textAlign = TextAlign.Center)
            if (status.geoBlockHint) {
                Text(
                    "Broadcasters often limit live streams to viewers in their own country.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onRetry) { Text("Try again") }
                if (hasNext) FilledTonalButton(onClick = onNext) { Text("Next channel") }
            }
        }
        else -> Unit
    }
}
