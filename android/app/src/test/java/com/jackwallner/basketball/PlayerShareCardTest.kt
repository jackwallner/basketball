package com.jackwallner.basketball

import com.jackwallner.basketball.data.StoreLinks
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.ui.screens.PlayerShare
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The words and rows on a shared percentile card. Mirrors iOS `PlayerShareCardTests`. */
class PlayerShareCardTest {
    private val player = testPlayer(
        name = "Stephen Curry",
        team = "GSW",
        metrics = listOf(
            metric("TS%", "64.1%", 95, MetricCategory.SCORING),
            metric("Pts/100", "38.2", 97, MetricCategory.SCORING),
            metric("AST%", "34.2%", 90, MetricCategory.PLAYMAKING),
            // Unranked rows stay off the card, and a category left with none is dropped.
            metric("REB%", "8.0%", 40, MetricCategory.REBOUNDING, rankable = false),
        ),
    )

    @Test
    fun cardDrawsRankedRowsGroupedInReadingOrder() {
        val groups = PlayerShare.groups(player)
        assertEquals(listOf(MetricCategory.SCORING, MetricCategory.PLAYMAKING), groups.map { it.first })
        assertEquals(setOf("TS%", "Pts/100"), groups[0].second.map { it.label }.toSet())
        assertEquals(listOf("AST%"), groups[1].second.map { it.label })
    }

    @Test
    fun aPlayerWithNothingRankedHasNoCard() {
        val unranked = testPlayer(metrics = listOf(metric("REB%", "8.0%", 40, MetricCategory.REBOUNDING, rankable = false)))
        assertTrue(PlayerShare.groups(unranked).isEmpty())
    }

    @Test
    fun cardIsRenderedAtThreeTimesCardWidth() {
        assertEquals(1170f, PlayerShare.CARD_WIDTH_DP * PlayerShare.SCALE)
    }

    @Test
    fun fileNameIsTheSluggedNameAndSeason() {
        assertEquals("Stephen-Curry-2025-26.png", PlayerShare.fileName("Stephen Curry", "2025-26"))
        assertEquals("Nikola-Jokić-2025-26-Playoffs.png", PlayerShare.fileName("Nikola Jokić", "2025-26 Playoffs"))
        assertEquals("Shai-Gilgeous-Alexander-2025-26.png", PlayerShare.fileName("Shai Gilgeous-Alexander", "2025-26"))
    }

    @Test
    fun shareMessageLinksThePlayListing() {
        val message = PlayerShare.message("Stephen Curry", "2025-26")
        assertTrue(message.startsWith("Stephen Curry, 2025-26 percentiles"))
        assertTrue(message.endsWith(StoreLinks.PLAY_LISTING_URL))
    }

    @Test
    fun liveBoardCarriesItsDatePastSeasonsSayWhatTheyAreRankedAgainst() {
        val updated = Instant.parse("2026-11-03T06:00:00Z")
        assertEquals("Through Nov 2", PlayerShare.footnote(true, updated, ZoneId.of("America/Los_Angeles")))
        assertEquals("Through Nov 3", PlayerShare.footnote(true, updated, ZoneId.of("America/New_York")))
        assertEquals("Ranked against NBA qualifiers", PlayerShare.footnote(false, updated))
    }

    @Test
    fun identityLineIsTeamAndPosition() {
        assertEquals("Golden State Warriors · G", PlayerShare.identityLine(player))
    }
}
