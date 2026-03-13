package nl.prezent.transcriptstudio.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary

/**
 * TranscriptStudio app logo — white waveform bars on magenta background.
 * Matches the macOS app icon (64x64, 14pt corner radius, shadow).
 */
@Composable
fun AppLogo(
    modifier: Modifier = Modifier,
    size: Dp = 64.dp,
    cornerRadius: Dp = 14.dp,
) {
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .shadow(
                elevation = 4.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.12f),
                spotColor = Color.Black.copy(alpha = 0.12f),
            )
            .size(size)
            .clip(shape)
            .background(BrandPrimary),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size(size * 0.6f)) {
            val w = this.size.width
            val h = this.size.height
            val centerY = h / 2f

            val barHeights = floatArrayOf(
                0.19f, 0.31f, 0.42f, 0.58f, 0.73f, 0.88f, 1.0f,
                0.88f, 0.73f, 0.58f, 0.42f, 0.31f, 0.19f,
            )
            val barCount = barHeights.size
            val barWidth = w / (barCount * 1.5f)
            val gap = (w - barCount * barWidth) / (barCount - 1)

            barHeights.forEachIndexed { index, heightFraction ->
                val barHeight = h * heightFraction
                val x = index * (barWidth + gap) + barWidth / 2f
                drawLine(
                    color = Color.White,
                    start = Offset(x, centerY - barHeight / 2f),
                    end = Offset(x, centerY + barHeight / 2f),
                    strokeWidth = barWidth,
                    cap = StrokeCap.Round,
                )
            }
        }
    }
}
