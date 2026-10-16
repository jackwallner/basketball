package com.jackwallner.basketball

import android.content.res.AssetManager
import com.jackwallner.basketball.data.KeyValueStore
import com.jackwallner.basketball.data.PlayerCaching
import com.jackwallner.basketball.data.StatcastProviding
import com.jackwallner.basketball.model.DataCoverage
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameDetail
import com.jackwallner.basketball.model.GameProjection
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.PlayerProfile
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.lenientList
import com.jackwallner.basketball.model.metricNumericValue
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * Deterministic rows used only by the store screenshot harness, a port of the
 * iOS `ScreenshotFixtureAPI`. They are real 2025-26 numbers for real players
 * (the same JSON as iOS `ScreenshotFixtureData`, under `debug/assets/screenshot`),
 * so a capture shows what the app shows while staying independent of network
 * timing and source publication lag. Debug builds only.
 *
 * Two statuses, chosen with the `fixtureStatus` launch extra:
 * - `pending` (the default, and what the app reads between October 1 and
 *   opening night): 2025-26 is the live season and 2026-27 is a schedule.
 * - `published`: 2025-26 is live with nothing pending after it.
 */
object ScreenshotFixtureApi : StatcastProviding {
    const val SEASON = 2026
    const val UPCOMING_SEASON = 2027

    /** Set from the launch extras before the feed is swapped in. */
    lateinit var assets: AssetManager
    var published = false

    /** `fixtureFresh`: no followed players or team and no onboarding flag, the first-run look. */
    var fresh = false

    /** The last game of the 2025-26 Finals, the coherent capture date. */
    private val asOf: Instant = Instant.parse("2026-06-14T04:00:00Z")
    private const val FINALS_GAME_ID = "401859967"

    private fun read(name: String): JsonElement =
        assets.open("screenshot/$name.json").bufferedReader().use { Json.parseToJsonElement(it.readText()) }

    private val allPlayers: List<Player> by lazy { read("players").lenientList(Player::fromJson) }
    private val allGames: List<Game> by lazy { read("games").lenientList(Game::fromJson) }

    /** Seeds the fan context so the Following board is deterministic. */
    fun prepareDefaults(defaults: KeyValueStore) {
        if (fresh) {
            defaults.remove("favorites.playerIds")
            defaults.remove("favoriteTeam")
            defaults.putBoolean("hasCompletedOnboarding", false)
        } else {
            // Gilgeous-Alexander, Wembanyama, Jokic.
            defaults.putString("favorites.playerIds", "4278073,5104157,3112335")
            defaults.putString("favoriteTeam", "NYK")
            defaults.putBoolean("hasCompletedOnboarding", true)
        }
        defaults.putString("stats.board", "STANDARD")
        defaults.remove("statcast.dataFreshness")
        defaults.remove("statcast.displayedDataRevision")
        StatScoutSeason.remember(StatScoutSeason.Live(SEASON, if (published) null else UPCOMING_SEASON), defaults)
    }

    /** In-memory cache so the prior season loads through the same lazy path as production. */
    val cache = object : PlayerCaching {
        override fun loadCurrentPlayers(): List<Player> = allPlayers.filter { (it.season ?: 0) >= SEASON }
        override fun loadHistoricalPlayers(): List<Player> = allPlayers.filter { (it.season ?: 0) < SEASON }
        override fun saveCurrentPlayers(players: List<Player>, liveSeason: Int) = Unit
        override fun loadHistoricalSeason(season: Int): List<Player> = allPlayers.filter { it.season == season }
        override fun loadNewestBundledSeason(atMost: Int): List<Player> {
            val newest = allPlayers.mapNotNull { it.season }.filter { it <= atMost }.maxOrNull() ?: return emptyList()
            return allPlayers.filter { it.season == newest }
        }
    }

    override suspend fun fetchHistoricalPlayers(before: Int): List<Player> = allPlayers.filter { (it.season ?: 0) < before }

    override suspend fun fetchCurrentPlayers(season: Int): List<Player> = allPlayers.filter { it.season == season }

    override suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> {
        if (seasonPhase != SeasonPhase.REGULAR || season != SEASON) return emptyList()
        val player = allPlayers.firstOrNull { it.playerId == playerId && it.season == season } ?: return emptyList()
        return makeGameLogs(player)
    }

    override suspend fun fetchPlayerRecentForm(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<RecentForm> {
        if (seasonPhase != SeasonPhase.REGULAR || season != SEASON) return emptyList()
        val player = allPlayers.firstOrNull { it.playerId == playerId && it.season == season } ?: return emptyList()
        return RecentWindow.entries.mapNotNull { makeRecentForm(player, it.value) }
    }

    override suspend fun fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int): List<RecentForm> {
        if (seasonPhase != SeasonPhase.REGULAR || season != SEASON) return emptyList()
        return allPlayers.filter { it.season == season }.mapNotNull { makeRecentForm(it, windowWeeks) }
    }

    private fun coverage() = DataCoverage(asOf = asOf, week = 37, phase = SeasonPhase.REGULAR, gamesIncluded = 1316, expectedGames = 1316)

    override suspend fun fetchDataCoverage(season: Int): DataCoverage? = if (season == SEASON) coverage() else null

    override suspend fun fetchDataFreshness(): DataFreshness {
        val pending = !published
        return DataFreshness(
            status = if (pending) DataFreshnessStatus.PENDING else DataFreshnessStatus.READY,
            revision = "screenshot-fixture-v1",
            publishedAt = asOf,
            checkedAt = asOf,
            coverage = coverage(),
            isCached = false,
            shotsStatus = "ready",
            playByPlayStatus = "ready",
            rawStatus = if (pending) "source_pending" else "published",
            season = if (pending) UPCOMING_SEASON else SEASON,
            publishedSeason = SEASON,
            lastErrorCode = if (pending) "season_pending" else null,
        )
    }

    override suspend fun fetchGames(season: Int): List<Game> = allGames.filter { it.season == season }

    override suspend fun fetchGameLogs(gameId: String): List<PlayerGameLog> =
        read("game-logs").lenientList(PlayerGameLog::fromJson).filter { it.gameId == gameId }

    override suspend fun fetchGameIdsWithStats(season: Int): Set<String> {
        val detail = fetchGameDetail(FINALS_GAME_ID) ?: return emptySet()
        return if (season == SEASON) setOf(detail.gameId) else emptySet()
    }

    override suspend fun fetchGameDetail(gameId: String): GameDetail? =
        read("game-detail").lenientList(GameDetail::fromJson).firstOrNull { it.gameId == gameId }

    override suspend fun fetchPlayerProfiles(season: Int): List<PlayerProfile> = read("profiles").lenientList(PlayerProfile::fromJson)

    override suspend fun fetchTeamRatings(season: Int): List<TeamRating> =
        if (season == SEASON) read("ratings").lenientList(TeamRating::fromJson) else emptyList()

    override suspend fun fetchGameProjections(season: Int): List<GameProjection> = read("projections").lenientList(GameProjection::fromJson)

    /** A stable value in -1..1 for a name, so the same capture always draws the same wobble (FNV-1a, as on iOS). */
    private fun unit(text: String): Double {
        var hash = -0x340d631b7bdddcdbL // 14695981039346656037 as a signed Long
        for (ch in text) {
            hash = (hash xor ch.code.toLong()) * 1_099_511_628_211L
        }
        return java.lang.Long.remainderUnsigned(hash, 2_001L).toDouble() / 1_000 - 1
    }

    private fun perGame(player: Player, label: String): Double? =
        player.standardStats?.firstOrNull { it.label == label }?.let { metricNumericValue(it.value) }

    /** Swift's `.rounded()`: half away from zero. */
    private fun r(value: Double): Double = if (value < 0) -Math.round(-value).toDouble() else Math.round(value).toDouble()

    /** Six games leading up to the capture date, each a seeded wobble around the player's season averages. */
    fun makeGameLogs(player: Player): List<PlayerGameLog> {
        val games = perGame(player, "G") ?: 60.0
        fun pair(label: String): Pair<Double, Double> {
            val parts = player.standardStats?.firstOrNull { it.label == label }?.value
                ?.split("/", limit = 2)?.mapNotNull { metricNumericValue(it) }.orEmpty()
            return if (parts.size == 2) parts[0] / games to parts[1] / games else 0.0 to 0.0
        }
        val fg = pair("FG")
        val three = pair("3P")
        val ft = pair("FT")
        val opponents = listOf("PHX", "POR", "DEN", "MEM", "UTA", "SAC")
        val day = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.of("America/New_York"))
        return (0 until 6).map { index ->
            val u = unit("${player.playerId}-$index")
            val factor = 1 + 0.25 * u
            val metrics = linkedMapOf(
                "min" to r(perGame(player, "MPG") ?: 30.0),
                "pts" to r((perGame(player, "PPG") ?: 15.0) * factor),
                "reb" to r((perGame(player, "RPG") ?: 4.0) * factor),
                "ast" to r((perGame(player, "APG") ?: 3.0) * factor),
                "stl" to r((perGame(player, "SPG") ?: 1.0) * (1 + 0.5 * u)),
                "blk" to r((perGame(player, "BPG") ?: 0.5) * (1 + 0.5 * u)),
                "tov" to 2.0,
                "pf" to 2.0,
                "fgm" to r(fg.first * factor),
                "fga" to r(fg.second * (1 + 0.1 * u)),
                "fg3m" to r(three.first * factor),
                "fg3a" to r(three.second),
                "ftm" to r(ft.first * factor),
                "fta" to r(ft.second),
                "starter" to 1.0,
                "plus_minus" to r(u * 12),
            )
            val date = asOf.minusSeconds((5 - index) * 2 * 86_400L)
            PlayerGameLog.fromJson(buildJsonObject {
                put("player_id", player.playerId)
                put("season", player.season ?: SEASON)
                put("season_type", "REG")
                put("game_date", day.format(date))
                put("player_type", player.playerType ?: "f")
                player.team.let { put("team", it) }
                put("opponent", opponents[index])
                put("plays", 18)
                put("touches", r(perGame(player, "MPG") ?: 30.0).toInt())
                putJsonObject("metrics") { metrics.forEach { (k, v) -> put(k, v) } }
            })
        }
    }

    /**
     * A rolling window built from the player's own season metrics: the current
     * span wobbles a few percent around the season figure and the prior span sits
     * on the other side of it, so Trends has both risers and fallers.
     */
    fun makeRecentForm(player: Player, windowWeeks: Int): RecentForm? {
        val games = max(1, min(windowWeeks * 3, (perGame(player, "G") ?: 3.0).toInt()))
        val seasonGames = perGame(player, "G") ?: 60.0
        val metrics = linkedMapOf<String, Double>()
        val prior = linkedMapOf<String, Double>()
        val delta = linkedMapOf<String, Double>()
        for (metric in player.metrics) {
            val key = RecentMetricKey.key(metric.label) ?: continue
            val value = metricNumericValue(metric.value) ?: continue
            val u = unit("${player.playerId}-$key-$windowWeeks")
            val current: Double
            val before: Double
            if (RecentMetricKey.isSeasonTotal(metric.label)) {
                current = r(value / seasonGames * games * (1 + 0.15 * u))
                before = r(value / seasonGames * games)
            } else {
                current = value * (1 + 0.1 * u)
                before = value * (1 - 0.06 * u)
            }
            metrics[key] = current
            prior[key] = before
            delta[key] = current - before
        }
        val minutes = ((perGame(player, "MPG") ?: 30.0) * games).roundToInt()
        return runCatching {
            RecentForm.fromJson(buildJsonObject {
                put("player_id", player.playerId)
                put("season", player.season ?: SEASON)
                put("season_type", "REG")
                put("player_type", player.playerType ?: "f")
                put("window_weeks", windowWeeks)
                put("as_of", "2026-04-12")
                put("start_week", 28 - windowWeeks + 1)
                put("end_week", 28)
                put("team", player.team)
                put("games", games)
                put("plays", games * 18)
                put("touches", minutes)
                putJsonObject("metrics") { metrics.forEach { (k, v) -> put(k, v) } }
                putJsonObject("prior_metrics") { prior.forEach { (k, v) -> put(k, v) } }
                putJsonObject("delta") { delta.forEach { (k, v) -> put(k, v) } }
            })
        }.getOrNull()
    }
}
