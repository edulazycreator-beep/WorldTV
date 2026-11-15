package io.github.worldtv.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import io.github.worldtv.model.Channel
import io.github.worldtv.model.Country
import io.github.worldtv.model.Programme
import io.github.worldtv.ui.theme.Dimens
import io.github.worldtv.ui.theme.WtvColors

/** A focus- and press-aware card surface (works with touch and TV remotes). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun WtvCard(
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    shape: RoundedCornerShape = RoundedCornerShape(Dimens.CardRadius),
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Box(
        modifier
            .scale(if (focused) 1.04f else 1f)
            .clip(shape)
            .background(if (focused) MaterialTheme.colorScheme.surfaceContainerHigh else MaterialTheme.colorScheme.surfaceContainer)
            .border(
                width = if (focused) 2.dp else 1.dp,
                color = if (focused) WtvColors.Accent else MaterialTheme.colorScheme.outlineVariant,
                shape = shape,
            )
            .combinedClickable(
                interactionSource = interaction,
                indication = androidx.compose.material3.ripple(),
                onClick = onClick,
                onLongClick = onLongClick,
            )
    ) { content() }
}

@Composable
fun ChannelLogo(channel: Channel, modifier: Modifier = Modifier, size: Dp = 48.dp, padding: Dp = 6.dp) {
    Box(
        modifier
            .size(size)
            .clip(RoundedCornerShape(size / 5))
            .background(WtvColors.LogoBackground),
        contentAlignment = Alignment.Center,
    ) {
        if (channel.logoUrl != null) {
            SubcomposeAsyncImage(
                model = channel.logoUrl,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize().padding(padding),
                error = { Monogram(channel.name, size) },
                loading = { Monogram(channel.name, size) },
            )
        } else {
            Monogram(channel.name, size)
        }
    }
}

@Composable
private fun Monogram(name: String, size: Dp) {
    val letters = name.split(' ').filter { it.isNotBlank() }.take(2).joinToString("") { it.take(1).uppercase() }
    Box(
        Modifier.fillMaxSize().background(Brush.linearGradient(listOf(WtvColors.tint(name), WtvColors.tint(name).copy(alpha = 0.6f)))),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            letters.ifEmpty { "TV" },
            color = Color.White,
            fontWeight = FontWeight.Bold,
            style = if (size > 60.dp) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleSmall,
        )
    }
}

@Composable
fun Pill(text: String, color: Color = Color.White.copy(alpha = 0.12f), textColor: Color = Color.White) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = textColor,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(color)
            .padding(horizontal = 6.dp, vertical = 2.dp),
        maxLines = 1,
    )
}

@Composable
fun LiveBadge() = Pill("LIVE", WtvColors.Live)

fun channelSubtitle(channel: Channel, country: Country?): String = buildList {
    country?.let { add("${it.flag} ${it.name}") } ?: channel.countryCode?.let { add("${Country.flagEmoji(it)} $it") }
    channel.primaryCategory?.let { add(it.replaceFirstChar { c -> c.uppercase() }) }
}.joinToString(" · ")

/** Grid / carousel tile: logo on a tinted backdrop, name and country below. */
@Composable
fun ChannelTile(
    channel: Channel,
    country: Country?,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
    nowPlaying: Programme? = null,
) {
    WtvCard(modifier = modifier, onClick = onClick, onLongClick = onLongClick) {
        Column {
            Box(
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .background(
                        Brush.linearGradient(listOf(WtvColors.tint(channel.id).copy(alpha = 0.55f), WtvColors.Surface))
                    ),
                contentAlignment = Alignment.Center,
            ) {
                ChannelLogo(channel, size = 64.dp, padding = 8.dp)
                Row(
                    Modifier.align(Alignment.TopStart).padding(8.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    channel.bestQualityLabel?.let { q -> if (q.takeWhile { it.isDigit() }.toIntOrNull() ?: 0 >= 720) Pill("HD") }
                    if (channel.isGeoBlocked) Pill("GEO", Color(0x66FF9800))
                }
                if (isFavorite) {
                    Icon(
                        Icons.Filled.Favorite, null,
                        tint = WtvColors.Live,
                        modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(16.dp),
                    )
                }
            }
            Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) {
                Text(channel.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    nowPlaying?.title ?: channelSubtitle(channel, country),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** Compact list row used in lists, search results and the player's channel drawer. */
@Composable
fun ChannelRow(
    channel: Channel,
    country: Country?,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
    isPlaying: Boolean = false,
    nowPlaying: Programme? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    WtvCard(modifier = modifier.fillMaxWidth(), onClick = onClick, onLongClick = onLongClick) {
        Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
            ChannelLogo(channel, size = 48.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        channel.name,
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                        color = if (isPlaying) WtvColors.Accent else MaterialTheme.colorScheme.onSurface,
                    )
                    if (isFavorite) {
                        Spacer(Modifier.width(6.dp))
                        Icon(Icons.Filled.Favorite, null, tint = WtvColors.Live, modifier = Modifier.size(14.dp))
                    }
                }
                Text(
                    channelSubtitle(channel, country),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (nowPlaying != null) {
                    Text(
                        "Now: ${nowPlaying.title}",
                        style = MaterialTheme.typography.bodySmall,
                        color = WtvColors.Accent,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    LinearProgressIndicator(
                        progress = { nowPlaying.progress(System.currentTimeMillis()) },
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp).height(2.dp),
                        color = WtvColors.Accent,
                        trackColor = MaterialTheme.colorScheme.outlineVariant,
                    )
                }
            }
            channel.bestQualityLabel?.let {
                Spacer(Modifier.width(8.dp))
                Pill(it)
            }
            if (isPlaying) {
                Spacer(Modifier.width(8.dp))
                LiveBadge()
            }
            trailing?.invoke()
        }
    }
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter).padding(top = 20.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
        if (action != null && onAction != null) TextButton(onClick = onAction) { Text(action) }
    }
}

@Composable
fun ChannelCarousel(
    channels: List<Channel>,
    countries: Map<String, Country>,
    favorites: Set<String>,
    onPlay: (Channel) -> Unit,
    onLongPress: (Channel) -> Unit,
    tileWidth: Dp = 180.dp,
) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = Dimens.Gutter),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(channels, key = { it.id }) { channel ->
            ChannelTile(
                channel = channel,
                country = channel.countryCode?.let { countries[it] },
                isFavorite = channel.id in favorites,
                onClick = { onPlay(channel) },
                onLongClick = { onLongPress(channel) },
                modifier = Modifier.width(tileWidth),
            )
        }
    }
}

@Composable
fun EmptyState(icon: ImageVector = Icons.Filled.Tv, title: String, message: String, action: (@Composable () -> Unit)? = null) {
    Column(
        Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.size(72.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = WtvColors.Accent, modifier = Modifier.size(36.dp)) }
        Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        action?.invoke()
    }
}

@Composable
fun LoadingState(message: String) {
    Column(
        Modifier.fillMaxWidth().padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        CircularProgressIndicator(color = WtvColors.Accent)
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
