@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.FileOpen
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.Playlist
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.components.Pill
import io.github.worldtv.ui.components.TextInputDialog
import io.github.worldtv.ui.components.WtvCard
import io.github.worldtv.ui.theme.Dimens
import java.text.DateFormat
import java.util.Date

@Composable
fun PlaylistsScreen(viewModel: AppViewModel, actions: ChannelActions, onBack: (() -> Unit)?) {
    val playlists by viewModel.playlists.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    val progress by viewModel.validationProgress.collectAsStateWithLifecycle()
    var addUrl by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Playlist?>(null) }
    var editingEpg by remember { mutableStateOf<Playlist?>(null) }
    var deleting by remember { mutableStateOf<Playlist?>(null) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) viewModel.importPlaylistFile(uri)
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = if (onBack == null) Dimens.Gutter else 4.dp, end = Dimens.Gutter, top = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Playlists", style = MaterialTheme.typography.headlineMedium)
        }
        Text(
            "Import your own M3U / M3U8 IPTV playlists. Only use playlists you are authorized to watch.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = Dimens.Gutter, vertical = 4.dp),
        )
        Row(Modifier.padding(horizontal = Dimens.Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { addUrl = true }, enabled = !busy) {
                Icon(Icons.Filled.Link, null)
                Text(" From URL")
            }
            OutlinedButton(onClick = { picker.launch(arrayOf("*/*")) }, enabled = !busy) {
                Icon(Icons.Filled.FileOpen, null)
                Text(" From file")
            }
        }
        if (busy) {
            val p = progress
            if (p != null && p.second > 0) {
                LinearProgressIndicator(
                    progress = { p.first.toFloat() / p.second },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter),
                )
                Text("Checking streams ${p.first}/${p.second}…", style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = Dimens.Gutter))
            } else {
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter))
            }
        }

        if (playlists.isEmpty()) {
            EmptyState(
                Icons.AutoMirrored.Filled.PlaylistPlay,
                "No playlists",
                "Add a playlist URL from your provider, or open an .m3u file from your device.",
            )
        } else {
            LazyColumn(
                contentPadding = PaddingValues(Dimens.Gutter),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                items(playlists, key = { it.id }) { playlist ->
                    PlaylistCard(
                        playlist = playlist,
                        busy = busy,
                        onOpen = { actions.openList(ListKind.PLAYLIST, playlist.id, playlist.name) },
                        onRefresh = { viewModel.refreshPlaylist(playlist.id) },
                        onValidate = { viewModel.validatePlaylist(playlist.id) },
                        onRemoveInvalid = { viewModel.removeInvalidStreams(playlist.id) },
                        onRename = { renaming = playlist },
                        onEpg = { editingEpg = playlist },
                        onDelete = { deleting = playlist },
                    )
                }
            }
        }
    }

    if (addUrl) {
        TextInputDialog(
            title = "Add playlist from URL",
            label = "https://…/playlist.m3u",
            confirm = "Import",
            secondLabel = "Name (optional)",
            onConfirm = {},
            onConfirmTwo = { url, name ->
                viewModel.importPlaylistUrl(name, url)
                addUrl = false
            },
            onDismiss = { addUrl = false },
        )
    }
    renaming?.let { playlist ->
        TextInputDialog("Rename playlist", "Name", initial = playlist.name, onConfirm = {
            viewModel.renamePlaylist(playlist.id, it)
            renaming = null
        }, onDismiss = { renaming = null })
    }
    editingEpg?.let { playlist ->
        TextInputDialog("Programme guide (XMLTV)", "https://…/guide.xml.gz", initial = playlist.epgUrl ?: "", onConfirm = {
            viewModel.setPlaylistEpg(playlist.id, it)
            editingEpg = null
        }, onDismiss = { editingEpg = null })
    }
    deleting?.let { playlist ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Remove “${playlist.name}”?") },
            text = { Text("Its ${playlist.channels.size} channels will be removed from World TV.") },
            confirmButton = { TextButton(onClick = { viewModel.deletePlaylist(playlist.id); deleting = null }) { Text("Remove") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun PlaylistCard(
    playlist: Playlist,
    busy: Boolean,
    onOpen: () -> Unit,
    onRefresh: () -> Unit,
    onValidate: () -> Unit,
    onRemoveInvalid: () -> Unit,
    onRename: () -> Unit,
    onEpg: () -> Unit,
    onDelete: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val formatter = remember { DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT) }
    WtvCard(modifier = Modifier.fillMaxWidth(), onClick = onOpen) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.AutoMirrored.Filled.PlaylistPlay, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(playlist.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    playlist.sourceLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Pill("${playlist.channels.size} channels")
                    if (playlist.epgUrl != null) Pill("Guide")
                    if (playlist.validation.isNotEmpty()) {
                        val bad = playlist.invalidStreamCount
                        Pill(if (bad == 0) "All streams OK" else "$bad unreachable")
                    }
                }
                Text(
                    "Updated ${formatter.format(Date(playlist.updatedAt))}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Open channels") }, onClick = { menu = false; onOpen() })
                    if (playlist.remoteUrl != null) {
                        DropdownMenuItem(text = { Text("Refresh from URL") }, enabled = !busy, onClick = { menu = false; onRefresh() })
                    }
                    DropdownMenuItem(text = { Text("Check streams") }, enabled = !busy, onClick = { menu = false; onValidate() })
                    if (playlist.invalidStreamCount > 0) {
                        DropdownMenuItem(text = { Text("Remove unreachable streams") }, onClick = { menu = false; onRemoveInvalid() })
                    }
                    DropdownMenuItem(text = { Text("Programme guide…") }, onClick = { menu = false; onEpg() })
                    DropdownMenuItem(text = { Text("Rename…") }, onClick = { menu = false; onRename() })
                    DropdownMenuItem(text = { Text("Remove playlist") }, onClick = { menu = false; onDelete() })
                }
            }
        }
    }
}
