package nl.prezent.transcriptstudio.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.TS

/**
 * Primary action button — BrandPrimary fill, white text, spring press animation.
 * Matches the iOS PrimaryButtonStyle from Theme.swift.
 */
@Composable
fun TSPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()

    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.97f else 1.0f,
        animationSpec = spring(
            dampingRatio = 0.7f,
            stiffness = 800f,
        ),
        label = "primary-button-scale",
    )

    Button(
        onClick = onClick,
        modifier = modifier.scale(scale),
        enabled = enabled,
        shape = RoundedCornerShape(TS.Radius.sm),
        colors = ButtonDefaults.buttonColors(
            containerColor = BrandPrimary,
            contentColor = Color.White,
            disabledContainerColor = BrandPrimary.copy(alpha = 0.38f),
            disabledContentColor = Color.White.copy(alpha = 0.6f),
        ),
        contentPadding = PaddingValues(
            horizontal = TS.Spacing.lg,
            vertical = TS.Spacing.sm + TS.Spacing.xs / 2, // ~10dp matching iOS sm+2
        ),
        interactionSource = interactionSource,
    ) {
        Text(
            text = text,
            fontWeight = FontWeight.SemiBold,
        )
    }
}
