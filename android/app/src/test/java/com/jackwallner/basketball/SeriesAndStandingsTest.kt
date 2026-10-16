package com.jackwallner.basketball

import com.jackwallner.basketball.model.EASTERN
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.SeriesStatus
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamAggregation
import com.jackwallner.basketball.model.parseDay
import com.jackwallner.basketball.ui.screens.metricBeats
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SeriesAndStandingsTest {
    private fun game(
        id: String, day: Int, away: String, home: String, awayScore: Int?, homeScore: Int?,
        phase: SeasonPhase = SeasonPhase.PLAYOFFS, type: String = "FIN",
    ) = Game(
        id = id, season = 2026, seasonPhase = phase, gameType = type, week = 30,
        tipoff = Instant.ofEpochSecond(1_780_000_000L + day * 86_400L),
        awayTeam = away, homeTeam = home, awayScore = awayScore, homeScore = homeScore,
    )

    @Test
    fun seriesCountsGamesAndWinsThroughTheGame() {
        val finals = listOf(
            game("1", 0, "NYK", "SAS", 100, 110),
            game("2", 2, "NYK", "SAS", 105, 99),
            game("3", 4, "SAS", "NYK", 90, 101),
            game("4", 6, "SAS", "NYK", 95, 98),
            game("5", 8, "NYK", "SAS", 94, 90),
            // Another round between other teams must not count.
            game("9", 1, "OKC", "SAS", 99, 100, type = "CF"),
        )
        val opener = SeriesStatus.of(finals[0], finals)!!
        assertEquals("NBA Finals · Game 1", opener.gameLabel)
        assertEquals("SAS leads 1-0", opener.standingLabel)
        assertEquals("Series tied 1-1", SeriesStatus.of(finals[1], finals)!!.standingLabel)
        val clincher = SeriesStatus.of(finals[4], finals)!!
        assertEquals(5, clincher.gameNumber)
        assertEquals("NYK wins 4-1", clincher.standingLabel)
        assertEquals("NBA Finals · Game 5 · NYK wins 4-1", finals[4].contextLine(clincher))
    }

    @Test
    fun upcomingFirstGameHasNoStanding() {
        val opener = game("1", 0, "BOS", "DET", null, null, type = "R1")
        val series = SeriesStatus.of(opener, listOf(opener))!!
        assertEquals("East 1st Round", series.round)
        assertNull(series.standingLabel)
    }

    @Test
    fun regularSeasonGameHasNoSeries() {
        val regular = game("1", 0, "BOS", "DET", 1, 2, SeasonPhase.REGULAR, "REG")
        assertNull(SeriesStatus.of(regular, listOf(regular)))
        assertNull(regular.contextLine(null))
    }

    @Test
    fun cupFinalAndPostponedGamesStayOutOfTheStandings() {
        val games = listOf(
            game("1", 0, "NYK", "SAS", 124, 113, SeasonPhase.REGULAR, "CUP"),
            game("2", 1, "NYK", "SAS", 100, 90, SeasonPhase.REGULAR, "REG"),
            game("3", 2, "NYK", "SAS", null, null, SeasonPhase.REGULAR, "PPD"),
        )
        val table = StandingsRow.build(games, listOf("NYK", "SAS"))
        assertEquals("1-0", table["NYK"]?.record)
        assertEquals("0-1", table["SAS"]?.record)
        assertEquals("NBA Cup Final", games[0].contextLine(null))
    }

    @Test
    fun gamesBackAndMargin() {
        val leader = StandingsRow("OKC", 64, 18, 9760, 8846)
        val chaser = StandingsRow("SAS", 62, 20, 9939, 9269)
        assertEquals(2.0, chaser.gamesBack(leader), 0.0)
        assertEquals("3.5", StandingsRow.formatGamesBack(3.5))
        assertEquals("12", StandingsRow.formatGamesBack(12.0))
        assertEquals("+11.1", leader.marginLabel)
        assertNull(StandingsRow("BOS").marginLabel)
    }

    @Test
    fun shotProfileStatsAreNotGraded() {
        val style = metric("Long Mid Freq", "5.6%", 99, MetricCategory.SHOOTING, id = "a")
        val skill = metric("TS%", "67.0%", 60, MetricCategory.SCORING, id = "b")
        assertTrue(style.isShotProfile)
        assertFalse(skill.isShotProfile)
        assertFalse(metricBeats(style, skill))
    }

    @Test
    fun comparisonWinnerUsesValuesAcrossPositionPools() {
        // A center's 99th-percentile AST% is not better than a guard's 40%.
        val center = metric("AST%", "20.0%", 99, MetricCategory.PLAYMAKING, id = "c")
        val guard = metric("AST%", "40.0%", 95, MetricCategory.PLAYMAKING, id = "g")
        assertTrue(metricBeats(guard, center))
        assertFalse(metricBeats(center, guard))
        // Lower is better for TOV%.
        val careful = metric("TOV%", "8.0%", 90, MetricCategory.PLAYMAKING, id = "t1")
        val loose = metric("TOV%", "15.0%", 20, MetricCategory.PLAYMAKING, id = "t2")
        assertTrue(metricBeats(careful, loose))
    }

    @Test
    fun easternDayParsingIgnoresThePhonesCalendar() {
        val date = parseDay("2026-10-20")
        assertNotNull(date)
        assertEquals(2026, date!!.atZone(EASTERN).year)
        assertEquals(20, date.atZone(EASTERN).dayOfMonth)
    }

    @Test
    fun teamFiguresScaleFloorSharesAndDropUsage() {
        assertEquals(5.0, TeamAggregation.teamScale("Pts/100")!!, 0.0)
        assertEquals(5.0, TeamAggregation.teamScale("REB%")!!, 0.0)
        assertEquals(1.0, TeamAggregation.teamScale("TS%")!!, 0.0)
        assertEquals(1.0, TeamAggregation.teamScale("On-Court +/-")!!, 0.0)
        assertNull(TeamAggregation.teamScale("USG%"))
        assertNull(TeamAggregation.teamScale("On-Off"))
    }
}
