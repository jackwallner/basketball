package com.jackwallner.basketball

import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameDay
import com.jackwallner.basketball.model.PlayerProfile
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.parseDay
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Date logic pinned to fixed instants, never the machine's clock. Mirrors iOS `ClockBoundaryTests`. */
class ClockBoundaryTest {
    private fun instant(iso: String): Instant = Instant.parse(iso)

    private fun day(iso: String) = GameDay(LocalDate.parse(iso), SeasonPhase.REGULAR)

    /** The handover is 8 AM on the Eastern clock, not 32 hours after Eastern midnight. */
    @Test
    fun gameDayHandsOverAtEightAmEasternIncludingTheChangeoverDays() {
        assertEquals("EDT: 8 AM is 12:00Z", instant("2026-10-21T12:00:00Z"), day("2026-10-20").handover)
        assertEquals("fall-back morning is EST", instant("2026-11-01T13:00:00Z"), day("2026-10-31").handover)
        assertEquals("EST: 8 AM is 13:00Z", instant("2026-11-02T13:00:00Z"), day("2026-11-01").handover)
        assertEquals("spring-forward morning is EDT", instant("2027-03-14T12:00:00Z"), day("2027-03-13").handover)
        assertEquals(instant("2027-03-15T12:00:00Z"), day("2027-03-14").handover)
    }

    @Test
    fun currentDayFlipsOnTheExactSecondOfTheHandover() {
        val fall = listOf(day("2026-11-01"), day("2026-11-02"))
        val fallHandover = instant("2026-11-02T13:00:00Z")
        assertEquals("2026-11-01", GameDay.current(fall, fallHandover.minusSeconds(1))?.id)
        assertEquals("2026-11-02", GameDay.current(fall, fallHandover)?.id)
        val spring = listOf(day("2027-03-13"), day("2027-03-14"))
        val springHandover = instant("2027-03-14T12:00:00Z")
        assertEquals("2027-03-13", GameDay.current(spring, springHandover.minusSeconds(1))?.id)
        assertEquals("2027-03-14", GameDay.current(spring, springHandover)?.id)
    }

    @Test
    fun currentDayBeforeTheSeasonAfterTheFinalsAndAcrossAGap() {
        val days = listOf(day("2026-10-21"), day("2026-10-23"), day("2027-06-18"))
        assertEquals("2026-10-21", GameDay.current(days, instant("2026-09-01T12:00:00Z"))?.id)
        assertEquals("2026-10-23", GameDay.current(days, instant("2026-10-22T20:00:00Z"))?.id)
        assertEquals("2027-06-18", GameDay.current(days, instant("2027-08-01T12:00:00Z"))?.id)
        assertNull(GameDay.current(emptyList<GameDay>(), instant("2026-10-22T20:00:00Z")))
    }

    /** The season is named for the year it ends in and flips on 1 October. */
    @Test
    fun calendarSeasonFlipsOnOctoberFirstAndHoldsThroughTheSummer() {
        assertEquals(2026, StatScoutSeason.calendarSeason(LocalDate.parse("2026-09-30")))
        assertEquals(2027, StatScoutSeason.calendarSeason(LocalDate.parse("2026-10-01")))
        assertEquals(2027, StatScoutSeason.calendarSeason(LocalDate.parse("2027-01-01")))
        assertEquals(2027, StatScoutSeason.calendarSeason(LocalDate.parse("2027-06-20")))
        assertEquals(2027, StatScoutSeason.calendarSeason(LocalDate.parse("2027-09-30")))
        assertEquals(2028, StatScoutSeason.calendarSeason(LocalDate.parse("2027-10-01")))
    }

    /** Age turns over on the birthday itself, leap-day births on 1 March. */
    @Test
    fun ageTurnsOverOnTheBirthday() {
        val player = PlayerProfile(playerId = 1, season = 2026, birthDate = LocalDate.parse("2000-09-24"))
        assertEquals(25, player.age(LocalDate.parse("2026-09-23")))
        assertEquals(26, player.age(LocalDate.parse("2026-09-24")))
        val leap = PlayerProfile(playerId = 2, season = 2026, birthDate = LocalDate.parse("2000-02-29"))
        assertEquals(26, leap.age(LocalDate.parse("2027-02-28")))
        assertEquals(27, leap.age(LocalDate.parse("2027-03-01")))
    }

    /** The line beside a final season reads "starts" until the first tip-off, which already counts as under way. */
    @Test
    fun upcomingSeasonLineFlipsAtTheFirstTipoff() = runTest {
        val finals = Game(
            id = "f", season = 2026, week = 1, tipoff = instant("2026-06-14T00:30:00Z"),
            gameDate = parseDay("2026-06-13")!!, awayTeam = "NYK", homeTeam = "SAS", awayScore = 94, homeScore = 90,
        )
        val tip = instant("2026-10-20T23:00:00Z")
        val opener = Game(
            id = "o", season = 2027, week = 1, tipoff = tip,
            gameDate = parseDay("2026-10-20")!!, awayTeam = "NYK", homeTeam = "SAS",
        )
        val pending = DataFreshness(
            status = DataFreshnessStatus.PENDING, rawStatus = "source_pending",
            season = 2027, publishedSeason = 2026, lastErrorCode = "season_pending",
        )
        var now = tip.minusSeconds(1)
        val vm = dashboard(ScheduleProvider(listOf(finals, opener), pending), clock = { now })
        vm.checkForUpdates(force = true)
        vm.loadGames(force = true)
        assertEquals("2026-27 starts Oct 20", vm.upcomingSeasonStartsText)
        now = tip
        assertEquals("2026-27 under way · stats arriving", vm.upcomingSeasonStartsText)
    }
}

private class ScheduleProvider(private val games: List<Game>, private val freshness: DataFreshness?) : MockProvider() {
    override suspend fun fetchGames(season: Int): List<Game> = games.filter { it.season == season }
    override suspend fun fetchDataFreshness(): DataFreshness? = freshness
}
