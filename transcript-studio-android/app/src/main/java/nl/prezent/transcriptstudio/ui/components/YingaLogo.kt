package nl.prezent.transcriptstudio.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary

/**
 * Yinga wordmark placeholder.
 * Renders "YINGA" in bold BrandPrimary. Replace with vector drawable
 * when the official logo asset is available.
 */
@Composable
fun YingaLogo(modifier: Modifier = Modifier) {
    Text(
        text = "YINGA",
        modifier = modifier,
        color = BrandPrimary,
        fontSize = 20.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 2.sp,
    )
}
