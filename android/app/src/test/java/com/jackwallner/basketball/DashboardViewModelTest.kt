package com.jackwallner.basketball

import com.jackwallner.basketball.data.DashboardViewModel.QualifierLevel
import com.jackwallner.basketball.data.InMemoryStore
import com.jackwallner.basketball.data.OfflineStatcastApi
import com.jackwallner.basketball.data.PlayerSnapshotValidator
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.LeagueConference
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.leagueTeamAbbreviations
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.TeamColor
import java.io.IOException
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DashboardViewModelTest {
    private val live = TEST_LIVE_SEASON

    private fun historicalPlayers() = (StatScoutSeason.EARLIEST until live).flatMap { completeSeasonPlayers(it, "Historical") }

    /** The career rollup leads the menu, then real seasons newest-first. */
    private val expectedSeasons: List<Int>
        get() = listOf(StatScoutSeason.ALL_TIME) + (StatScoutSeason.EARLIEST..live).toList().reversed()

    private fun boardPlayer(id: Int, type: String, metrics: List<Metric>) = testPlayer(
        id, "P$id", "BOS", type.uppercase(), live, type = type, metrics = metrics.mapIndexed { i, m -> m.copy(id = "m$id-$i") },
    )

    @Test
    fun allMetricsKeyCollision() = runTest {
        val players = listOf(
            testPlayer(1, "A", "BOS", "G", live, type = "g", metrics = listOf(metric("AST", "448", 90, MetricCategory.PLAYMAKING, id = "m1"))),
            testPlayer(
                2, "B", "DEN", "C", live, type = "c",
                metrics = listOf(
                    metric("AST", "420", 85, MetricCategory.PLAYMAKING, id = "m2"),
                    metric("AST", "9", 85, MetricCategory.DEFENSE, id = "m3"),
                ),
            ),
        )
        val vm = dashboard(MockProvider(players))
        vm.load()
        assertEquals("Same label in different categories should produce 2 entries", 2, vm.allMetrics.size)
    }

    @Test
    fun loadDistinguishesErrors() = runTest {
        val format = dashboard(MockProvider(error = SerializationException("bad row")))
        format.load()
        assertTrue(format.errorMessage?.contains("format changed") == true)

        val offline = dashboard(MockProvider(error = IOException("offline")))
        offline.load()
        assertTrue(offline.errorMessage?.contains("connection") == true)
    }

    @Test
    fun lastUpdatedReturnsNullWhenEmpty() = runTest {
        assertNull(dashboard(MockProvider()).lastUpdated)
    }

    @Test
    fun teamNamesAndCodes() {
        assertEquals("Boston Celtics", teamFullName("BOS"))
        assertEquals("Golden State Warriors", teamFullName("GSW"))
        assertEquals("Philadelphia 76ers", teamFullName("PHI"))
        assertEquals("Seattle SuperSonics", teamFullName("SEA"))
        assertEquals("Unknown", teamFullName("Unknown"))
        assertEquals(30, leagueTeamAbbreviations.size)
        assertEquals(30, leagueTeamAbbreviations.toSet().size)
        assertTrue(leagueTeamAbbreviations.all { teamFullName(it) != it })
        // ESPN's short forms and old spellings land on the app's codes.
        val aliases = listOf(
            "GS" to "GSW", "NY" to "NYK", "SA" to "SAS", "UTAH" to "UTA", "WSH" to "WAS",
            "NO" to "NOP", "BRK" to "BKN", "PHO" to "PHX", "Boston Celtics" to "BOS",
        )
        for ((raw, code) in aliases) assertEquals(raw, code, normalizedTeamAbbreviation(raw))
        // Every team has a color of its own.
        assertTrue(leagueTeamAbbreviations.all { TeamColor.color(it) != HardwoodPalette.inkTertiary })
    }

    @Test
    fun playersForTeamMatchesAliases() = runTest {
        val players = listOf(
            testPlayer(1, "A", "Boston Celtics", "G", live),
            testPlayer(2, "B", "BRK", "F", live),
        )
        val vm = dashboard(MockProvider(players))
        vm.load()

        assertEquals(listOf(1), vm.players("BOS").map { it.playerId })
        assertEquals(listOf(2), vm.players("BKN").map { it.playerId })
    }

    @Test
    fun conferenceFilterScopesPlayersTeamsAndMetrics() = runTest {
        val players = listOf(
            testPlayer(1, "East Player", "BOS", "G", live, type = "g", metrics = listOf(metric("PPG", "28.1", 90, MetricCategory.SCORING, id = "east"))),
            testPlayer(2, "West Player", "DEN", "C", live, type = "c", metrics = listOf(metric("RPG", "12.1", 80, MetricCategory.REBOUNDING, id = "west"))),
        )
        val vm = dashboard(MockProvider(players))
        vm.load()

        vm.selectedConference = LeagueConference.EAST
        vm.searchText = "Boston"
        assertEquals(listOf("East Player"), vm.filteredPlayers.map { it.name })
        assertEquals(listOf("BOS"), vm.searchedTeams)
        assertEquals(listOf("PPG"), vm.allMetrics.map { it.label })

        vm.selectedConference = LeagueConference.WEST
        vm.searchText = "Denver"
        assertEquals(listOf("West Player"), vm.filteredPlayers.map { it.name })
        assertEquals(listOf("DEN"), vm.searchedTeams)
        assertEquals(listOf("RPG"), vm.allMetrics.map { it.label })
    }

    @Test
    fun everyTeamIsInExactlyOneConference() {
        for (team in leagueTeamAbbreviations) {
            assertNotEquals(team, LeagueConference.EAST.contains(team), LeagueConference.WEST.contains(team))
        }
        assertEquals(15, leagueTeamAbbreviations.count { LeagueConference.EAST.contains(it) })
    }

    @Test
    fun teamCountsPopulatedAfterLoad() = runTest {
        val players = listOf(
            testPlayer(1, "A", "BOS", "G", live),
            testPlayer(2, "B", "BOS", "F", live),
            testPlayer(3, "C", "DEN", "C", live),
        )
        val vm = dashboard(MockProvider(players))
        vm.load()
        assertEquals(2, vm.teamCounts["BOS"])
        assertEquals(1, vm.teamCounts["DEN"])
    }

    @Test
    fun partialRefreshPreservesCompleteCache() = runTest {
        val cached = completeCurrentPlayers()
        val cache = InMemoryPlayerCache(cached)
        val vm = dashboard(MockProvider(cached.take(5)), cache)

        vm.load()

        assertEquals(cached.size, vm.seasonPlayers.size)
        assertEquals(30, vm.teamsWithData.size)
        assertTrue(vm.lastFetchFailed)
        assertEquals(cached.size, cache.savedPlayers.size)
    }

    @Test
    fun completeRefreshReplacesCurrentCache() = runTest {
        val refreshed = completeCurrentPlayers("Fresh")
        val cache = InMemoryPlayerCache(completeCurrentPlayers())
        val vm = dashboard(MockProvider(refreshed), cache)

        vm.load()

        assertEquals(refreshed.size, vm.seasonPlayers.size)
        assertTrue(vm.seasonPlayers.all { it.name.startsWith("Fresh") })
        assertEquals(refreshed.size, cache.savedPlayers.size)
    }

    @Test
    fun cacheHydratesPlayersBeforeFetch() = runTest {
        val cached = listOf(testPlayer(99, "Cached", "BOS", "G", season = null))
        val vm = dashboard(MockProvider(error = IOException("offline")), InMemoryPlayerCache(cached))
        vm.load()
        assertEquals("Cached players should be shown even when refresh fails", listOf("99-0-REG"), vm.players.map { it.id })
    }

    /** Every cohort has the same menu of metrics; what differs is which one its board opens on. */
    @Test
    fun eachPositionBoardOpensOnItsOwnDefaultMetric() = runTest {
        val everything = listOf(
            metric("Pts/100", "30.1", 80, MetricCategory.SCORING), metric("TS%", "58.0%", 70, MetricCategory.SCORING),
            metric("PPG", "20.0", 75, MetricCategory.SCORING), metric("AST%", "25.0%", 85, MetricCategory.PLAYMAKING),
            metric("APG", "6.1", 80, MetricCategory.PLAYMAKING), metric("REB%", "14.0%", 60, MetricCategory.REBOUNDING),
            metric("RPG", "9.0", 62, MetricCategory.REBOUNDING),
        )
        val vm = dashboard(MockProvider(listOf(boardPlayer(1, "g", everything), boardPlayer(2, "f", everything), boardPlayer(3, "c", everything))))
        vm.load()

        assertEquals(PlayerPositionGroup.ALL, vm.selectedPosition)
        assertEquals("Pts/100", vm.sortLabel)
        vm.selectedPosition = PlayerPositionGroup.GUARD
        assertEquals("AST%", vm.sortLabel)
        vm.selectedPosition = PlayerPositionGroup.FORWARD
        assertEquals("Pts/100", vm.sortLabel)
        vm.selectedPosition = PlayerPositionGroup.CENTER
        assertEquals("REB%", vm.sortLabel)
    }

    @Test
    fun boardFallsBackToTheFirstAvailableMetricAndThenToTheDefaultLabel() = runTest {
        val onlyRebounds = boardPlayer(1, "c", listOf(metric("OREB", "120", 70, MetricCategory.REBOUNDING)))
        val vm = dashboard(MockProvider(listOf(onlyRebounds)))
        vm.load()
        vm.selectedPosition = PlayerPositionGroup.CENTER
        assertEquals("OREB", vm.sortLabel)
        assertEquals(1, vm.filteredPlayers.size)
        // A cohort with nobody in it has no metric to sort by.
        vm.selectedPosition = PlayerPositionGroup.GUARD
        assertEquals("Top Metric", vm.sortLabel)
        assertTrue(vm.leaderboard.isEmpty())
    }

    @Test
    fun allBoardMixesCohortsAndRanksByTheNumber() = runTest {
        val guard = boardPlayer(1, "g", listOf(metric("REB%", "9.0%", 95, MetricCategory.REBOUNDING)))
        val center = boardPlayer(2, "c", listOf(metric("REB%", "17.0%", 40, MetricCategory.REBOUNDING)))
        val vm = dashboard(MockProvider(listOf(guard, center)))
        vm.load()

        assertEquals(listOf(2, 1), vm.leaderboard.map { it.playerId })
        vm.selectedPosition = PlayerPositionGroup.GUARD
        assertEquals(listOf(1), vm.leaderboard.map { it.playerId })
    }

    @Test
    fun historicalArchiveRequiresEverySupportedSeason() {
        val complete = historicalPlayers()
        assertTrue(PlayerSnapshotValidator.isCompleteHistorical(complete, live - 1))

        val missingFirst = complete.filter { it.season != StatScoutSeason.EARLIEST }
        assertFalse(PlayerSnapshotValidator.isCompleteHistorical(missingFirst, live - 1))
    }

    @Test
    fun availableSeasonsRunFromTheEarliestThroughLivePlusAllTime() = runTest {
        val vm = dashboard(MockProvider(historicalPlayers() + completeCurrentPlayers()))
        vm.applyProState(true)

        vm.load()

        assertEquals(expectedSeasons, vm.availableSeasons)
        assertEquals(StatScoutSeason.ALL_TIME, vm.availableSeasons.first())
        assertEquals(2003, StatScoutSeason.EARLIEST)
    }

    @Test
    fun availableSeasonsIncludesLockedHistoryBeforeHistoryLoads() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertEquals(expectedSeasons, vm.availableSeasons)
        assertTrue(vm.isSeasonLocked(live - 1))
    }

    /** All Time is Pro, like every season other than the live one. */
    @Test
    fun allTimeIsLockedForFreeUsers() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.applyProState(false)
        assertTrue(vm.isSeasonLocked(StatScoutSeason.ALL_TIME))
        vm.applyProState(true)
        assertFalse(vm.isSeasonLocked(StatScoutSeason.ALL_TIME))
    }

    /** Opening night: two teams have played. The live season is still the default, for Pro too. */
    @Test
    fun aThinLiveSeasonIsStillTheDefault() = runTest {
        val lastSeason = completeSeasonPlayers(live - 1, "LastYear")
        val opener = completeCurrentPlayers("Opener").filter { it.team in listOf("BOS", "NYK") }
        val vm = dashboard(MockProvider(lastSeason + opener))
        vm.applyProState(true)

        vm.load()

        assertEquals(live, vm.selectedSeason)
        assertFalse(vm.isSeasonLocked(live))
        assertTrue(vm.players.any { it.season == live })
    }

    /** All Players (the default) keeps small samples dimmed below qualified ones; Qualified hides them. */
    @Test
    fun qualifiedFilterHonoursTheLiveSeasonFlag() = runTest {
        val store = InMemoryStore()
        val starter = testPlayer(
            1, "Starter", "BOS", "G", live, type = "g",
            metrics = listOf(metric("TS%", "58.0%", 60, MetricCategory.SCORING, qualified = true, id = "s")),
        )
        val reserve = testPlayer(
            2, "Reserve", "DEN", "G", live, type = "g",
            metrics = listOf(metric("TS%", "79.0%", 99, MetricCategory.SCORING, qualified = false, id = "b")),
        )
        val vm = dashboard(MockProvider(listOf(starter, reserve)), store = store)
        vm.load()

        assertEquals(QualifierLevel.ALL, vm.qualifierLevel)
        // The reserve's 99th percentile outranks the starter, but a small sample never tops a board.
        assertEquals(listOf("Starter", "Reserve"), vm.leaderboard.map { it.name })
        vm.qualifierLevel = QualifierLevel.QUALIFIED
        assertEquals(listOf("Starter"), vm.leaderboard.map { it.name })
        assertEquals("the choice persists", QualifierLevel.QUALIFIED, dashboard(MockProvider(), store = store).qualifierLevel)
    }

    @Test
    fun metricDecodesWithAndWithoutTheQualifiedFlag() {
        val json = """
            [{"id":"a","label":"TS%","value":"58.0%","percentile":50,"category":"Scoring","qualified":false},
             {"id":"b","label":"TS%","value":"60.0%","percentile":60,"category":"Scoring"}]
        """.trimIndent()
        val metrics = (Json.parseToJsonElement(json) as JsonArray).map { Metric.fromJson(it as JsonObject) }
        assertEquals(listOf(false, null), metrics.map { it.qualified })
    }

    /** Recent form covers the live season and the one before it, as far back as the rollup has ever held rows. */
    @Test
    fun recentFormCoversTheLiveSeasonAndTheOneBeforeWhereItExists() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertEquals(live, vm.recentFormSeason)
        assertEquals("Newest first", vm.freeSeason, vm.recentFormSeasons.first())
        assertTrue(vm.recentFormSeasons.size <= 2)
        assertEquals(vm.recentFormSeasons.sortedDescending(), vm.recentFormSeasons)
        vm.recentFormSeasons.forEach { assertTrue(vm.supportsRecentForm(it)) }
        assertFalse(vm.supportsRecentForm(StatScoutSeason.ALL_TIME))
    }

    /** While 2025-26 is the live season, 2024-25 has no rolling rows, so Trends must not offer it. */
    @Test
    fun trendsDoesNotOfferASeasonWithNoRecentFormRows() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.load()

        assertEquals(listOf(2026), vm.recentFormSeasons)
        assertFalse(vm.supportsRecentForm(2025))
        vm.recentFormSeasons.forEach { assertTrue(it >= StatScoutSeason.EARLIEST_RECENT_FORM) }
    }

    /**
     * The floor is a fact about the database: `player_game_logs` and
     * `player_recent_form` hold 2026 and nothing else. Moving it down without
     * re-ingesting puts an empty year in the Trends menu.
     */
    @Test
    fun recentFormFloorMatchesTheSeasonsTheRollupHolds() {
        assertEquals(2026, StatScoutSeason.EARLIEST_RECENT_FORM)
        assertTrue(StatScoutSeason.EARLIEST_RECENT_FORM <= live)
    }

    /** Tip-off, end to end: once the new season's rows land and the status names it, it is the free season. */
    @Test
    fun theAppMovesToTheNewSeasonTheDayItsDataLands() = runTest {
        val rows = completeSeasonPlayers(2026, "LastYear") + completeSeasonPlayers(2027, "NewYear")
        val published = DataFreshness(
            status = DataFreshnessStatus.READY, revision = "r27", rawStatus = "published", season = 2027, publishedSeason = 2027,
        )
        val vm = dashboard(MockProvider(rows, freshness = published))
        vm.load()

        assertEquals(2027, vm.freeSeason)
        assertEquals("the board follows the rollover by itself", 2027, vm.selectedSeason)
        assertFalse(vm.isSeasonLocked(2027))
        assertTrue("last season becomes Pro, not gone", vm.isSeasonLocked(2026))
        assertTrue(vm.availableSeasons.contains(2026))
        assertEquals(listOf(2027, 2026), vm.recentFormSeasons)
        assertFalse(vm.isSeasonPending)
    }

    /** Between the October rollover and opening night the live season is still 2025-26, with 2026-27 only a schedule. */
    @Test
    fun aPendingSeasonKeepsThePublishedSeasonLive() = runTest {
        val rows = completeSeasonPlayers(2026, "Final")
        val pending = DataFreshness(
            status = DataFreshnessStatus.PENDING, revision = "r26", rawStatus = "source_pending",
            season = 2027, publishedSeason = 2026, lastErrorCode = "season_pending",
        )
        val vm = dashboard(MockProvider(rows, freshness = pending))
        vm.load()

        assertEquals(2026, vm.freeSeason)
        assertEquals(2026, vm.selectedSeason)
        assertEquals(2027, vm.upcomingSeason)
        assertTrue(vm.isSeasonPending)
        assertEquals("2025-26 · final", vm.liveSeasonCaption())
        assertFalse(vm.isSeasonLocked(2026))
        assertTrue(vm.isSeasonLocked(2025))
        // Trends offers only what has rows: 2026 now, not an empty 2027.
        assertEquals(listOf(2026), vm.recentFormSeasons)
        // A pending season is not a problem with the data on screen.
        assertEquals(DataFreshnessStatus.READY, vm.freshnessStatus)
        assertEquals(rows.size, vm.players.count { it.season == 2026 })
    }

    /** The resolved live season is remembered, so the next cold start opens on it before the first status check lands. */
    @Test
    fun resolvedLiveSeasonSurvivesARelaunch() = runTest {
        val store = InMemoryStore()
        val pending = DataFreshness(
            status = DataFreshnessStatus.PENDING, rawStatus = "source_pending",
            season = 2027, publishedSeason = 2026, lastErrorCode = "season_pending",
        )
        dashboard(MockProvider(completeSeasonPlayers(2026, "A"), freshness = pending), store = store).load()

        val second = dashboard(OfflineStatcastApi, store = store)
        assertEquals(2026, second.freeSeason)
        assertEquals(2027, second.upcomingSeason)
        assertEquals(2026, second.selectedSeason)
    }

    /** With nothing remembered and no connection, the app opens on the newest season it can draw. */
    @Test
    fun aColdOfflineStartOpensOnTheNewestBundledSeason() {
        val live = StatScoutSeason.initialLive(InMemoryStore(), calendarSeason = 2027)
        assertEquals(StatScoutSeason.BUNDLED_NEWEST, live.season)
        assertNull(live.upcoming)
    }

    /** History is loaded on demand, so the first tap on a past season has to start that load. */
    @Test
    fun selectingAPastSeasonLoadsTheHistoryItNeeds() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.applyProState(true)
        vm.load()
        assertFalse("History should still be unfetched after a plain load", vm.hasLoadedHistorical)

        vm.selectSeason(StatScoutSeason.ALL_TIME)

        // The header moves on the tap; the rows arrive behind it.
        assertEquals(StatScoutSeason.ALL_TIME, vm.selectedSeason)
        assertNotNull("Choosing a past season should start the history load", vm.seasonLoadJob)
        vm.seasonLoadJob?.join()
    }

    /** The live season needs no extra fetch, so it must not start one. */
    @Test
    fun selectingTheFreeSeasonDoesNotRefetchHistory() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))
        vm.load()

        vm.selectSeason(vm.freeSeason)

        assertNull(vm.seasonLoadJob)
    }

    /** Trends ranks rolling week windows, so a career has nothing to rank. */
    @Test
    fun trendsSeasonListExcludesAllTime() = runTest {
        val vm = dashboard(MockProvider(completeCurrentPlayers()))

        vm.load()

        assertFalse(vm.seasonsExcludingAllTime.contains(StatScoutSeason.ALL_TIME))
        assertEquals(vm.availableSeasons.size - 1, vm.seasonsExcludingAllTime.size)
    }

    /** The sentinel never reaches the UI as "0", and a hoopR integer never reaches it bare: it names the year a season ends. */
    @Test
    fun seasonLabelRendersTheNbaConvention() {
        assertEquals("All Time", SeasonLabel.display(StatScoutSeason.ALL_TIME))
        assertEquals("2025-26", SeasonLabel.display(2026))
        assertEquals("2026-27", SeasonLabel.display(2027))
        assertEquals("2009-10", SeasonLabel.display(2010))
        assertEquals("1999-00", SeasonLabel.display(2000))
        assertEquals("2002-03", SeasonLabel.display(2003))
        assertEquals("All Time · Regular Season", SeasonLabel.display(StatScoutSeason.ALL_TIME, SeasonPhase.REGULAR))
        assertEquals("2025-26 Playoffs", SeasonLabel.display(2026, SeasonPhase.PLAYOFFS))
    }

    @Test
    fun seasonPhaseAlwaysReadsAsAFullName() {
        assertEquals("Regular Season", SeasonPhase.REGULAR.label)
        assertEquals("Playoffs", SeasonPhase.PLAYOFFS.label)
    }

    @Test
    fun seasonPlayersReturnsPlayersForSelectedSeason() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Player 2026", "NYK", "G", 2026), testPlayer(2, "Player 2025", "BOS", "F", 2025))))
        vm.load()

        vm.selectedSeason = 2026
        assertEquals(listOf(1), vm.seasonPlayers.map { it.playerId })

        vm.selectedSeason = 2025
        assertEquals(listOf(2), vm.seasonPlayers.map { it.playerId })
    }

    @Test
    fun seasonPlayersIsEmptyWhenSeasonHasNoData() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Player 2026", "NYK", "G", 2026))))
        vm.load()

        // A season with no data reports empty (no stale fallback).
        vm.selectedSeason = 2024
        assertTrue(vm.seasonPlayers.isEmpty())
    }

    @Test
    fun loadNeverSnapsAwayFromTheLiveSeason() = runTest {
        val vm = dashboard(MockProvider(listOf(testPlayer(1, "Last Season", "BOS", "G", live - 1))))
        vm.applyProState(true)
        vm.load()
        assertEquals(live, vm.selectedSeason)
    }
}
