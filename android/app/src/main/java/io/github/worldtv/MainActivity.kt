package io.github.worldtv

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.worldtv.player.PlaybackStatus
import io.github.worldtv.ui.AppViewModel
import io.github.worldtv.ui.WorldTVApp
import io.github.worldtv.ui.theme.WorldTVTheme

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels()

    /** True while the player screen is visible; Picture-in-Picture is only offered then. */
    var playerVisible = false
    private var inPip by mutableStateOf(false)
    private var pendingImport by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleIntent(intent)
        setContent {
            val settings by viewModel.settings.collectAsStateWithLifecycle()
            WorldTVTheme(settings.theme) {
                WorldTVApp(
                    viewModel = viewModel,
                    isInPictureInPicture = inPip,
                    openPlaylists = pendingImport,
                    onPlaylistsOpened = { pendingImport = false },
                    onPlayerVisible = { playerVisible = it },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            intent.data?.let { uri ->
                if (uri.scheme == "http" || uri.scheme == "https") {
                    viewModel.importPlaylistUrl("", uri.toString())
                } else {
                    viewModel.importPlaylistFile(uri)
                }
                pendingImport = true
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        maybeEnterPip()
    }

    private fun maybeEnterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val status = viewModel.player.state.value.status
        val playing = status is PlaybackStatus.Playing || status is PlaybackStatus.Buffering ||
            status is PlaybackStatus.Loading || status is PlaybackStatus.Reconnecting
        if (!playerVisible || !playing || !viewModel.settings.value.autoPictureInPicture) return
        runCatching {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
            )
        }
    }

    /** Called from the player's PiP button. */
    fun enterPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build())
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPip = isInPictureInPictureMode
    }

    override fun onStop() {
        super.onStop()
        // Leaving the app without PiP: pause rather than stream in the background.
        if (!inPip) viewModel.player.player.pause()
    }
}
