package com.jackwallner.basketball

import com.jackwallner.basketball.model.DataCoverage
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.ui.components.shortAge
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DataFreshnessTest {
    private fun decode(json: String) = DataFreshness.fromJson(Json.parseToJsonElement(json) as JsonObject)

    @Test
    fun productionStatusDecodesCoverageAndPendingEnrichment() {
        val status = decode(
            """{"status":"degraded","refresh_id":"v2","source_published_at":null,
             "published_at":"2026-10-22T12:05:00Z","last_checked_at":"2026-10-22T12:10:00Z",
             "max_game_date":"2026-10-21","max_week":3,"observed_games":10,"expected_games":10,"season_type":"REG",
             "season":2027,"published_season":2027,"ngs_status":"pending","pfr_status":"ready"}""",
        )
        assertEquals(DataFreshnessStatus.PARTIAL, status.status)
        assertEquals("v2", status.revision)
        assertEquals(10, status.coverage?.gamesIncluded)
        assertEquals(2027, status.publishedSeason)
        assertEquals("pending", status.shotsStatus)
        assertNull(status.sourcePublishedAt)
        assertFalse(status.isSeasonPending)
    }

    /** The row the publisher really wrote on 2026-10-08, trimmed to the columns the app reads. */
    @Test
    fun theRealPendingRowDecodes() {
        val status = decode(
            """{"status":"source_pending","refresh_id":"ec7f98cf","source_published_at":null,
             "published_at":"2026-10-08T21:43:06.835518+00:00","last_checked_at":"2026-10-08T22:14:07.504338+00:00",
             "season":2027,"season_type":"POST,REG","max_week":37,"max_game_date":"2026-06-13",
             "expected_games":1316,"observed_games":1316,"coverage_status":"complete",
             "ngs_status":"ready","pfr_status":"ready","last_error_code":"season_pending","published_season":2026}""",
        )
        assertTrue(status.isSeasonPending)
        assertEquals(DataFreshnessStatus.PENDING, status.status)
        assertEquals(2027, status.season)
        assertEquals(2026, status.publishedSeason)
        assertEquals("season_pending", status.lastErrorCode)
        // A "POST,REG" season_type is not a phase; the coverage defaults to regular.
        assertEquals(SeasonPhase.REGULAR, status.coverage?.phase)
        assertEquals(1316, status.coverage?.gamesIncluded)
        assertFalse(status.isAdvancedPending)
    }

    @Test
    fun pendingNeedsAllThreeConditions() {
        fun status(raw: String, season: Int?, published: Int?, code: String?) =
            DataFreshness(rawStatus = raw, season = season, publishedSeason = published, lastErrorCode = code)
        assertTrue(status("source_pending", 2027, 2026, "season_pending").isSeasonPending)
        // An ordinary stall in the middle of a season is not a pending season.
        assertFalse(status("source_pending", 2027, 2027, "season_pending").isSeasonPending)
        assertFalse(status("source_pending", 2027, 2026, null).isSeasonPending)
        assertFalse(status("published", 2027, 2026, "season_pending").isSeasonPending)
        assertFalse(status("source_pending", null, 2026, "season_pending").isSeasonPending)
    }

    @Test
    fun statusSurvivesTheLocalCache() {
        val pending = DataFreshness(
            status = DataFreshnessStatus.PENDING, revision = "r", rawStatus = "source_pending",
            season = 2027, publishedSeason = 2026, lastErrorCode = "season_pending",
        )
        assertTrue(DataFreshness.fromJson(pending.toJson()).isSeasonPending)
        // A local display override is no longer what the publisher said.
        assertFalse(pending.withStatus(DataFreshnessStatus.OFFLINE).isSeasonPending)
        assertEquals(2026, pending.withStatus(pending.status, cached = true).publishedSeason)
    }

    @Test
    fun publishedCoreRevisionIsAdoptedWithAdvancedMetricsPending() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v1"), DataFreshnessStatus.PARTIAL))
        vm.load()
        assertEquals("v1", vm.freshnessRevision)
        assertEquals(DataFreshnessStatus.PARTIAL, vm.freshnessStatus)
        assertEquals(2, vm.dataCoverage?.gamesIncluded)
    }

    @Test
    fun revisionChangeDuringFetchDoesNotAdoptMixedData() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v2")))
        vm.load()
        // A cold start draws the players it fetched rather than a blank screen,
        // but a revision that moved under the fetch is never adopted.
        assertFalse(vm.players.isEmpty())
        assertNull(vm.freshnessRevision)
        assertNull(vm.freshnessForDisplay?.coverage)
        assertEquals(DataFreshnessStatus.CHECKING, vm.freshnessStatus)
    }

    @Test
    fun failedFirstStatusReadStillShowsPlayers() = runTest {
        val vm = dashboard(RevisionProvider(listOf("v1", "v1"), failFirstCheck = true))
        vm.load()
        assertFalse(vm.players.isEmpty())
    }

    @Test
    fun equivalentRefreshRequestsShareOnePlayerFetch() = runTest {
        val provider = RevisionProvider(listOf("v1", "v1"))
        val vm = dashboard(provider)
        val first = async { vm.load() }
        val second = async { vm.load() }
        first.await()
        second.await()
        assertEquals(1, provider.playerFetches)
    }
}

private class RevisionProvider(
    private val revisions: List<String>,
    private val status: DataFreshnessStatus = DataFreshnessStatus.READY,
    private val failFirstCheck: Boolean = false,
) : MockProvider() {
    private var checks = 0
    var playerFetches = 0
        private set

    override suspend fun fetchDataFreshness(): DataFreshness? {
        if (failFirstCheck && checks == 0) {
            checks += 1
            throw IOException("offline")
        }
        val revision = revisions[minOf(checks, revisions.size - 1)]
        checks += 1
        return DataFreshness(
            status = status, revision = revision,
            coverage = DataCoverage(Instant.ofEpochSecond(1000), 1, SeasonPhase.REGULAR, 2, 2),
            season = TEST_LIVE_SEASON, publishedSeason = TEST_LIVE_SEASON,
        )
    }

    override suspend fun fetchCurrentPlayers(season: Int): List<Player> {
        playerFetches += 1
        delay(20)
        return listOf(
            testPlayer(name = "Fixture", team = "BOS", season = TEST_LIVE_SEASON, type = "g", updatedAt = Instant.ofEpochSecond(1000)),
        )
    }
}

class DataFreshnessCaptionTest {
    @Test
    fun shortAgeStaysCompact() {
        val now = Instant.ofEpochSecond(1_800_000_000)
        assertEquals("just now", shortAge(now.plusSeconds(5), now))
        assertEquals("just now", shortAge(now.minusSeconds(59), now))
        assertEquals("10m ago", shortAge(now.minusSeconds(600), now))
        assertEquals("2h ago", shortAge(now.minusSeconds(7_200), now))
    }
}
