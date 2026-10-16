package com.jackwallner.basketball

import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricFamily
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.SeasonPhase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerTest {
    private fun player(
        name: String = "Test",
        team: String = "BOS",
        position: String = "G",
        type: String? = null,
        metrics: List<com.jackwallner.basketball.model.Metric> = emptyList(),
    ) = testPlayer(name = name, team = team, position = position, type = type, metrics = metrics)

    @Test
    fun overallPercentileDoubleAverage() {
        val metrics = listOf(
            metric("A", "1", 75, id = "m1"),
            metric("B", "2", 76, id = "m2"),
            metric("C", "3", 77, id = "m3"),
        )
        assertEquals(76, player(metrics = metrics).overallPercentile)
    }

    @Test
    fun shareSummaryIncludesTopSignalAndAppName() {
        val summary = player(
            name = "Shai Gilgeous-Alexander", team = "OKC",
            metrics = listOf(metric("Pts/100", "44.3", 100, id = "m1")),
        ).shareSummary
        assertTrue(summary.contains("Shai Gilgeous-Alexander"))
        assertTrue(summary.contains("Pts/100"))
        assertTrue(summary.contains("100th"))
        assertTrue(summary.endsWith("Hardwood StatScout"))
    }

    @Test
    fun multiCategoryOverallUsesBestCategoryAverage() {
        // A rim protector who scores little: the headline is the best category, not a blend.
        val metrics = listOf(
            metric("BLK%", "6.1%", 95, MetricCategory.DEFENSE, id = "d1"),
            metric("BPG", "2.4", 95, MetricCategory.DEFENSE, id = "d2"),
            metric("PPG", "8.0", 30, MetricCategory.SCORING, id = "s1"),
            metric("USG%", "13.0%", 30, MetricCategory.SCORING, id = "s2"),
        )
        assertEquals(95, player(type = "c", metrics = metrics).overallPercentile)
        assertEquals(MetricCategory.DEFENSE, player(type = "c", metrics = metrics).primaryCategory)
    }

    @Test
    fun playerDecodesSeasonAndPlayerType() {
        val json = """
            {"id": 1, "name": "Test", "team": "BOS", "position": "G", "handedness": "",
             "image_url": null, "updated_at": "2026-06-14T12:00:00Z", "season": 2026,
             "player_type": "g", "source": "hoopR", "metrics": [], "standard_stats": [], "games": []}
        """.trimIndent()
        val decoded = Player.fromJson(Json.parseToJsonElement(json) as JsonObject)
        assertEquals(2026, decoded.season)
        assertEquals("g", decoded.playerType)
        assertEquals("hoopR", decoded.source)
        assertEquals(SeasonPhase.REGULAR, decoded.seasonPhase)
        assertEquals(PlayerPositionGroup.GUARD, decoded.positionGroup)
    }

    @Test
    fun everyPlayerTypeQualifiesForEveryCategory() {
        for (type in listOf("g", "f", "c", "unknown")) {
            for (category in MetricCategory.entries) {
                assertTrue("$type should qualify for $category", player(type = type).matchesPlayerType(category))
            }
        }
    }

    @Test
    fun positionGroupFromPlayerTypeAndPosition() {
        assertEquals(PlayerPositionGroup.GUARD, player(type = "g").positionGroup)
        assertEquals(PlayerPositionGroup.FORWARD, player(type = "f").positionGroup)
        assertEquals(PlayerPositionGroup.CENTER, player(type = "c").positionGroup)
        // An unknown type reads the box score's own position, and folds into forwards when there is none.
        assertEquals(PlayerPositionGroup.CENTER, player(position = "C", type = "unknown").positionGroup)
        assertEquals(PlayerPositionGroup.FORWARD, player(position = "", type = "unknown").positionGroup)
    }

    @Test
    fun initialsHandleSuffixes() {
        assertEquals("LN", player(name = "Larry Nance Jr.").initials)
        assertEquals("GP", player(name = "Gary Payton II").initials)
        assertEquals("JJ", player(name = "Jaime Jaquez Jr.").initials)
    }

    @Test
    fun initialsStandardNames() {
        assertEquals("LD", player(name = "Luka Doncic").initials)
        assertEquals("SG", player(name = "Shai Gilgeous-Alexander").initials)
        assertEquals("N", player(name = "Nene").initials)
    }

    @Test
    fun rawNumericStripsThousandsSeparators() {
        assertEquals(1502.0, DashboardViewModel.rawNumeric("1,502")!!, 0.001)
        assertEquals(61.2, DashboardViewModel.rawNumeric("61.2%")!!, 0.001)
        assertEquals(6.3, DashboardViewModel.rawNumeric("+6.3")!!, 0.001)
    }

    @Test
    fun displayPositionFallsBackToPlayerType() {
        assertEquals("C", player(position = "TBD", type = "c").displayPosition)
        assertEquals("", player(position = "", type = "unknown").displayPosition)
    }

    @Test
    fun volumeCaptionIsMinutes() {
        val p = testPlayer(standard = listOf(std("MIN", "2,262")))
        assertEquals("2,262 min", p.volumeCaption(MetricCategory.SCORING))
    }
}

class BasketballMetricRegistryTest {
    /** The labels the backend writes, in the order the contract lists them. */
    private val contractLabels: Map<MetricCategory, List<String>> = mapOf(
        MetricCategory.SCORING to listOf("Pts/100", "USG%", "TS%", "eFG%", "FT Rate", "3PT Rate", "PPG", "FG%", "3P%", "FT%", "3PM"),
        MetricCategory.SHOOTING to listOf("Rim Freq", "Rim FG%", "Short Mid Freq", "Short Mid FG%", "Long Mid Freq", "Long Mid FG%", "Corner 3%", "Non-Corner 3%", "Assisted FG%"),
        MetricCategory.PLAYMAKING to listOf("AST%", "AST/100", "TOV%", "AST:TO", "AST:USG", "APG", "AST", "TOV/G"),
        MetricCategory.REBOUNDING to listOf("OREB%", "DREB%", "REB%", "RPG", "OREB", "DREB"),
        MetricCategory.DEFENSE to listOf("STL%", "BLK%", "Stocks/100", "Fouls/100", "SPG", "BPG", "STL", "BLK"),
        MetricCategory.IMPACT to listOf("On-Court +/-", "On-Off", "Min%", "MPG", "GS", "+/-"),
    )

    @Test
    fun registryMatchesTheContractLabelForLabel() {
        for ((category, labels) in contractLabels) {
            val registry = BasketballMetricRegistry.definitions.filter { it.category == category }.map { it.label }
            assertEquals("$category labels drifted from the contract", labels.toSet(), registry.toSet())
            assertEquals("$category has a duplicate label", labels.size, registry.size)
        }
        assertEquals(48, BasketballMetricRegistry.definitions.size)
    }

    @Test
    fun advancedAndTraditionalClassification() {
        assertEquals(MetricKind.ADVANCED, BasketballMetricRegistry.kind(metric("TS%", "61.0%", 90, id = "ts")))
        assertEquals(MetricKind.TRADITIONAL, BasketballMetricRegistry.kind(metric("PPG", "27.1", 85, id = "ppg")))
        // Shooting is advanced throughout.
        assertTrue(
            BasketballMetricRegistry.definitions.filter { it.category == MetricCategory.SHOOTING }.all { it.kind == MetricKind.ADVANCED },
        )
    }

    @Test
    fun everyCategoryHasBothAdvancedAndTraditionalExceptShooting() {
        for (category in MetricCategory.entries.filter { it != MetricCategory.SHOOTING }) {
            val definitions = BasketballMetricRegistry.definitions.filter { it.category == category }
            assertTrue("$category has no advanced metric", definitions.any { it.kind == MetricKind.ADVANCED })
            assertTrue("$category has no traditional metric", definitions.any { it.kind == MetricKind.TRADITIONAL })
        }
    }

    @Test
    fun lowerIsBetterMetricsAreExactlyTheContractOnes() {
        val lower = BasketballMetricRegistry.definitions.filter { !it.higherIsBetter }.map { it.label }.toSet()
        assertEquals(setOf("TOV%", "Fouls/100", "TOV/G"), lower)
    }

    @Test
    fun everyDefinitionIsOpenToEveryPositionGroupWithADescription() {
        for (definition in BasketballMetricRegistry.definitions) {
            assertEquals(definition.label, PlayerPositionGroup.cohorts.toSet(), definition.positions)
            assertFalse(definition.label, definition.description.isEmpty())
            assertFalse("no em dashes: ${definition.label}", definition.description.contains('—'))
        }
    }

    @Test
    fun advancedMetricsLeadDisplayOrder() {
        for (category in MetricCategory.entries) {
            val order = BasketballMetricRegistry.definitions.filter { it.category == category }.sortedBy { it.priority }
            val firstTraditional = order.indexOfFirst { it.kind == MetricKind.TRADITIONAL }
            val lastAdvanced = order.indexOfLast { it.kind == MetricKind.ADVANCED }
            if (firstTraditional >= 0 && lastAdvanced >= 0) assertTrue("$category", lastAdvanced < firstTraditional)
        }
    }

    @Test
    fun positionBoardDefaults() {
        assertEquals(listOf("On-Off", "On-Court +/-", "AST%", "TS%", "USG%"), PlayerPositionGroup.GUARD.preferredAdvancedMetrics)
        assertEquals(listOf("On-Off", "On-Court +/-", "Pts/100", "TS%", "USG%"), PlayerPositionGroup.FORWARD.preferredAdvancedMetrics)
        assertEquals(listOf("On-Off", "On-Court +/-", "REB%", "Rim FG%", "BLK%"), PlayerPositionGroup.CENTER.preferredAdvancedMetrics)
        assertEquals(listOf("APG", "PPG", "SPG"), PlayerPositionGroup.GUARD.preferredTraditionalMetrics)
        assertEquals(listOf("PPG", "RPG", "3PM"), PlayerPositionGroup.FORWARD.preferredTraditionalMetrics)
        assertEquals(listOf("RPG", "BPG", "FG%"), PlayerPositionGroup.CENTER.preferredTraditionalMetrics)
        // Every board opens on the all-in-one impact number.
        assertEquals("On-Off", PlayerPositionGroup.ALL.preferredAdvancedMetrics.first())
        assertEquals("PPG", PlayerPositionGroup.ALL.preferredTraditionalMetrics.first())
        assertEquals(listOf("All", "G", "F", "C"), PlayerPositionGroup.entries.map { it.raw })
    }

    @Test
    fun lowerIsBetterUsesRegistry() {
        assertTrue(DashboardViewModel.lowerIsBetter("TOV%", MetricCategory.PLAYMAKING))
        assertTrue(DashboardViewModel.lowerIsBetter("Fouls/100", MetricCategory.DEFENSE))
        assertFalse(DashboardViewModel.lowerIsBetter("TS%", MetricCategory.SCORING))
    }

    @Test
    fun unknownMetricIsPreserved() {
        val unknown = metric("New Metric", "1.0", 50, id = "unknown")
        assertEquals(MetricKind.ADVANCED, BasketballMetricRegistry.kind(unknown))
        assertTrue(BasketballMetricRegistry.isSupported(unknown, PlayerPositionGroup.GUARD))
        assertEquals(listOf(unknown), BasketballMetricRegistry.sorted(listOf(unknown)))
    }

    @Test
    fun zeroCountIsUnrankedButZeroRateIsNot() {
        assertTrue(metric("BLK", "0", 47, MetricCategory.DEFENSE, id = "blk").isUnranked)
        assertFalse(metric("On-Off", "0.0", 50, MetricCategory.IMPACT, id = "oo").isUnranked)
    }

    @Test
    fun familiesAreBasketballOnes() {
        assertEquals(
            setOf(
                "Efficiency", "Usage", "Shooting", "Frequency", "Accuracy", "Playmaking", "Turnovers",
                "Rebounding", "Rim Protection", "Steals", "Impact", "Playing Time", "Production",
            ),
            MetricFamily.entries.map { it.label }.toSet(),
        )
    }
}
