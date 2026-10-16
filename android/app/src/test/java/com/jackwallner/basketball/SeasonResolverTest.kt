package com.jackwallner.basketball

import com.jackwallner.basketball.data.InMemoryStore
import com.jackwallner.basketball.data.PlayerCaching
import com.jackwallner.basketball.data.PlayerSnapshotValidator
import com.jackwallner.basketball.data.TwoTierPlayerCache
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StandardStatSemantics
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.parseDate
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** How the app decides which season is live, and that it rolls over by itself. */
class SeasonResolverTest {
    private fun status(raw: String, season: Int?, published: Int?, code: String? = null) = DataFreshness(
        status = DataFreshnessStatus.from(raw), rawStatus = raw, season = season, publishedSeason = published, lastErrorCode = code,
    )

    @Test
    fun calendarSeasonFollowsTheOctoberRule() {
        fun season(iso: String) = StatScoutSeason.calendarSeason(LocalDate.parse(iso))
        assertEquals(2026, season("2026-09-30"))
        assertEquals(2027, season("2026-10-01"))
        assertEquals(2027, season("2026-10-08"))
        assertEquals(2027, season("2026-12-31"))
        assertEquals(2027, season("2027-01-01"))
        assertEquals(2027, season("2027-06-30"))
        assertEquals(2028, season("2027-10-01"))
    }

    /** The state the backend is in today: the calendar says 2026-27, the data is still 2025-26. */
    @Test
    fun pendingSeasonKeepsThePublishedSeasonLive() {
        val live = StatScoutSeason.resolveLive(status("source_pending", 2027, 2026, "season_pending"), 2026)
        assertEquals(2026, live.season)
        assertEquals(2027, live.upcoming)
        assertTrue(live.isPending)
    }

    /** The moment the publisher flips to a published revision for the new season, the app follows. */
    @Test
    fun rolloverHappensWhenThePublisherCatchesUp() {
        for (raw in listOf("published", "degraded", "complete")) {
            val live = StatScoutSeason.resolveLive(status(raw, 2027, 2027), 2026)
            assertEquals(raw, 2027, live.season)
            assertNull(raw, live.upcoming)
            assertFalse(raw, live.isPending)
        }
    }

    @Test
    fun aMidSeasonStallIsNotAPendingSeason() {
        val live = StatScoutSeason.resolveLive(status("source_pending", 2027, 2027, "source_unavailable"), 2026)
        assertEquals(2027, live.season)
        assertNull(live.upcoming)
    }

    /** A pending flag with no published season on the row cannot be proven to be a season gap. */
    @Test
    fun anOlderRowWithoutPublishedSeasonUsesTheRowsSeason() {
        val live = StatScoutSeason.resolveLive(status("source_pending", 2026, null, "season_pending"), 2025)
        assertEquals(2026, live.season)
        assertNull(live.upcoming)
    }

    @Test
    fun noStatusFallsBackToTheLastKnownSeason() {
        assertEquals(StatScoutSeason.Live(2026, null), StatScoutSeason.resolveLive(null, 2026))
        assertEquals("a status row with no seasons on it changes nothing", 2026, StatScoutSeason.resolveLive(DataFreshness(), 2026).season)
    }

    /** A failed check is a display state, not a season change. */
    @Test
    fun aFailedCheckDoesNotMoveTheSeason() {
        assertEquals(2026, StatScoutSeason.resolveLive(status("failed", 2027, 2026), 2026).season)
    }

    @Test
    fun initialLiveRemembersTheLastResolution() {
        val store = InMemoryStore()
        // Nothing remembered: the calendar's season, capped at the bundle.
        assertEquals(2026, StatScoutSeason.initialLive(store, 2027).season)
        assertEquals(2025, StatScoutSeason.initialLive(store, 2025).season)

        StatScoutSeason.remember(StatScoutSeason.Live(2026, 2027), store)
        assertEquals(StatScoutSeason.Live(2026, 2027), StatScoutSeason.initialLive(store, 2027))

        StatScoutSeason.remember(StatScoutSeason.Live(2027, null), store)
        assertEquals(StatScoutSeason.Live(2027, null), StatScoutSeason.initialLive(store, 2027))
    }

    @Test
    fun seasonsReadAsTheYearTheyEndIn() {
        assertEquals("2026-27", SeasonLabel.display(2027))
        assertEquals("2025-26", SeasonLabel.display(2026))
        assertEquals("All Time", SeasonLabel.display(0))
        assertFalse(SeasonLabel.display(2026).contains("2026"))
    }
}

/** The two-tier cache while the bundled archive and the live season overlap. */
class TwoTierCacheTest {
    private val directories = mutableListOf<File>()

    @After
    fun cleanUp() {
        directories.forEach { it.deleteRecursively() }
    }

    private fun directory(): File = Files.createTempDirectory("two-tier").toFile().also { directories += it }

    private fun players(season: Int, name: String, count: Int = 24): List<Player> = (0 until count).map { index ->
        testPlayer(
            id = 100 + index, name = "$name $index", team = listOf("BOS", "NYK")[index % 2], position = "G",
            season = season, type = listOf("g", "f", "c")[index % 3], updatedAt = Instant.EPOCH,
            metrics = listOf(
                metric("Pts/100", "25.0", 50, MetricCategory.SCORING, id = "p"),
                metric("AST%", "15.0%", 50, MetricCategory.PLAYMAKING, id = "a"),
                metric("REB%", "10.0%", 50, MetricCategory.REBOUNDING, id = "r"),
            ),
        )
    }

    /** The APK's assets, read from the module source tree the way the packager ships them. */
    private val assets = File("src/main/assets")

    private fun bundledCache(dir: File = directory()) = TwoTierPlayerCache(dir) { name ->
        File(assets, name).takeIf { it.exists() }?.inputStream()
    }

    private fun emptyCache(dir: File) = TwoTierPlayerCache(dir) { null }

    @Test
    fun completeOpeningNightIsCacheableBeforeFullSlate() {
        assertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(2027, "A"), 2027))
    }

    @Test
    fun currentSnapshotNeedsTwoTeamsAllCohortsAndTheCoreMetrics() {
        val oneTeam = players(2027, "A").map { it.copy(team = "BOS") }
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(oneTeam, 2027))
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(2027, "A").filter { it.playerType != "c" }, 2027))
        val noCore = players(2027, "A").map { it.copy(metrics = listOf(metric("TS%", "1", 1, id = "x"))) }
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(noCore, 2027))
    }

    /** Last season's rows are not the live season's, whichever season is asked. */
    @Test
    fun aSnapshotOfAnotherSeasonIsNotCurrentData() {
        assertFalse(PlayerSnapshotValidator.isCompleteCurrent(players(2026, "A"), 2027))
        assertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(2026, "A"), 2026))
        // With no season named, the newest regular season present is judged.
        assertTrue(PlayerSnapshotValidator.isCompleteCurrent(players(2026, "A")))
    }

    @Test
    fun savedServerSnapshotIsKeptWhateverItsAge() {
        val dir = directory()
        val cache = emptyCache(dir)
        cache.saveCurrentPlayers(players(2026, "Server"), 2026)
        val file = File(dir, "players-current.json")
        val weekAgo = System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
        file.setLastModified(weekAgo)

        assertEquals(24, cache.loadCurrentPlayers().size)
        assertEquals(weekAgo.toDouble(), file.lastModified().toDouble(), 1000.0)
    }

    @Test
    fun noSavedSnapshotServesNoCurrentPlayers() {
        assertTrue(emptyCache(directory()).loadCurrentPlayers().isEmpty())
    }

    /** The live season splits from history at the season the server is writing, 2026 while 2026-27 is pending. */
    @Test
    fun saveSplitsHistoryFromTheLiveSeasonAtTheLiveSeason() {
        val dir = directory()
        val cache = emptyCache(dir)
        cache.saveCurrentPlayers(players(2026, "Live"), 2026)
        assertEquals(24, cache.loadCurrentPlayers().size)
        assertTrue(File(dir, "players-current.json").exists())
        val written = dir.list().orEmpty()
        assertFalse("a save writes no history: the bundle is the archive", written.any { it.startsWith("players-historical") })
    }

    /** One file per season, so a screen decodes only the season it shows. */
    @Test
    fun theArchiveIsOneFilePerSeasonAndNoCombinedFile() {
        assertFalse(File(assets, "players-historical.bin").exists())
        for (season in TwoTierPlayerCache.bundledSeasons) {
            assertTrue("missing file for season $season", File(assets, "${TwoTierPlayerCache.HISTORY_PREFIX}$season.bin").exists())
        }
        assertEquals("All Time plus 2003 through 2026", 25, TwoTierPlayerCache.bundledSeasons.size)
    }

    @Test
    fun oneSeasonDecodesWithoutTheRest() {
        val rows = bundledCache().loadHistoricalSeason(2026)
        assertTrue(rows.size > 400)
        assertEquals(setOf(2026), rows.mapNotNull { it.season }.toSet())
        assertEquals(setOf(0), bundledCache().loadHistoricalSeason(StatScoutSeason.ALL_TIME).mapNotNull { it.season }.toSet())
        assertTrue("no file, no rows", bundledCache().loadHistoricalSeason(1999).isEmpty())
    }

    /** An offline first launch shows the newest bundled season no later than the live one, and that is a single file. */
    @Test
    fun theOfflineFallbackIsTheNewestBundledSeasonAtMostTheLiveOne() {
        val cache = bundledCache()
        assertEquals(
            "2027 is pending and not bundled, so 2026 is what there is",
            setOf(2026), cache.loadNewestBundledSeason(2027).mapNotNull { it.season }.toSet(),
        )
        assertEquals(setOf(2010), cache.loadNewestBundledSeason(2010).mapNotNull { it.season }.toSet())
        assertTrue(cache.loadNewestBundledSeason(2002).isEmpty())
    }

    /** The bundled archive carries 2025-26 too, so a real row has to decode end to end. */
    @Test
    fun aRealBundledRowFrom2026Decodes() {
        val row = bundledCache().loadHistoricalSeason(2026).first {
            it.name == "Shai Gilgeous-Alexander" && it.seasonPhase == SeasonPhase.REGULAR
        }
        assertEquals(4278073, row.playerId)
        assertEquals("OKC", row.team)
        assertEquals("g", row.playerType)
        assertEquals(PlayerPositionGroup.GUARD, row.positionGroup)
        assertEquals(47, row.metrics.size)
        assertEquals("all six categories", MetricCategory.entries.toSet(), row.metrics.map { it.category }.toSet())
        val ppg = row.metrics.first { it.label == "PPG" }
        assertEquals("31.1", ppg.value)
        assertEquals(MetricCategory.SCORING, ppg.category)
        // Every label the backend wrote is one the registry knows.
        for (metric in row.metrics) {
            assertNotNull("${metric.label} / ${metric.category}", BasketballMetricRegistry.definition(metric.label, metric.category))
        }
        // The standard line, in the contract's order, with made/attempted pairs.
        assertEquals(
            listOf("G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN"),
            row.standardStats?.map { it.label },
        )
        assertEquals("731/1,321", row.standardStats?.first { it.label == "FG" }?.value)
        assertEquals(731.0 / 1321.0 * 100, StandardStatSemantics.numericValue("FG", "731/1,321")!!, 0.001)
    }

    /** Rows whose `updated_at` carries five fractional digits once failed the decode of every past season. */
    @Test
    fun bundledRowsWithAStringTimestampDecode() {
        val all = bundledCache().loadHistoricalPlayers()
        assertTrue(all.size > 11_000)
        val row = all.first { it.season == 2008 && it.seasonPhase == SeasonPhase.REGULAR }
        assertTrue(row.updatedAt.epochSecond > 1_700_000_000)
        assertNotNull(parseDate("2026-10-08T21:38:26.20338+00:00"))
        assertNotNull(parseDate("2026-10-08T21:38:26+00:00"))
        assertNotNull(parseDate("2026-10-08"))
        assertNull(parseDate("not a date"))
    }

    @Test
    fun theBundleCarriesEverySeasonFrom2003ThroughTheLastCompleted() {
        val all = bundledCache().loadHistoricalPlayers()
        assertTrue(PlayerSnapshotValidator.isCompleteHistorical(all))
        val seasons = all.mapNotNull { it.season }.toSet()
        assertEquals(StatScoutSeason.BUNDLED_NEWEST, seasons.max())
        assertEquals(StatScoutSeason.EARLIEST, (seasons - StatScoutSeason.ALL_TIME).min())
        assertTrue("the career rollup", seasons.contains(StatScoutSeason.ALL_TIME))
    }

    /** Archive rows for the live season fill in what the network has not delivered and never overwrite it. */
    @Test
    fun loadingHistoryNeverOverwritesTheLiveSeasonFromTheNetwork() = runTest {
        val live = players(2026, "Network")
        val archive = players(2026, "Archive") + players(2025, "Past")
        val vm = dashboard(MockProvider(live), ArchiveCache(archive))
        vm.applyProState(true)
        vm.load()
        vm.loadHistoricalIfNeeded()

        val liveRows = vm.players(2026, SeasonPhase.REGULAR)
        assertEquals(24, liveRows.size)
        assertTrue(liveRows.all { it.name.startsWith("Network") })
        assertEquals(24, vm.players(2025, SeasonPhase.REGULAR).size)
    }
}

/** A cache whose archive overlaps the live season, as the real bundle does. */
private class ArchiveCache(private val archive: List<Player>) : PlayerCaching {
    override fun loadCurrentPlayers(): List<Player> = emptyList()
    override fun loadHistoricalPlayers(): List<Player> = archive
    override fun saveCurrentPlayers(players: List<Player>, liveSeason: Int) {}
    override fun loadHistoricalSeason(season: Int): List<Player> = archive.filter { it.season == season }
}
