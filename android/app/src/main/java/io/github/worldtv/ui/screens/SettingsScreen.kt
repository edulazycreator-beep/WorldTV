@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.BuildConfig
import io.github.worldtv.data.DirectoryApi
import io.github.worldtv.model.ThemeMode
import io.github.worldtv.model.VideoScale
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.components.TextInputDialog
import io.github.worldtv.ui.theme.Dimens
import java.text.DateFormat
import java.util.Date

@Composable
fun SettingsScreen(viewModel: AppViewModel, onBack: (() -> Unit)?) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val catalog by viewModel.catalogState.collectAsStateWithLifecycle()
    var editBaseUrl by remember { mutableStateOf(false) }
    val update = viewModel::updateSettings

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = 32.dp)) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = if (onBack == null) Dimens.Gutter else 4.dp, top = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
            Text("Settings", style = MaterialTheme.typography.headlineMedium)
        }

        Section("Playback")
        Label("Aspect ratio")
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter)) {
            VideoScale.entries.forEachIndexed { i, scale ->
                SegmentedButton(
                    selected = settings.videoScale == scale,
                    onClick = { update { it.copy(videoScale = scale) } },
                    shape = SegmentedButtonDefaults.itemShape(i, VideoScale.entries.size),
                ) { Text(scale.title.substringBefore(" ")) }
            }
        }
        Toggle("Prefer highest-quality stream", settings.preferHighestQuality) { v -> update { it.copy(preferHighestQuality = v) } }
        Toggle("Hide channels marked geo-blocked", settings.hideGeoBlocked) { v -> update { it.copy(hideGeoBlocked = v) } }
        Toggle("Start playing when a channel is selected", settings.autoplayOnSelect) { v -> update { it.copy(autoplayOnSelect = v) } }
        Toggle("Start muted", settings.startMuted) { v -> update { it.copy(startMuted = v) } }
        Toggle("Picture-in-Picture when leaving the app", settings.autoPictureInPicture) { v -> update { it.copy(autoPictureInPicture = v) } }
        Stepper("Reconnect attempts", settings.reconnectAttempts, 0..10) { v -> update { it.copy(reconnectAttempts = v) } }

        Section("Appearance")
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter)) {
            ThemeMode.entries.forEachIndexed { i, mode ->
                SegmentedButton(
                    selected = settings.theme == mode,
                    onClick = { update { it.copy(theme = mode) } },
                    shape = SegmentedButtonDefaults.itemShape(i, ThemeMode.entries.size),
                ) { Text(mode.name.lowercase().replaceFirstChar { c -> c.uppercase() }) }
            }
        }

        Section("Channel directory")
        Toggle("Use the iptv-org public directory", settings.directoryEnabled) { v ->
            update { it.copy(directoryEnabled = v) }
            if (v) viewModel.refreshCatalog()
        }
        Stepper("Refresh every (hours)", settings.directoryRefreshHours, 1..168) { v -> update { it.copy(directoryRefreshHours = v) } }
        Row(
            Modifier.fillMaxWidth().clickable { editBaseUrl = true }.padding(horizontal = Dimens.Gutter, vertical = 12.dp),
        ) {
            Column {
                Text("Directory address", style = MaterialTheme.typography.bodyLarge)
                Text(settings.directoryBaseUrl, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text(
            catalog.catalog.updatedAt?.let {
                "${catalog.catalog.channels.size} channels · updated " +
                    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))
            } ?: "Not downloaded yet",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = Dimens.Gutter),
        )
        Row(Modifier.padding(horizontal = Dimens.Gutter, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { viewModel.refreshCatalog() }, enabled = !catalog.isLoading) {
                Text(if (catalog.isLoading) "Refreshing…" else "Refresh now")
            }
            OutlinedButton(onClick = { viewModel.clearCaches() }) { Text("Clear cache") }
        }

        Section("Network")
        Stepper("Request timeout (seconds)", settings.requestTimeout, 5..120, step = 5) { v -> update { it.copy(requestTimeout = v) } }
        Stepper("Retries", settings.maxRetries, 0..6) { v -> update { it.copy(maxRetries = v) } }

        Section("About")
        Text(
            "World TV ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\n\n" +
                "World TV hosts no content. The built-in directory is the public iptv-org community database " +
                "(github.com/iptv-org), downloaded at runtime; adult, closed and DMCA-blocklisted channels are excluded. " +
                "Every stream belongs to its broadcaster and may be geo-restricted or offline. Only import playlists you are authorized to use.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = Dimens.Gutter),
        )
    }

    if (editBaseUrl) {
        TextInputDialog(
            title = "Directory address",
            label = DirectoryApi.DEFAULT_BASE_URL,
            initial = settings.directoryBaseUrl,
            onConfirm = { url ->
                update { it.copy(directoryBaseUrl = url.trim().ifBlank { DirectoryApi.DEFAULT_BASE_URL }) }
                editBaseUrl = false
                viewModel.refreshCatalog()
            },
            onDismiss = { editBaseUrl = false },
        )
    }
}

@Composable
private fun Section(title: String) {
    Column(Modifier.padding(top = 20.dp)) {
        HorizontalDivider(Modifier.padding(horizontal = Dimens.Gutter))
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = Dimens.Gutter, vertical = 12.dp),
        )
    }
}

@Composable
private fun Label(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(horizontal = Dimens.Gutter, vertical = 6.dp))
}

@Composable
private fun Toggle(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(horizontal = Dimens.Gutter, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun Stepper(title: String, value: Int, range: IntRange, step: Int = 1, onChange: (Int) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        IconButton(onClick = { onChange((value - step).coerceIn(range)) }, enabled = value > range.first) {
            Icon(Icons.Filled.Remove, "Decrease")
        }
        Text("$value", style = MaterialTheme.typography.titleMedium)
        IconButton(onClick = { onChange((value + step).coerceIn(range)) }, enabled = value < range.last) {
            Icon(Icons.Filled.Add, "Increase")
        }
    }
}
