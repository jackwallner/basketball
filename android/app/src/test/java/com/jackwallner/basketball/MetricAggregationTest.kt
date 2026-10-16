package com.jackwallner.basketball

import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.MetricAggregation
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricValueFormat
import com.jackwallner.basketball.model.MetricWeight
import com.jackwallner.basketball.model.StandardStat
import com.jackwallner.basketball.model.metricNumericValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Roster-pooling rules the team comparison relies on. A rate is weighted by the
 * volume it was measured over: an unweighted mean lets a ten-minute cameo outrank
 * a 2,000-minute season, which is the failure mode these tests exist to prevent.
 */
class MetricAggregationTest {
    private fun aggregation(label: String, category: MetricCategory) = BasketballMetricRegistry.aggregation(label, category)

    private fun player(standard: List<StandardStat>) = testPlayer(season = 2026, standard = standard)

    @Test
    fun advancedRatesWeightByMinutes() {
        val rates = listOf(
            "TS%" to MetricCategory.SCORING, "AST%" to MetricCategory.PLAYMAKING, "REB%" to MetricCategory.REBOUNDING,
            "BLK%" to MetricCategory.DEFENSE, "On-Off" to MetricCategory.IMPACT, "Rim FG%" to MetricCategory.SHOOTING,
            "FG%" to MetricCategory.SCORING,
        )
        for ((label, category) in rates) {
            assertEquals(label, MetricAggregation.Weighted(MetricWeight.MINUTES), aggregation(label, category))
        }
    }

    @Test
    fun countsAndPerGameLinesAddUp() {
        val sums = listOf(
            "PPG" to MetricCategory.SCORING, "3PM" to MetricCategory.SCORING, "APG" to MetricCategory.PLAYMAKING,
            "AST" to MetricCategory.PLAYMAKING, "RPG" to MetricCategory.REBOUNDING, "BLK" to MetricCategory.DEFENSE,
            "+/-" to MetricCategory.IMPACT, "GS" to MetricCategory.IMPACT,
        )
        for ((label, category) in sums) assertEquals(label, MetricAggregation.Sum, aggregation(label, category))
    }

    @Test
    fun minutesPerGameWeightsByGames() {
        assertEquals(MetricAggregation.Weighted(MetricWeight.GAMES), aggregation("MPG", MetricCategory.IMPACT))
    }

    @Test
    fun everyRegistryMetricHasAnAggregationRule() {
        for (definition in BasketballMetricRegistry.definitions) {
            assertNotNull(definition.label, aggregation(definition.label, definition.category))
        }
    }

    @Test
    fun minuteWeightReadsTotalMinutesWithItsGrouping() {
        assertEquals(2262.0, MetricWeight.MINUTES.value(player(listOf(std("MIN", "2,262"))))!!, 0.0)
    }

    @Test
    fun gameWeightReadsPlainColumn() {
        assertEquals(68.0, MetricWeight.GAMES.value(player(listOf(std("G", "68"))))!!, 0.0)
    }

    /** A player with no volume drops out of the weighted mean rather than entering it at weight 1. */
    @Test
    fun missingWeightIsNullNotZero() {
        val p = player(listOf(std("PPG", "17.0")))
        assertNull(MetricWeight.MINUTES.value(p))
        assertNull(MetricWeight.GAMES.value(p))
    }

    @Test
    fun zeroVolumeIsTreatedAsMissing() {
        assertNull(MetricWeight.MINUTES.value(player(listOf(std("MIN", "0")))))
    }

    @Test
    fun percentFormatIsPreserved() {
        val format = MetricValueFormat.inferred(listOf("6.2%", "4.8%"))
        assertTrue(format.isPercent)
        assertEquals(1, format.decimals)
        assertEquals("5.5%", format.string(5.5))
    }

    @Test
    fun signedFormatKeepsLeadingPlus() {
        val format = MetricValueFormat.inferred(listOf("+2.3", "-1.1"))
        assertTrue(format.isSigned)
        assertEquals("+1.4", format.string(1.4))
        assertEquals("-1.4", format.string(-1.4))
    }

    @Test
    fun groupedIntegerFormat() {
        val format = MetricValueFormat.inferred(listOf("1,502", "1,004"))
        assertTrue(format.hasGrouping)
        assertEquals(0, format.decimals)
        assertEquals("2,918", format.string(2918.0))
    }

    /** Mixed precision in one column renders at the finer of the two, not silently truncated. */
    @Test
    fun decimalsTakeTheMaximumSeen() {
        val format = MetricValueFormat.inferred(listOf("0.1", "0.12"))
        assertEquals(2, format.decimals)
        assertEquals("0.15", format.string(0.155))
    }

    @Test
    fun twoDecimalRateFormat() {
        val format = MetricValueFormat.inferred(listOf("0.25", "0.18"))
        assertFalse(format.isPercent)
        assertEquals("0.20", format.string(0.2))
    }

    @Test
    fun numericParsingHandlesFeedShapes() {
        assertEquals(1502.0, metricNumericValue("1,502")!!, 0.0)
        assertEquals(6.2, metricNumericValue("6.2%")!!, 0.0)
        assertEquals(2.3, metricNumericValue("+2.3")!!, 0.0)
        assertEquals(-1.4, metricNumericValue("-1.4")!!, 0.0)
        assertEquals(0.5, metricNumericValue(".5")!!, 0.0)
        assertNull(metricNumericValue("-"))
    }
}
