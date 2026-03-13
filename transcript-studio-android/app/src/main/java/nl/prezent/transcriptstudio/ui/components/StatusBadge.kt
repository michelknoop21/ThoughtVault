package nl.prezent.transcriptstudio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import nl.prezent.transcriptstudio.ui.theme.TS

/**
 * Small chip showing a status label with an appropriate color.
 *
 * Uses a simple (text, color) signature so it can be used before
 * the TaskStatus enum is available. Wrap it later with a convenience
 * overload that maps TaskStatus to Dutch label + color.
 */
@Composable
fun StatusBadge(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        modifier = modifier
            .background(
                color = color.copy(alpha = 0.12f),
                shape = RoundedCornerShape(TS.Radius.xs),
            )
            .padding(
                horizontal = TS.Spacing.sm,
                vertical = TS.Spacing.xs,
            ),
        color = color,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        lineHeight = 16.sp,
    )
}
