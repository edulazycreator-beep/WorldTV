package io.github.worldtv.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.worldtv.model.Channel
import io.github.worldtv.model.ChannelGroup
import io.github.worldtv.model.Country
import io.github.worldtv.model.Programme
import io.github.worldtv.ui.theme.WtvColors

/** Channel details and actions: play, favorite, groups, website. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelSheet(
    channel: Channel,
    country: Country?,
    isFavorite: Boolean,
    groups: List<ChannelGroup>,
    nowPlaying: Programme?,
    upNext: List<Programme>,
    onPlay: () -> Unit,
    onToggleFavorite: () -> Unit,
    onToggleGroup: (String) -> Unit,
    onCreateGroup: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var newGroup by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                ChannelLogo(channel, size = 72.dp, padding = 10.dp)
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(channel.name, style = MaterialTheme.typography.headlineSmall)
                    Text(
                        channelSubtitle(channel, country),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 6.dp)) {
                        channel.bestQualityLabel?.let { Pill(it) }
                        if (channel.isGeoBlocked) Pill("Geo-blocked", Color(0x66FF9800))
                        Pill("${channel.streams.size} stream${if (channel.streams.size == 1) "" else "s"}")
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onPlay, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Filled.PlayArrow, null)
                    Spacer(Modifier.width(6.dp))
                    Text("Watch live")
                }
                TextButton(onClick = onToggleFavorite) {
                    Icon(
                        if (isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, null,
                        tint = if (isFavorite) WtvColors.Live else MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(if (isFavorite) "Favorited" else "Favorite")
                }
            }

            if (nowPlaying != null || upNext.isNotEmpty()) {
                HorizontalDivider()
                Text("On air", style = MaterialTheme.typography.titleMedium)
                nowPlaying?.let { ProgrammeLine(it, isNow = true) }
                upNext.take(3).forEach { ProgrammeLine(it, isNow = false) }
            }

            HorizontalDivider()
            Text("Groups", style = MaterialTheme.typography.titleMedium)
            groups.forEach { group ->
                val member = channel.id in group.channelIds
                ListItem(
                    headlineContent = { Text(group.name) },
                    leadingContent = {
                        Icon(
                            if (member) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null,
                            tint = if (member) WtvColors.Accent else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickableRow { onToggleGroup(group.id) },
                )
            }
            ListItem(
                headlineContent = { Text("New group…") },
                leadingContent = { Icon(Icons.AutoMirrored.Filled.PlaylistAdd, null) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.clickableRow { newGroup = "" },
            )

            HorizontalDivider()
            Text("About", style = MaterialTheme.typography.titleMedium)
            Text(
                channel.attribution,
                style = MaterialTheme.typography.bodyMedium,
            )
            channel.usageNotes?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (channel.languages.isNotEmpty()) {
                Text(
                    "Languages: ${channel.languages.joinToString()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            channel.website?.let { site ->
                TextButton(onClick = {
                    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(site))) }
                }) {
                    Icon(Icons.Filled.Language, null)
                    Spacer(Modifier.width(6.dp))
                    Text("Broadcaster website")
                }
            }
        }
    }

    newGroup?.let { text ->
        TextInputDialog(
            title = "New group",
            label = "Group name",
            initial = text,
            confirm = "Create",
            onConfirm = {
                onCreateGroup(it)
                newGroup = null
            },
            onDismiss = { newGroup = null },
        )
    }
}

@Composable
fun ProgrammeLine(programme: Programme, isNow: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            formatTime(programme.start),
            style = MaterialTheme.typography.labelMedium,
            color = if (isNow) WtvColors.Accent else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(56.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(programme.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1)
            programme.subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
        }
        if (isNow) LiveBadge()
    }
}

fun formatTime(millis: Long): String =
    java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(millis))

@Composable
fun TextInputDialog(
    title: String,
    label: String,
    initial: String = "",
    confirm: String = "Save",
    secondLabel: String? = null,
    secondInitial: String = "",
    onConfirm: (String) -> Unit,
    onConfirmTwo: ((String, String) -> Unit)? = null,
    onDismiss: () -> Unit,
) {
    var value by remember { mutableStateOf(initial) }
    var second by remember { mutableStateOf(secondInitial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = value, onValueChange = { value = it }, label = { Text(label) }, singleLine = true)
                if (secondLabel != null) {
                    OutlinedTextField(value = second, onValueChange = { second = it }, label = { Text(secondLabel) }, singleLine = true)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = value.isNotBlank(),
                onClick = { if (onConfirmTwo != null) onConfirmTwo(value, second) else onConfirm(value) },
            ) { Text(confirm) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

fun Modifier.clickableRow(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)
