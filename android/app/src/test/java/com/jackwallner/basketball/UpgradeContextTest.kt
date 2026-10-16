package com.jackwallner.basketball

import com.jackwallner.basketball.data.PlayerSnapshotValidator
import com.jackwallner.basketball.data.TwoTierPlayerCache
import com.jackwallner.basketball.data.toJson
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.ui.nav.Route
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.buildJsonArray
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regressions for three context bugs: an
 * unprovenanced current-season cache surviving an upgrade, a team page whose
 * roster ignored its own season picker, and drill-down routes that dropped
 * the phase they were opened from.
 */
class UpgradeContextTest {
    private val directory: File = Files.createTempDirectory("upgrade-context").toFile()
    private val current = TEST_LIVE_SEASON

    @After
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private fun cache() = TwoTierPlayerCache(directory) { null }

    private fun players(
        teams: List<String>, count: Int, season: Int = current, phase: SeasonPhase = SeasonPhase.REGULAR, idOffset: Int = 0,
    ): List<Player> = (0 until count).map { index ->
        testPlayer(
            id = idOffset + index, name = "Player ${idOffset + index}", team = teams[index % teams.size],
            season = season, phase = phase, type = listOf("g", "f", "c")[index % 3],
            updatedAt = Instant.EPOCH,
            metrics = listOf(
                metric("Pts/100", "25.0", 50, MetricCategory.SCORING, id = "scoring"),
                metric("AST%", "15.0%", 50, MetricCategory.PLAYMAKING, id = "playmaking"),
                metric("REB%", "10.0%", 50, MetricCategory.REBOUNDING, id = "rebounding"),
            ),
        )
    }

    private fun writeWithoutProvenance(rows: List<Player>): File {
        directory.mkdirs()
        val file = File(directory, "players-current.json")
        file.writeText(buildJsonArray { rows.forEach { add(it.toJson()) } }.toString())
        return file
    }

    /**
     * The shape of the artifact an early build could write: a real server export, but only the
     * teams that had played by then. It passes `isCompleteCurrent` by design, so
     * the validator can never be what separates it from a full snapshot.
     */
    @Test
    fun cacheWithoutProvenanceIsDiscardedOnUpgrade() {
        val openingWeek = players(listOf("LAL", "BOS", "SAS", "GSW"), 110)
        assertTrue(
            "The artifact has to clear the opening-night rule, or this test isn't reproducing the bug",
            PlayerSnapshotValidator.isCompleteCurrent(openingWeek),
        )
        val file = writeWithoutProvenance(openingWeek)

        assertTrue("A snapshot of unknown origin must never populate the current board", cache().loadCurrentPlayers().isEmpty())
        assertFalse("The discarded snapshot should be removed, not re-read on every launch", file.exists())
    }

    @Test
    fun snapshotSavedByThisBuildIsTrustedOnReload() {
        val cache = cache()
        cache.saveCurrentPlayers(players(listOf("SAS", "BOS"), 30), current)

        assertEquals(30, cache.loadCurrentPlayers().size)
        assertTrue(File(directory, "players-current-provenance.json").exists())
        // Still trusted on a second read: the marker is not consumed.
        assertEquals(30, cache().loadCurrentPlayers().size)
    }

    @Test
    fun discardedSnapshotIsReplacedByTheNextServerSave() {
        writeWithoutProvenance(players(listOf("LAL", "BOS", "SAS", "GSW"), 110))

        val cache = cache()
        assertTrue(cache.loadCurrentPlayers().isEmpty())

        cache.saveCurrentPlayers(players(listOf("SAS", "BOS", "DEN", "MIL"), 40), current)
        assertEquals(40, cache.loadCurrentPlayers().size)
    }

    @Test
    fun teamRosterFollowsSelectedSeasonAndPhase() = runTest {
        val sasThisYear = players(listOf("SAS"), 5, current)
        val sasLastYear = players(listOf("SAS"), 3, current - 1, idOffset = 100)
        val sasPlayoffs = players(listOf("SAS"), 2, current - 1, SeasonPhase.PLAYOFFS, idOffset = 200)
        val vm = dashboard(MockProvider(sasThisYear + sasLastYear + sasPlayoffs))
        vm.load()

        vm.selectedSeason = current
        vm.selectedPhase = SeasonPhase.REGULAR
        assertEquals(5, vm.players("SAS").size)

        // The team page derives its roster from exactly this call, so moving
        // the page's picker has to move the rows underneath it.
        vm.selectedSeason = current - 1
        assertEquals(3, vm.players("SAS").size)

        vm.selectedPhase = SeasonPhase.PLAYOFFS
        assertEquals(2, vm.players("SAS").size)
    }

    @Test
    fun playersForSeasonHonoursAnExplicitPhase() = runTest {
        val regular = players(listOf("SAS", "BOS"), 6, current - 1)
        val playoffs = players(listOf("SAS", "BOS"), 2, current - 1, SeasonPhase.PLAYOFFS, idOffset = 50)
        val vm = dashboard(MockProvider(regular + playoffs))
        vm.load()
        vm.selectedPhase = SeasonPhase.REGULAR

        // A route opened from a playoff profile resolves against its own phase,
        // not whichever one the tab happens to be sitting on.
        assertEquals(2, vm.players(current - 1, SeasonPhase.PLAYOFFS).size)
        assertEquals(6, vm.players(current - 1, SeasonPhase.REGULAR).size)
    }

    @Test
    fun routesCarrySeasonAndPhase() {
        val metric = Route.Metric("TS%", MetricCategory.SCORING, 2024, SeasonPhase.PLAYOFFS)
        assertEquals(2024, metric.season)
        assertEquals(SeasonPhase.PLAYOFFS, metric.phase)

        val standard = Route.StandardStat("PPG", PlayerPositionGroup.GUARD, 2024, SeasonPhase.PLAYOFFS)
        assertEquals(2024, standard.season)
        assertEquals(SeasonPhase.PLAYOFFS, standard.phase)

        // Two routes to the same stat in the same year but different halves of
        // it are different destinations, or the stack coalesces them.
        assertNotEquals(metric, Route.Metric("TS%", MetricCategory.SCORING, 2024, SeasonPhase.REGULAR))
    }
}
