package nl.prezent.transcriptstudio.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * Light color scheme — maps Yinga brand colors to Material 3 roles.
 * No dynamic color: this is a branded app.
 */
private val LightColorScheme = lightColorScheme(
    primary = BrandPrimary,
    onPrimary = androidx.compose.ui.graphics.Color.White,
    primaryContainer = AccentBgPrimaryLight,
    onPrimaryContainer = BrandPrimary,
    secondary = BrandSecondary,
    onSecondary = androidx.compose.ui.graphics.Color.White,
    secondaryContainer = AccentBgSecondaryLight,
    onSecondaryContainer = BrandSecondary,
    tertiary = BrandAccent,
    onTertiary = androidx.compose.ui.graphics.Color.White,
    tertiaryContainer = AccentBgAccentLight,
    onTertiaryContainer = BrandAccent,
    error = StatusError,
    onError = androidx.compose.ui.graphics.Color.White,
    errorContainer = StatusError.copy(alpha = 0.12f),
    onErrorContainer = StatusError,
    background = SurfacePrimaryLight,
    onBackground = LabelPrimaryLight,
    surface = SurfacePrimaryLight,
    onSurface = LabelPrimaryLight,
    surfaceVariant = SurfaceSecondaryLight,
    onSurfaceVariant = LabelSecondaryLight,
    surfaceContainerLowest = SurfacePrimaryLight,
    surfaceContainerLow = SurfacePrimaryLight,
    surfaceContainer = SurfaceSecondaryLight,
    surfaceContainerHigh = SurfaceTertiaryLight,
    surfaceContainerHighest = SurfaceTertiaryLight,
    outline = BorderPrimaryLight,
    outlineVariant = BorderSecondaryLight,
    inverseSurface = SurfacePrimaryDark,
    inverseOnSurface = LabelPrimaryDark,
    inversePrimary = BrandPrimary,
)

/**
 * Dark color scheme — maps Yinga brand colors to Material 3 roles.
 */
private val DarkColorScheme = darkColorScheme(
    primary = BrandPrimary,
    onPrimary = androidx.compose.ui.graphics.Color.White,
    primaryContainer = AccentBgPrimaryDark,
    onPrimaryContainer = BrandPrimary,
    secondary = BrandSecondary,
    onSecondary = androidx.compose.ui.graphics.Color.White,
    secondaryContainer = AccentBgSecondaryDark,
    onSecondaryContainer = BrandSecondary,
    tertiary = BrandAccent,
    onTertiary = androidx.compose.ui.graphics.Color.White,
    tertiaryContainer = AccentBgAccentDark,
    onTertiaryContainer = BrandAccent,
    error = StatusError,
    onError = androidx.compose.ui.graphics.Color.White,
    errorContainer = StatusError.copy(alpha = 0.12f),
    onErrorContainer = StatusError,
    background = SurfacePrimaryDark,
    onBackground = LabelPrimaryDark,
    surface = SurfacePrimaryDark,
    onSurface = LabelPrimaryDark,
    surfaceVariant = SurfaceSecondaryDark,
    onSurfaceVariant = LabelSecondaryDark,
    surfaceContainerLowest = SurfacePrimaryDark,
    surfaceContainerLow = SurfacePrimaryDark,
    surfaceContainer = SurfaceSecondaryDark,
    surfaceContainerHigh = SurfaceTertiaryDark,
    surfaceContainerHighest = SurfaceTertiaryDark,
    outline = BorderPrimaryDark,
    outlineVariant = BorderSecondaryDark,
    inverseSurface = SurfacePrimaryLight,
    inverseOnSurface = LabelPrimaryLight,
    inversePrimary = BrandPrimary,
)

@Composable
fun TranscriptStudioTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    // Tint the system status bar to match the surface
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.surface.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = TSTypography,
        content = content,
    )
}
