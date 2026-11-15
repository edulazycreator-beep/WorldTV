@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package io.github.worldtv.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.data.SearchService
import io.github.worldtv.model.Continent
import io.github.worldtv.model.Country
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.ChannelActions
import io.github.worldtv.ui.components.WtvCard
import io.github.worldtv.ui.theme.Dimens
import io.github.worldtv.ui.theme.WtvColors

private val tabs = listOf("Countries", "Continents", "Categories", "Languages")

@Composable
fun ExploreScreen(viewModel: AppViewModel, actions: ChannelActions) {
    val index by viewModel.index.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var filter by rememberSaveable { mutableStateOf("") }

    Column(Modifier.fillMaxSize()) {
        Text(
            "Explore",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.statusBarsPadding().padding(horizontal = Dimens.Gutter, vertical = 12.dp),
        )
        PrimaryScrollableTabRow(
            selectedTabIndex = tab,
            edgePadding = Dimens.Gutter,
            containerColor = MaterialTheme.colorScheme.background,
        ) {
            tabs.forEachIndexed { i, title ->
                Tab(selected = tab == i, onClick = { tab = i; filter = "" }, text = { Text(title) })
            }
        }
        if (tab == 0 || tab == 3) {
            OutlinedTextField(
                value = filter,
                onValueChange = { filter = it },
                placeholder = { Text(if (tab == 0) "Filter countries" else "Filter languages") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = Dimens.Gutter, vertical = 8.dp),
            )
        }
        val q = SearchService.normalize(filter)
        LazyVerticalGrid(
            columns = GridCells.Adaptive(if (tab == 1) 260.dp else 160.dp),
            contentPadding = PaddingValues(Dimens.Gutter),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxSize(),
        ) {
            when (tab) {
                0 -> {
                    val featured = Country.featuredCodes.mapNotNull { index.countryByCode[it] }
                        .filter { (index.channelCountByCountry[it.code] ?: 0) > 0 }
                    if (q.isEmpty() && featured.isNotEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) { GridHeader("Featured") }
                        items(featured, key = { "f-" + it.code }) { country ->
                            CountryCard(country, index.channelCountByCountry[country.code] ?: 0, Modifier.fillMaxWidth()) {
                                actions.openList(ListKind.COUNTRY, country.code, "${country.flag} ${country.name}")
                            }
                        }
                        item(span = { GridItemSpan(maxLineSpan) }) { GridHeader("All countries") }
                    }
                    val list = index.countries.filter {
                        q.isEmpty() || SearchService.normalize(it.name).contains(q) || it.code.equals(q, ignoreCase = true)
                    }
                    items(list, key = { it.code }) { country ->
                        CountryCard(country, index.channelCountByCountry[country.code] ?: 0, Modifier.fillMaxWidth()) {
                            actions.openList(ListKind.COUNTRY, country.code, "${country.flag} ${country.name}")
                        }
                    }
                }
                1 -> {
                    val counts = index.channels.groupingBy { Continent.of(it.countryCode) }.eachCount()
                    val countryCounts = index.countries.groupingBy { it.continent }.eachCount()
                    items(Continent.entries.filter { (counts[it] ?: 0) > 0 }, key = { it.name }) { continent ->
                        ContinentCard(continent, counts[continent] ?: 0, countryCounts[continent] ?: 0) {
                            actions.openList(ListKind.CONTINENT, continent.name, continent.displayName)
                        }
                    }
                }
                2 -> {
                    items(index.categories, key = { it.id }) { category ->
                        CategoryCard(category.id, category.name, index.channelCountByCategory[category.id] ?: 0, Modifier.fillMaxWidth()) {
                            actions.openList(ListKind.CATEGORY, category.id, category.name)
                        }
                    }
                }
                else -> {
                    val counts = HashMap<String, Int>()
                    index.channels.forEach { c -> c.languages.forEach { counts[it] = (counts[it] ?: 0) + 1 } }
                    val list = index.languages
                        .filter { (counts[it.code] ?: 0) > 0 }
                        .filter { q.isEmpty() || SearchService.normalize(it.name).contains(q) }
                        .sortedByDescending { counts[it.code] ?: 0 }
                    items(list, key = { it.code }) { language ->
                        WtvCard(
                            modifier = Modifier.height(72.dp),
                            onClick = { actions.openList(ListKind.LANGUAGE, language.code, language.name) },
                        ) {
                            Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.Center) {
                                Text(language.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(
                                    "${counts[language.code] ?: 0} channels",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GridHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun ContinentCard(continent: Continent, channels: Int, countries: Int, onClick: () -> Unit) {
    WtvCard(modifier = Modifier.height(120.dp), onClick = onClick) {
        Box(
            Modifier.fillMaxSize().background(
                Brush.linearGradient(listOf(WtvColors.tint(continent.name), WtvColors.Surface))
            ).padding(16.dp)
        ) {
            Icon(Icons.Filled.Public, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(32.dp).align(Alignment.TopEnd))
            Column(Modifier.align(Alignment.BottomStart)) {
                Text(continent.displayName, style = MaterialTheme.typography.titleLarge, color = Color.White)
                Row {
                    Text("$channels channels · $countries countries", style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.75f))
                }
            }
        }
    }
}
