package nl.prezent.transcriptstudio.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * TranscriptStudio typography scale.
 * Matches the iOS type ramp from Theme.swift (SF sizes).
 */
val TSTypography = Typography(
    // ~34pt — hero / display text (iOS: largeTitle)
    headlineLarge = TextStyle(
        fontSize = 34.sp,
        fontWeight = FontWeight.Bold,
        lineHeight = 41.sp,
    ),
    // ~28pt — screen titles (iOS: title)
    headlineMedium = TextStyle(
        fontSize = 28.sp,
        fontWeight = FontWeight.Bold,
        lineHeight = 34.sp,
    ),
    // ~22pt — major section titles (iOS: title2)
    headlineSmall = TextStyle(
        fontSize = 22.sp,
        fontWeight = FontWeight.Bold,
        lineHeight = 28.sp,
    ),
    // ~20pt — view section titles (iOS: title3)
    titleLarge = TextStyle(
        fontSize = 20.sp,
        fontWeight = FontWeight.SemiBold,
        lineHeight = 25.sp,
    ),
    // ~17pt — card headers (iOS: headline)
    titleMedium = TextStyle(
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        lineHeight = 22.sp,
    ),
    // ~17pt — primary body content (iOS: body)
    bodyLarge = TextStyle(
        fontSize = 17.sp,
        lineHeight = 22.sp,
    ),
    // ~16pt — secondary body text (iOS: callout)
    bodyMedium = TextStyle(
        fontSize = 16.sp,
        lineHeight = 21.sp,
    ),
    // ~13pt — secondary labels, nav items (iOS: footnote)
    bodySmall = TextStyle(
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    // ~16pt medium — emphasized callout labels
    labelLarge = TextStyle(
        fontSize = 16.sp,
        fontWeight = FontWeight.Medium,
        lineHeight = 21.sp,
    ),
    // ~12pt medium — metadata, timestamps (iOS: caption)
    labelMedium = TextStyle(
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        lineHeight = 16.sp,
    ),
    // ~10pt medium — tiny badges, counts (iOS: caption2)
    labelSmall = TextStyle(
        fontSize = 10.sp,
        fontWeight = FontWeight.Medium,
        lineHeight = 13.sp,
    ),
)
