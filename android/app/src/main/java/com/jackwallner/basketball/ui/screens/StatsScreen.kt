package com.jackwallner.basketball.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import com.jackwallner.basketball.ui.components.HardwoodTabs
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.data.KeyValueStore
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricCoverage
import com.jackwallner.basketball.model.LeagueConference
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.StandardStatSemantics
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.competitionRanks
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.metricValue
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.HomeTopBar
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.SeasonPhaseNavPill
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.ChipButton
import com.jackwallner.basketball.ui.components.ChipTrailing
import com.jackwallner.basketball.ui.components.DataFreshnessView
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodChip
import com.jackwallner.basketball.ui.components.HardwoodMenu
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.InfoNote
import com.jackwallner.basketball.ui.components.LeaderboardTableHeader
import com.jackwallner.basketball.ui.components.LeaderboardTableRow
import com.jackwallner.basketball.ui.components.LoadingCard
import com.jackwallner.basketball.ui.components.LoadingStatusBar
import com.jackwallner.basketball.ui.components.MenuItem
import com.jackwallner.basketball.ui.components.MenuSection
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.SortDirectionButton
import com.jackwallner.basketball.ui.components.StatOption
import com.jackwallner.basketball.ui.components.StatPickerMenu
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.cardSlice
import com.jackwallner.basketball.ui.components.gateBlur
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.nav.rememberRetained
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.theme.TeamColor
import kotlinx.coroutines.launch

/** Which league-wide board the Stats tab is drawing. */
enum class StatsBoard { ADVANCED, STANDARD, BEST_WORST }

/** Traditional production stats offered for each position group: the `standard_stats` labels in the hoopR contract. */
object StandardStatCatalog {
    private val EVERYONE = listOf("PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MPG", "MIN", "G", "GS")

    fun stats(position: PlayerPositionGroup): List<String> {
        val lead = when (position) {
            PlayerPositionGroup.ALL, PlayerPositionGroup.FORWARD -> "PPG"
            PlayerPositionGroup.GUARD -> "APG"
            PlayerPositionGroup.CENTER -> "RPG"
        }
        return listOf(lead) + EVERYONE.filter { it != lead }
    }

    /** Best first: turnovers and fouls read better low, so their boards open lowest-first. */
    @Suppress("UNUSED_PARAMETER")
    fun defaultDescending(stat: String, position: PlayerPositionGroup): Boolean = StandardStatSemantics.higherIsBetter(stat)

    fun defaultStat(position: PlayerPositionGroup): String = stats(position).firstOrNull() ?: "G"

    /** A stat picked on purpose follows to any position that offers it; a default does not. */
    fun stat(current: String, from: PlayerPositionGroup, to: PlayerPositionGroup): String =
        if (current != defaultStat(from) && current in stats(to)) current else defaultStat(to)
}

/** The Stats tab's shared board state, kept across pushes like iOS `@State`. */
@Stable
class StatsBoardState(private val defaults: KeyValueStore) {
    private var boardState by mutableStateOf(
        StatsBoard.entries.firstOrNull { it.name == defaults.getString(BOARD_KEY) } ?: StatsBoard.ADVANCED,
    )
    var board: StatsBoard
        get() = boardState
        set(value) {
            boardState = value
            defaults.putString(BOARD_KEY, value.name)
        }
    var standardStat by mutableStateOf("PPG")
    var standardSortDescending by mutableStateOf(true)

    /** The leaderboard Best & Worst was opened from, so Leaderboard goes back to it. */
    var boardBeforeBestWorst: StatsBoard
        get() = StatsBoard.entries.firstOrNull { it.name == defaults.getString(BEFORE_KEY) } ?: StatsBoard.ADVANCED
        set(value) = defaults.putString(BEFORE_KEY, value.name)

    private companion object {
        const val BOARD_KEY = "stats.board"
        const val BEFORE_KEY = "stats.board.beforeBestWorst"
    }
}

/** Single home for every league-wide statistic. */
@Composable
fun StatsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val actions = LocalAppActions.current
    val state = rememberRetained("statsBoard") { StatsBoardState(graph.defaults) }
    var showingFollowing by remember { mutableStateOf(false) }

    // Position changes: keep a chosen stat, fall back from Advanced where a cohort has none.
    var lastPosition by remember { mutableStateOf(vm.selectedPosition) }
    LaunchedEffect(vm) {
        snapshotFlow { vm.selectedPosition }.collect { next ->
            val old = lastPosition
            lastPosition = next
            if (old == next) return@collect
            val kept = StandardStatCatalog.stat(state.standardStat, old, next)
            if (kept != state.standardStat) {
                state.standardStat = kept
                state.standardSortDescending = StandardStatCatalog.defaultDescending(kept, next)
            }
        }
    }
    // The board choice persists; a free user who peeked at the Best & Worst gate must not relaunch onto it.
    val isPro = graph.subscriptions.isPro
    LaunchedEffect(Unit) {
        if (!isPro && state.board == StatsBoard.BEST_WORST) state.board = StatsBoard.ADVANCED
    }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HomeTopBar(leading = {
            SeasonPhaseNavPill(vm.availableSeasons) { actions.openTrialPitch(PaywallTrigger.LockedSeason(it)) }
        })
        if (vm.selectedSeason == vm.freeSeason && vm.selectedPhase == SeasonPhase.REGULAR) {
            DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 4.dp))
        }
        HardwoodSegmented(
            segments = listOf(Segment(false, "League leaders"), Segment(true, "Following", icon = "star.fill")),
            selection = showingFollowing,
            onSelect = { showingFollowing = it },
            modifier = Modifier.padding(horizontal = 12.dp),
        )
        if (showingFollowing) FollowingStatsView(vm)
        else when (state.board) {
            StatsBoard.ADVANCED -> AdvancedBoard(vm, state)
            StatsBoard.STANDARD -> StandardStatsLeadersView(
                players = vm.qualifiedSeasonPlayers.filter { vm.selectedPosition.includes(it) && vm.matchesBoardFilters(it) },
                selectedStat = state.standardStat,
                onSelectStat = { state.standardStat = it },
                selectedPosition = vm.selectedPosition,
                onSelectPosition = { vm.selectedPosition = it },
                sortDescending = state.standardSortDescending,
                onSortDescending = { state.standardSortDescending = it },
                boardState = state,
                viewModel = vm,
            )
            StatsBoard.BEST_WORST -> BestWorstBoard(vm, state)
        }
    }
}

@Composable
private fun BestWorstBoard(vm: DashboardViewModel, state: StatsBoardState) {
    val isPro = LocalGraph.current.subscriptions.isPro
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 4.dp)) { StatsViewMenu(vm, state) }
        if (isPro) MetricLeadersView(vm.allMetrics)
        else Box(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize().gateBlur()) { MetricLeadersView(vm.allMetrics, interactive = false) }
            BlurGateUnlock(
                "See who leads and who trails on every metric in the league",
                PaywallTrigger.BestWorst,
                Modifier.align(Alignment.BottomCenter).padding(horizontal = 12.dp).padding(bottom = 100.dp),
            )
        }
    }
}

/** Picking a statistic also selects the vocabulary that owns it. */
@Composable
fun StatsBoardStatPicker(vm: DashboardViewModel, state: StatsBoardState) {
    val position = vm.selectedPosition
    val active = when (state.board) {
        StatsBoard.ADVANCED -> vm.currentSortMetric ?: vm.sortLabel
        StatsBoard.STANDARD -> state.standardStat
        StatsBoard.BEST_WORST -> "Best & Worst"
    }
    StatPickerMenu(
        activeLabel = active,
        advanced = StatOption.categorized(
            vm.availableAdvancedSortMetrics,
            if (state.board == StatsBoard.ADVANCED) vm.currentSortMetric else null,
        ),
        standard = StandardStatCatalog.stats(position).map {
            StatOption(it, it, state.board == StatsBoard.STANDARD && it == state.standardStat)
        },
        onSelectAdvanced = {
            state.board = StatsBoard.ADVANCED
            vm.setUserSortMetric(it.id)
        },
        onSelectStandard = {
            state.board = StatsBoard.STANDARD
            state.standardStat = it.id
            state.standardSortDescending = StandardStatCatalog.defaultDescending(it.id, position)
        },
    )
}

/** Secondary board options: conference, rookies, qualifier, and Best & Worst. */
@Composable
fun StatsViewMenu(vm: DashboardViewModel, state: StatsBoardState) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val board = state.board
    val isActive = vm.qualifierLevel != DashboardViewModel.QualifierLevel.ALL || vm.selectedConference != LeagueConference.ALL ||
        vm.isRookieFilterActive || board == StatsBoard.BEST_WORST
    val leaderboard = board != StatsBoard.BEST_WORST
    HardwoodMenu(
        listOfNotNull(
            // What the board is first, then how it is filtered.
            MenuSection("Show", listOf(
                MenuItem("Leaderboard", checked = leaderboard) { if (!leaderboard) state.board = state.boardBeforeBestWorst },
                MenuItem(
                    if (isPro || board == StatsBoard.BEST_WORST) "Best & Worst" else "Best & Worst (StatScout+)",
                    checked = board == StatsBoard.BEST_WORST,
                    locked = !isPro && board != StatsBoard.BEST_WORST,
                ) {
                    if (board != StatsBoard.BEST_WORST) state.boardBeforeBestWorst = board
                    state.board = StatsBoard.BEST_WORST
                },
            )),
            MenuSection("Conference", LeagueConference.entries.map { c ->
                MenuItem(c.label, checked = c == vm.selectedConference) { vm.selectedConference = c }
            }),
            if (vm.canFilterRookies) MenuSection("Players", listOf(false, true).map { rookies ->
                MenuItem(if (rookies) "Rookies only" else "Everyone", checked = rookies == vm.rookiesOnly) { vm.rookiesOnly = rookies }
            }) else null,
            MenuSection("Qualifier", DashboardViewModel.QualifierLevel.entries.map { level ->
                MenuItem("${level.label} · ${level.description}", checked = level == vm.qualifierLevel) { vm.qualifierLevel = level }
            }),
        ),
        Modifier.testTag("viewMenu"),
    ) { open ->
        ChipButton(open, description = "View options") {
            HardwoodChip(title = "View", icon = "slider.horizontal.3", trailing = ChipTrailing.Chevron, isActive = isActive)
        }
    }
}

/** The stat picker, direction, search toggle and View menu row every board shares. */
@Composable
fun BoardControlRow(
    picker: @Composable () -> Unit,
    descending: Boolean,
    statLabel: String,
    onToggleDirection: () -> Unit,
    isSearchActive: Boolean,
    onToggleSearch: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        Modifier.fillMaxWidth().padding(top = HardwoodGeo.controlRowGap - 6.dp).padding(end = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(start = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            picker()
            SortDirectionButton(descending, statLabel, onToggleDirection)
        }
        ChipButton(onToggleSearch, description = "Search players", modifier = Modifier.testTag("searchToggle")) {
            HardwoodChip(icon = "magnifyingglass", isActive = isSearchActive)
        }
        trailing?.invoke()
    }
}

@Composable
fun SearchRow(text: String, onTextChange: (String) -> Unit, onCancel: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SearchField(text, onTextChange, Modifier.weight(1f), focusOnAppear = true)
        TextAction("Cancel", HardwoodType.small, HardwoodPalette.court, onCancel)
    }
}

/** The Advanced leaderboard (iOS `DashboardView`). */
@Composable
private fun AdvancedBoard(vm: DashboardViewModel, state: StatsBoardState) {
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val store = LocalGraph.current.subscriptions
    val haptic = rememberHaptic()
    var isSearching by remember { mutableStateOf(false) }
    val activeSearch = isSearching || vm.searchText.isNotEmpty()

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            if ((vm.isLoading || vm.isHistoricalLoading) && vm.players.isNotEmpty()) {
                LoadingStatusBar(vm.loadingMessage, vm.loadingProgress, Modifier.padding(top = 8.dp))
            }
            HardwoodTabs(
                PlayerPositionGroup.entries.map { it.raw },
                vm.selectedPosition.raw,
                { raw -> PlayerPositionGroup.entries.firstOrNull { it.raw == raw }?.let { if (it != vm.selectedPosition) vm.selectedPosition = it } },
                Modifier.padding(top = 8.dp).semantics { contentDescription = "Position" },
            )
            if (vm.players.isNotEmpty()) {
                BoardControlRow(
                    picker = { StatsBoardStatPicker(vm, state) },
                    descending = vm.sortDescending,
                    statLabel = vm.currentSortMetric ?: vm.sortLabel,
                    onToggleDirection = vm::toggleSortDirection,
                    isSearchActive = activeSearch,
                    onToggleSearch = {
                        isSearching = !isSearching
                        if (!isSearching) vm.searchText = ""
                        haptic()
                    },
                    trailing = { StatsViewMenu(vm, state) },
                )
                AnimatedVisibility(activeSearch) {
                    SearchRow(vm.searchText, { vm.searchText = it }) {
                        isSearching = false
                        vm.searchText = ""
                    }
                }
            }
            RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
                val sort = vm.currentSortMetricForDisplay
                val leaderboard = vm.leaderboard
                val ranks = competitionRanks(
                    leaderboard.map { player ->
                        val label = sort.first
                        val category = sort.second
                        if (label == null || category == null) null else metricValue(player, label, category)
                    },
                )
                // League rank while searching; 0 (a dash) for a match the board can't rank.
                val searchRanks = vm.leaderboardRanks
                val listState = rememberLazyListState()
                // A new ranking starts at its top, not at the old one's row 40.
                val boardKey = "${vm.selectedPosition.raw}-${vm.currentSortMetric}-${vm.sortDescending}-${vm.selectedSeason}-${vm.selectedPhase.raw}"
                LaunchedEffect(boardKey) { listState.scrollToItem(0) }
                LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = bottomBarPadding()) {
                    if (vm.players.isNotEmpty() && activeSearch) item { TeamResults(vm.searchedTeams.take(3)) }
                    item { Spacer(Modifier.height(8.dp)) }
                    val status = boardStatus(vm, leaderboard.isEmpty())
                    if (status != null) {
                        item { Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, true)) { status() } }
                    } else {
                        item {
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, leaderboard.isEmpty())) {
                                LeaderboardTableHeader(vm.sortDescending, vm.currentSortMetric ?: vm.sortLabel, onToggleDirection = vm::toggleSortDirection)
                            }
                        }
                        itemsIndexed(leaderboard, key = { _, p -> p.id }) { index, player ->
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == leaderboard.lastIndex)) {
                                LeaderboardTableRow(
                                    rank = searchRanks?.let { it[player.id] ?: 0 } ?: ranks[index],
                                    player = player,
                                    stripe = index,
                                    metricLabel = sort.first,
                                    metricCategory = sort.second,
                                    volume = vm.volumeCaption(player, sort.second),
                                    isSmallSample = isSmallSample(vm, player, sort.first, sort.second),
                                ) { navigator.push(Route.PlayerProfile(player)) }
                            }
                        }
                    }
                    if (vm.players.isNotEmpty()) {
                        item { Spacer(Modifier.height(12.dp)) }
                        coverageNoteText(vm)?.let { note -> item { InfoNote(note) } }
                        item {
                            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                if (!store.isPro) {
                                    Row(
                                        Modifier.heightIn(min = 36.dp).clip(CircleShape).background(HardwoodPalette.court)
                                            .clickable { actions.openTrialPitch(store.defaultUpgradeTrigger) }.padding(horizontal = 16.dp, vertical = 8.dp),
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        SfIcon("crown.fill", 12.dp, Color.White)
                                        Text(store.upgradeCTALabel, style = HardwoodType.micro, color = Color.White)
                                    }
                                }
                                TextAction("About StatScout", HardwoodType.micro, HardwoodPalette.inkTertiary, { navigator.push(Route.Settings) })
                            }
                        }
                    }
                }
            }
        }
        if (vm.isLoading && vm.players.isEmpty()) {
            LoadingCard(vm.loadingMessage, vm.loadingProgress, Modifier.align(Alignment.Center))
        }
    }
}

private fun isSmallSample(vm: DashboardViewModel, player: Player, label: String?, category: MetricCategory?): Boolean {
    label ?: return false
    val metric = player.metrics.firstOrNull { it.label == label && (category == null || it.category == category) } ?: return false
    return !vm.isQualified(player, metric)
}

/** The empty, error and loading states in place of the board; null when there are rows to show. */
private fun boardStatus(vm: DashboardViewModel, empty: Boolean): (@Composable () -> Unit)? {
    if (!empty) return null
    return when {
        vm.searchText.isNotEmpty() -> { { EmptyState("No players found", "magnifyingglass", "Try a different search term.", Modifier.heightIn(min = 200.dp)) } }
        vm.errorMessage != null -> {
            {
                val offline = vm.lastFailureWasConnectivity
                val scope = androidx.compose.runtime.rememberCoroutineScope()
                EmptyState(
                    if (offline) "No connection" else "Data Error",
                    if (offline) "wifi.exclamationmark" else "exclamationmark.triangle",
                    if (offline) "The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline."
                    else vm.errorMessage,
                    Modifier.heightIn(min = 200.dp),
                    actionTitle = "Retry",
                ) { scope.launch { vm.load() } }
            }
        }
        // The moment a new season goes live its rows are still on the way; that is loading, not "no data".
        vm.isHistoricalLoading || (vm.seasonPlayers.isEmpty() && vm.isRefreshing) -> {
            {
                Column(Modifier.fillMaxWidth().heightIn(min = 200.dp).padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(color = HardwoodPalette.inkTertiary)
                    Text("Loading ${SeasonLabel.display(vm.selectedSeason)}…", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
            }
        }
        !vm.isLoading -> {
            {
                val hasSeasonData = vm.seasonPlayers.isNotEmpty()
                val needsFirstConnection = !hasSeasonData && vm.selectedSeason == vm.freeSeason && vm.lastFetchFailed
                val scope = androidx.compose.runtime.rememberCoroutineScope()
                if (hasSeasonData && vm.hasActiveBoardFilters) EmptyState(
                    "No players match these filters",
                    "line.3.horizontal.decrease.circle",
                    "The View menu's filters leave nobody on this board.",
                    Modifier.heightIn(min = 200.dp),
                    actionTitle = "Clear Filters",
                    action = { vm.clearBoardFilters() },
                ) else EmptyState(
                    when {
                        needsFirstConnection -> "Connect to load ${SeasonLabel.display(vm.selectedSeason)}"
                        hasSeasonData -> "No matching metrics"
                        else -> "No players yet"
                    },
                    if (needsFirstConnection) "wifi.exclamationmark" else "basketball.fill",
                    when {
                        needsFirstConnection -> "The current season needs a connection for its first update. Once it has loaded, your saved stats are here offline."
                        hasSeasonData -> "No ${if (vm.selectedPosition == PlayerPositionGroup.ALL) "player" else vm.selectedPosition.noun} has ${vm.currentSortMetric ?: "this stat"} in ${SeasonLabel.display(vm.selectedSeason)}."
                        else -> "No player data yet for ${vm.selectedSeasonPhrase}."
                    },
                    Modifier.heightIn(min = 200.dp),
                    actionTitle = if (needsFirstConnection) "Try Again" else null,
                    action = if (needsFirstConnection) ({ scope.launch { vm.load() } }) else null,
                )
            }
        }
        else -> { { Spacer(Modifier.height(200.dp)) } }
    }
}

/**
 * Why a season, or the live season so far, shows fewer advanced metrics, plus
 * what the dimmed rows and the bars mean.
 */
private fun coverageNoteText(vm: DashboardViewModel): String? {
    val isLive = vm.selectedSeason == vm.freeSeason && vm.selectedPhase == SeasonPhase.REGULAR
    val pending = if (isLive) MetricCoverage.pendingNote(null, vm.dataFreshness?.shotsStatus, vm.dataFreshness?.playByPlayStatus) else null
    val noun = vm.selectedPosition.noun
    val cohort = if (isLive) "qualified ${noun}s; players under the minimum are placed against that pool" else "qualified ${noun}s"
    val minimum = if (vm.qualifierLevel == DashboardViewModel.QualifierLevel.ALL) "Dimmed rows are under the playing-time minimum."
    else "Players under the playing-time minimum are hidden; View shows them."
    val ruler = if (vm.selectedPosition == PlayerPositionGroup.ALL) "Bars show each player's percentile within his own position group."
    else "Bars show the percentile among $cohort."
    val legend = if (isLive) "$ruler $minimum" else ruler
    return listOfNotNull(MetricCoverage.note(vm.selectedSeason, null, vm.selectedPhase), pending, legend).joinToString(" ")
}

/** Teams matching the search, above the player rows: "celtics" usually means Boston. */
@Composable
private fun TeamResults(teams: List<String>) {
    if (teams.isEmpty()) return
    val navigator = LocalNavigator.current
    Column(Modifier.padding(horizontal = 12.dp).padding(top = 8.dp).hardwoodCard()) {
        teams.forEachIndexed { index, team ->
            if (index > 0) com.jackwallner.basketball.ui.components.Hairline()
            Row(
                Modifier.fillMaxWidth().heightIn(min = HardwoodGeo.rowHeight).clickable { navigator.push(Route.Team(team)) }
                    .padding(horizontal = HardwoodGeo.padCard),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(28.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                    FitText(displayTeamAbbr(team), HardwoodType.micro, Color.White, minScale = 0.6f)
                }
                Text(teamFullName(team), style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                Text("TEAM PAGE", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
                SfIcon("chevron.right", 14.dp, HardwoodPalette.inkTertiary)
            }
        }
    }
}
