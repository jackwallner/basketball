package com.jackwallner.basketball

import com.jackwallner.basketball.data.TwoTierPlayerCache
import com.jackwallner.basketball.model.DataCoverage
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.SeasonPhase
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The first screen has to appear without waiting on anything it does not need:
 * the leaderboard is drawn as soon as the players arrive (not after the
 * follow-up reads), and an offline first launch decodes one bundled season
 * rather than the whole archive.
 */
class LaunchPathTest {
    private val directory: File = Files.createTempDirectory("launch-path").toFile()

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private fun livePlayers(count: Int = 24): List<Player> = (0 until count).map { index ->
        testPlayer(
            id = 100 + index, name = "Live $index", team = listOf("BOS", "NYK")[index % 2], position = "G",
            season = TEST_LIVE_SEASON, type = listOf("g", "f", "c")[index % 3], updatedAt = Instant.EPOCH,
            metrics = listOf(
                metric("Pts/100", "25.0", 50, MetricCategory.SCORING, id = "p"),
                metric("AST%", "15.0%", 50, MetricCategory.PLAYMAKING, id = "a"),
                metric("REB%", "10.0%", 50, MetricCategory.REBOUNDING, id = "r"),
            ),
        )
    }

    private fun bundledCache() = TwoTierPlayerCache(directory) { name ->
        File("src/main/assets", name).takeIf { it.exists() }?.inputStream()
    }

    @Test
    fun theLeaderboardIsOnScreenBeforeTheFollowUpReadsFinish() = runTest {
        val provider = object : MockProvider(livePlayers()) {
            override suspend fun fetchDataCoverage(season: Int): DataCoverage? {
                delay(1_500)
                return null
            }
        }
        val vm = dashboard(provider)
        val load = launch { vm.load() }
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals("players are drawn before the slow coverage read returns", 24, vm.players.size)
        assertFalse(vm.isLoading)
        load.cancel()
    }

    /** An offline first launch with nothing saved shows the newest bundled season, and leaves the rest for when something asks. */
    @Test
    fun offlineColdStartDecodesOnlyTheNewestBundledSeason() = runTest {
        val vm = dashboard(MockProvider(error = IOException("offline")), bundledCache())
        vm.load()

        assertFalse("a cold offline start still has a board", vm.players.isEmpty())
        assertTrue("and still says the refresh failed", vm.lastFetchFailed)
        assertEquals(setOf(TEST_LIVE_SEASON), vm.players.mapNotNull { it.season }.toSet())
        assertFalse("the other seasons are not decoded until asked for", vm.hasLoadedHistorical)
    }

    /** Picking a past season decodes that season first and the rest after. */
    @Test
    fun selectingAPastSeasonLoadsItAndThenTheRestOfTheArchive() = runTest {
        val vm = dashboard(MockProvider(livePlayers()), bundledCache())
        vm.applyProState(true)
        vm.load()

        vm.selectSeason(2010)
        vm.seasonLoadJob?.join()

        assertFalse(vm.players(2010, SeasonPhase.REGULAR).isEmpty())
        assertTrue(vm.hasLoadedHistorical)
        assertFalse("the rest of the archive follows", vm.players(2003, SeasonPhase.REGULAR).isEmpty())
        val network = vm.players(TEST_LIVE_SEASON, SeasonPhase.REGULAR).filter { it.name.startsWith("Live ") }
        assertEquals("the network rows are untouched by the archive", 24, network.size)
    }
}
