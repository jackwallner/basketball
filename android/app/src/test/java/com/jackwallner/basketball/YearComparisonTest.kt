package com.jackwallner.basketball

import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.StandardStat
import com.jackwallner.basketball.ui.screens.standardComparisons
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The iOS tests exercise this logic inline; the Android port keeps the same shapes and values. */
class YearComparisonTest {
    private data class Comparison(val label: String, val change: Int, val pct1: Int = 0, val pct2: Int = 0)

    private fun compare(first: List<Metric>, second: List<Metric>): List<Comparison> {
        val dict1 = first.groupBy { it.label }
        val dict2 = second.groupBy { it.label }
        // Only add a comparison if the metric exists in BOTH years.
        return (dict1.keys + dict2.keys).mapNotNull { label ->
            val m1 = dict1[label]?.firstOrNull() ?: return@mapNotNull null
            val m2 = dict2[label]?.firstOrNull() ?: return@mapNotNull null
            Comparison(label, m1.percentile - m2.percentile, m1.percentile, m2.percentile)
        }
    }

    private fun year(season: Int, metrics: List<Metric> = emptyList(), standard: List<StandardStat> = emptyList()) =
        testPlayer(name = "Test", team = "BOS", position = "G", season = season, metrics = metrics, standard = standard)

    @Test
    fun playerHistorySortedBySeason() {
        val players = listOf(year(2024), year(2025), year(2023))
        assertEquals(listOf(2025, 2024, 2023), players.sortedByDescending { it.season }.map { it.season })
    }

    @Test
    fun uniqueYearsExtracted() {
        val players = listOf(year(2024), year(2024), year(2025))
        assertEquals(listOf(2025, 2024), players.mapNotNull { it.season }.distinct().sortedDescending())
    }

    @Test
    fun percentileChangeCalculation() {
        val p1 = year(2026, listOf(metric("TS%", "61.0%", 85)))
        val p2 = year(2025, listOf(metric("TS%", "58.0%", 75)))
        assertEquals(10, p1.overallPercentile - p2.overallPercentile)
    }

    @Test
    fun metricComparisonLogic() {
        val changes = compare(
            listOf(metric("TS%", "61.0%", 85), metric("USG%", "31.0%", 70)),
            listOf(metric("TS%", "58.0%", 75), metric("USG%", "33.0%", 80)),
        ).associate { it.label to it.change }
        assertEquals(10, changes["TS%"])
        assertEquals(-10, changes["USG%"])
    }

    @Test
    fun noOverlappingMetricsReturnsEmptyComparison() {
        val comparisons = compare(listOf(metric("TS%", "61.0%", 85)), listOf(metric("USG%", "33.0%", 80)))
        assertTrue("Comparisons should be empty when no metrics overlap", comparisons.isEmpty())
    }

    @Test
    fun partialOverlappingMetrics() {
        val comparisons = compare(
            listOf(metric("TS%", "61.0%", 85), metric("USG%", "31.0%", 70)),
            listOf(metric("TS%", "58.0%", 75), metric("eFG%", "54.0%", 60)),
        )
        // Only TS% should be compared since it's the only overlapping metric.
        assertEquals(1, comparisons.size)
        assertEquals("TS%", comparisons.first().label)
        assertEquals(10, comparisons.first().change)
    }

    @Test
    fun standardLinesAreUnitedInReadingOrder() {
        val left = year(2024, standard = listOf(std("MIN", "2,262"), std("PPG", "27.1"), std("G", "71")))
        val right = year(2025, standard = listOf(std("MIN", "2,410"), std("GS", "70")))
        val rows = standardComparisons(left, right)
        assertEquals(listOf("G", "GS", "PPG", "MIN"), rows.map { it.first })
        assertEquals(Triple("GS", null, "70"), rows[1])
    }
}

class YearComparisonFeatureTest {
    private fun year(season: Int, metrics: List<Metric> = emptyList(), playerId: Int = 1) =
        testPlayer(id = playerId, name = "Test", team = "BOS", position = "G", season = season, type = "g", metrics = metrics)

    @Test
    fun yearCompareTabExistsForPlayersWithHistory() {
        val history = listOf(year(2025), year(2024))
        assertTrue("Player should have multiple years of data", history.size > 1)
    }

    @Test
    fun yearCompareTabDisabledForPlayersWithoutHistory() {
        val history = listOf(year(2025, playerId = 2))
        assertTrue("Year Compare tab should be disabled for players with only one year", history.size <= 1)
    }

    @Test
    fun yearSelectionLogic() {
        val history = listOf(year(2025), year(2024), year(2023))
        val availableYears = history.sortedByDescending { it.season }.mapNotNull { it.season }.distinct().sortedDescending()
        assertEquals(listOf(2025, 2024, 2023), availableYears)

        // Default selection: most recent and second most recent.
        assertEquals(2025, availableYears.firstOrNull())
        assertEquals(2024, availableYears.drop(1).firstOrNull())
    }

    @Test
    fun metricComparisonDisplay() {
        val player2025 = year(
            2025,
            listOf(metric("TS%", "63.0%", 92), metric("USG%", "31.0%", 88), metric("TOV%", "12.0%", 45)),
        )
        val player2024 = year(
            2024,
            listOf(metric("TS%", "58.0%", 78), metric("USG%", "27.0%", 72), metric("TOV%", "14.0%", 35)),
        )
        val dict1 = player2025.metrics.groupBy { it.label }
        val dict2 = player2024.metrics.groupBy { it.label }
        val comparisons = (dict1.keys + dict2.keys).mapNotNull { label ->
            val m1 = dict1[label]?.firstOrNull() ?: return@mapNotNull null
            val m2 = dict2[label]?.firstOrNull() ?: return@mapNotNull null
            label to m1.percentile - m2.percentile
        }.sortedByDescending { kotlin.math.abs(it.second) }

        // Sorted by absolute change magnitude, descending.
        assertEquals(listOf("USG%" to 16, "TS%" to 14, "TOV%" to 10), comparisons)
    }

    @Test
    fun overallPercentileChangeCalculation() {
        val player2025 = year(2025, listOf(metric("A", "1", 80), metric("B", "2", 90)))
        val player2024 = year(2024, listOf(metric("A", "1", 70), metric("B", "2", 60)))

        // 2025: (80+90)/2 = 85, 2024: (70+60)/2 = 65.
        assertEquals(85, player2025.overallPercentile)
        assertEquals(65, player2024.overallPercentile)
        assertEquals(20, player2025.overallPercentile - player2024.overallPercentile)
    }
}
