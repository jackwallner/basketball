package com.jackwallner.basketball

import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.StandardStatSemantics
import com.jackwallner.basketball.ui.screens.LeaguePercentileCurve
import com.jackwallner.basketball.ui.screens.StandardStatCatalog
import kotlin.math.roundToInt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StandardStatsTest {
    @Test
    fun positionCatalogLeadsWithWhatEachCohortIsReadOn() {
        assertEquals("PPG", StandardStatCatalog.defaultStat(PlayerPositionGroup.ALL))
        assertEquals("APG", StandardStatCatalog.defaultStat(PlayerPositionGroup.GUARD))
        assertEquals("PPG", StandardStatCatalog.defaultStat(PlayerPositionGroup.FORWARD))
        assertEquals("RPG", StandardStatCatalog.defaultStat(PlayerPositionGroup.CENTER))
        // Same fifteen stat lines for everyone, in the order the feed ships them after the lead.
        for (position in PlayerPositionGroup.entries) {
            assertEquals(
                setOf("G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN"),
                StandardStatCatalog.stats(position).toSet(),
            )
        }
    }

    @Test
    fun walkingThePositionTabsRanksEachPositionByItsOwnDefault() {
        var stat = StandardStatCatalog.defaultStat(PlayerPositionGroup.ALL)
        var position = PlayerPositionGroup.ALL
        for (next in listOf(PlayerPositionGroup.GUARD, PlayerPositionGroup.FORWARD, PlayerPositionGroup.CENTER, PlayerPositionGroup.ALL)) {
            stat = StandardStatCatalog.stat(stat, position, next)
            position = next
            assertEquals(StandardStatCatalog.defaultStat(next), stat)
        }
    }

    @Test
    fun deliberatelyChosenStatFollowsAcrossPositions() {
        assertEquals("BPG", StandardStatCatalog.stat("BPG", PlayerPositionGroup.ALL, PlayerPositionGroup.CENTER))
        assertEquals("BPG", StandardStatCatalog.stat("BPG", PlayerPositionGroup.CENTER, PlayerPositionGroup.GUARD))
        // A default is not a choice: it does not follow.
        assertEquals("RPG", StandardStatCatalog.stat("APG", PlayerPositionGroup.GUARD, PlayerPositionGroup.CENTER))
    }

    @Test
    fun turnoversAndFoulsDefaultLowestFirst() {
        assertFalse(StandardStatCatalog.defaultDescending("TOV", PlayerPositionGroup.GUARD))
        assertFalse(StandardStatCatalog.defaultDescending("PF", PlayerPositionGroup.CENTER))
        assertTrue(StandardStatCatalog.defaultDescending("PPG", PlayerPositionGroup.ALL))
        assertTrue(StandardStatCatalog.defaultDescending("+/-", PlayerPositionGroup.ALL))
    }

    @Test
    fun metricCategoryDecodesCaseInsensitively() {
        for (raw in listOf("scoring", "SCORING", "Scoring")) {
            val json = """{"id":"m","label":"Pts/100","value":"31.2","percentile":88,"category":"$raw"}"""
            val decoded = Metric.fromJson(Json.parseToJsonElement(json) as JsonObject)
            assertEquals(MetricCategory.SCORING, decoded.category)
        }
    }

    @Test
    fun madeAttemptedLinesRankByPercentage() {
        // 612/1,250 is 49.0%, and the comma has to survive the parse.
        assertEquals(48.96, StandardStatSemantics.numericValue("FG", "612/1,250")!!, 0.001)
        assertEquals(38.59, StandardStatSemantics.numericValue("3P", "115/298")!!, 0.01)
        assertEquals(87.95, StandardStatSemantics.numericValue("FT", "540/614")!!, 0.01)
        // A pair with no attempts has no percentage.
        assertNull(StandardStatSemantics.numericValue("3P", "0/0"))
        // The other lines are plain numbers, signs and commas included.
        assertEquals(788.0, StandardStatSemantics.numericValue("+/-", "+788")!!, 0.0)
        assertEquals(2262.0, StandardStatSemantics.numericValue("MIN", "2,262")!!, 0.0)
    }

    @Test
    fun standardComparisonRespectsDirectionAndRates() {
        // More makes at a worse percentage loses.
        assertEquals(StandardStatSemantics.Winner.RIGHT, StandardStatSemantics.winner("FG", "400/900", "300/600"))
        // Fewer turnovers and fouls win.
        assertEquals(StandardStatSemantics.Winner.LEFT, StandardStatSemantics.winner("TOV", "120", "151"))
        assertEquals(StandardStatSemantics.Winner.RIGHT, StandardStatSemantics.winner("PF", "200", "139"))
        assertNull(StandardStatSemantics.winner("G", "60", "60"))
    }

    @Test
    fun pairPercentilesRankPeersByPercentage() {
        // 8/11 is 72.7%; against 5/9 (55.6%) and 10/10 (100%) it is the middle.
        assertEquals(50, StandardStatSemantics.percentile("FT", "8/11", listOf("8/11", "5/9", "10/10")))
        // 3P: 40.0% beats a 33.3% and a 25.0% shooter, whatever their makes.
        assertEquals(
            ((2.0 + 0.5) / 3.0 * 100).roundToInt(),
            StandardStatSemantics.percentile("3P", "100/250", listOf("100/250", "150/450", "50/200")),
        )
    }

    @Test
    fun everyExistingStandardStatGetsAPercentile() {
        assertEquals(50, StandardStatSemantics.percentile("G", "1", emptyList()))
    }

    @Test
    fun percentileRanksAgainstWhicheverPeersHaveTheStat() {
        assertEquals(75, StandardStatSemantics.percentile("PPG", "24.0", listOf("24.0", "9.0")))
        assertEquals(50, StandardStatSemantics.percentile("PPG", "24.0", listOf("24.0")))
        // Direction still applies with a thin pool: fewer turnovers is better.
        val peers = listOf("90", "180")
        assertTrue(StandardStatSemantics.percentile("TOV", "90", peers) > StandardStatSemantics.percentile("TOV", "180", peers))
    }

    @Test
    fun percentileIsNeverZeroForAnExistingValue() {
        // A stat that exists always lands on a drawable 1-100 bar.
        for (value in listOf("0", "1", "250", "0.0")) {
            val pct = StandardStatSemantics.percentile("PPG", value, listOf("0", "1", "250", "999"))
            assertTrue("$value produced $pct", pct in 1..100)
        }
    }

    @Test
    fun leagueCurveInterpolatesFromTwoPoints() {
        val curve = LeaguePercentileCurve.of(listOf(100.0 to 20.0, 300.0 to 80.0))
        assertNotNull(curve)
        assertEquals(50, curve!!.percentile(200.0))
        assertEquals(20, curve.percentile(50.0))
        assertEquals(80, curve.percentile(400.0))
        assertNull(LeaguePercentileCurve.of(listOf(100.0 to 20.0)))
    }
}
