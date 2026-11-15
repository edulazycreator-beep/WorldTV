@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.Channel
import io.github.worldtv.model.Country
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelCarousel
import io.github.worldtv.ui.components.ChannelLogo
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.components.LiveBadge
import io.github.worldtv.ui.components.LoadingState
import io.github.worldtv.ui.components.SectionHeader
import io.github.worldtv.ui.components.WtvCard
import io.github.worldtv.ui.components.channelSubtitle
import io.github.worldtv.ui.theme.Dimens
import io.github.worldtv.ui.theme.WtvColors

@Composable
fun HomeScreen(viewModel: AppViewModel, actions: ChannelActions) {
    val home by viewModel.home.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    val catalogState by viewModel.catalogState.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val guide by viewModel.guideState.collectAsStateWithLifecycle()
    val favorites = library.favoriteIds.toSet()
    val countries = index.countryByCode

    LazyColumn(
        Modifier.fillMaxSize().background(WtvColors.Backdrop),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item {
            Row(
                Modifier.fillMaxWidth().statusBarsPadding().padding(start = Dimens.Gutter, end = 4.dp, top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("World TV", style = MaterialTheme.typography.displaySmall)
                    Text(
                        if (index.channels.isEmpty()) "Television from around the world"
                        else "${index.channels.size} live channels · ${index.countries.size} countries",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                IconButton(onClick = { viewModel.refreshCatalog() }, enabled = !catalogState.isLoading) {
                    Icon(Icons.Filled.Refresh, "Refresh directory")
                }
            }
            if (catalogState.isLoading && index.channels.isNotEmpty()) {
                LinearProgressIndicator(Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter, vertical = 8.dp))
            }
        }

        if (index.channels.isEmpty()) {
            item {
                when {
                    catalogState.isLoading -> LoadingState("Loading the world's channels…")
                    catalogState.error != null -> EmptyState(
                        icon = Icons.Filled.CloudOff,
                        title = "Couldn't load the channel directory",
                        message = catalogState.error ?: "",
                        action = { Button(onClick = { viewModel.refreshCatalog() }) { Text("Try again") } },
                    )
                    else -> EmptyState(
                        title = "No channels yet",
                        message = "Enable the public directory in Settings or import your own M3U playlist.",
                        action = {
                            OutlinedButton(onClick = { actions.navigate("playlists") }) { Text("Import a playlist") }
                        },
                    )
                }
            }
            return@LazyColumn
        }

        catalogState.error?.let { error ->
            item {
                Text(
                    "Showing saved channels — $error",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = Dimens.Gutter, vertical = 4.dp),
                )
            }
        }

        if (home.featured.isNotEmpty()) {
            item {
                Spacer(Modifier.height(16.dp))
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Dimens.Gutter),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    items(home.featured, key = { "hero-" + it.id }) { channel ->
                        val guideId = guide.guide.guideId(channel)
                        HeroCard(
                            channel = channel,
                            country = channel.countryCode?.let { countries[it] },
                            now = guideId?.let { guide.guide.current(it)?.title },
                            onClick = { actions.play(channel, home.featured) },
                            onLongClick = { actions.showDetails(channel) },
                        )
                    }
                }
            }
        }

        if (home.recent.isNotEmpty()) {
            item { SectionHeader("Continue watching", action = "History", onAction = { actions.navigate("library") }) }
            item {
                ChannelCarousel(home.recent, countries, favorites, { actions.play(it, home.recent) }, actions.showDetails)
            }
        }
        if (home.favorites.isNotEmpty()) {
            item { SectionHeader("Favorites", action = "See all", onAction = { actions.openList(ListKind.FAVORITES, "", "Favorites") }) }
            item {
                ChannelCarousel(home.favorites, countries, favorites, { actions.play(it, home.favorites) }, actions.showDetails)
            }
        }
        item { SectionHeader("Popular now", action = "See all", onAction = { actions.openList(ListKind.ALL, "", "All channels") }) }
        item { ChannelCarousel(home.popular, countries, favorites, { actions.play(it, home.popular) }, actions.showDetails) }

        if (home.categories.isNotEmpty()) {
            item { SectionHeader("Browse by category", action = "Explore", onAction = { actions.navigate("explore") }) }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Dimens.Gutter),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(home.categories, key = { "cat-" + it.first.id }) { (category, count) ->
                        CategoryCard(category.id, category.name, count) {
                            actions.openList(ListKind.CATEGORY, category.id, category.name)
                        }
                    }
                }
            }
        }

        val featuredCountries = Country.featuredCodes.mapNotNull { countries[it] }
            .filter { (index.channelCountByCountry[it.code] ?: 0) > 0 }
        if (featuredCountries.isNotEmpty()) {
            item { SectionHeader("Featured countries") }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = Dimens.Gutter),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(featuredCountries, key = { "country-" + it.code }) { country ->
                        CountryCard(country, index.channelCountByCountry[country.code] ?: 0) {
                            actions.openList(ListKind.COUNTRY, country.code, "${country.flag} ${country.name}")
                        }
                    }
                }
            }
        }

        if (home.recentlyAdded.isNotEmpty()) {
            item { SectionHeader("Recently added") }
            item {
                ChannelCarousel(home.recentlyAdded, countries, favorites, { actions.play(it, home.recentlyAdded) }, actions.showDetails)
            }
        }

        item {
            Text(
                "Channels come from the public iptv-org directory and your own playlists. World TV hosts no content; every stream belongs to its broadcaster.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(Dimens.Gutter).padding(top = 16.dp),
            )
        }
    }
}

@Composable
private fun HeroCard(channel: Channel, country: Country?, now: String?, onClick: () -> Unit, onLongClick: () -> Unit) {
    WtvCard(modifier = Modifier.width(300.dp).height(170.dp), onClick = onClick, onLongClick = onLongClick) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.linearGradient(listOf(WtvColors.tint(channel.id), WtvColors.Surface))
            )
        ) {
            ChannelLogo(channel, size = 84.dp, padding = 10.dp, modifier = Modifier.align(Alignment.TopEnd).padding(16.dp))
            Column(Modifier.align(Alignment.BottomStart).padding(16.dp).fillMaxWidth(0.7f)) {
                LiveBadge()
                Spacer(Modifier.height(6.dp))
                Text(channel.name, style = MaterialTheme.typography.titleLarge, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    now?.let { "Now: $it" } ?: channelSubtitle(channel, country),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.75f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Icon(
                Icons.Filled.PlayArrow, null, tint = Color.White,
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp).size(32.dp),
            )
        }
    }
}

@Composable
fun CategoryCard(id: String, name: String, count: Int, modifier: Modifier = Modifier.width(150.dp), onClick: () -> Unit) {
    WtvCard(modifier = modifier.height(96.dp), onClick = onClick) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.linearGradient(listOf(WtvColors.tint("cat$id").copy(alpha = 0.8f), WtvColors.Surface))
            ).padding(12.dp)
        ) {
            Icon(categoryIcon(id), null, tint = Color.White.copy(alpha = 0.9f), modifier = Modifier.size(26.dp))
            Column(Modifier.align(Alignment.BottomStart)) {
                Text(name, style = MaterialTheme.typography.titleSmall, color = Color.White, maxLines = 1)
                Text("$count channels", style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.7f))
            }
        }
    }
}

@Composable
fun CountryCard(country: Country, count: Int, modifier: Modifier = Modifier.width(150.dp), onClick: () -> Unit) {
    WtvCard(modifier = modifier.height(96.dp), onClick = onClick) {
        Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.SpaceBetween) {
            Text(country.flag, style = MaterialTheme.typography.headlineMedium)
            Column {
                Text(country.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("$count channels", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
