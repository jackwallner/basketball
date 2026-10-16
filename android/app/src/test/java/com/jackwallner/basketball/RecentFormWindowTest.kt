package com.jackwallner.basketball

import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.TrendMetric
import com.jackwallner.basketball.model.TrendSide
import com.jackwallner.basketball.model.TrendWindow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The rolling windows are 1, 2 and 4 calendar weeks, and say so the same way on every screen. */
class RecentFormWindowTest {
    private fun parse(json: String) = RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)

    @Test
    fun windowsAreOneTwoAndFourWeeks() {
        assertEquals(listOf(1, 2, 4), RecentWindow.entries.map { it.value })
        assertEquals(RecentWindow.entries, TrendWindow.entries)
    }

    @Test
    fun controlLabelsAreShortWeeks() {
        assertEquals(listOf("1 wk", "2 wk", "4 wk"), RecentWindow.entries.map { it.segmentLabel })
    }

    @Test
    fun proseNamesTheSpan() {
        assertEquals("last week", RecentWindow.WEEK.prose)
        assertEquals("last 2 weeks", RecentWindow.TWO_WEEKS.prose)
        assertEquals("last 4 weeks", RecentWindow.FOUR_WEEKS.prose)
        assertEquals("Last week", RecentWindow.WEEK.label)
        assertEquals("Last 4 weeks", RecentWindow.FOUR_WEEKS.label)
        assertEquals(28, RecentWindow.FOUR_WEEKS.days)
    }

    @Test
    fun recentFormRowLabelsItsOwnWindow() {
        val form = parse(
            """{"player_id":1966,"season":2026,"season_type":"REG","player_type":"f","as_of":"2026-04-12",
             "start_week":28,"end_week":28,"team":"LAL","games":3,"plays":66,"touches":81,"window_weeks":2,
             "metrics":{"ppg":24.0,"ts_pct":64.4},"prior_metrics":{"ppg":19.5,"ts_pct":59.3},
             "delta":{"ppg":4.5,"ts_pct":5.1}}""",
        )
        assertEquals("2 wk", form.windowLabel)
        assertEquals(81, form.minutes)
        assertEquals(4.5, form.delta["ppg"]!!, 0.0)
        assertFalse(form.isSmallSample)
    }

    @Test
    fun smallSampleIsGamesAndMinutes() {
        fun form(games: Int, minutes: Int) = parse(
            """{"player_id":1,"season":2026,"player_type":"g","window_weeks":1,"games":$games,
             "plays":10,"touches":$minutes,"metrics":{},"prior_metrics":{},"delta":{}}""",
        )
        assertTrue(form(1, 90).isSmallSample)
        assertTrue(form(3, 40).isSmallSample)
        assertFalse(form(2, 60).isSmallSample)
        assertFalse(form(1, 60).isSmallSample(minimumGames = 1))
    }

    /** The rollup keys are the season metric ids, so every registry metric maps. */
    @Test
    fun everyRegistryMetricHasARollupKey() {
        for (definition in BasketballMetricRegistry.definitions) {
            assertNotNull(definition.label, RecentMetricKey.key(definition.label))
        }
        assertEquals("pts_per_100", RecentMetricKey.key("Pts/100"))
        assertEquals("on_net", RecentMetricKey.key("On-Court +/-"))
        assertEquals("nc3_fg", RecentMetricKey.key("Non-Corner 3%"))
        assertEquals("ftr", RecentMetricKey.key("FT Rate"))
    }

    @Test
    fun formattingFollowsTheMetricKind() {
        assertEquals("61.2%", RecentMetricKey.format(61.24, "TS%"))
        assertEquals("28.0%", RecentMetricKey.format(28.0, "Rim Freq"))
        assertEquals("0.38", RecentMetricKey.format(0.38, "FT Rate"))
        assertEquals("+31.3", RecentMetricKey.format(31.34, "On-Off"))
        assertEquals("-7", RecentMetricKey.format(-7.0, "+/-"))
        assertEquals("1,502", RecentMetricKey.format(1_502.0, "3PM"))
        assertTrue(RecentMetricKey.lowerIsBetter("TOV%"))
        assertFalse(RecentMetricKey.lowerIsBetter("TS%"))
    }

    @Test
    fun trendBoardsCoverAllThreeCohortsWithoutAnEmptyList() {
        for (side in TrendSide.entries) {
            assertFalse(TrendMetric.advanced(side).isEmpty())
            assertFalse(TrendMetric.standard(side).isEmpty())
        }
        assertEquals(listOf("G", "F", "C"), TrendSide.entries.map { it.shortLabel })
        val turnovers = TrendMetric.advanced(TrendSide.GUARD).first { it.label == "TOV%" }
        assertTrue(turnovers.lowerIsBetter)
        assertEquals("12.3%", turnovers.format(12.34))
    }
}
