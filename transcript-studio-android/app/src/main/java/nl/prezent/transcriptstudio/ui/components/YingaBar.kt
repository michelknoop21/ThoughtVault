package nl.prezent.transcriptstudio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.BrandAccent
import nl.prezent.transcriptstudio.ui.theme.BrandOrange
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary

/**
 * Yinga four-color horizontal brand bar.
 * Matches the iOS YingaBar from Theme.swift.
 */
@Composable
fun YingaBar(
    modifier: Modifier = Modifier,
    height: Dp = 4.dp,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(height),
    ) {
        Box(modifier = Modifier.weight(1f).background(BrandPrimary).height(height))
        Box(modifier = Modifier.weight(1f).background(BrandSecondary).height(height))
        Box(modifier = Modifier.weight(1f).background(BrandAccent).height(height))
        Box(modifier = Modifier.weight(1f).background(BrandOrange).height(height))
    }
}
