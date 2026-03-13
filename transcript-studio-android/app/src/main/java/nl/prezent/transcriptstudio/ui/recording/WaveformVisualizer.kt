package nl.prezent.transcriptstudio.ui.recording

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.NeonBlue

private const val MAX_BARS = 80
private const val BAR_WIDTH_FRACTION = 0.6f
private const val MIN_BAR_HEIGHT_FRACTION = 0.05f

/**
 * Real-time audio waveform visualizer drawn on Canvas.
 * Displays a scrolling bar graph of audio levels.
 *
 * @param audioLevel Current audio level (0..1), updated at ~60 Hz.
 * @param isActive Whether the visualizer is active (adds new bars).
 * @param color Bar color, defaults to NeonBlue.
 * @param height Height of the visualizer.
 */
@Composable
fun WaveformVisualizer(
    audioLevel: Float,
    isActive: Boolean,
    modifier: Modifier = Modifier,
    color: Color = NeonBlue,
    height: Dp = 120.dp,
) {
    val levels = remember { mutableStateListOf<Float>() }

    LaunchedEffect(audioLevel, isActive) {
        if (isActive) {
            levels.add(audioLevel.coerceIn(0f, 1f))
            if (levels.size > MAX_BARS) {
                levels.removeAt(0)
            }
        }
    }

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height),
    ) {
        val canvasWidth = size.width
        val canvasHeight = size.height
        val barCount = levels.size
        if (barCount == 0) return@Canvas

        val totalBarWidth = canvasWidth / MAX_BARS
        val barWidth = totalBarWidth * BAR_WIDTH_FRACTION
        val gap = totalBarWidth * (1f - BAR_WIDTH_FRACTION)
        val cornerRadius = CornerRadius(barWidth / 2, barWidth / 2)

        // Draw bars right-aligned (newest bar at right edge)
        val startX = canvasWidth - (barCount * totalBarWidth)

        for (i in levels.indices) {
            val level = levels[i]
            val barHeight = (canvasHeight * level.coerceAtLeast(MIN_BAR_HEIGHT_FRACTION))
            val x = startX + i * totalBarWidth + gap / 2
            val y = (canvasHeight - barHeight) / 2

            // Fade older bars slightly
            val ageFraction = i.toFloat() / MAX_BARS
            val alpha = 0.4f + 0.6f * ageFraction

            drawRoundRect(
                color = color.copy(alpha = alpha),
                topLeft = Offset(x, y),
                size = Size(barWidth, barHeight),
                cornerRadius = cornerRadius,
            )
        }
    }
}
