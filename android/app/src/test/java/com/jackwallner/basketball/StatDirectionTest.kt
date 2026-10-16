package com.jackwallner.basketball

import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StatDirectionTest {
    private fun player(
        id: Int,
        name: String,
        value: String,
        percentile: Int,
        label: String = "TS%",
        category: MetricCategory = MetricCategory.SCORING,
        type: String = "g",
    ) = testPlayer(
        id = id, name = name, team = "BOS", position = type.uppercase(), season = 2026, type = type,
        metrics = listOf(metric(label, value, percentile, category, id = "m$id")),
    )

    private fun ranked(players: List<Player>, descending: Boolean = true) =
        players.sortedWith(DashboardViewModel.metricComparator("TS%", MetricCategory.SCORING, descending))

    @Test
    fun basketballLowerIsBetterMetrics() {
        assertTrue(DashboardViewModel.lowerIsBetter("TOV%", MetricCategory.PLAYMAKING))
        assertTrue(DashboardViewModel.lowerIsBetter("TOV/G", MetricCategory.PLAYMAKING))
        assertTrue(DashboardViewModel.lowerIsBetter("Fouls/100", MetricCategory.DEFENSE))
        assertFalse(DashboardViewModel.lowerIsBetter("TS%", MetricCategory.SCORING))
        assertFalse(DashboardViewModel.lowerIsBetter("BLK%", MetricCategory.DEFENSE))
        // Assisted FG% is descriptive, ranked higher-is-better like the rest.
        assertFalse(DashboardViewModel.lowerIsBetter("Assisted FG%", MetricCategory.SHOOTING))
    }

    @Test
    fun lowerIsBetterBoardsOpenBestFirst() {
        assertFalse(DashboardViewModel.defaultSortDescending("TOV%", MetricCategory.PLAYMAKING))
        assertTrue(DashboardViewModel.defaultSortDescending("TS%", MetricCategory.SCORING))
    }

    @Test
    fun blankValuesRankByPercentileInsteadOfLast() {
        val players = listOf(
            player(1, "Printable but poor", "48.0%", 5),
            player(2, "Blank but elite", "", 99),
            player(3, "Blank and poor", "", 2),
        )
        assertEquals(listOf("Blank but elite", "Printable but poor", "Blank and poor"), ranked(players).map { it.name })
    }

    @Test
    fun equalPercentilesBreakTiesOnValue() {
        val players = listOf(player(1, "Lower value", "58.2%", 80), player(2, "Higher value", "59.9%", 80))
        assertEquals(listOf("Higher value", "Lower value"), ranked(players).map { it.name })
    }

    /** The All board mixes cohorts, and a percentile only means something inside one, so there the raw number leads. */
    @Test
    fun allBoardRanksByTheNumberNotTheCohortPercentile() {
        val players = listOf(
            player(1, "Guard, high percentile", "9.0%", 95, "REB%", MetricCategory.REBOUNDING, "g"),
            player(2, "Center, low percentile", "17.0%", 40, "REB%", MetricCategory.REBOUNDING, "c"),
        )
        val byPercentile = players.sortedWith(DashboardViewModel.metricComparator("REB%", MetricCategory.REBOUNDING, true))
        assertEquals("Guard, high percentile", byPercentile.first().name)
        val byValue = players.sortedWith(DashboardViewModel.metricComparator("REB%", MetricCategory.REBOUNDING, true, acrossCohorts = true))
        assertEquals("Center, low percentile", byValue.first().name)
    }

    @Test
    fun missingMetricSortsLastInBothDirections() {
        val hasMetric = player(1, "Has it", "58.0%", 50)
        val lacksMetric = player(2, "Lacks it", "31.0", 40, label = "Pts/100")
        for (descending in listOf(true, false)) {
            assertEquals("Lacks it", ranked(listOf(lacksMetric, hasMetric), descending).last().name)
        }
    }
}
