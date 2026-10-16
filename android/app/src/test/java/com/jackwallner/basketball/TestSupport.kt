package com.jackwallner.basketball

import com.jackwallner.basketball.data.AppClock
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.data.InMemoryStore
import com.jackwallner.basketball.data.KeyValueStore
import com.jackwallner.basketball.data.PlayerCaching
import com.jackwallner.basketball.data.StatcastProviding
import com.jackwallner.basketball.model.DataCoverage
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.GameTrend
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StandardStat
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.leagueTeamAbbreviations
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/** Shared builders so each test reads like its iOS counterpart. */
fun metric(
    label: String,
    value: String = "1",
    percentile: Int = 50,
    category: MetricCategory = MetricCategory.SCORING,
    qualified: Boolean? = null,
    rankable: Boolean? = null,
    id: String = "${category.raw}-$label",
) = Metric(label, value, percentile, category, qualified, rankable, id)

fun std(label: String, value: String) = StandardStat(label, value, "std-$label")

fun testPlayer(
    id: Int = 1,
    name: String = "Test",
    team: String = "BOS",
    position: String = "G",
    season: Int? = TEST_LIVE_SEASON,
    phase: SeasonPhase = SeasonPhase.REGULAR,
    type: String? = null,
    metrics: List<Metric> = emptyList(),
    standard: List<StandardStat>? = emptyList(),
    games: List<GameTrend> = emptyList(),
    updatedAt: Instant = Instant.parse("2026-04-28T12:00:00Z"),
) = Player(
    playerId = id, name = name, team = team, position = position, handedness = "",
    updatedAt = updatedAt, season = season, seasonPhase = phase, playerType = type,
    metrics = metrics, standardStats = standard, games = games,
)

/** The season the tests treat as live: the newest the bundle carries, what a fresh install resolves to. */
const val TEST_LIVE_SEASON = StatScoutSeason.BUNDLED_NEWEST

/** A [StatcastProviding] whose only data is what the test hands it; every other feed is empty. */
open class MockProvider(
    private val players: List<Player> = emptyList(),
    private val error: Throwable? = null,
    private val freshness: DataFreshness? = null,
) : StatcastProviding {
    private fun check() { error?.let { throw it } }

    override suspend fun fetchHistoricalPlayers(before: Int): List<Player> {
        check()
        return players.filter { (it.season ?: 0) < before }
    }

    override suspend fun fetchCurrentPlayers(season: Int): List<Player> {
        check()
        return players
    }

    override suspend fun fetchDataFreshness(): DataFreshness? {
        check()
        return freshness
    }

    override suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> {
        check()
        return emptyList()
    }

    override suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm> {
        check()
        return emptyList()
    }

    override suspend fun fetchDataCoverage(season: Int): DataCoverage? {
        check()
        return null
    }
}

class InMemoryPlayerCache(seed: List<Player> = emptyList()) : PlayerCaching {
    var savedPlayers: List<Player> = seed
        private set

    override fun loadCurrentPlayers(): List<Player> = savedPlayers
    override fun loadHistoricalPlayers(): List<Player> = emptyList()
    override fun saveCurrentPlayers(players: List<Player>, liveSeason: Int) { savedPlayers = players }
}

/** A view model on the test scheduler, so `load()` is deterministic and virtual time is free. */
fun TestScope.dashboard(
    provider: StatcastProviding,
    cache: PlayerCaching? = null,
    store: KeyValueStore = InMemoryStore(),
) = DashboardViewModel(provider, cache, store, this, io = StandardTestDispatcher(testScheduler))

/** Three players a team, one per cohort, so every cohort is present. */
fun completeSeasonPlayers(season: Int, namePrefix: String): List<Player> =
    leagueTeamAbbreviations.flatMapIndexed { index, team ->
        listOf("g", "f", "c").mapIndexed { offset, type ->
            testPlayer(
                id = 10_000 + index * 3 + offset, name = "$namePrefix $team $type", team = team,
                position = type.uppercase(), season = season, type = type,
                metrics = listOf(
                    metric("Pts/100", "25.0", 50, MetricCategory.SCORING, id = "pts-$index-$offset"),
                    metric("AST%", "15.0%", 50, MetricCategory.PLAYMAKING, id = "ast-$index-$offset"),
                    metric("REB%", "10.0%", 50, MetricCategory.REBOUNDING, id = "reb-$index-$offset"),
                ),
                standard = listOf(StandardStat("G", "60", "games-$index")),
            )
        }
    }

fun completeCurrentPlayers(namePrefix: String = "Cached") = completeSeasonPlayers(TEST_LIVE_SEASON, namePrefix)

/** A clock the test moves by hand. */
class FakeClock(var instant: Instant = Instant.parse("2026-10-13T12:00:00Z"), private val zone: ZoneId = ZoneOffset.UTC) : AppClock {
    override fun now(): Instant = instant
    override fun zone(): ZoneId = zone
}
