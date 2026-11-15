@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.Channel
import io.github.worldtv.model.Programme
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelLogo
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.components.TextInputDialog
import io.github.worldtv.ui.components.formatTime
import io.github.worldtv.ui.theme.Dimens
import io.github.worldtv.ui.theme.WtvColors
import kotlinx.coroutines.delay

private val DP_PER_MINUTE = 4.dp
private const val WINDOW_HOURS = 8
private val CHANNEL_COLUMN = 132.dp

@Composable
fun GuideScreen(viewModel: AppViewModel, actions: ChannelActions) {
    val guideState by viewModel.guideState.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    var favoritesOnly by rememberSaveable { mutableStateOf(false) }
    var editUrl by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Pair<Channel, Programme>?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = System.currentTimeMillis()
        }
    }

    val guide = guideState.guide
    val rows = remember(guide, index, library.favoriteIds, favoritesOnly) {
        val favorites = library.favoriteIds.toSet()
        index.channels.asSequence()
            .filter { !favoritesOnly || it.id in favorites }
            .mapNotNull { channel -> guide.guideId(channel)?.let { channel to it } }
            .sortedWith(compareByDescending<Pair<Channel, String>> { it.first.id in favorites }.thenByDescending { it.first.popularity })
            .take(300)
            .toList()
    }
    // Timeline starts at the previous half hour.
    val windowStart = now - now % (30 * 60_000L)
    val windowEnd = windowStart + WINDOW_HOURS * 3_600_000L

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = Dimens.Gutter, end = 4.dp, top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("TV Guide", style = MaterialTheme.typography.headlineMedium)
                Text(
                    if (guide.isEmpty) "No programme data loaded"
                    else "${guide.programmeCount} programmes · ${rows.size} channels",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = { viewModel.loadGuide(force = true) }, enabled = !guideState.isLoading) {
                Icon(Icons.Filled.Refresh, "Reload guide")
            }
        }
        Row(Modifier.padding(horizontal = Dimens.Gutter), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = favoritesOnly, onClick = { favoritesOnly = !favoritesOnly }, label = { Text("Favorites only") })
            FilterChip(selected = settings.guideUrl.isNotBlank(), onClick = { editUrl = true }, label = { Text("Guide source…") })
        }
        if (guideState.isLoading) LinearProgressIndicator(Modifier.fillMaxWidth().padding(Dimens.Gutter))
        guideState.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(Dimens.Gutter))
        }

        if (rows.isEmpty() && !guideState.isLoading) {
            EmptyState(
                icon = Icons.Filled.CalendarMonth,
                title = if (guide.isEmpty) "Add a programme guide" else "No matching channels",
                message = if (guide.isEmpty) "World TV reads XMLTV guides (.xml or .xml.gz). Add a guide URL here, or import a playlist that includes one (url-tvg)."
                else "None of your channels appear in the loaded guide.",
                action = { Button(onClick = { editUrl = true }) { Text("Set guide URL") } },
            )
        } else {
            val scroll = rememberScrollState()
            // Time ruler
            Row(Modifier.fillMaxWidth().padding(top = 8.dp)) {
                Spacer(Modifier.width(CHANNEL_COLUMN))
                Row(Modifier.horizontalScroll(scroll)) {
                    var t = windowStart
                    while (t < windowEnd) {
                        Text(
                            formatTime(t),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.width(DP_PER_MINUTE * 30).padding(start = 4.dp),
                        )
                        t += 30 * 60_000L
                    }
                }
            }
            LazyColumn(Modifier.fillMaxSize()) {
                items(rows, key = { it.first.id }) { (channel, guideId) ->
                    Row(Modifier.fillMaxWidth().height(64.dp).padding(vertical = 3.dp)) {
                        Row(
                            Modifier.width(CHANNEL_COLUMN).fillMaxHeight()
                                .clickable { actions.play(channel, rows.map { it.first }) }
                                .padding(horizontal = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            ChannelLogo(channel, size = 40.dp)
                            Text(
                                channel.name,
                                style = MaterialTheme.typography.labelMedium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.padding(start = 6.dp),
                            )
                        }
                        Box(Modifier.horizontalScroll(scroll).fillMaxHeight()) {
                            Box(Modifier.width(DP_PER_MINUTE * (WINDOW_HOURS * 60)).fillMaxHeight()) {
                                guide.schedule(guideId, windowStart, windowEnd).forEach { programme ->
                                    val start = maxOf(programme.start, windowStart)
                                    val end = minOf(programme.stop, windowEnd)
                                    val offsetMin = ((start - windowStart) / 60_000L).toInt()
                                    val lengthMin = ((end - start) / 60_000L).toInt().coerceAtLeast(1)
                                    val airing = programme.isAiring(now)
                                    Box(
                                        Modifier
                                            .offset(x = DP_PER_MINUTE * offsetMin)
                                            .width(DP_PER_MINUTE * lengthMin)
                                            .fillMaxHeight()
                                            .padding(end = 2.dp)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(
                                                if (airing) WtvColors.Accent.copy(alpha = 0.22f)
                                                else MaterialTheme.colorScheme.surfaceContainer
                                            )
                                            .border(1.dp, if (airing) WtvColors.Accent.copy(alpha = 0.6f) else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(8.dp))
                                            .clickable { selected = channel to programme }
                                            .padding(horizontal = 8.dp, vertical = 6.dp),
                                    ) {
                                        Column {
                                            Text(programme.title, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                            Text(
                                                "${formatTime(programme.start)} – ${formatTime(programme.stop)}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                maxLines = 1,
                                            )
                                        }
                                    }
                                }
                                // "Now" marker
                                Box(
                                    Modifier
                                        .offset(x = DP_PER_MINUTE * ((now - windowStart) / 60_000L).toInt())
                                        .width(2.dp)
                                        .fillMaxHeight()
                                        .background(WtvColors.Live)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (editUrl) {
        TextInputDialog(
            title = "Programme guide (XMLTV)",
            label = "https://…/guide.xml or .xml.gz",
            initial = settings.guideUrl,
            confirm = "Load",
            onConfirm = { url ->
                viewModel.updateSettings { it.copy(guideUrl = url.trim()) }
                editUrl = false
                viewModel.loadGuide(force = true)
            },
            onDismiss = { editUrl = false },
        )
    }

    selected?.let { (channel, programme) ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { selected = null },
            title = { Text(programme.title) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${channel.name} · ${formatTime(programme.start)} – ${formatTime(programme.stop)}", color = WtvColors.Accent)
                    programme.subtitle?.let { Text(it, style = MaterialTheme.typography.titleSmall) }
                    programme.description?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    if (programme.categories.isNotEmpty()) {
                        Text(programme.categories.joinToString(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    selected = null
                    actions.play(channel, listOf(channel))
                }) { Text("Watch channel") }
            },
            dismissButton = { androidx.compose.material3.TextButton(onClick = { selected = null }) { Text("Close") } },
        )
    }
}
