package com.jackwallner.basketball.data

import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.basketball.model.DataCoverage
import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameDetail
import com.jackwallner.basketball.model.GameProjection
import com.jackwallner.basketball.model.GameDay
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.DateText
import com.jackwallner.basketball.model.LiveScore
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.LeagueConference
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.PlayerProfile
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeriesStatus
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.TrendWindow
import com.jackwallner.basketball.model.metricNumericValue
import com.jackwallner.basketball.model.leagueTeamAbbreviations
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.matchesSearch
import com.jackwallner.basketball.model.searchMatches
import com.jackwallner.basketball.model.teamFullName
import java.io.IOException
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * The shared state behind every screen: the league snapshot, season and
 * position selection, the schedule, enrichment and Recent Form windows. A port
 * of the iOS `DashboardViewModel`, with the same gates and the same rules for
 * accepting or refusing a refresh.
 */
class DashboardViewModel(
    private val provider: StatcastProviding,
    private val cache: PlayerCaching?,
    private val defaults: KeyValueStore,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.Default,
    private val clock: () -> Instant = Instant::now,
    private val log: (String) -> Unit = {},
) {
    // MARK: Selection

    var players by mutableStateOf<List<Player>>(emptyList())
        private set
    var playerHistories by mutableStateOf<Map<Int, List<Player>>>(emptyMap())
        private set
    var searchText by mutableStateOf("")
    var selectedConference by mutableStateOf(LeagueConference.ALL)
    /** Calder-eligible players only. Applies on the live season, the only one with the league's rookie flag. */
    var rookiesOnly by mutableStateOf(false)

    private var selectedPositionState by mutableStateOf(PlayerPositionGroup.ALL)
    var selectedPosition: PlayerPositionGroup
        get() = selectedPositionState
        set(value) {
            if (value == selectedPositionState) return
            selectedPositionState = value
            // A stat the user picked follows them to any position that has it; otherwise back to the default.
            val picked = userSortMetricState
            if (picked != null && picked in availableSortMetrics) return
            userSortMetricState = null
            applyDefaultSortDirection()
        }

    private var userSortMetricState by mutableStateOf<String?>(null)
    var sortDescending by mutableStateOf(true)
    /**
     * The newest season with published data, resolved from the publisher's status
     * ([StatScoutSeason.resolveLive]). Between October 1 and opening night this is
     * still the finished season; when the status flips every screen follows.
     */
    var live by mutableStateOf(StatScoutSeason.initialLive(defaults))
        private set
    var selectedSeason by mutableStateOf(live.season)
    var selectedPhase by mutableStateOf(SeasonPhase.REGULAR)

    val sortLabel: String get() = currentSortMetric ?: "Top Metric"

    val currentSortMetric: String?
        get() {
            val user = userSortMetricState
            if (user != null && user in availableSortMetrics) return user
            return determineSortMetricLabel()
        }

    val availableSortMetrics: List<String> by derivedStateOf {
        BasketballMetricRegistry.sorted(eligibleMetrics).map { it.label }.distinct()
    }

    val availableAdvancedSortMetrics: List<String>
        get() = availableSortMetrics.filter { label ->
            eligibleMetrics.any { it.label == label && BasketballMetricRegistry.definition(it.label, it.category)?.kind == MetricKind.ADVANCED }
        }

    fun setUserSortMetric(label: String?) {
        userSortMetricState = label
        applyDefaultSortDirection()
    }

    fun toggleSortDirection() {
        sortDescending = !sortDescending
    }

    /** "Best first" for the active metric. */
    private fun applyDefaultSortDirection() {
        val label = currentSortMetric
        val metric = label?.let { l -> eligibleMetrics.firstOrNull { it.label == l } }
        sortDescending = if (label == null || metric == null) true
        else BasketballMetricRegistry.definition(label, metric.category)?.higherIsBetter ?: true
    }

    /** Mirrors the subscription gate; set by the UI so the VM never depends on the store. */
    var isPro by mutableStateOf(false)
        private set

    /** The season a free user gets: the live one. Every season before it is StatScout+. */
    val freeSeason: Int get() = live.season

    /** A scheduled season with no games played yet, or null once it has data. */
    val upcomingSeason: Int? get() = live.upcoming

    /** The live season is over and the next has not started. */
    val isSeasonPending: Boolean get() = live.isPending

    /** "2025-26 · final" while the next season is pending, "2025-26" otherwise. */
    fun liveSeasonCaption(): String =
        if (isSeasonPending) "${SeasonLabel.display(freeSeason)} · final" else SeasonLabel.display(freeSeason)

    /** When the pending season's first game is played, "Oct 20", or null. */
    val upcomingSeasonStart: String?
        get() {
            if (!isSeasonPending) return null
            val first = upcomingGames.filter { it.seasonPhase == SeasonPhase.REGULAR }.minOfOrNull { it.gameDate } ?: return null
            return DateText.gameDay(first)
        }

    /** "2026-27 starts Oct 20", the line beside a final season. */
    val upcomingSeasonStartsText: String?
        get() {
            val upcoming = upcomingSeason ?: return null
            val start = upcomingSeasonStart ?: return null
            val firstTip = upcomingGames.mapNotNull { it.tipoff }.minOrNull()
            if (firstTip != null && firstTip <= clock()) return "${SeasonLabel.display(upcoming)} under way · stats arriving"
            return "${SeasonLabel.display(upcoming)} starts $start"
        }

    fun isSeasonLocked(season: Int): Boolean = !isPro && season != freeSeason

    val recentFormSeason: Int get() = freeSeason

    /** The live season and the one before it, newest first, floored at the oldest rollup. */
    val recentFormSeasons: List<Int>
        get() = listOf(recentFormSeason, recentFormSeason - 1).filter { it >= StatScoutSeason.EARLIEST_RECENT_FORM }

    fun supportsRecentForm(season: Int): Boolean = season in recentFormSeasons

    /** Switch season first (the header acknowledges the tap), then load what it needs. */
    fun selectSeason(season: Int) {
        selectedSeason = season
        if (hasLoadedHistorical || season == freeSeason) return
        seasonLoadJob = scope.launch { loadHistoricalIfNeeded() }
    }

    var seasonLoadJob: Job? = null
        private set

    /** Push Pro in and re-clamp so a free user can never land on a locked season. */
    fun applyProState(pro: Boolean) {
        isPro = pro
        clampSelectedSeason()
    }

    private fun clampSelectedSeason() {
        if (!isSeasonLocked(selectedSeason)) return
        val target = availableSeasons.firstOrNull { !isSeasonLocked(it) } ?: freeSeason
        if (selectedSeason != target) selectedSeason = target
    }

    // MARK: Load state

    /** True from the first frame so the board shows a spinner, not an empty season. */
    var isLoading by mutableStateOf(true)
        private set
    var isHistoricalLoading by mutableStateOf(false)
        private set
    var hasLoadedHistorical by mutableStateOf(false)
        private set
    var loadingMessage by mutableStateOf("Starting up…")
        private set
    var loadingProgress by mutableStateOf(0.05)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var lastFetchFailed by mutableStateOf(false)
        private set
    /** The network failed, not the data: drives the offline framing. */
    var lastFailureWasConnectivity by mutableStateOf(false)
        private set
    private var hasStartedLoading = false
    private var loadTask: Deferred<Unit>? = null
    private var freshnessCheckTask: Deferred<FreshnessCheckResult>? = null
    private var lastForegroundCheckAt: Instant? = null
    private var lastStatusCheckAt: Instant? = null

    var dataFreshness by mutableStateOf<DataFreshness?>(null)
        private set
    /** Revision represented by what is on screen; can lag the server while a new one is pending. */
    var displayedDataRevision by mutableStateOf<String?>(null)
        private set
    var localLastCheckedAt by mutableStateOf<Instant?>(null)
        private set
    /** The last game the data covers, as opposed to when rows were written. */
    var dataCoverage by mutableStateOf<DataCoverage?>(null)
        private set

    val freshnessRevision: String? get() = displayedDataRevision

    val freshnessForDisplay: DataFreshness?
        get() {
            val remote = dataFreshness ?: return null
            val freshness = remote.copy(coverage = dataCoverage)
            if (lastFetchFailed) {
                return freshness.copy(
                    status = DataFreshnessStatus.FAILED,
                    message = errorMessage ?: "Showing saved data while the latest refresh is retried.",
                    isCached = true,
                )
            }
            val server = freshness.revision
            val displayed = displayedDataRevision
            if (freshness.status != DataFreshnessStatus.READY || server == null || displayed == null || server == displayed) return freshness
            return freshness.copy(
                status = DataFreshnessStatus.STALE,
                message = "New game data is ready, but this screen is still showing the last complete revision.",
                isCached = true,
            )
        }

    val freshnessStatus: DataFreshnessStatus
        get() {
            if (lastFetchFailed) return DataFreshnessStatus.FAILED
            return freshnessForDisplay?.status ?: if (players.isEmpty() && isLoading) DataFreshnessStatus.CHECKING else DataFreshnessStatus.READY
        }

    val lastCheckedAt: Instant? get() = localLastCheckedAt ?: dataFreshness?.checkedAt

    var isRefreshing by mutableStateOf(false)
        private set

    enum class FreshnessCheckResult { UNAVAILABLE, UNCHANGED, UPDATED, PENDING, PARTIAL, STALE, FAILED, THROTTLED }

    val isReady: Boolean get() = players.isNotEmpty()

    // MARK: Season data

    /** Unique players in the selected season and phase. Empty when there is none. */
    val seasonPlayers: List<Player> by derivedStateOf { playersFor(selectedSeason, selectedPhase) }

    private val teamCache by derivedStateOf {
        val teams = sortedSetOf<String>()
        val accum = HashMap<String, Pair<Int, Int>>()
        for (player in seasonPlayers) {
            val abbr = normalizedTeamAbbreviation(player.team)
            teams += abbr
            val score = player.overallPercentile
            if (score > 0) {
                val (sum, count) = accum[abbr] ?: (0 to 0)
                accum[abbr] = (sum + score) to (count + 1)
            }
        }
        teams.toList() to accum.mapValues { it.value.first.toDouble() / it.value.second }
    }

    val teamsWithData: List<String> get() = teamCache.first
    val teamScores: Map<String, Double> get() = teamCache.second

    val teamCounts: Map<String, Int> get() = seasonPlayers.groupingBy { normalizedTeamAbbreviation(it.team) }.eachCount()

    val lastUpdated: Instant? get() = players.maxOfOrNull { it.updatedAt }

    suspend fun fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<PlayerGameLog> =
        provider.fetchGameLogs(playerId, season, seasonPhase)

    suspend fun fetchPlayerRecentForm(playerId: Int, season: Int, seasonPhase: SeasonPhase): List<RecentForm> =
        provider.fetchPlayerRecentForm(playerId, season, seasonPhase)

    init {
        if (cache != null) {
            DataFreshnessCache.load(defaults)?.let { cached ->
                dataFreshness = cached.copy(isCached = true)
                dataCoverage = cached.coverage
                displayedDataRevision = DataFreshnessCache.loadDisplayedRevision(defaults)
                localLastCheckedAt = cached.checkedAt
            }
        }
    }

    /** Every supported season, newest first, with the career rollup at the top. */
    val availableSeasons: List<Int> by derivedStateOf {
        val seasons = (StatScoutSeason.EARLIEST..maxOf(freeSeason, StatScoutSeason.EARLIEST)).toMutableSet()
        playerHistories.values.forEach { history -> history.forEach { p -> p.season?.let(seasons::add) } }
        listOf(StatScoutSeason.ALL_TIME) + (seasons - StatScoutSeason.ALL_TIME).sortedDescending()
    }

    /** Trends and Teams can't honestly show a career row; see the iOS note. */
    val seasonsExcludingAllTime: List<Int> get() = availableSeasons.filter { !StatScoutSeason.isAllTime(it) }

    // MARK: Games

    /** The live season's schedule and posted finals, from `public.games`. */
    var games by mutableStateOf<List<Game>>(emptyList())
        private set

    /** The next season's schedule while it is pending: the Games tab's front door in October. */
    var upcomingGames by mutableStateOf<List<Game>>(emptyList())
        private set

    /** Last season's schedule once a new one is live, so last season's game logs still resolve. */
    var priorGames by mutableStateOf<List<Game>>(emptyList())
        private set

    /** Games whose advanced breakdown is published. */
    var gameIdsWithStats by mutableStateOf<Set<String>>(emptySet())
        private set
    var isGamesLoading by mutableStateOf(false)
        private set
    var gamesError by mutableStateOf<String?>(null)
        private set
    private var gamesLoadedAt: Instant? = null
    private var gamesTask: Deferred<Unit>? = null

    /** What the Games strip is drawn from: the upcoming slate while the next season is pending. */
    val slateGames: List<Game> get() = if (isSeasonPending && upcomingGames.isNotEmpty()) upcomingGames else games

    /** Every day on the slate, in order. */
    val slateDays: List<GameDay> by derivedStateOf { GameDay.days(slateGames) }

    private val slateByDay: Map<String, List<Game>> by derivedStateOf {
        slateGames.groupBy { dayKey(GameDay(GameDay.day(it), it.seasonPhase)) }
    }

    val currentGameDay: GameDay? get() = GameDay.current(slateDays, clock())

    /** The slate's games on one day. */
    fun slateGames(day: GameDay): List<Game> = slateByDay[dayKey(day)].orEmpty()

    private fun dayKey(day: GameDay) = "${day.id}|${day.phase.raw}"

    /** Running scores for games tipped off without a posted final, keyed by game id. */
    var liveScores by mutableStateOf<Map<String, LiveScore>>(emptyMap())
        private set
    private var liveScoresFetchedAt: Instant? = null

    fun liveScore(game: Game): LiveScore? = if (game.isFinal) null else liveScores[game.id]

    /** Tipped off in the last twelve hours with no posted final. Older unscored games never keep the poll alive. */
    private fun startedWithoutFinal(now: Instant): List<Game> = (games + upcomingGames).filter { game ->
        val status = game.status(now)
        val tipoff = game.tipoff
        (status == GameStatus.IN_PROGRESS || status == GameStatus.AWAITING_SCORE) &&
            tipoff != null && Duration.between(tipoff, now).seconds < 12 * 3_600
    }

    /** A game is on: tipped off, no final from the schedule, not already final on the scoreboard. */
    fun hasGamesUnderway(now: Instant = clock()): Boolean = startedWithoutFinal(now).any { liveScores[it.id]?.isFinal != true }

    /** The scoreboard calls a game final that the schedule has not posted yet. */
    fun hasFinalsAwaitingSchedule(now: Instant = clock()): Boolean = startedWithoutFinal(now).any { liveScores[it.id]?.isFinal == true }

    /** When the next game tips off, for pacing the polls before it. */
    fun nextTipoff(after: Instant = clock()): Instant? = (games + upcomingGames).mapNotNull { it.tipoff }.filter { it > after }.minOrNull()

    /** Re-reads the scoreboard for every started game without a final; one read every 20 seconds serves every screen. */
    suspend fun refreshLiveScores(now: Instant = clock()) {
        liveScoresFetchedAt?.let { if (Duration.between(it, now).seconds < 20) return }
        liveScoresFetchedAt = now
        val started = startedWithoutFinal(now)
        if (started.isEmpty()) {
            if (liveScores.isNotEmpty()) liveScores = emptyMap()
            return
        }
        val dates = started.map { LiveScore.dateKey(it.gameDate) }.toSet()
        val fetched = runCatchingNonCancel { provider.fetchLiveScores(dates) }.orEmpty()
        // A failed read keeps the last scores on screen rather than blanking them.
        if (fetched.isEmpty()) return
        val ids = started.map { it.id }.toSet()
        val next = fetched.filterKeys { it in ids }
        if (next != liveScores) liveScores = next
    }

    /** The last day of games the live season played, for the card under the upcoming slate. */
    val lastPlayedGames: List<Game>
        get() {
            if (!isSeasonPending) return emptyList()
            val finals = games.filter { it.isFinal }
            val day = finals.maxOfOrNull { it.gameDate } ?: return emptyList()
            return Game.slateOrder(finals.filter { it.gameDate == day }, clock())
        }

    // MARK: Enrichment

    var profiles by mutableStateOf<Map<Int, PlayerProfile>>(emptyMap())
        private set
    var teamRatings by mutableStateOf<Map<String, TeamRating>>(emptyMap())
        private set
    var projections by mutableStateOf<Map<String, GameProjection>>(emptyMap())
        private set

    fun profile(player: Player): PlayerProfile? = profiles[player.playerId]?.takeIf { it.season == player.season }

    fun teamRating(team: String): TeamRating? = teamRatings[normalizedTeamAbbreviation(team)]

    fun projection(game: Game): GameProjection? = if (game.isFinal) null else projections[game.id]

    private suspend fun loadProfiles() {
        val loaded = runCatchingNonCancel { provider.fetchPlayerProfiles(freeSeason) } ?: return
        if (loaded.isEmpty()) return
        val out = LinkedHashMap<Int, PlayerProfile>()
        for (p in loaded) out.putIfAbsent(p.playerId, p)
        profiles = out
    }

    /** League standings from posted finals, every team present. */
    val standings: Map<String, StandingsRow> by derivedStateOf { StandingsRow.build(games, leagueTeamAbbreviations) }

    /** The schedule, at most once a minute unless forced. Failures keep what is on screen. */
    suspend fun loadGames(force: Boolean = false) {
        gamesTask?.let { it.await(); return }
        val loadedAt = gamesLoadedAt
        if (!force && loadedAt != null && Duration.between(loadedAt, clock()).seconds < 60) return
        val task = scope.async { performGamesLoad() }
        gamesTask = task
        try {
            task.await()
        } finally {
            if (gamesTask === task) gamesTask = null
        }
    }

    private suspend fun performGamesLoad() {
        isGamesLoading = games.isEmpty() && upcomingGames.isEmpty()
        val season = freeSeason
        val upcoming = upcomingSeason
        try {
            coroutineScope {
                // Everything the Games tab needs goes out at once.
                val schedule = async { provider.fetchGames(season) }
                val withStats = async { provider.fetchGameIdsWithStats(season) }
                val nextSchedule = async { upcoming?.let { runCatchingNonCancel { provider.fetchGames(it) } } }
                val ratings = async { runCatchingNonCancel { provider.fetchTeamRatings(season) } }
                val projected = async { runCatchingNonCancel { provider.fetchGameProjections(upcoming ?: season) } }
                val loadedGames = schedule.await()
                val loadedIds = withStats.await()
                if (loadedGames.isNotEmpty() || games.isEmpty()) games = loadedGames.filter { !it.isPostponed }
                upcomingGames = if (upcoming != null) nextSchedule.await()?.filter { !it.isPostponed } ?: upcomingGames else emptyList()
                gameIdsWithStats = loadedIds
                gamesError = null
                gamesLoadedAt = clock()
                ratings.await()?.takeIf { it.isNotEmpty() }?.let { list ->
                    val map = LinkedHashMap<String, TeamRating>()
                    for (r in list) map.putIfAbsent(normalizedTeamAbbreviation(r.team), r)
                    teamRatings = map
                }
                if (!isSeasonPending && priorGames.firstOrNull()?.season != season - 1) {
                    runCatchingNonCancel { provider.fetchGames(season - 1) }?.let { prior -> priorGames = prior.filter { !it.isPostponed } }
                }
                projected.await()?.let { list ->
                    val map = LinkedHashMap<String, GameProjection>()
                    for (p in list) map.putIfAbsent(p.gameId, p)
                    projections = map
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            gamesError = "Couldn't load games. Check your connection and try again."
        }
        isGamesLoading = false
    }

    /** Round, game number and series score for a playoff game. */
    fun seriesStatus(game: Game): SeriesStatus? {
        if (game.playoffRoundName == null) return null
        val schedule = when {
            game.season == freeSeason -> games
            game.season < freeSeason -> priorGames
            else -> upcomingGames
        }
        return SeriesStatus.of(game, schedule)
    }

    fun game(id: String): Game? =
        games.firstOrNull { it.id == id } ?: upcomingGames.firstOrNull { it.id == id } ?: priorGames.firstOrNull { it.id == id }

    /** A team's game on the day the Games tab calls current, or null on an off night. */
    fun currentGame(team: String): Game? {
        val day = currentGameDay ?: return null
        return slateGames(day).firstOrNull { it.involves(team) }
    }

    /** Regular-season record from posted finals, "52-30", optionally through one game. A game from another season has none. */
    fun record(team: String, through: Game? = null): String? {
        if (through != null && through.season != freeSeason) return null
        val cutoff = through?.sortInstant ?: Instant.MAX
        val finals = games.filter { it.countsInStandings && it.isFinal && it.involves(team) && it.sortInstant <= cutoff }
        if (finals.isEmpty()) return null
        val results = finals.mapNotNull { it.result(team) }
        return "${results.count { it == "W" }}-${results.count { it == "L" }}"
    }

    /** Every game on a team's schedule in tip-off order: the live season, then the upcoming one while pending. */
    fun schedule(team: String): List<Game> = (games + upcomingGames).filter { it.involves(team) }.sortedBy { it.sortInstant }

    fun hasStats(game: Game): Boolean = game.id in gameIdsWithStats

    suspend fun fetchGameDetail(gameId: String): GameDetail? = provider.fetchGameDetail(gameId)

    suspend fun fetchGameLogs(gameId: String): List<PlayerGameLog> = provider.fetchGameLogs(gameId)

    /** The row for a game-log line, for names and links. */
    fun player(id: Int, season: Int, phase: SeasonPhase): Player? {
        val history = playerHistories[id].orEmpty()
        return history.firstOrNull { it.season == season && it.seasonPhase == phase } ?: history.firstOrNull { it.season == season }
    }

    // MARK: Recent form

    var recentFormByWindow by mutableStateOf<Map<Int, Map<Int, RecentForm>>>(emptyMap())
        private set
    var recentFormLoadingWindows by mutableStateOf<Set<Int>>(emptySet())
        private set
    var recentFormError by mutableStateOf<String?>(null)
        private set
    private var recentFormContext: String? = null
    private val recentFormTasks = HashMap<Int, Deferred<Unit>>()
    private var recentFormRowsByWindow by mutableStateOf<Map<Int, List<RecentForm>>>(emptyMap())

    /**
     * Two weeks (about seven games), so movement exists from the fifth week of the
     * season. Four left the paid board with nothing to rank through the first month.
     */
    var recentWindow by mutableStateOf(TrendWindow.TWO_WEEKS)

    /** True while a board shows recent form rather than season totals. */
    var showingRecent by mutableStateOf(false)

    fun recentForm(playerId: Int, window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null): RecentForm? {
        val s = season ?: selectedSeason
        val p = phase ?: selectedPhase
        return recentFormByWindow[(window ?: recentWindow).value]?.get(playerId)?.takeIf { it.season == s && it.seasonPhase == p }
    }

    val isRecentFormLoading: Boolean get() = recentWindow.value in recentFormLoadingWindows

    fun recentFormAsOf(window: TrendWindow, season: Int, phase: SeasonPhase): Instant? =
        recentFormRowsByWindow[window.value]?.filter { it.season == season && it.seasonPhase == phase }?.mapNotNull { it.asOf }?.maxOrNull()

    /** Every row for a window and side; a two-way player has one row per player_type. */
    fun recentFormRows(window: TrendWindow, playerType: String, season: Int, phase: SeasonPhase): List<RecentForm> =
        recentFormRowsByWindow[window.value].orEmpty().filter { it.playerType == playerType && it.season == season && it.seasonPhase == phase }

    /** The whole league's rows for a window, loading them first: a team's recent form is ranked against the others'. */
    suspend fun leagueRecentForm(window: TrendWindow, season: Int, phase: SeasonPhase): List<RecentForm> {
        loadRecentFormIfNeeded(window, season, phase)
        return recentFormRowsByWindow[window.value].orEmpty().filter { it.season == season && it.seasonPhase == phase }
    }

    /** After a new revision is adopted; in-flight requests can't repopulate a newer snapshot. */
    fun invalidateRecentFormCache() {
        recentFormTasks.values.forEach { it.cancel() }
        recentFormTasks.clear()
        recentFormLoadingWindows = emptySet()
        recentFormByWindow = emptyMap()
        recentFormRowsByWindow = emptyMap()
        recentFormContext = null
        recentFormError = null
    }

    suspend fun reloadRecentForm(window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null) {
        val target = window ?: recentWindow
        recentFormTasks.remove(target.value)?.cancel()
        recentFormByWindow = recentFormByWindow - target.value
        recentFormRowsByWindow = recentFormRowsByWindow - target.value
        recentFormError = null
        loadRecentFormIfNeeded(target, season, phase)
    }

    suspend fun loadRecentFormIfNeeded(window: TrendWindow? = null, season: Int? = null, phase: SeasonPhase? = null) {
        val target = window ?: recentWindow
        val targetSeason = season ?: selectedSeason
        val targetPhase = phase ?: selectedPhase
        val context = "$targetSeason-${targetPhase.raw}"
        if (recentFormContext != context) {
            recentFormTasks.values.forEach { it.cancel() }
            recentFormTasks.clear()
            recentFormLoadingWindows = emptySet()
            recentFormByWindow = emptyMap()
            recentFormRowsByWindow = emptyMap()
            recentFormContext = context
        }
        if (recentFormByWindow[target.value] != null) return
        recentFormTasks[target.value]?.let { runCatching { it.await() }; return }

        recentFormLoadingWindows = recentFormLoadingWindows + target.value
        recentFormError = null
        val task = scope.async {
            try {
                val rows = provider.fetchRecentForm(targetSeason, targetPhase, target.value)
                if (recentFormContext != context || !rows.all { it.season == targetSeason && it.seasonPhase == targetPhase }) return@async
                val byPlayer = HashMap<Int, RecentForm>()
                for (row in rows) {
                    val existing = byPlayer[row.playerId]
                    if (existing != null && existing.plays >= row.plays) continue
                    byPlayer[row.playerId] = row
                }
                recentFormByWindow = recentFormByWindow + (target.value to byPlayer)
                recentFormRowsByWindow = recentFormRowsByWindow + (target.value to rows)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                recentFormError = "Couldn't load recent form."
            } finally {
                recentFormLoadingWindows = recentFormLoadingWindows - target.value
            }
        }
        recentFormTasks[target.value] = task
        try {
            task.await()
        } catch (_: CancellationException) {
        } finally {
            if (recentFormTasks[target.value] === task) recentFormTasks.remove(target.value)
        }
    }

    /** Unique players for any season, for drill-downs opened from a player page. */
    fun players(season: Int, phase: SeasonPhase? = null): List<Player> = playersFor(season, phase ?: selectedPhase)

    private fun playersFor(season: Int, phase: SeasonPhase): List<Player> {
        val seen = HashSet<Int>()
        val out = ArrayList<Player>()
        for (history in playerHistories.values) {
            for (p in history) {
                if (p.season == season && p.seasonPhase == phase && seen.add(p.playerId)) out += p
            }
        }
        return out
    }

    /** Teams whose name or abbreviation matches the search: typing "celtics" is usually after Boston. */
    val searchedTeams: List<String>
        get() {
            val query = searchText.trim()
            if (query.isEmpty()) return emptyList()
            return teamsWithData.filter {
                selectedConference.contains(it) && (teamFullName(it).searchMatches(query) || it.searchMatches(query))
            }.sortedBy { teamFullName(it) }
        }

    private val eligibleMetrics: List<Metric> by derivedStateOf {
        val position = selectedPositionState
        seasonPlayers.filter { position.includes(it) }.flatMap { it.metrics }.filter { BasketballMetricRegistry.isSupported(it, position) }
    }

    val filteredPlayers: List<Player> get() = boardPlayers(searchText)

    private fun boardPlayers(search: String): List<Player> {
        val gateLabel = if (qualifierLevel == QualifierLevel.QUALIFIED) currentSortMetricLabelForGate else null
        val position = selectedPositionState
        return seasonPlayers.filter { player ->
            if (!player.matchesSearch(search) || !position.includes(player) || !matchesBoardFilters(player)) return@filter false
            val matching = player.metrics.filter { BasketballMetricRegistry.isSupported(it, position) }
            matching.isNotEmpty() && isQualifiedForBoard(player, matching, gateLabel)
        }
    }

    /** Conference, plus the rookie filter where it applies. */
    fun matchesBoardFilters(player: Player): Boolean {
        if (!selectedConference.contains(player.team)) return false
        return !isRookieFilterActive || isRookie(player)
    }

    /** Rookies are known for the live season only; profiles a season behind after the rollover don't count. */
    val canFilterRookies: Boolean get() = selectedSeason == freeSeason && profiles.values.any { it.season == freeSeason && it.isRookie }

    val isRookieFilterActive: Boolean get() = rookiesOnly && canFilterRookies

    /** "the 2026-27 Regular Season", or "the 2026-27 playoffs, which start in April" while the season is under way. */
    val selectedSeasonPhrase: String
        get() {
            if (selectedPhase == SeasonPhase.PLAYOFFS && selectedSeason == freeSeason &&
                players(selectedSeason, SeasonPhase.REGULAR).isNotEmpty()
            ) return "the ${SeasonLabel.display(selectedSeason)} playoffs, which start in April"
            return "the ${SeasonLabel.display(selectedSeason, selectedPhase)}"
        }

    /** A View-menu filter is narrowing the board. */
    val hasActiveBoardFilters: Boolean
        get() = isRookieFilterActive || selectedConference != LeagueConference.ALL || qualifierLevel == QualifierLevel.QUALIFIED

    fun clearBoardFilters() {
        rookiesOnly = false
        selectedConference = LeagueConference.ALL
        qualifierLevel = QualifierLevel.ALL
    }

    fun isRookie(player: Player): Boolean = profile(player)?.isRookie == true

    enum class QualifierLevel(val label: String, val description: String) {
        ALL("All Players", "Small samples dimmed"),
        QUALIFIED("Qualified", "Playing-time minimum");

        companion object {
            fun from(raw: String?): QualifierLevel? = entries.firstOrNull { it.label == raw }
        }
    }

    private var qualifierState by mutableStateOf(QualifierLevel.from(defaults.getString(QUALIFIER_KEY)) ?: QualifierLevel.ALL)

    /** All players by default, small samples dimmed below; Qualified hides them. */
    var qualifierLevel: QualifierLevel
        get() = qualifierState
        set(value) {
            qualifierState = value
            defaults.putString(QUALIFIER_KEY, value.label)
        }

    fun isQualified(player: Player, category: MetricCategory?): Boolean = when (qualifierLevel) {
        QualifierLevel.ALL -> true
        QualifierLevel.QUALIFIED -> isPlayerQualified(player, category)
    }

    /** Whether a player clears the bar, whatever the filter says: the feed's own prorated flag. */
    fun isPlayerQualified(player: Player, category: MetricCategory?): Boolean = hasQualifyingMetric(player, category)

    /** Per metric: a shooter over the minutes bar is not thereby qualified for a Corner 3% board. */
    fun isQualified(player: Player, metric: Metric): Boolean = metric.qualified != false

    private fun isQualifiedForBoard(player: Player, metrics: List<Metric>, sortLabel: String?): Boolean {
        if (qualifierLevel != QualifierLevel.QUALIFIED) return true
        if (sortLabel != null) metrics.firstOrNull { it.label == sortLabel }?.let { return isQualified(player, it) }
        return metrics.any { isQualified(player, it) }
    }

    private val currentSortMetricLabelForGate: String? get() = userSortMetricState ?: determineSortMetricLabel()

    val leaderboard: List<Player> get() = rankedBoard(searchText)

    /** Each player's place on the unsearched board while a search narrows it; null when nothing is searched. */
    val leaderboardRanks: Map<String, Int>?
        get() {
            if (searchText.isBlank()) return null
            val out = HashMap<String, Int>()
            rankedBoard("").forEachIndexed { index, player -> out.putIfAbsent(player.id, index + 1) }
            return out
        }

    private fun rankedBoard(search: String): List<Player> {
        val players = boardPlayers(search)
        val label = currentSortMetric
        val reference = label?.let { l -> eligibleMetrics.firstOrNull { it.label == l } }
        if (label == null || reference == null) return players.sortedBy { it.name }
        // A board ranked by one metric lists the players who have it; a searched name still shows, with a dash.
        val ranked = if (search.isNotBlank()) players
        else players.filter { p -> p.metrics.any { it.label == label && it.category == reference.category } }
        val sorted = ranked.sortedWith(
            metricComparator(label, reference.category, sortDescending, acrossCohorts = selectedPositionState == PlayerPositionGroup.ALL),
        )
        // Small samples go below the rest, so the top of a board is never a two-game call-up.
        val isSmall = { player: Player ->
            val metric = player.metrics.firstOrNull { it.label == label && it.category == reference.category }
            metric != null && !isQualified(player, metric)
        }
        return sorted.filterNot(isSmall) + sorted.filter(isSmall)
    }

    /** Board subtitle volume: "1,820 min". */
    fun volumeCaption(player: Player, category: MetricCategory?): String? = player.volumeCaption(category ?: player.primaryCategory)

    private fun determineSortMetricLabel(): String? {
        val position = selectedPositionState
        val preferred = position.preferredAdvancedMetrics + position.preferredTraditionalMetrics
        for (label in preferred) if (eligibleMetrics.any { it.label == label }) return label
        return availableSortMetrics.firstOrNull()
    }

    val currentSortMetricForDisplay: Pair<String?, MetricCategory?>
        get() {
            val label = currentSortMetric ?: return null to null
            val metric = eligibleMetrics.firstOrNull { it.label == label } ?: return null to null
            return label to metric.category
        }

    /** A team's roster, standouts first. */
    fun players(team: String): List<Player> {
        val normalized = normalizedTeamAbbreviation(team)
        return seasonPlayers.filter { normalizedTeamAbbreviation(it.team) == normalized }.sortedByDescending { it.overallPercentile }
    }

    fun teamScore(abbr: String): Double = teamScores[normalizedTeamAbbreviation(abbr)] ?: 0.0

    val qualifiedSeasonPlayers: List<Player>
        get() = seasonPlayers.filter { player ->
            val categories = player.metrics.map { it.category }.toSet()
            if (categories.isEmpty()) isQualified(player, null as MetricCategory?) else categories.any { isQualified(player, it) }
        }

    data class MetricExtreme(val player: Player, val percentile: Int, val actualValue: String)
    data class MetricLeaderEntry(val label: String, val category: MetricCategory, val best: MetricExtreme?, val worst: MetricExtreme?)

    /** Best and worst by percentile (direction-correct), never by parsing values. */
    val allMetrics: List<MetricLeaderEntry>
        get() {
            val map = LinkedHashMap<String, Pair<MetricCategory, MutableList<MetricExtreme>>>()
            for (player in seasonPlayers) {
                if (!matchesBoardFilters(player)) continue
                for (metric in player.metrics) {
                    if (!isQualified(player, metric.category)) continue
                    val key = "${metric.label}|${metric.category.raw}"
                    map.getOrPut(key) { metric.category to mutableListOf() }.second += MetricExtreme(player, metric.percentile, metric.value)
                }
            }
            return map.mapNotNull { (key, data) ->
                val label = key.substringBefore("|")
                // Percentiles rank within a position group, so across cohorts the raw
                // value decides when every entry has one: a center's 99th-percentile
                // AST% is not the league's best passer.
                val lowerBetter = lowerIsBetter(label, data.first)
                val values = data.second
                val allNumeric = values.all { rawNumeric(it.actualValue) != null }
                val byPercentile = if (allNumeric) {
                    values.sortedWith { x, y ->
                        val a = rawNumeric(x.actualValue) ?: 0.0
                        val b = rawNumeric(y.actualValue) ?: 0.0
                        if (lowerBetter) b.compareTo(a) else a.compareTo(b)
                    }
                } else values.sortedBy { it.percentile }
                val best = byPercentile.lastOrNull() ?: return@mapNotNull null
                val worst = byPercentile.firstOrNull()
                MetricLeaderEntry(label, data.first, best, if (worst?.player?.id == best.player.id) null else worst)
            }.sortedBy { it.label }
        }

    // MARK: Loading

    suspend fun loadIfNeeded() {
        if (hasStartedLoading) return
        hasStartedLoading = true
        load()
    }

    suspend fun load() {
        loadTask?.let { it.await(); return }
        val task = scope.async { performLoad() }
        loadTask = task
        isRefreshing = true
        try {
            task.await()
        } finally {
            if (loadTask === task) loadTask = null
            isRefreshing = freshnessCheckTask != null
        }
    }

    /** A changed ready revision triggers a full load; otherwise just the schedule. */
    suspend fun refreshOnForeground(now: Instant = clock()) {
        val interval = if (dataFreshness?.status == DataFreshnessStatus.PENDING) 120L else 300L
        lastForegroundCheckAt?.let { if (Duration.between(it, now).seconds < interval) return }
        lastForegroundCheckAt = now
        if (checkForUpdates(false) == FreshnessCheckResult.UPDATED) load() else loadGames()
    }

    suspend fun checkForUpdates(force: Boolean = false): FreshnessCheckResult {
        freshnessCheckTask?.let { return it.await() }
        val last = lastStatusCheckAt
        val interval = if (dataFreshness?.status == DataFreshnessStatus.PENDING) 120L else 300L
        if (!force && last != null && Duration.between(last, clock()).seconds < interval) return FreshnessCheckResult.THROTTLED
        val task = scope.async { performFreshnessCheck() }
        freshnessCheckTask = task
        isRefreshing = true
        return try {
            task.await()
        } finally {
            if (freshnessCheckTask === task) freshnessCheckTask = null
            isRefreshing = loadTask != null
        }
    }

    private suspend fun performFreshnessCheck(): FreshnessCheckResult {
        val now = clock()
        lastStatusCheckAt = now
        localLastCheckedAt = now
        return try {
            // The endpoint is optional while the backend rolls out; the player load stays the source of truth.
            val remote = provider.fetchDataFreshness() ?: return FreshnessCheckResult.UNAVAILABLE
            // The season rollover rides on this one row.
            applyLive(StatScoutSeason.resolveLive(remote, live.season))
            // A pending next season is not a problem with the data on screen: the
            // published revision is final, so it reads as ready.
            val status = if (remote.isSeasonPending) DataFreshnessStatus.READY else remote.status
            dataFreshness = (if (status == remote.status) remote else remote.withStatus(status))
                .copy(checkedAt = remote.checkedAt ?: now, isCached = false)
            persistFreshness()
            when (status) {
                DataFreshnessStatus.READY ->
                    if (remote.revision != null && remote.revision != displayedDataRevision) FreshnessCheckResult.UPDATED else FreshnessCheckResult.UNCHANGED
                DataFreshnessStatus.PENDING -> FreshnessCheckResult.PENDING
                DataFreshnessStatus.PARTIAL ->
                    if (remote.revision != null && remote.revision != displayedDataRevision) FreshnessCheckResult.UPDATED else FreshnessCheckResult.PARTIAL
                DataFreshnessStatus.STALE -> FreshnessCheckResult.STALE
                DataFreshnessStatus.CHECKING -> FreshnessCheckResult.UNCHANGED
                DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> FreshnessCheckResult.FAILED
            }
        } catch (_: CancellationException) {
            FreshnessCheckResult.FAILED
        } catch (_: Throwable) {
            dataFreshness?.let { existing ->
                dataFreshness = existing.copy(
                    status = DataFreshnessStatus.OFFLINE,
                    checkedAt = now,
                    message = "We couldn't check for new game data.",
                    isCached = true,
                )
                persistFreshness()
            }
            FreshnessCheckResult.FAILED
        }
    }

    /**
     * Adopts a newly resolved live season. The selected season follows it when the
     * user was on the old live one, so a rollover moves the app on by itself; a
     * user browsing history stays where they are.
     */
    private fun applyLive(resolved: StatScoutSeason.Live) {
        if (resolved == live) return
        val old = live
        live = resolved
        StatScoutSeason.remember(resolved, defaults)
        if (selectedSeason == old.season) {
            selectedSeason = resolved.season
            // A new season opens on its regular season: its playoffs are months away.
            selectedPhase = SeasonPhase.REGULAR
        }
        clampSelectedSeason()
        invalidateRecentFormCache()
        // Old ratings beside the new season's records would pass for its own.
        if (resolved.season != old.season) {
            teamRatings = emptyMap()
            gamesLoadedAt = null
        }
    }

    private suspend fun performLoad() {
        hasStartedLoading = true
        // The schedule does not depend on the player snapshot, so scores and standings load alongside it.
        scope.launch { loadGames() }
        isLoading = players.isEmpty()
        loadingMessage = if (players.isEmpty()) "Loading saved players…" else "Refreshing player data…"
        loadingProgress = if (players.isEmpty()) 0.12 else 0.2

        val started = System.currentTimeMillis()
        val cached = withContext(io) { runCatching { cache?.loadCurrentPlayers() }.getOrNull().orEmpty() }
        log("cache ${cached.size} players in ${System.currentTimeMillis() - started}ms")
        if (players.isEmpty() && cached.isNotEmpty()) ingestPlayers(cached)

        loadingMessage = "Checking for updates…"
        loadingProgress = 0.45
        isLoading = players.isEmpty()
        errorMessage = null
        lastFetchFailed = false
        lastFailureWasConnectivity = false

        val freshnessResult = checkForUpdates(true)
        log("status $freshnessResult at ${System.currentTimeMillis() - started}ms")
        val revisionAtStart = dataFreshness?.revision

        var acceptedCurrent: List<Player> = emptyList()
        var loadedCurrentData = false
        var playersToIngest: List<Player> = emptyList()

        var drewLeaderboardEarly = false
        try {
            val liveSeason = live.season
            val current = provider.fetchCurrentPlayers(liveSeason)
            log("fetched ${current.size} players at ${System.currentTimeMillis() - started}ms")
            val fallback = cached.ifEmpty { playerHistories.values.flatten() }
            val hasCompleteFallback = PlayerSnapshotValidator.isCompleteCurrent(fallback, liveSeason)
            val passes = PlayerSnapshotValidator.isCompleteCurrent(current, liveSeason)
            acceptedCurrent = if (passes || !hasCompleteFallback) current else emptyList()
            // Without the status endpoint, a regression can still clear the minimum: keep the complete cache.
            if (acceptedCurrent.isNotEmpty() &&
                (freshnessResult == FreshnessCheckResult.UNAVAILABLE || freshnessResult == FreshnessCheckResult.FAILED) &&
                hasUnsafeSnapshotRegression(current, fallback)
            ) acceptedCurrent = emptyList()
            val all = if (acceptedCurrent.isEmpty()) fallback else mergePlayers(acceptedCurrent)

            if (all.isEmpty()) {
                // Offseason, cold cache or offline: the bundled season is the board, not an empty state.
                showBundledSeasonIfNothingIsShown()
                if (players.isEmpty()) {
                    errorMessage = "No players found."
                    lastFetchFailed = true
                }
            } else {
                loadingMessage = "Preparing leaderboard…"
                loadingProgress = 0.85
                playersToIngest = all
                if (acceptedCurrent.isNotEmpty()) loadedCurrentData = true
                else if (current.isNotEmpty()) {
                    errorMessage = "Showing complete saved data while the live feed finishes updating."
                    lastFetchFailed = true
                }
                // Nothing is on screen yet: draw now rather than after two more round trips.
                if (players.isEmpty()) {
                    ingestPlayers(all)
                    drewLeaderboardEarly = true
                    isLoading = false
                    loadingProgress = 1.0
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            showBundledSeasonIfNothingIsShown()
            lastFetchFailed = true
            when (error) {
                is DataFormatException, is SerializationException -> errorMessage = "Data format changed - app may need an update."
                is IOException -> {
                    errorMessage = if (players.isEmpty()) "Can't reach data feed. Check your connection."
                    else "Showing saved data. Pull to refresh when your connection improves."
                    lastFailureWasConnectivity = true
                }
                else -> errorMessage = if (players.isEmpty()) "Something went wrong loading player data."
                else "Showing saved data. Pull to refresh to try again."
            }
        }
        isLoading = false
        loadingProgress = 1.0
        log("board ready at ${System.currentTimeMillis() - started}ms")

        // Off the critical path: only the About sheet reads it.
        val candidateCoverage = runCatchingNonCancel { provider.fetchDataCoverage(freeSeason) }

        // Bracket the candidate with a second status read so a new revision can't pair with older rows.
        val endingResult = checkForUpdates(true)
        val revisionAtEnd = dataFreshness?.revision
        val drifted = revisionAtStart != null && revisionAtEnd != null && revisionAtEnd != revisionAtStart
        if (drifted) {
            playersToIngest = emptyList()
            acceptedCurrent = emptyList()
            loadedCurrentData = false
            dataFreshness?.let {
                dataFreshness = it.copy(
                    status = DataFreshnessStatus.CHECKING,
                    message = "A newer game revision arrived while this update was loading.",
                    isCached = true,
                )
            }
        } else if (playersToIngest.isNotEmpty() && !drewLeaderboardEarly) {
            // Past seasons can finish loading during the awaits above; merge again so they survive.
            ingestPlayers(if (acceptedCurrent.isEmpty()) playersToIngest else mergePlayers(acceptedCurrent))
        }
        if (loadedCurrentData) {
            dataCoverage = dataFreshness?.coverage ?: candidateCoverage
            val toSave = acceptedCurrent
            val saveSeason = live.season
            withContext(io) { runCatching { cache?.saveCurrentPlayers(toSave, saveSeason) } }
            adoptLoadedRevision(acceptedCurrent, canUseServerRevision(freshnessResult, endingResult))
        } else if (lastFetchFailed) {
            dataFreshness?.let {
                dataFreshness = it.copy(
                    status = DataFreshnessStatus.FAILED,
                    message = errorMessage ?: "Showing saved data while the latest refresh is retried.",
                    isCached = true,
                )
            }
        }
        persistFreshness()
        loadProfiles()
        loadGames(force = true)
    }

    /** Draws the newest bundled season (no later than the live one) when nothing else is on screen. */
    private suspend fun showBundledSeasonIfNothingIsShown() {
        if (players.isNotEmpty()) return
        val season = live.season
        val rows = withContext(io) { runCatching { cache?.loadNewestBundledSeason(season) }.getOrNull().orEmpty() }
        if (players.isNotEmpty() || rows.isEmpty()) return
        ingestPlayers(rows)
    }

    private fun adoptLoadedRevision(loaded: List<Player>, useServerRevision: Boolean) {
        val current = dataFreshness
        val candidate = if (useServerRevision &&
            (current?.status == DataFreshnessStatus.READY || current?.status == DataFreshnessStatus.PARTIAL) &&
            current.revision != null
        ) current.revision else fallbackRevision(loaded, dataCoverage)
        candidate ?: return
        val changed = displayedDataRevision != candidate
        displayedDataRevision = candidate
        if (changed) invalidateRecentFormCache()
        dataFreshness = if (current != null) {
            current.copy(
                status = if (current.status == DataFreshnessStatus.CHECKING) DataFreshnessStatus.READY else current.status,
                revision = if (useServerRevision) current.revision else candidate,
                coverage = dataCoverage,
                isCached = false,
            )
        } else {
            DataFreshness(status = DataFreshnessStatus.READY, revision = candidate, checkedAt = localLastCheckedAt ?: clock(), coverage = dataCoverage)
        }
    }

    private fun canUseServerRevision(initial: FreshnessCheckResult, ending: FreshnessCheckResult): Boolean {
        val allowed = setOf(FreshnessCheckResult.UPDATED, FreshnessCheckResult.UNCHANGED, FreshnessCheckResult.PARTIAL)
        return initial in allowed && ending in allowed
    }

    private fun fallbackRevision(players: List<Player>, coverage: DataCoverage?): String? {
        val latest = players.maxOfOrNull { it.updatedAt } ?: return null
        return "players-${latest.epochSecond}-week-${coverage?.week ?: 0}-asof-${coverage?.asOf?.epochSecond ?: 0}"
    }

    private fun hasUnsafeSnapshotRegression(candidate: List<Player>, fallback: List<Player>): Boolean {
        val season = live.season
        val fallbackCurrent = fallback.filter { it.season == season && it.seasonPhase == SeasonPhase.REGULAR }
        val candidateCurrent = candidate.filter { it.season == season && it.seasonPhase == SeasonPhase.REGULAR }
        if (fallbackCurrent.isEmpty() || candidateCurrent.isEmpty()) return false
        val fallbackTeams = fallbackCurrent.map { normalizedTeamAbbreviation(it.team) }.toSet()
        val candidateTeams = candidateCurrent.map { normalizedTeamAbbreviation(it.team) }.toSet()
        if (!candidateTeams.containsAll(fallbackTeams)) return true
        val fallbackIds = fallbackCurrent.map { it.playerId }.toSet()
        val candidateIds = candidateCurrent.map { it.playerId }.toSet()
        val missing = (fallbackIds - candidateIds).size
        return missing.toDouble() / fallbackIds.size > 0.20
    }

    private fun persistFreshness() {
        if (cache == null) return
        val freshness = dataFreshness ?: return
        DataFreshnessCache.save(freshness.copy(coverage = dataCoverage), displayedDataRevision, defaults)
    }

    suspend fun loadHistoricalIfNeeded() {
        if (hasLoadedHistorical || isHistoricalLoading) return
        isHistoricalLoading = true
        loadingMessage = "Loading past seasons…"
        loadingProgress = 0.12

        // The past season the user is looking at comes first, on its own: one
        // season decodes in a fraction of a second, the whole archive in several.
        val wanted = selectedSeason
        if (wanted != live.season && !hasSeasonLoaded(wanted)) {
            val first = withContext(io) { runCatching { cache?.loadHistoricalSeason(wanted) }.getOrNull().orEmpty() }
            if (first.isNotEmpty()) ingestPlayers(mergePlayers(first))
        }

        var historical = withContext(io) { runCatching { cache?.loadHistoricalPlayers() }.getOrNull().orEmpty() }
        // Fixture providers may disable the cache; fetch their history directly.
        if (historical.isEmpty()) historical = runCatchingNonCancel { provider.fetchHistoricalPlayers(live.season) }.orEmpty()
        loadingMessage = "Preparing season history…"
        loadingProgress = 0.78
        if (historical.isNotEmpty()) {
            // The archive carries the live season too. Server rows already loaded win:
            // archive rows from the live season only fill in what is absent. No suspension
            // between here and ingest, so a newer ingest is never overwritten.
            val loadedIds = playerHistories.values.flatten().map { it.id }.toSet()
            val liveSeason = live.season
            val archive = historical.filter { (it.season ?: 0) < liveSeason || it.id !in loadedIds }
            ingestPlayers(mergePlayers(archive))
            hasLoadedHistorical = true
        }
        isHistoricalLoading = false
        loadingProgress = 1.0
    }

    private fun hasSeasonLoaded(season: Int): Boolean = playerHistories.values.any { h -> h.any { it.season == season } }

    private fun ingestPlayers(all: List<Player>) {
        val grouped = all.groupBy { it.playerId }
        val histories = HashMap<Int, List<Player>>(grouped.size)
        val latest = ArrayList<Player>(grouped.size)
        for ((id, history) in grouped) {
            val sorted = history.sortedWith { a, b ->
                val s1 = a.season
                val s2 = b.season
                when {
                    s1 == null && s2 == null -> 0
                    s1 == null -> 1
                    s2 == null -> -1
                    s1 == s2 && a.seasonPhase != b.seasonPhase -> if (a.seasonPhase == SeasonPhase.REGULAR) -1 else 1
                    else -> s2.compareTo(s1)
                }
            }
            histories[id] = sorted
            sorted.firstOrNull()?.let(latest::add)
        }
        playerHistories = histories
        players = latest
    }

    private fun mergePlayers(replacements: List<Player>): List<Player> {
        val merged = LinkedHashMap<String, Player>()
        for (history in playerHistories.values) for (p in history) merged[p.id] = p
        for (p in replacements) merged[p.id] = p
        return merged.values.toList()
    }

    companion object {
        private const val QUALIFIER_KEY = "stats.qualifier"

        fun hasQualifyingMetric(player: Player, category: MetricCategory?): Boolean =
            player.metrics.any { (category == null || it.category == category) && it.qualified != false }

        /**
         * Rank by the direction-correct percentile; the raw number only breaks a tied
         * bucket. `acrossCohorts` is the All board: a percentile only means something
         * within a cohort, so there the raw number leads and the percentile breaks ties.
         */
        fun metricComparator(label: String, category: MetricCategory, descending: Boolean, acrossCohorts: Boolean = false): Comparator<Player> {
            val percentileDescending = descending != lowerIsBetter(label, category)
            return Comparator { first, second ->
                val a = first.metrics.firstOrNull { it.label == label && it.category == category }
                val b = second.metrics.firstOrNull { it.label == label && it.category == category }
                val crossA = if (acrossCohorts) a?.let { metricNumericValue(it.value) } else null
                val crossB = if (acrossCohorts) b?.let { metricNumericValue(it.value) } else null
                when {
                    a == null && b == null -> first.name.compareTo(second.name)
                    a == null -> 1
                    b == null -> -1
                    crossA != null && crossB != null && crossA != crossB ->
                        if (descending) crossB.compareTo(crossA) else crossA.compareTo(crossB)
                    a.percentile != b.percentile ->
                        if (percentileDescending) b.percentile.compareTo(a.percentile) else a.percentile.compareTo(b.percentile)
                    else -> {
                        val av = metricNumericValue(a.value)
                        val bv = metricNumericValue(b.value)
                        if (av != null && bv != null && av != bv) {
                            if (descending) bv.compareTo(av) else av.compareTo(bv)
                        } else first.name.compareTo(second.name)
                    }
                }
            }
        }

        fun rawNumeric(value: String): Double? = metricNumericValue(value)

        fun lowerIsBetter(label: String, category: MetricCategory): Boolean =
            BasketballMetricRegistry.definition(label, category)?.higherIsBetter?.not() ?: false

        fun defaultSortDescending(label: String?, category: MetricCategory?): Boolean {
            if (label == null || category == null) return true
            return !lowerIsBetter(label, category)
        }
    }
}

/** The last known-good status, kept apart from the player cache so a failed check can't replace good data. */
object DataFreshnessCache {
    private const val KEY = "statcast.dataFreshness"
    private const val DISPLAYED_REVISION_KEY = "statcast.displayedDataRevision"

    fun load(defaults: KeyValueStore): DataFreshness? {
        val text = defaults.getString(KEY) ?: return null
        return runCatching { DataFreshness.fromJson(Json.parseToJsonElement(text) as JsonObject) }.getOrNull()
    }

    fun save(freshness: DataFreshness, displayedRevision: String?, defaults: KeyValueStore) {
        defaults.putString(KEY, freshness.toJson().toString())
        if (displayedRevision != null) defaults.putString(DISPLAYED_REVISION_KEY, displayedRevision) else defaults.remove(DISPLAYED_REVISION_KEY)
    }

    fun loadDisplayedRevision(defaults: KeyValueStore): String? = defaults.getString(DISPLAYED_REVISION_KEY)
}

/** `try?` that still lets cancellation through. */
internal suspend fun <T> runCatchingNonCancel(block: suspend () -> T): T? = try {
    block()
} catch (error: CancellationException) {
    throw error
} catch (_: Throwable) {
    null
}
