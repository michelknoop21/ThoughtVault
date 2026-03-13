package nl.prezent.transcriptstudio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.TS

/**
 * Error banner with icon, tinted background and border.
 * Matches macOS error banner styling from LoginView.swift.
 */
@Composable
fun ErrorBanner(
    message: String,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(TS.Radius.xs)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(StatusError.copy(alpha = 0.08f))
            .border(1.dp, StatusError.copy(alpha = 0.25f), shape)
            .padding(TS.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = StatusError,
        )
        Spacer(modifier = Modifier.width(TS.Spacing.sm))
        Text(
            text = message,
            color = StatusError,
            fontSize = 13.sp,
            fontWeight = FontWeight.Normal,
            lineHeight = 18.sp,
        )
    }
}
