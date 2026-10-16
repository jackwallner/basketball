package com.jackwallner.basketball

import com.jackwallner.basketball.model.FanStatsSelection
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StandardStat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FanStatsSelectionTest {
    private fun player(id: Int, season: Int = 2026, phase: SeasonPhase = SeasonPhase.REGULAR, stats: List<StandardStat> = emptyList()) =
        testPlayer(id = id, name = "Player $id", team = "SEA", position = "G", season = season, phase = phase, type = "g", standard = stats)

    @Test
    fun followingDoesNotSubstitutePriorSeasonOrPostseasonStats() {
        val players = listOf(player(1, season = 2025), player(2), player(1, phase = SeasonPhase.PLAYOFFS))
        val selected = FanStatsSelection.players(listOf(1, 2), players, 2026, SeasonPhase.REGULAR)
        assertEquals(listOf(2), selected.map { it.playerId })
    }

    @Test
    fun followingPreservesPersonalOrderAndDeduplicates() {
        val players = listOf(player(1), player(2), player(2), player(3))
        val selected = FanStatsSelection.players(listOf(3, 2, 3, 99, 1), players, 2026, SeasonPhase.REGULAR)
        assertEquals(listOf(3, 2, 1), selected.map { it.playerId })
    }

    @Test
    fun missingSummaryStatsAreNotShownAsZero() {
        val selected = player(1, stats = listOf(StandardStat("PPG", "28.4", "ppg")))
        assertEquals(listOf("PPG"), FanStatsSelection.summary(selected).map { it.label })
        assertTrue(FanStatsSelection.summary(player(2)).isEmpty())
    }

    @Test
    fun summaryIsScoringReboundingAndPlaymakingInThatOrder() {
        val stats = listOf("APG", "RPG", "PPG", "SPG").map { StandardStat(it, "1.0", it) }
        assertEquals(listOf("PPG", "RPG", "APG"), FanStatsSelection.summary(player(1, stats = stats)).map { it.label })
    }
}
