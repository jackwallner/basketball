package com.jackwallner.basketball

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Raw captures for the Play listing, the Android side of the iOS
 * StatScoutV12ScreenshotUITests: the debug fixture feed (real 2025-26 NBA
 * rows), Pro unlocked, a settled season, the same screens as the App Store set.
 *
 * Excluded from `connectedDebugAndroidTest` (`notClass` in build.gradle.kts);
 * run it with `am instrument -e class com.jackwallner.basketball.StoreScreenshotTest`.
 * Files land in the app's external files dir under
 * `screens/`, named as scripts/play_screenshot_compositor.py expects.
 */
@RunWith(AndroidJUnit4::class)
class StoreScreenshotTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val fixturePlayer = "Shai Gilgeous-Alexander"
    private val comparisonPlayer = "Jalen Brunson"
    private var scenario: ActivityScenario<MainActivity>? = null

    @After
    fun tearDown() {
        scenario?.close()
    }

    @Test
    fun capture01LeagueLeaders() {
        launch(tab = 0)
        waitForText("League leaders")
        waitForText(fixturePlayer)
        // The board opens on On-Off; the App Store frame sorts by Pts/100.
        node(matcher("On-Off")).performClick()
        waitFor(hasTestTag("menu_Pts/100"))
        node(hasTestTag("menu_Pts/100")).performClick()
        compose.waitUntil(90_000) {
            compose.onAllNodes(hasTestTag("menu_Pts/100")).fetchSemanticsNodes().isEmpty() &&
                compose.onAllNodes(matcher("On-Off")).fetchSemanticsNodes().isEmpty()
        }
        compose.waitForIdle()
        capture("01_league_leaders")
    }

    @Test
    fun capture02PlayerProfile() {
        launch(tab = 0)
        openLeader(fixturePlayer)
        scrollNearTop("ADVANCED PERCENTILES")
        capture("02_player_profile")
    }

    @Test
    fun capture03Trends() {
        launch(tab = 2)
        waitForText("Heating up")
        waitFor(hasTestTag("trendRow"))
        capture("03_trends")
    }

    @Test
    fun capture04Comparison() {
        launch(tab = 0)
        openLeader(fixturePlayer)
        node(hasTestTag("compareButton")).performClick()
        // The picker is a lazy list: search so the row is composed at all.
        waitFor(hasTestTag("pickerRow"))
        node(hasSetTextAction()).performTextInput(comparisonPlayer)
        waitFor(hasTestTag("pickerRow") and hasText(comparisonPlayer, substring = true))
        node(hasTestTag("pickerRow") and hasText(comparisonPlayer, substring = true)).performClick()
        waitForText("Player Comparison")
        waitForText(comparisonPlayer)
        capture("04_player_comparison")
    }

    @Test
    fun capture05Team() {
        launch(tab = 3)
        waitForText("TEAM ADVANCED STATS")
        waitForText("New York Knicks")
        // Scoring's team Pts/100 is scaled from the whole roster; the fixture
        // carries only part of one, so Shooting is the honest frame.
        node(matcher("SHOOTING")).performClick()
        waitForText("SHOOTING")
        compose.waitForIdle()
        capture("05_team")
    }

    @Test
    fun capture06YearHistory() {
        launch(tab = 0)
        openLeader(fixturePlayer)
        node(hasTestTag("profileTab_Year Compare")).performClick()
        waitForText("STANDARD STATS")
        waitForText("2024-25", substring = true)
        capture("06_year_history")
    }

    @Test
    fun capture07Teams() {
        launch(tab = 3)
        // Teams opens on the followed club; back out to the grid of all 30.
        waitForText("TEAM ADVANCED STATS")
        node(hasTestTag("back")).performClick()
        waitForText("30 teams")
        compose.waitForIdle()
        capture("07_teams")
    }

    // Helpers

    private fun launch(tab: Int) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("uiTest", true)
            .putExtra("screenshotData", true)
            .putExtra("onboarded", true)
            .putExtra("forcePro", true)
            .putExtra("fixtureStatus", "published")
            .putExtra("statsBoard", "ADVANCED")
            .putExtra("tab", tab)
        scenario = ActivityScenario.launch(intent)
    }

    private fun matcher(text: String, substring: Boolean = false) =
        hasText(text, substring = substring) or hasContentDescription(text, substring = substring)

    private fun waitFor(matcher: androidx.compose.ui.test.SemanticsMatcher, timeout: Long = 90_000, useUnmergedTree: Boolean = false) {
        compose.waitUntil(timeout) { compose.onAllNodes(matcher, useUnmergedTree).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun waitForText(text: String, timeout: Long = 90_000, substring: Boolean = false) = waitFor(matcher(text, substring), timeout)

    private fun node(matcher: androidx.compose.ui.test.SemanticsMatcher): SemanticsNodeInteraction = compose.onAllNodes(matcher).onFirst()

    private fun openLeader(name: String) {
        waitForText(name)
        node(matcher(name)).performClick()
        waitForText("ADVANCED PERCENTILES")
    }

    /** Slow drags, no fling, until [text] sits just under the top bar. */
    private fun scrollNearTop(text: String) {
        val target = 420f
        var last = Float.MAX_VALUE
        repeat(40) {
            val top = compose.onAllNodes(matcher(text)).fetchSemanticsNodes().firstOrNull()?.boundsInRoot?.top ?: return
            // A drag shorter than touch slop lands as a tap on whatever row is under it.
            if (top <= target + 80f || kotlin.math.abs(top - last) < 1f) return
            last = top
            val step = minOf(top - target, 500f)
            compose.onRoot().performTouchInput {
                val x = width / 2f
                swipe(androidx.compose.ui.geometry.Offset(x, height * 0.75f), androidx.compose.ui.geometry.Offset(x, height * 0.75f - step), durationMillis = 900)
            }
            compose.waitForIdle()
        }
    }

    private fun capture(name: String) {
        // A refresh spinner is an infinite animation, so idling does not wait for it.
        compose.waitUntil(180_000) {
            compose.onAllNodes(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate)).fetchSemanticsNodes().isEmpty()
        }
        compose.waitForIdle()
        Thread.sleep(1_500)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap: Bitmap = instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot failed for $name")
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "screens").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}
