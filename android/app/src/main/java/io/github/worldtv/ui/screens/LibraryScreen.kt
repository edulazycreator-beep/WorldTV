@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.ChannelGroup
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelRow
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.components.TextInputDialog
import io.github.worldtv.ui.components.WtvCard
import io.github.worldtv.ui.theme.Dimens
import java.text.DateFormat
import java.util.Date

@Composable
fun LibraryScreen(viewModel: AppViewModel, actions: ChannelActions, showExtras: Boolean) {
    val library by viewModel.library.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var newGroup by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<ChannelGroup?>(null) }
    var confirmClear by remember { mutableStateOf(false) }
    val favorites = library.favoriteIds.toSet()

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = Dimens.Gutter, end = 4.dp, top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Library", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
            if (showExtras) {
                IconButton(onClick = { actions.navigate("playlists") }) { Icon(Icons.AutoMirrored.Filled.List, "Playlists") }
                IconButton(onClick = { actions.navigate("settings") }) { Icon(Icons.Filled.Settings, "Settings") }
            }
        }
        PrimaryTabRow(selectedTabIndex = tab, containerColor = MaterialTheme.colorScheme.background) {
            listOf("Favorites", "History", "Groups").forEachIndexed { i, title ->
                Tab(selected = tab == i, onClick = { tab = i }, text = { Text(title) })
            }
        }

        val gridModifier = Modifier.fillMaxSize()
        when (tab) {
            0 -> {
                val channels = library.favoriteIds.mapNotNull { index.byId[it] }
                if (channels.isEmpty()) {
                    EmptyState(Icons.Filled.FavoriteBorder, "No favorites yet", "Long-press any channel and tap Favorite.")
                } else {
                    LazyVerticalGrid(
                        GridCells.Adaptive(340.dp), gridModifier,
                        contentPadding = PaddingValues(Dimens.Gutter),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(channels, key = { it.id }) { channel ->
                            ChannelRow(
                                channel, channel.countryCode?.let { index.countryByCode[it] }, true,
                                onClick = { actions.play(channel, channels) },
                                onLongClick = { actions.showDetails(channel) },
                            )
                        }
                    }
                }
            }
            1 -> {
                val entries = library.history.filter { index.byId.containsKey(it.channelId) }.take(200)
                if (entries.isEmpty()) {
                    EmptyState(Icons.Filled.History, "No history", "Channels you watch will appear here.")
                } else {
                    val formatter = remember { DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT) }
                    LazyVerticalGrid(
                        GridCells.Adaptive(340.dp), gridModifier,
                        contentPadding = PaddingValues(Dimens.Gutter),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Row(horizontalArrangement = Arrangement.End) {
                                TextButton(onClick = { confirmClear = true }) {
                                    Icon(Icons.Filled.DeleteSweep, null)
                                    Text(" Clear history")
                                }
                            }
                        }
                        items(entries, key = { it.id }) { entry ->
                            val channel = index.byId.getValue(entry.channelId)
                            Column {
                                ChannelRow(
                                    channel, channel.countryCode?.let { index.countryByCode[it] }, channel.id in favorites,
                                    onClick = { actions.play(channel, entries.mapNotNull { index.byId[it.channelId] }.distinctBy { it.id }) },
                                    onLongClick = { actions.showDetails(channel) },
                                )
                                Text(
                                    formatter.format(Date(entry.startedAt)) +
                                        if (entry.duration > 60_000) " · ${entry.duration / 60_000} min" else "",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 12.dp, top = 2.dp),
                                )
                            }
                        }
                    }
                }
            }
            else -> {
                LazyVerticalGrid(
                    GridCells.Adaptive(300.dp), gridModifier,
                    contentPadding = PaddingValues(Dimens.Gutter),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        OutlinedButton(onClick = { newGroup = true }) {
                            Icon(Icons.Filled.Add, null)
                            Text(" New group")
                        }
                    }
                    if (library.groups.isEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            EmptyState(Icons.Filled.Folder, "No groups", "Create groups like “Morning news” or “Sports” and add channels with a long-press.")
                        }
                    }
                    items(library.groups, key = { it.id }) { group ->
                        WtvCard(onClick = { actions.openList(ListKind.GROUP, group.id, group.name) }) {
                            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Filled.Folder, null, tint = MaterialTheme.colorScheme.primary)
                                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                                    Text(group.name, style = MaterialTheme.typography.titleSmall)
                                    Text(
                                        "${group.channelIds.size} channels",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = { renaming = group }) { Icon(Icons.Filled.Edit, "Rename") }
                                IconButton(onClick = { viewModel.deleteGroup(group.id) }) { Icon(Icons.Filled.Delete, "Delete") }
                            }
                        }
                    }
                }
            }
        }
    }

    if (newGroup) {
        TextInputDialog("New group", "Group name", confirm = "Create", onConfirm = {
            viewModel.createGroup(it)
            newGroup = false
        }, onDismiss = { newGroup = false })
    }
    renaming?.let { group ->
        TextInputDialog("Rename group", "Group name", initial = group.name, onConfirm = {
            viewModel.renameGroup(group.id, it)
            renaming = null
        }, onDismiss = { renaming = null })
    }
    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("Clear watch history?") },
            text = { Text("This removes your history and “Continue watching”. Favorites and groups are kept.") },
            confirmButton = { TextButton(onClick = { viewModel.clearHistory(); confirmClear = false }) { Text("Clear") } },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Cancel") } },
        )
    }
}
