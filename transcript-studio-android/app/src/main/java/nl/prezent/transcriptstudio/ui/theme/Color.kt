package nl.prezent.transcriptstudio.ui.theme

import androidx.compose.ui.graphics.Color

// Yinga brand color palette with adaptive light/dark mode support.
// Source of truth: macos/Extensions/Color+Brand.swift

// Brand colors (static)

/** Yinga primary — magenta #E50074 */
val BrandPrimary = Color(0xFFE50074)

/** Yinga secondary — blue #007BC4 */
val BrandSecondary = Color(0xFF007BC4)

/** Yinga accent — green #009F3C */
val BrandAccent = Color(0xFF009F3C)

/** Yinga orange #F39200 */
val BrandOrange = Color(0xFFF39200)

/** Darker magenta variant for hero gradients */
val BrandPrimaryDark = Color(0xFFB80061)

/** Neon blue used in waveform visualizations #00C2FF */
val NeonBlue = Color(0xFF00C2FF)

// Dark backgrounds (for widgets / Dynamic Island equivalents)

/** Very dark background #0B0C15 */
val BackgroundDark = Color(0xFF0B0C15)

/** Dark card background #1A1C29 */
val CardDark = Color(0xFF1A1C29)

// Surface colors — Light mode
// iOS: surfacePrimary light = (1.0, 1.0, 1.0)
val SurfacePrimaryLight = Color(0xFFFFFFFF)
// iOS: surfaceSecondary light = (0.96, 0.96, 0.97)
val SurfaceSecondaryLight = Color(0xFFF5F5F8)
// iOS: surfaceTertiary light = (0.92, 0.92, 0.94)
val SurfaceTertiaryLight = Color(0xFFEBEBF0)

// Surface colors — Dark mode
// iOS: surfacePrimary dark = (0.10, 0.11, 0.16)
val SurfacePrimaryDark = Color(0xFF1A1C29)
// iOS: surfaceSecondary dark = (0.13, 0.14, 0.20)
val SurfaceSecondaryDark = Color(0xFF212433)
// iOS: surfaceTertiary dark = (0.16, 0.17, 0.24)
val SurfaceTertiaryDark = Color(0xFF292B3D)

// Label colors — Light mode
// iOS: labelPrimary light = (0.20, 0.20, 0.23)
val LabelPrimaryLight = Color(0xFF33333B)
// iOS: labelSecondary light = (0.42, 0.42, 0.47)
val LabelSecondaryLight = Color(0xFF6B6B78)
// iOS: labelTertiary light = (0.60, 0.60, 0.65)
val LabelTertiaryLight = Color(0xFF9999A6)

// Label colors — Dark mode
// iOS: labelPrimary dark = (0.95, 0.95, 0.97)
val LabelPrimaryDark = Color(0xFFF2F2F8)
// iOS: labelSecondary dark = (0.62, 0.62, 0.68)
val LabelSecondaryDark = Color(0xFF9E9EAD)
// iOS: labelTertiary dark = (0.42, 0.42, 0.48)
val LabelTertiaryDark = Color(0xFF6B6B7A)

// Accent tint backgrounds — Light mode
// iOS: accentBgPrimary light = (1.0, 0.90, 0.95)
val AccentBgPrimaryLight = Color(0xFFFFE6F2)
// iOS: accentBgSecondary light = (0.88, 0.94, 1.0)
val AccentBgSecondaryLight = Color(0xFFE0F0FF)
// iOS: accentBgAccent light = (0.88, 0.97, 0.91)
val AccentBgAccentLight = Color(0xFFE0F8E8)
// iOS: accentBgOrange light = (1.0, 0.95, 0.88)
val AccentBgOrangeLight = Color(0xFFFFF2E0)

// Accent tint backgrounds — Dark mode
// iOS: accentBgPrimary dark = (0.25, 0.05, 0.15)
val AccentBgPrimaryDark = Color(0xFF400D26)
// iOS: accentBgSecondary dark = (0.05, 0.15, 0.28)
val AccentBgSecondaryDark = Color(0xFF0D2647)
// iOS: accentBgAccent dark = (0.04, 0.20, 0.10)
val AccentBgAccentDark = Color(0xFF0A331A)
// iOS: accentBgOrange dark = (0.25, 0.15, 0.02)
val AccentBgOrangeDark = Color(0xFF402605)

// Border colors — Light mode
// iOS: borderPrimary light = (0.88, 0.88, 0.90)
val BorderPrimaryLight = Color(0xFFE0E0E6)
// iOS: borderSecondary light = (0.93, 0.93, 0.95)
val BorderSecondaryLight = Color(0xFFEDEDF2)

// Border colors — Dark mode
// iOS: borderPrimary dark = (0.22, 0.23, 0.30)
val BorderPrimaryDark = Color(0xFF383B4D)
// iOS: borderSecondary dark = (0.17, 0.18, 0.25)
val BorderSecondaryDark = Color(0xFF2B2E40)

// Status colors
// iOS: statusError = (0.937, 0.267, 0.267) → #EF4444
val StatusError = Color(0xFFEF4444)
// iOS: statusWarning = (0.976, 0.647, 0.0) → #F9A500
val StatusWarning = Color(0xFFF9A500)
// iOS: statusSuccess = brandAccent → #009F3C
val StatusSuccess = Color(0xFF009F3C)
/** Info — system blue */
val StatusInfo = Color(0xFF007AFF)

// Platform brand colors (calendar integrations)
val PlatformTeams = Color(0xFF4A35B0)
val PlatformZoom = Color(0xFF2D8CFF)
val PlatformMeet = Color(0xFF009E73)
