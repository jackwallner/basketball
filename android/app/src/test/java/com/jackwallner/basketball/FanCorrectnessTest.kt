package com.jackwallner.basketball

import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.TrendMetric
import com.jackwallner.basketball.model.TrendSide
import com.jackwallner.basketball.model.competitionRanks
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Numbers a basketball fan checks against the box score, on the Android-only
 * paths: leaderboards share ranks on a tie, and the Trends board reads the
 * rollup's own then, now and change.
 */
class FanCorrectnessTest {
    private fun form(metrics: String, prior: String, delta: String, type: String = "g"): RecentForm {
        val json = """{"player_id":1,"season":2026,"player_type":"$type","window_weeks":2,"games":4,"metrics":$metrics,"prior_metrics":$prior,"delta":$delta}"""
        return RecentForm.fromJson(Json.parseToJsonElement(json) as JsonObject)
    }

    /** The board ranks the change the rollup published, never a re-derived one. */
    @Test
    fun trendValuesPassThroughTheRollup() {
        val ppg = TrendMetric.standard.first { it.label == "PPG" }
        val values = ppg.values(form("""{"${ppg.key}":31.4}""", """{"${ppg.key}":26.0}""", """{"${ppg.key}":5.4}"""))
        assertEquals(31.4, values.now!!, 1e-9)
        assertEquals(26.0, values.then!!, 1e-9)
        assertEquals(5.4, values.delta!!, 1e-9)
        assertEquals("31.4", ppg.display(31.4))
    }

    @Test
    fun turnoversRankLowestFirstAndPercentagesCarryTheirSign() {
        assertTrue(TrendMetric.standard.first { it.label == "TOV/G" }.lowerIsBetter)
        assertTrue(TrendMetric.advanced(TrendSide.GUARD).first { it.label == "TOV%" }.lowerIsBetter)
        assertTrue(TrendMetric.standard.first { it.label == "FG%" }.display(48.2).endsWith("%"))
        for (side in TrendSide.entries) assertTrue(side.hasAdvancedMetrics)
        assertEquals("c", TrendSide.CENTER.playerType)
    }

    /** Two guards on 31.0 points a game are not 21st and 22nd. */
    @Test
    fun tiesShareALeaderboardRank() {
        assertEquals(listOf(1, 2, 2, 4), competitionRanks(listOf(40.0, 31.0, 31.0, 20.0)))
        assertEquals(listOf(1, 2), competitionRanks(listOf(null, null)))
    }

    @Test
    fun onlyAWinReadsAsAWin() {
        assertEquals(HardwoodPalette.performanceHigh, HardwoodPalette.resultColor("W"))
        assertEquals(HardwoodPalette.performanceLow, HardwoodPalette.resultColor("L"))
    }
}
