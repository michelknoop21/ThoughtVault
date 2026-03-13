package nl.prezent.transcriptstudio.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.StatusError

/**
 * Animated pulsing red dot used as a recording indicator.
 * Matches the iOS PulsingRecordingDot from Theme.swift:
 * - Outer ring scales 1.0 -> 1.4, fades from 0.6 -> 0.0
 * - Inner solid dot stays static
 * - 1.2s cycle, no autoreversal
 */
@Composable
fun PulsingRecordingDot(
    modifier: Modifier = Modifier,
    size: Dp = 12.dp,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "recording-pulse")

    val scale by infiniteTransition.animateFloat(
        initialValue = 1.0f,
        targetValue = 1.4f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse-scale",
    )

    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.6f,
        targetValue = 0.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200),
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse-alpha",
    )

    Box(
        modifier = modifier.size(size * 2.2f),
        contentAlignment = Alignment.Center,
    ) {
        // Outer pulsing ring
        Box(
            modifier = Modifier
                .size(size * 2.2f)
                .scale(scale)
                .alpha(alpha)
                .background(
                    color = StatusError.copy(alpha = 0.3f),
                    shape = CircleShape,
                ),
        )
        // Inner solid dot
        Box(
            modifier = Modifier
                .size(size)
                .background(
                    color = StatusError,
                    shape = CircleShape,
                ),
        )
    }
}
