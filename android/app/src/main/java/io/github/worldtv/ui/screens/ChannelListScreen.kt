package io.github.worldtv.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Apps
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.Church
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.FamilyRestroom
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Spa
import androidx.compose.material.icons.filled.Theaters
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.Channel
import io.github.worldtv.model.Continent
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelRow
import io.github.worldtv.ui.components.ChannelTile
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.theme.Dimens

enum class ListKind { ALL, COUNTRY, CONTINENT, CATEGORY, LANGUAGE, FAVORITES, HISTORY, GROUP, PLAYLIST }

enum class SortOrder(val label: String) { POPULAR("Most popular"), NAME("Name A–Z"), NEWEST("Recently added") }

fun categoryIcon(id: String): ImageVector = when (id) {
    "news" -> Icons.AutoMirrored.Filled.Article
    "sports" -> Icons.Filled.SportsSoccer
    "entertainment" -> Icons.Filled.AutoAwesome
    "movies" -> Icons.Filled.Movie
    "music" -> Icons.Filled.MusicNote
    "documentary" -> Icons.Filled.Videocam
    "kids", "animation" -> Icons.Filled.ChildCare
    "education" -> Icons.Filled.School
    "religious" -> Icons.Filled.Church
    "business" -> Icons.Filled.Business
    "weather" -> Icons.Filled.Cloud
    "cooking" -> Icons.Filled.Restaurant
    "travel" -> Icons.Filled.Flight
    "science" -> Icons.Filled.Science
    "series" -> Icons.Filled.Theaters
    "comedy" -> Icons.Filled.TheaterComedy
    "culture" -> Icons.Filled.Palette
    "lifestyle", "relax" -> Icons.Filled.Spa
    "shop" -> Icons.Filled.ShoppingBag
    "auto" -> Icons.Filled.DirectionsCar
    "outdoor" -> Icons.Filled.Landscape
    "family" -> Icons.Filled.FamilyRestroom
    "legislative" -> Icons.Filled.AccountBalance
    "classic" -> Icons.Filled.History
    "general" -> Icons.Filled.Tv
    else -> Icons.Filled.Tv
}

/** The channels for a list kind/value, before sorting. */
fun channelsFor(viewModel: AppViewModel, kind: ListKind, value: String): List<Channel> {
    val index = viewModel.index.value
    val library = viewModel.library.value
    return when (kind) {
        ListKind.ALL -> index.channels
        ListKind.COUNTRY -> index.channels.filter { it.countryCode == value }
        ListKind.CONTINENT -> index.channels.filter { Continent.of(it.countryCode).name == value }
        ListKind.CATEGORY -> index.channels.filter { value in it.categories }
        ListKind.LANGUAGE -> index.channels.filter { value in it.languages }
        ListKind.FAVORITES -> library.favoriteIds.mapNotNull { index.byId[it] }
        ListKind.HISTORY -> library.recentChannelIds(200).mapNotNull { index.byId[it] }
        ListKind.GROUP -> library.groups.firstOrNull { it.id == value }?.channelIds.orEmpty().mapNotNull { index.byId[it] }
        ListKind.PLAYLIST -> viewModel.playlists.value.firstOrNull { it.id == value }?.channels.orEmpty()
            .mapNotNull { index.byId[it.id] ?: it }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelListScreen(
    viewModel: AppViewModel,
    actions: ChannelActions,
    kind: ListKind,
    value: String,
    title: String,
    onBack: () -> Unit,
) {
    // Recompose when the underlying data changes.
    val index by viewModel.index.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val playlists by viewModel.playlists.collectAsStateWithLifecycle()
    val guide by viewModel.guideState.collectAsStateWithLifecycle()
    var sort by rememberSaveable { mutableStateOf(if (kind == ListKind.FAVORITES || kind == ListKind.HISTORY || kind == ListKind.GROUP || kind == ListKind.PLAYLIST) null else SortOrder.POPULAR) }
    var grid by rememberSaveable { mutableStateOf(true) }
    var sortMenu by remember { mutableStateOf(false) }

    val channels = remember(index, library, playlists, kind, value, sort) {
        val base = channelsFor(viewModel, kind, value)
        when (sort) {
            SortOrder.POPULAR -> base.sortedByDescending { it.popularity }
            SortOrder.NAME -> base.sortedBy { it.name.lowercase() }
            SortOrder.NEWEST -> base.sortedByDescending { it.firstSeen ?: 0 }
            null -> base
        }
    }
    val favorites = library.favoriteIds.toSet()

    Column(Modifier.fillMaxSize()) {
        TopAppBar(
            title = {
                Column {
                    Text(title, maxLines = 1)
                    Text("${channels.size} channels", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
            actions = {
                IconButton(onClick = { sortMenu = true }) { Icon(Icons.AutoMirrored.Filled.Sort, "Sort") }
                DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                    SortOrder.entries.forEach { order ->
                        DropdownMenuItem(
                            text = { Text((if (order == sort) "✓ " else "") + order.label) },
                            onClick = { sort = order; sortMenu = false },
                        )
                    }
                }
                IconButton(onClick = { grid = !grid }) {
                    Icon(if (grid) Icons.AutoMirrored.Filled.ViewList else Icons.Filled.Apps, "Layout")
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
        )
        if (channels.isEmpty()) {
            EmptyState(
                title = "Nothing here yet",
                message = when (kind) {
                    ListKind.FAVORITES -> "Long-press any channel and tap Favorite to keep it here."
                    ListKind.HISTORY -> "Channels you watch will appear here."
                    ListKind.GROUP -> "Long-press a channel to add it to this group."
                    else -> "No channels match."
                },
            )
            return@Column
        }
        LazyVerticalGrid(
            columns = if (grid) GridCells.Adaptive(160.dp) else GridCells.Adaptive(340.dp),
            contentPadding = PaddingValues(Dimens.Gutter),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(channels, key = { it.id }) { channel ->
                val country = channel.countryCode?.let { index.countryByCode[it] }
                val now = guide.guide.guideId(channel)?.let { guide.guide.current(it) }
                if (grid) {
                    ChannelTile(
                        channel, country, channel.id in favorites,
                        onClick = { actions.play(channel, channels) },
                        onLongClick = { actions.showDetails(channel) },
                        nowPlaying = now,
                    )
                } else {
                    ChannelRow(
                        channel, country, channel.id in favorites,
                        onClick = { actions.play(channel, channels) },
                        onLongClick = { actions.showDetails(channel) },
                        nowPlaying = now,
                    )
                }
            }
        }
    }
}
