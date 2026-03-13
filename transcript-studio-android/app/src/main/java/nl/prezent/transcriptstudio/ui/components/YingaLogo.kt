package nl.prezent.transcriptstudio.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import nl.prezent.transcriptstudio.ui.theme.BrandAccent
import nl.prezent.transcriptstudio.ui.theme.BrandOrange
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary

private const val VIEWBOX_WIDTH = 400.42f
private const val VIEWBOX_HEIGHT = 171.77f
private const val ASPECT_RATIO = VIEWBOX_WIDTH / VIEWBOX_HEIGHT

/**
 * Yinga full-color logo (spinner + wordmark) drawn via Compose Canvas.
 * Traced from official SVG at yinga.nl — matches macOS and Windows implementations.
 */
@Composable
fun YingaLogo(
    modifier: Modifier = Modifier,
    height: Dp = 28.dp,
) {
    Canvas(
        modifier = modifier
            .height(height)
            .aspectRatio(ASPECT_RATIO),
    ) {
        val scaleX = size.width / VIEWBOX_WIDTH
        val scaleY = size.height / VIEWBOX_HEIGHT
        scale(scaleX, scaleY, pivot = androidx.compose.ui.geometry.Offset.Zero) {
            drawSpinnerOrange()
            drawSpinnerMagenta()
            drawSpinnerGreen()
            drawSpinnerBlue()
            drawWordmark()
        }
    }
}

// Spinner: orange (top-right)
private fun DrawScope.drawSpinnerOrange() {
    val path = Path().apply {
        moveTo(370.22f, 22.26f)
        cubicTo(373.84f, 23.68f, 376.73f, 26.57f, 378.15f, 30.19f)
        cubicTo(378.49f, 31.06f, 379.33f, 31.64f, 380.27f, 31.64f)
        lineTo(398.12f, 31.64f)
        cubicTo(399.54f, 31.64f, 400.63f, 30.25f, 400.38f, 28.97f)
        cubicTo(397.76f, 14.28f, 386.14f, 2.66f, 371.45f, 0.04f)
        cubicTo(370.06f, -0.21f, 368.78f, 0.88f, 368.78f, 2.3f)
        lineTo(368.78f, 20.15f)
        cubicTo(368.78f, 21.09f, 369.36f, 21.93f, 370.22f, 22.26f)
        close()
    }
    drawPath(path, BrandOrange)
}

// Spinner: magenta (top-left)
private fun DrawScope.drawSpinnerMagenta() {
    val path = Path().apply {
        moveTo(352.13f, 30.19f)
        cubicTo(353.55f, 26.57f, 356.44f, 23.68f, 360.06f, 22.26f)
        cubicTo(360.93f, 21.92f, 361.51f, 21.08f, 361.51f, 20.14f)
        lineTo(361.51f, 2.3f)
        cubicTo(361.51f, 0.88f, 360.23f, -0.21f, 358.84f, 0.04f)
        cubicTo(344.15f, 2.66f, 332.53f, 14.28f, 329.91f, 28.97f)
        cubicTo(329.66f, 30.36f, 330.76f, 31.64f, 332.17f, 31.64f)
        lineTo(350.02f, 31.64f)
        cubicTo(350.96f, 31.64f, 351.80f, 31.06f, 352.13f, 30.19f)
        close()
    }
    drawPath(path, BrandPrimary)
}

// Spinner: green (bottom-right)
private fun DrawScope.drawSpinnerGreen() {
    val path = Path().apply {
        moveTo(378.15f, 40.36f)
        cubicTo(376.73f, 43.98f, 373.84f, 46.87f, 370.22f, 48.29f)
        cubicTo(369.35f, 48.63f, 368.77f, 49.47f, 368.77f, 50.41f)
        lineTo(368.77f, 68.26f)
        cubicTo(368.77f, 69.68f, 370.05f, 70.77f, 371.44f, 70.52f)
        cubicTo(386.13f, 67.90f, 397.75f, 56.28f, 400.37f, 41.59f)
        cubicTo(400.62f, 40.20f, 399.52f, 38.92f, 398.11f, 38.92f)
        lineTo(380.26f, 38.92f)
        cubicTo(379.32f, 38.92f, 378.48f, 39.50f, 378.15f, 40.36f)
        close()
    }
    drawPath(path, BrandAccent)
}

// Spinner: blue (bottom-left)
private fun DrawScope.drawSpinnerBlue() {
    val path = Path().apply {
        moveTo(360.06f, 48.29f)
        cubicTo(356.44f, 46.87f, 353.55f, 43.98f, 352.13f, 40.36f)
        cubicTo(351.79f, 39.49f, 350.95f, 38.91f, 350.01f, 38.91f)
        lineTo(332.16f, 38.91f)
        cubicTo(330.74f, 38.91f, 329.65f, 40.19f, 329.90f, 41.58f)
        cubicTo(332.52f, 56.27f, 344.14f, 67.89f, 358.83f, 70.51f)
        cubicTo(360.22f, 70.76f, 361.50f, 69.67f, 361.50f, 68.25f)
        lineTo(361.50f, 50.40f)
        cubicTo(361.50f, 49.46f, 360.92f, 48.63f, 360.06f, 48.29f)
        close()
    }
    drawPath(path, BrandSecondary)
}

// Wordmark "yinga" in magenta — evenOdd fill rule
private fun DrawScope.drawWordmark() {
    val path = Path().apply {
        fillType = androidx.compose.ui.graphics.PathFillType.EvenOdd

        // Letter "y"
        moveTo(59.09f, 137.38f)
        lineTo(59.09f, 71.88f)
        cubicTo(59.09f, 68.22f, 56.12f, 65.25f, 52.46f, 65.25f)
        cubicTo(48.80f, 65.25f, 45.83f, 68.22f, 45.83f, 71.88f)
        lineTo(45.83f, 112.84f)
        cubicTo(45.83f, 125.78f, 40.40f, 132.16f, 29.54f, 132.16f)
        cubicTo(18.68f, 132.16f, 13.25f, 125.78f, 13.25f, 112.84f)
        lineTo(13.25f, 71.88f)
        cubicTo(13.25f, 68.22f, 10.28f, 65.25f, 6.62f, 65.25f)
        cubicTo(2.96f, 65.25f, 0f, 68.22f, 0f, 71.88f)
        lineTo(0f, 114.12f)
        cubicTo(0f, 133.44f, 9.42f, 143.66f, 26.99f, 143.66f)
        cubicTo(35.14f, 143.66f, 41.53f, 141.10f, 45.52f, 135.84f)
        lineTo(45.84f, 135.84f)
        lineTo(45.84f, 137.41f)
        lineTo(45.84f, 146.21f)
        cubicTo(45.84f, 155.47f, 41.37f, 160.26f, 33.06f, 160.26f)
        cubicTo(30.02f, 160.26f, 27.47f, 159.62f, 25.07f, 158.35f)
        cubicTo(24.52f, 158.05f, 24.07f, 157.81f, 23.56f, 157.81f)
        cubicTo(21.50f, 157.26f, 19.28f, 157.81f, 17.85f, 159.50f)
        lineTo(17.83f, 159.52f)
        cubicTo(15.60f, 162.17f, 16.41f, 165.62f, 19.32f, 167.92f)
        cubicTo(19.32f, 167.92f, 19.98f, 168.46f, 20.43f, 168.73f)
        cubicTo(23.95f, 170.65f, 28.58f, 171.77f, 34.49f, 171.77f)
        cubicTo(50.78f, 171.77f, 59.09f, 163.14f, 59.09f, 146.53f)
        lineTo(59.09f, 137.41f)
        lineTo(59.09f, 137.38f)
        close()

        // Letter "i" dot
        moveTo(78.94f, 43.66f)
        cubicTo(78.13f, 37.42f, 82.67f, 32.97f, 88.70f, 33.89f)
        cubicTo(92.17f, 34.42f, 94.97f, 37.21f, 95.49f, 40.68f)
        cubicTo(96.41f, 46.72f, 91.96f, 51.26f, 85.72f, 50.44f)
        cubicTo(82.21f, 49.98f, 79.39f, 47.17f, 78.94f, 43.66f)
        close()

        // Letter "i" stem
        moveTo(80.60f, 137.66f)
        lineTo(87.23f, 137.66f)
        cubicTo(90.89f, 137.66f, 93.86f, 134.69f, 93.86f, 131.03f)
        lineTo(93.86f, 65.23f)
        cubicTo(93.86f, 61.57f, 90.89f, 58.60f, 87.23f, 58.60f)
        cubicTo(83.57f, 58.60f, 80.60f, 61.57f, 80.60f, 65.23f)
        lineTo(80.60f, 131.03f)
        cubicTo(80.60f, 134.69f, 83.57f, 137.66f, 87.23f, 137.66f)
        close()

        // Letter "n"
        moveTo(160.29f, 94.30f)
        cubicTo(160.29f, 80.89f, 155.18f, 74.82f, 144f, 74.82f)
        cubicTo(132.82f, 74.82f, 127.71f, 80.89f, 127.71f, 94.30f)
        lineTo(127.71f, 137.66f)
        cubicTo(127.71f, 141.32f, 124.74f, 144.29f, 121.08f, 144.29f)
        cubicTo(117.42f, 144.29f, 114.45f, 141.32f, 114.45f, 137.66f)
        lineTo(114.45f, 92.96f)
        cubicTo(114.45f, 73.70f, 127.75f, 63.27f, 144.13f, 63.32f)
        cubicTo(163.21f, 63.37f, 173.54f, 73.75f, 173.54f, 92.87f)
        lineTo(173.54f, 137.67f)
        cubicTo(173.54f, 141.33f, 170.57f, 144.30f, 166.91f, 144.30f)
        cubicTo(163.25f, 144.30f, 160.28f, 141.33f, 160.28f, 137.67f)
        lineTo(160.29f, 94.30f)
        close()

        // Letter "g"
        moveTo(251.48f, 93.52f)
        lineTo(251.48f, 143.51f)
        cubicTo(251.48f, 161.08f, 240.14f, 171.78f, 221.46f, 171.78f)
        cubicTo(210.92f, 171.78f, 202.14f, 168.75f, 195.59f, 163f)
        cubicTo(189.45f, 158.48f, 195.73f, 149.27f, 202.30f, 153.90f)
        cubicTo(207.57f, 158.21f, 213.48f, 160.29f, 220.67f, 160.29f)
        cubicTo(232.17f, 160.29f, 238.24f, 153.55f, 238.24f, 142.56f)
        lineTo(238.24f, 135.69f)
        lineTo(237.92f, 135.69f)
        cubicTo(233.93f, 140.96f, 227.54f, 143.67f, 219.24f, 143.67f)
        cubicTo(201.03f, 143.67f, 191.29f, 134.03f, 191.29f, 113.49f)
        lineTo(191.29f, 93.53f)
        cubicTo(191.29f, 73.66f, 202.07f, 63.17f, 221.98f, 63.35f)
        cubicTo(238.39f, 63.55f, 251.50f, 77.12f, 251.50f, 93.53f)
        close()

        // Letter "g" counter (inner shape)
        moveTo(238.22f, 112.05f)
        lineTo(238.22f, 94.80f)
        cubicTo(238.22f, 81.22f, 232.95f, 74.84f, 221.29f, 74.84f)
        cubicTo(209.63f, 74.84f, 204.52f, 81.22f, 204.52f, 94.80f)
        lineTo(204.52f, 112.05f)
        cubicTo(204.52f, 125.78f, 209.79f, 132.17f, 221.29f, 132.17f)
        cubicTo(232.95f, 132.17f, 238.22f, 125.46f, 238.22f, 112.05f)
        close()

        // Letter "a"
        moveTo(326.38f, 94.30f)
        lineTo(326.38f, 116.02f)
        cubicTo(326.38f, 135.66f, 315.84f, 146.20f, 296.04f, 146.20f)
        cubicTo(277.67f, 146.20f, 267.45f, 137.26f, 267.45f, 121.61f)
        cubicTo(267.45f, 106.02f, 277.51f, 97.49f, 295.88f, 97.49f)
        lineTo(313.13f, 97.49f)
        lineTo(313.13f, 95.57f)
        cubicTo(313.13f, 81.04f, 307.22f, 74.81f, 294.92f, 74.81f)
        cubicTo(289.01f, 74.81f, 283.42f, 77.21f, 279.11f, 80.88f)
        cubicTo(272.96f, 85.65f, 265.77f, 76.13f, 271.92f, 71.62f)
        cubicTo(278.79f, 66.03f, 286.77f, 63.31f, 296.04f, 63.31f)
        cubicTo(315.68f, 63.31f, 326.38f, 73.85f, 326.38f, 94.29f)
        close()

        // Letter "a" counter (inner shape)
        moveTo(313.13f, 114.74f)
        lineTo(313.13f, 108.51f)
        lineTo(297.48f, 108.51f)
        cubicTo(286.94f, 108.51f, 280.71f, 112.98f, 280.71f, 121.77f)
        cubicTo(280.71f, 130.50f, 286.30f, 134.71f, 296.04f, 134.71f)
        cubicTo(307.70f, 134.71f, 313.13f, 128.32f, 313.13f, 114.75f)
        close()
    }
    drawPath(path, BrandPrimary)
}
