package com.jackwallner.basketball

import android.content.Intent
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.basketball.data.TwoTierPlayerCache
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * End-to-end flows on a real device. Most run on the debug fixture feed so
 * they are deterministic; the live test hits the production Supabase feed on
 * purpose, since a mock would only prove the mock still matches.
 */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(fixture: Boolean = true, onboarded: Boolean = true, forcePro: Boolean = false, tab: Int = 0) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("uiTest", true)
            .putExtra("screenshotData", fixture)
            .putExtra("onboarded", onboarded)
            .putExtra("forcePro", forcePro)
            .putExtra("previewStore", true)
            .putExtra("tab", tab)
        scenario = ActivityScenario.launch(intent)
    }

    @After
    fun tearDown() {
        scenario?.close()
    }

    private fun waitForText(text: String, timeout: Long = 30_000, substring: Boolean = false) {
        compose.waitUntil(timeout) {
            compose.onAllNodes(hasText(text, substring = substring) or hasContentDescription(text, substring = substring))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun tap(text: String, substring: Boolean = false) {
        compose.onAllNodes(hasText(text, substring = substring) or hasContentDescription(text, substring = substring))
            .onFirst().performClick()
    }

    @Test
    fun firstLaunchShowsOnboarding() {
        launch(fixture = false, onboarded = false)
        waitForText("Your Pocket", substring = true)
        waitForText("Continue")
    }

    @Test
    fun leaderboardOpensAPlayerProfile() {
        launch()
        waitForText("League leaders")
        waitForText("Shai Gilgeous-Alexander")
        tap("Shai Gilgeous-Alexander")
        waitForText("ADVANCED PERCENTILES")
        waitForText("TS%", substring = true)
    }

    @Test
    fun freeTrendsShowTheTeaserAndPaywall() {
        launch(tab = 2)
        waitForText("Heating up")
        waitForText("See all plans")
        tap("See all plans")
        waitForText("Restore Purchases")
        waitForText("Lifetime")
    }

    @Test
    fun proYearCompareShowsBothSeasons() {
        launch(forcePro = true)
        waitForText("Shai Gilgeous-Alexander")
        tap("Shai Gilgeous-Alexander")
        compose.onNodeWithTag("profileTab_Year Compare").performClick()
        waitForText("STANDARD STATS")
        waitForText("2024-25", substring = true)
    }

    @Test
    fun everyTabOpens() {
        launch()
        waitForText("League leaders")
        for (tab in listOf("Games", "Trends", "Teams", "Compare", "Stats")) {
            compose.onNodeWithTag("tab_$tab").performClick()
            compose.waitForIdle()
        }
        waitForText("League leaders")
    }

    /** Rate and Send Feedback are separate rows with no question in front; support lives in feedback. */
    @Test
    fun settingsSeparatesRatingFromFeedback() {
        launch()
        waitForText("League leaders")
        compose.onNodeWithTag("settingsButton").performClick()
        compose.onNodeWithTag("rateRow").performScrollTo()
        waitForText("Rate on Google Play")
        waitForText("Opens Google Play to write a review.")
        compose.onNodeWithTag("feedbackRow").performScrollTo()
        // Same label as iOS: feedback goes to a person, separate from the store rating.
        waitForText("Contact Support")
        waitForText("jackwallner+bb@gmail.com")
    }

    @Test
    fun bundledHistoryDecodesFromTheApk() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val cache = TwoTierPlayerCache(context.cacheDir) { name -> runCatching { context.assets.open(name) }.getOrNull() }
        val seasons = cache.loadHistoricalPlayers().mapNotNull { it.season }.toSet()
        assertTrue("Expected every bundled season, got $seasons", seasons.containsAll(TwoTierPlayerCache.bundledSeasons))
    }

    @Test
    fun liveFeedLoadsTheLeaderboard() {
        launch(fixture = false)
        // The Debug build parses the full feed slowly on an emulator; allow for it.
        compose.waitUntil(240_000) { compose.onAllNodesWithTag("tab_Stats").fetchSemanticsNodes().isNotEmpty() }
        // A fresh install opens on the Advanced board: real rows from the production feed.
        compose.waitUntil(240_000) { compose.onAllNodesWithTag("leaderboardRow").fetchSemanticsNodes().size >= 10 }
        compose.onAllNodesWithTag("leaderboardRow").onFirst().performClick()
        waitForText("ADVANCED PERCENTILES", timeout = 120_000)
    }
}
