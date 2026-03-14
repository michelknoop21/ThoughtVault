package nl.prezent.transcriptstudio.ui.recording

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.TS
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Wave configuration matching macOS WaveformView.swift.
 */
private data class WaveConfig(
    val frequency: Float,
    val speed: Float,
    val amplitudeScale: Float,
    val phaseOffset: Float,
    val lineWidth: Float,
    val glowWidth: Float,
    val glowOpacity: Float,
)

private val waveConfigs = listOf(
    WaveConfig(1.5f, 6.0f, 1.0f, 0.0f, 2.5f, 10.0f, 0.35f),
    WaveConfig(1.8f, 5.2f, 0.85f, 0.7f, 2.0f, 8.0f, 0.28f),
    WaveConfig(1.2f, 7.5f, 0.75f, 1.5f, 1.5f, 6.0f, 0.22f),
    WaveConfig(2.0f, 4.8f, 0.65f, 2.1f, 1.2f, 5.0f, 0.18f),
    WaveConfig(2.4f, 3.8f, 0.55f, 2.8f, 1.2f, 5.0f, 0.18f),
    WaveConfig(0.9f, 8.0f, 0.45f, 3.3f, 1.0f, 4.0f, 0.14f),
    WaveConfig(1.6f, 5.5f, 0.35f, 3.9f, 0.8f, 3.0f, 0.12f),
    WaveConfig(2.8f, 3.5f, 0.25f, 4.5f, 0.8f, 2.0f, 0.10f),
)

/** Gradient colors: blue -> violet -> magenta -> cyan */
private val gradientColors = listOf(
    Color(0xFF1440B3),
    Color(0xFF4F3DFF),
    Color(0xFFA114C7),
    Color(0xFF29A1FF),
)

/** Dark background for waveform — additive blending requires dark surface */
private val waveformBackground = Brush.verticalGradient(
    colors = listOf(
        Color(0xFF0D0E1A),
        Color(0xFF111225),
        Color(0xFF0D0E1A),
    ),
)

/**
 * Siri-style waveform visualizer matching the macOS WaveformView.
 *
 * 8 layered sine waves with Gaussian envelope, per-wave glow,
 * animated gradient, smooth amplitude tracking, and organic wobble.
 *
 * Renders on a dark background for proper additive blending.
 *
 * @param audioLevel Current audio level (0..1), updated at ~60 Hz.
 * @param isActive Whether the visualizer is active.
 * @param height Height of the visualizer.
 */
@Composable
fun WaveformVisualizer(
    audioLevel: Float,
    isActive: Boolean,
    modifier: Modifier = Modifier,
    height: Dp = 160.dp,
) {
    // Smooth amplitude (fast attack, slow release — matches macOS)
    var smoothedLevel by remember { mutableFloatStateOf(0.01f) }
    val targetLevel = if (isActive) max(0.01f, audioLevel) else 0.01f
    val delta = targetLevel - smoothedLevel
    val smoothingFactor = if (delta > 0) 0.2f else 0.05f
    smoothedLevel += delta * smoothingFactor

    // Continuous time driver at 60 fps
    val infiniteTransition = rememberInfiniteTransition(label = "waveform-time")
    val time by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1_000_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "waveform-time",
    )

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(RoundedCornerShape(TS.Radius.md))
            .background(waveformBackground),
    ) {
        val canvasWidth = size.width
        val canvasHeight = size.height
        val midY = canvasHeight / 2f
        val padding = min(max(4f, midY * 0.15f), 16f)
        val maxAmplitude = midY - padding
        if (maxAmplitude <= 1f) return@Canvas

        val currentLevel = smoothedLevel
        val gradientOffset = sin(time * 0.5f) * 0.1f

        // Draw waves back to front
        for (i in waveConfigs.indices.reversed()) {
            val config = waveConfigs[i]
            val wavePhase = -(time * config.speed) + config.phaseOffset

            // Organic wobble per wave
            val wobble = 0.88f + 0.12f * sin(time * 3.0f + i * 1.7f)
            val level = max(0.01f, currentLevel * config.amplitudeScale * wobble)

            val path = buildWavePath(
                width = canvasWidth,
                midY = midY,
                maxAmplitude = maxAmplitude,
                frequency = config.frequency,
                phase = wavePhase,
                level = level,
            )

            // Per-wave opacity
            val idxRatio = 1f - (i.toFloat() / waveConfigs.size)
            val opacity = if (i == 0) 0.9f else min(0.8f, 0.3f + idxRatio * 0.5f)

            val brush = createAnimatedGradient(canvasWidth, gradientOffset)

            // Glow pass (bloom)
            drawPath(
                path = path,
                brush = brush,
                alpha = config.glowOpacity,
                style = Stroke(
                    width = config.glowWidth,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )

            // Main stroke
            drawPath(
                path = path,
                brush = brush,
                alpha = opacity,
                style = Stroke(
                    width = config.lineWidth,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
            )
        }
    }
}

private fun buildWavePath(
    width: Float,
    midY: Float,
    maxAmplitude: Float,
    frequency: Float,
    phase: Float,
    level: Float,
): Path {
    val path = Path()
    val step = 2f
    val twoPi = (2.0 * PI).toFloat()
    val midX = width / 2f
    val gaussianScale = 2.5f

    var first = true
    var x = 0f
    while (x <= width) {
        val normalized = (x - midX) / midX
        val envelope = exp(-(normalized * gaussianScale).pow(2))

        val angle = twoPi * (x / width) * frequency + phase
        val sineVal = sin(angle)

        val amplitude = envelope * maxAmplitude * level
        val y = midY + amplitude * sineVal

        if (first) {
            path.moveTo(x, y)
            first = false
        } else {
            path.lineTo(x, y)
        }
        x += step
    }
    return path
}

private fun DrawScope.createAnimatedGradient(
    width: Float,
    offset: Float,
): Brush {
    val shiftPx = width * offset
    return Brush.linearGradient(
        colors = gradientColors,
        start = Offset(-shiftPx, 0f),
        end = Offset(width - shiftPx, 0f),
    )
}
