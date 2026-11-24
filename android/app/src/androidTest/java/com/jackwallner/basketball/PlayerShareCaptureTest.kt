package com.jackwallner.basketball

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.ui.screens.PlayerShare
import com.jackwallner.basketball.ui.screens.ShareCardCapture
import com.jackwallner.basketball.ui.screens.ShareRequest
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The share card renders off screen into a real bitmap at three times its layout width. */
@RunWith(AndroidJUnit4::class)
class PlayerShareCaptureTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun capturesTheCardAtThreeTimesItsWidth() {
        val scoring = listOf(
            Metric("TS%", "64.1%", 95, MetricCategory.SCORING),
            Metric("Pts/100", "38.2", 97, MetricCategory.SCORING),
        )
        val player = Player(
            playerId = 1, name = "Stephen Curry", team = "GSW", position = "G", handedness = "",
            updatedAt = Instant.parse("2026-11-03T12:00:00Z"), season = 2026,
            metrics = scoring, standardStats = emptyList(), games = emptyList(),
        )
        val request = ShareRequest(player, listOf(MetricCategory.SCORING to scoring), "2025-26", "Through Nov 3")
        var captured: ImageBitmap? = null
        var done = false
        compose.setContent {
            ShareCardCapture(request) {
                captured = it
                done = true
            }
        }
        compose.waitUntil(10_000) { done }
        assertNotNull("the capture produced a bitmap", captured)
        val image = captured!!
        assertEquals((PlayerShare.CARD_WIDTH_DP * PlayerShare.SCALE).toInt(), image.width)
        assertTrue("the card has a header, two rows and a footer", image.height > 300)
        // The header band is midnight, so the card was really drawn, not left blank.
        val header = image.toPixelMap()[image.width - 4, 4]
        assertEquals(HardwoodPalette.midnight.red, header.red, 0.02f)
        assertEquals(HardwoodPalette.midnight.green, header.green, 0.02f)
    }
}
