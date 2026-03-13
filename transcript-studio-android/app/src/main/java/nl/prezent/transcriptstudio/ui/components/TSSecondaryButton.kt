package nl.prezent.transcriptstudio.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.AccentBgPrimaryLight
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.TS

/**
 * Secondary action button — outlined with BrandPrimary border, tinted background.
 * Matches the iOS SecondaryButtonStyle from Theme.swift.
 */
@Composable
fun TSSecondaryButton(
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
        label = "secondary-button-scale",
    )

    OutlinedButton(
        onClick = onClick,
        modifier = modifier.scale(scale),
        enabled = enabled,
        shape = RoundedCornerShape(TS.Radius.sm),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = BrandPrimary.copy(alpha = 0.08f),
            contentColor = BrandPrimary,
            disabledContainerColor = BrandPrimary.copy(alpha = 0.04f),
            disabledContentColor = BrandPrimary.copy(alpha = 0.38f),
        ),
        border = BorderStroke(
            width = 1.dp,
            color = if (enabled) BrandPrimary.copy(alpha = 0.35f) else BrandPrimary.copy(alpha = 0.12f),
        ),
        contentPadding = PaddingValues(
            horizontal = TS.Spacing.lg,
            vertical = TS.Spacing.sm + TS.Spacing.xs / 2,
        ),
        interactionSource = interactionSource,
    ) {
        Text(
            text = text,
            fontWeight = FontWeight.Medium,
        )
    }
}
