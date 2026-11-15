package io.github.worldtv.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.worldtv.model.ThemeMode

/** World TV design tokens: near-black charcoal with a cyan-to-violet signature gradient. */
object WtvColors {
    val Background = Color(0xFF090A0C)
    val Surface = Color(0xFF16171B)
    val SurfaceRaised = Color(0xFF1F2126)
    val Stroke = Color(0x12FFFFFF)
    val LogoBackground = Color(0xFF292B33)
    val Accent = Color(0xFF35C8F9)
    val AccentSecondary = Color(0xFF8B6BFE)
    val Live = Color(0xFFFF4554)

    val BrandGradient = Brush.linearGradient(listOf(Accent, AccentSecondary))
    val Backdrop = Brush.verticalGradient(listOf(Color(0xFF12141C), Background))

    /** Deterministic per-channel tint used behind logos on hero cards. */
    fun tint(key: String): Color {
        var hash = -0x340d631b7bdddcdbL // FNV-1a offset basis
        for (byte in key.toByteArray()) {
            hash = (hash xor (byte.toLong() and 0xff)) * 0x100000001b3L
        }
        val hue = ((hash ushr 1) % 360).toFloat()
        return Color.hsv(hue, 0.55f, 0.45f)
    }
}

object Dimens {
    val CardRadius = 14.dp
    val Gutter = 16.dp
}

private val DarkScheme = darkColorScheme(
    primary = WtvColors.Accent,
    onPrimary = Color(0xFF00141C),
    secondary = WtvColors.AccentSecondary,
    onSecondary = Color.White,
    tertiary = WtvColors.Live,
    background = WtvColors.Background,
    onBackground = Color(0xFFEDEEF2),
    surface = WtvColors.Background,
    onSurface = Color(0xFFEDEEF2),
    surfaceVariant = WtvColors.Surface,
    onSurfaceVariant = Color(0xFFA3A7B3),
    surfaceContainer = WtvColors.Surface,
    surfaceContainerHigh = WtvColors.SurfaceRaised,
    surfaceContainerHighest = Color(0xFF282A31),
    surfaceContainerLow = Color(0xFF111215),
    outline = Color(0x33FFFFFF),
    outlineVariant = WtvColors.Stroke,
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF0A86B8),
    secondary = Color(0xFF6A4BDE),
    tertiary = WtvColors.Live,
)

private val WtvTypography = Typography(
    displaySmall = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold),
    headlineSmall = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 14.sp),
    bodySmall = TextStyle(fontSize = 12.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.5.sp),
)

@Composable
fun WorldTVTheme(mode: ThemeMode, content: @Composable () -> Unit) {
    val dark = when (mode) {
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
    }
    MaterialTheme(
        colorScheme = if (dark) DarkScheme else LightScheme,
        typography = WtvTypography,
        content = content,
    )
}
