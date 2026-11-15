@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.model.Continent
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.ChannelRow
import io.github.worldtv.ui.components.EmptyState
import io.github.worldtv.ui.theme.Dimens

@Composable
fun SearchScreen(viewModel: AppViewModel, actions: ChannelActions) {
    val query by viewModel.searchQuery.collectAsStateWithLifecycle()
    val filters by viewModel.searchFilters.collectAsStateWithLifecycle()
    val results by viewModel.searchResults.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val favorites = library.favoriteIds.toSet()

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = { viewModel.searchQuery.value = it },
            placeholder = { Text("Channels, countries, categories…") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            trailingIcon = {
                if (query.isNotEmpty()) IconButton(onClick = { viewModel.searchQuery.value = "" }) { Icon(Icons.Filled.Clear, "Clear") }
            },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Dimens.Gutter, vertical = 12.dp),
        )
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = Dimens.Gutter),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterDropdown(
                label = filters.countryCode?.let { code -> index.countryByCode[code]?.let { "${it.flag} ${it.name}" } ?: code } ?: "Country",
                selected = filters.countryCode != null,
                options = listOf<Pair<String?, String>>(null to "Any country") + index.countries.map { it.code to "${it.flag} ${it.name}" },
                onSelect = { code -> viewModel.searchFilters.value = filters.copy(countryCode = code) },
            )
            FilterDropdown(
                label = filters.continent?.displayName ?: "Continent",
                selected = filters.continent != null,
                options = listOf<Pair<String?, String>>(null to "Any continent") + Continent.entries.map { it.name to it.displayName },
                onSelect = { name -> viewModel.searchFilters.value = filters.copy(continent = name?.let { Continent.valueOf(it) }) },
            )
            FilterDropdown(
                label = filters.categoryId?.let { index.categoryById[it]?.name ?: it } ?: "Category",
                selected = filters.categoryId != null,
                options = listOf<Pair<String?, String>>(null to "Any category") + index.categories.map { it.id to it.name },
                onSelect = { id -> viewModel.searchFilters.value = filters.copy(categoryId = id) },
            )
            FilterDropdown(
                label = filters.languageCode?.let { code -> index.languages.firstOrNull { it.code == code }?.name ?: code } ?: "Language",
                selected = filters.languageCode != null,
                options = listOf<Pair<String?, String>>(null to "Any language") + index.languages.map { it.code to it.name },
                onSelect = { code -> viewModel.searchFilters.value = filters.copy(languageCode = code) },
            )
            FilterChip(
                selected = filters.favoritesOnly,
                onClick = { viewModel.searchFilters.value = filters.copy(favoritesOnly = !filters.favoritesOnly) },
                label = { Text("Favorites") },
            )
            FilterChip(
                selected = filters.hideGeoBlocked,
                onClick = { viewModel.searchFilters.value = filters.copy(hideGeoBlocked = !filters.hideGeoBlocked) },
                label = { Text("Hide geo-blocked") },
            )
        }

        when {
            query.isBlank() && !filters.isActive -> EmptyState(
                icon = Icons.Filled.Search,
                title = "Search ${index.channels.size} channels",
                message = "Try a channel name like “RTB”, a country like “Japan”, or a category like “news”.",
            )
            results.isEmpty() -> EmptyState(
                icon = Icons.Filled.SearchOff,
                title = "No results",
                message = "Try a different spelling or remove some filters.",
            )
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(340.dp),
                contentPadding = PaddingValues(Dimens.Gutter),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(results, key = { it.id }) { channel ->
                    ChannelRow(
                        channel = channel,
                        country = channel.countryCode?.let { index.countryByCode[it] },
                        isFavorite = channel.id in favorites,
                        onClick = { actions.play(channel, results) },
                        onLongClick = { actions.showDetails(channel) },
                    )
                }
            }
        }
    }
}

@Composable
private fun FilterDropdown(
    label: String,
    selected: Boolean,
    options: List<Pair<String?, String>>,
    onSelect: (String?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(
            selected = selected,
            onClick = { open = true },
            label = { Text(label, maxLines = 1) },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null) },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.heightIn(max = 420.dp)) {
            options.forEach { (value, text) ->
                DropdownMenuItem(text = { Text(text) }, onClick = {
                    onSelect(value)
                    open = false
                })
            }
        }
    }
}
