package io.github.worldtv.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LiveTv
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import io.github.worldtv.model.Channel
import io.github.worldtv.ui.components.ChannelSheet
import io.github.worldtv.ui.screens.ChannelListScreen
import io.github.worldtv.ui.screens.ExploreScreen
import io.github.worldtv.ui.screens.GuideScreen
import io.github.worldtv.ui.screens.HomeScreen
import io.github.worldtv.ui.screens.LibraryScreen
import io.github.worldtv.ui.screens.ListKind
import io.github.worldtv.ui.screens.PlayerScreen
import io.github.worldtv.ui.screens.PlaylistsScreen
import io.github.worldtv.ui.screens.SearchScreen
import io.github.worldtv.ui.screens.SettingsScreen
import java.net.URLDecoder
import java.net.URLEncoder

private data class Destination(val route: String, val label: String, val icon: ImageVector)

private val primaryDestinations = listOf(
    Destination("home", "Home", Icons.Filled.Home),
    Destination("explore", "Explore", Icons.Filled.Explore),
    Destination("search", "Search", Icons.Filled.Search),
    Destination("guide", "Guide", Icons.Filled.CalendarMonth),
    Destination("library", "Library", Icons.Filled.VideoLibrary),
)

private val railExtras = listOf(
    Destination("playlists", "Playlists", Icons.AutoMirrored.Filled.List),
    Destination("settings", "Settings", Icons.Filled.Settings),
)

/** Callbacks every screen uses to act on a channel. */
class ChannelActions(
    val play: (Channel, List<Channel>) -> Unit,
    val showDetails: (Channel) -> Unit,
    val openList: (ListKind, String, String) -> Unit,
    val navigate: (String) -> Unit,
)

fun listRoute(kind: ListKind, value: String, title: String): String =
    "list/${kind.name}/${URLEncoder.encode(value, "UTF-8")}/${URLEncoder.encode(title, "UTF-8")}"

@Composable
fun WorldTVApp(
    viewModel: AppViewModel,
    isInPictureInPicture: Boolean,
    openPlaylists: Boolean,
    onPlaylistsOpened: () -> Unit,
    onPlayerVisible: (Boolean) -> Unit,
) {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val snackbar = remember { SnackbarHostState() }
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val library by viewModel.library.collectAsStateWithLifecycle()
    val index by viewModel.index.collectAsStateWithLifecycle()
    val guideState by viewModel.guideState.collectAsStateWithLifecycle()
    var sheetChannelId by rememberSaveable { mutableStateOf<String?>(null) }

    val context = LocalContext.current
    val isTv = remember {
        (context.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager).currentModeType ==
            Configuration.UI_MODE_TYPE_TELEVISION
    }
    val wide = isTv || LocalConfiguration.current.screenWidthDp >= 600

    LaunchedEffect(Unit) { viewModel.messages.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(openPlaylists) {
        if (openPlaylists) {
            nav.navigate("playlists") { launchSingleTop = true }
            onPlaylistsOpened()
        }
    }
    LaunchedEffect(route) { onPlayerVisible(route == "player") }

    val actions = remember(nav, settings.autoplayOnSelect) {
        ChannelActions(
            play = { channel, queue ->
                if (settings.autoplayOnSelect) {
                    viewModel.play(channel, queue)
                    nav.navigate("player") { launchSingleTop = true }
                } else {
                    sheetChannelId = channel.id
                }
            },
            showDetails = { sheetChannelId = it.id },
            openList = { kind, value, title -> nav.navigate(listRoute(kind, value, title)) },
            navigate = { target -> nav.navigateTopLevel(target) },
        )
    }

    val showChrome = route != "player"

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showChrome && !wide) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainerLow) {
                    primaryDestinations.forEach { dest ->
                        NavigationBarItem(
                            selected = backStack.isOn(dest.route),
                            onClick = { nav.navigateTopLevel(dest.route) },
                            icon = { Icon(dest.icon, dest.label) },
                            label = { Text(dest.label) },
                            colors = NavigationBarItemDefaults.colors(indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)),
                        )
                    }
                }
            }
        },
    ) { padding ->
        Row(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(padding)) {
            if (showChrome && wide) {
                NavigationRail(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                    header = { Icon(Icons.Filled.LiveTv, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(vertical = 16.dp)) },
                ) {
                    (primaryDestinations + railExtras).forEach { dest ->
                        NavigationRailItem(
                            selected = backStack.isOn(dest.route),
                            onClick = { nav.navigateTopLevel(dest.route) },
                            icon = { Icon(dest.icon, dest.label) },
                            label = { Text(dest.label) },
                            colors = NavigationRailItemDefaults.colors(indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)),
                        )
                    }
                }
            }
            Box(Modifier.weight(1f)) {
                NavHost(navController = nav, startDestination = "home") {
                    composable("home") { HomeScreen(viewModel, actions) }
                    composable("explore") { ExploreScreen(viewModel, actions) }
                    composable("search") { SearchScreen(viewModel, actions) }
                    composable("guide") { GuideScreen(viewModel, actions) }
                    composable("library") { LibraryScreen(viewModel, actions, showExtras = !wide) }
                    composable("playlists") { PlaylistsScreen(viewModel, actions, onBack = if (wide) null else ({ nav.popBackStack() })) }
                    composable("settings") { SettingsScreen(viewModel, onBack = if (wide) null else ({ nav.popBackStack() })) }
                    composable(
                        "list/{kind}/{value}/{title}",
                        arguments = listOf(
                            navArgument("kind") { type = NavType.StringType },
                            navArgument("value") { type = NavType.StringType },
                            navArgument("title") { type = NavType.StringType },
                        ),
                    ) { entry ->
                        val args = entry.arguments
                        ChannelListScreen(
                            viewModel = viewModel,
                            actions = actions,
                            kind = ListKind.valueOf(args?.getString("kind") ?: ListKind.ALL.name),
                            value = URLDecoder.decode(args?.getString("value") ?: "", "UTF-8"),
                            title = URLDecoder.decode(args?.getString("title") ?: "", "UTF-8"),
                            onBack = { nav.popBackStack() },
                        )
                    }
                    composable("player") {
                        PlayerScreen(
                            viewModel = viewModel,
                            actions = actions,
                            isInPictureInPicture = isInPictureInPicture,
                            onClose = {
                                viewModel.stopPlayback()
                                nav.popBackStack()
                            },
                        )
                    }
                }
            }
        }
    }

    sheetChannelId?.let { id ->
        val channel = index.byId[id]
        if (channel == null) {
            sheetChannelId = null
        } else {
            val guideId = guideState.guide.guideId(channel)
            ChannelSheet(
                channel = channel,
                country = channel.countryCode?.let { index.countryByCode[it] },
                isFavorite = library.isFavorite(channel.id),
                groups = library.groups,
                nowPlaying = guideId?.let { guideState.guide.current(it) },
                upNext = guideId?.let { guideState.guide.upcoming(it, limit = 3) }.orEmpty(),
                onPlay = {
                    sheetChannelId = null
                    viewModel.play(channel, listOf(channel))
                    nav.navigate("player") { launchSingleTop = true }
                },
                onToggleFavorite = { viewModel.toggleFavorite(channel.id) },
                onToggleGroup = { viewModel.toggleInGroup(channel.id, it) },
                onCreateGroup = { name ->
                    viewModel.createGroup(name)
                    viewModel.showMessage("Group “$name” created.")
                },
                onDismiss = { sheetChannelId = null },
            )
        }
    }
}

private fun androidx.navigation.NavBackStackEntry?.isOn(route: String): Boolean =
    this?.destination?.hierarchy?.any { it.route == route } == true

private val androidx.navigation.NavDestination.hierarchy: Sequence<androidx.navigation.NavDestination>
    get() = generateSequence(this) { it.parent }

private fun NavHostController.navigateTopLevel(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}
