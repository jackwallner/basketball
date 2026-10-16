package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.LeagueDivision
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.matchesSearch
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.StatOption
import com.jackwallner.basketball.ui.components.StatPickerMenu
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.leagueTeamAbbreviations
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.ChipButton
import com.jackwallner.basketball.ui.components.ChipTrailing
import com.jackwallner.basketball.ui.components.DataFreshnessView
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodChip
import com.jackwallner.basketball.ui.components.HardwoodMenu
import com.jackwallner.basketball.ui.components.HardwoodNavPill
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.ui.components.HardwoodTopBar
import com.jackwallner.basketball.ui.components.LeaderboardTableHeader
import com.jackwallner.basketball.ui.components.LeaderboardTableRow
import com.jackwallner.basketball.ui.components.MenuItem
import com.jackwallner.basketball.ui.components.MenuSection
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SeasonPhasePicker
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatGlossaryLink
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType

private enum class TeamTab(val raw: String) { ADVANCED("Advanced"), STANDARD("Standard"), ROSTER("Roster") }

private enum class RosterMode(val raw: String) { SEASON("Season"), RECENT("Recent") }

/** One team's page: tonight's game, the season at a glance, then Advanced, Standard and Roster tabs. */
@Composable
fun TeamScreen(abbr: String) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val isPro = graph.subscriptions.isPro
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val haptic = rememberHaptic()

    var selectedTab by rememberSaveable { mutableStateOf(TeamTab.ADVANCED) }
    var searchText by rememberSaveable { mutableStateOf("") }
    var isSearching by rememberSaveable { mutableStateOf(false) }
    // The roster opens on On-Off, the same all-in-one number the Stats board opens on,
    // and offers the same controls: position tabs, the stat picker, the sort arrow,
    // search and the View menu.
    var rosterStat by rememberSaveable { mutableStateOf("On-Off") }
    var rosterPosition by rememberSaveable { mutableStateOf(PlayerPositionGroup.ALL) }
    var sortDescending by rememberSaveable { mutableStateOf(true) }
    var lastDefaultedSortKey by rememberSaveable { mutableStateOf<String?>(null) }
    var rosterMode by rememberSaveable { mutableStateOf(RosterMode.SEASON) }
    var rosterWindow by rememberSaveable { mutableStateOf(RecentWindow.TWO_WEEKS) }
    // The Stats board's qualifier, shared so the two never disagree.
    val qualifierLevel = vm.qualifierLevel

    // The roster for the season and phase that are selected right now, so the
    // nav-bar picker moves the rows, cards and sort metrics together.
    val players = vm.players(abbr)
    val displaySeason = vm.selectedSeason
    val leaguePlayers = vm.seasonPlayers
    val displayPhase = vm.selectedPhase

    // Recent form exists for the newest two seasons only, so every Recent control
    // on this screen is hidden (not locked) on a historical one.
    val supportsRecent = vm.supportsRecentForm(displaySeason)
    val isRosterRecent = rosterMode == RosterMode.RECENT && isPro && supportsRecent

    // Every metric the roster carries, one per label, in the registry's order.
    val rosterMetrics: List<Metric> = run {
        val seen = HashSet<String>()
        val present = players.filter { rosterPosition.includes(it) }.flatMap { it.metrics }
            .filter { BasketballMetricRegistry.isSupported(it, rosterPosition) }
        BasketballMetricRegistry.sorted(present).filter { seen.add(it.label) }
    }
    fun rosterLabels(kind: MetricKind) = rosterMetrics.filter { BasketballMetricRegistry.kind(it) == kind }.map { it.label }
    val sortMetric: Pair<String, MetricCategory>? = (
        rosterMetrics.firstOrNull { it.label == rosterStat } ?: rosterMetrics.firstOrNull { it.label == "On-Off" } ?: rosterMetrics.firstOrNull()
    )?.let { it.label to it.category }
    val sortLabel = sortMetric?.first ?: "Overall"
    val rowLabel = sortMetric?.first
    val rowCategory = sortMetric?.second

    fun recentFormFor(player: Player) = vm.recentForm(player.playerId, rosterWindow)
    val recentKey = sortMetric?.first?.let { RecentMetricKey.key(it) }
    fun recentValue(player: Player): Double? = recentKey?.let { recentFormFor(player)?.metrics?.get(it) }
    fun recentDelta(player: Player): Double? = recentKey?.let { recentFormFor(player)?.delta?.get(it) }
    fun recentValueText(player: Player): String {
        val label = sortMetric?.first ?: return "-"
        val value = recentValue(player) ?: return "-"
        return RecentMetricKey.format(value, label)
    }
    val hasRecentData = vm.recentFormByWindow[rosterWindow.value] != null

    fun isQualified(player: Player): Boolean = when (qualifierLevel) {
        DashboardViewModel.QualifierLevel.ALL -> true
        DashboardViewModel.QualifierLevel.QUALIFIED -> DashboardViewModel.hasQualifyingMetric(player, sortMetric?.second)
    }
    // Under the playing-time bar for the ranked metric.
    fun isSmallSample(player: Player): Boolean {
        val sm = sortMetric ?: return false
        val metric = player.metrics.firstOrNull { it.label == sm.first && it.category == sm.second } ?: return false
        return !vm.isQualified(player, metric)
    }

    fun rosterBoard(search: String): List<Player> {
        val bySearch = if (search.isEmpty()) players else players.filter {
            it.matchesSearch(search, includingTeam = false) || it.displayPosition.contains(search, ignoreCase = true)
        }
        val byQualifier = bySearch.filter { rosterPosition.includes(it) }.filter { isQualified(it) }
        if (isRosterRecent && sortMetric != null) {
            return byQualifier.filter { recentValue(it) != null }.sortedWith { a, b ->
                val first = recentValue(a) ?: 0.0
                val second = recentValue(b) ?: 0.0
                if (sortDescending) second.compareTo(first) else first.compareTo(second)
            }
        }
        if (sortMetric == null) {
            return byQualifier.sortedWith { a, b ->
                if (sortDescending) b.overallPercentile.compareTo(a.overallPercentile) else a.overallPercentile.compareTo(b.overallPercentile)
            }
        }
        // A roster mixes guards, forwards and centers, whose percentiles come from different
        // pools: order by the value itself. Small samples sit below the rest, so a cameo never leads.
        val sorted = byQualifier.sortedWith(DashboardViewModel.metricComparator(sortMetric.first, sortMetric.second, sortDescending, acrossCohorts = true))
        return sorted.filter { !isSmallSample(it) } + sorted.filter { isSmallSample(it) }
    }
    val filteredPlayers = rosterBoard(searchText)
    // Each player's place on the unsearched roster while a search narrows it.
    val rosterRanks: Map<String, Int>? = if (searchText.isEmpty()) null else rosterBoard("").mapIndexed { i, p -> p.id to i + 1 }.toMap()

    // A new metric, position or season re-defaults the sort direction.
    val sortKey = sortMetric?.let { "${it.second.raw}|${it.first}" } ?: "-"
    LaunchedEffect(sortKey) {
        if (sortKey != lastDefaultedSortKey) {
            lastDefaultedSortKey = sortKey
            sortDescending = DashboardViewModel.defaultSortDescending(sortMetric?.first, sortMetric?.second)
        }
    }

    LaunchedEffect(rosterMode, rosterWindow, displaySeason, displayPhase, isPro, vm.freshnessRevision ?: "none") {
        if (isRosterRecent) vm.loadRecentFormIfNeeded(rosterWindow)
    }

    // The league's rows for one window, for the team cards' Recent modes.
    val loadRecent: suspend (RecentWindow) -> List<RecentForm> = { window -> vm.leagueRecentForm(window, displaySeason, displayPhase) }
    val openTeamPitch = { actions.openTrialPitch(PaywallTrigger.TeamView) }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTopBar(
            onBack = { navigator.pop() },
            leading = { TeamSwitcher(abbr) },
            trailing = {
                SeasonPhasePicker(
                    // A single team page, so no All Time: a career row can't be attributed to one franchise.
                    seasons = vm.seasonsExcludingAllTime,
                    selectedSeason = vm.selectedSeason,
                    selectedPhase = vm.selectedPhase,
                    isSeasonLocked = vm::isSeasonLocked,
                    onSelectSeason = { season ->
                        if (vm.isSeasonLocked(season)) actions.openTrialPitch(PaywallTrigger.LockedSeason(season)) else vm.selectSeason(season)
                    },
                    onSelectPhase = { vm.selectedPhase = it },
                ) { open ->
                    // No glyph and the short year alone: the team name is long ("Portland Trail
                    // Blazers"), and spelling the phase out as well would crowd the bar.
                    HardwoodNavPill(
                        title = SeasonLabel.display(vm.selectedSeason) + if (vm.selectedPhase == SeasonPhase.PLAYOFFS) " · Playoffs" else "",
                        onClick = open,
                        description = "Season and season type, ${SeasonLabel.display(vm.selectedSeason)}, ${vm.selectedPhase.label}",
                    )
                }
            },
        )
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                if (displaySeason == vm.freeSeason) {
                    seasonSummary(vm, abbr)?.let {
                        Text(
                            it,
                            style = HardwoodType.smallBold.copy(fontFeatureSettings = "tnum"),
                            color = HardwoodPalette.inkSecondary,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 10.dp),
                        )
                    }
                }
                DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 10.dp), season = displaySeason, phase = displayPhase)
                if (displaySeason == vm.freeSeason) {
                    Box(Modifier.padding(horizontal = 12.dp).padding(top = 10.dp)) { TeamGameCard(vm, abbr) }
                    if (displayPhase == SeasonPhase.REGULAR) {
                        Box(Modifier.padding(horizontal = 12.dp).padding(top = 10.dp)) { TeamSeasonGlance(vm, abbr) }
                    }
                }
                TabSelector(selectedTab, Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { selectedTab = it }

                when (selectedTab) {
                    TeamTab.ADVANCED -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        TeamRankingsCard(
                            team = abbr,
                            season = displaySeason,
                            players = players,
                            leaguePlayers = leaguePlayers,
                            loadRecent = loadRecent,
                            // Explicit tap, always answer it; the gate only caps automatic pop-ups.
                            onUpgradeTap = openTeamPitch,
                            seasonPhase = displayPhase,
                            freshnessRevision = vm.freshnessRevision,
                            freshnessStatus = vm.freshnessStatus,
                            supportsRecent = supportsRecent,
                        )
                    }
                    TeamTab.STANDARD -> Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) {
                        TeamStandardCard(
                            team = abbr,
                            season = displaySeason,
                            players = players,
                            leaguePlayers = leaguePlayers,
                            loadRecent = loadRecent,
                            onUpgradeTap = openTeamPitch,
                            seasonPhase = displayPhase,
                            supportsRecent = supportsRecent,
                        )
                    }
                    TeamTab.ROSTER -> Column {
                        if (supportsRecent) {
                            HardwoodSegmented(
                                RosterMode.entries.map { Segment(it, it.raw, isLocked = !isPro && it == RosterMode.RECENT) },
                                rosterMode,
                                { rosterMode = it },
                                Modifier.padding(horizontal = 12.dp).padding(top = 12.dp),
                                onLockedTap = { actions.openTrialPitch(PaywallTrigger.RecentForm) },
                            )
                        }
                        if (isRosterRecent) {
                            HardwoodSegmented(
                                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                                rosterWindow,
                                { rosterWindow = it },
                                Modifier.padding(horizontal = 12.dp).padding(top = 8.dp),
                            )
                        }
                        HardwoodTabs(
                            tabs = PlayerPositionGroup.entries.map { it.raw },
                            selected = rosterPosition.raw,
                            onSelect = { raw -> PlayerPositionGroup.entries.firstOrNull { it.raw == raw }?.let { rosterPosition = it } },
                            modifier = Modifier.padding(horizontal = 12.dp).padding(top = 8.dp).semantics { contentDescription = "Position" },
                        )

                        if (players.isNotEmpty()) {
                            BoardControlRow(
                                picker = {
                                    StatPickerMenu(
                                        activeLabel = sortLabel,
                                        advanced = StatOption.categorized(rosterLabels(MetricKind.ADVANCED), sortMetric?.first),
                                        standard = rosterLabels(MetricKind.TRADITIONAL).map { StatOption(it, it, it == sortMetric?.first) },
                                        onSelectAdvanced = { rosterStat = it.id },
                                        onSelectStandard = { rosterStat = it.id },
                                    )
                                },
                                descending = sortDescending,
                                statLabel = sortLabel,
                                onToggleDirection = {
                                    sortDescending = !sortDescending
                                    haptic()
                                },
                                isSearchActive = isSearching || searchText.isNotEmpty(),
                                onToggleSearch = {
                                    isSearching = !isSearching
                                    if (!isSearching) searchText = ""
                                    haptic()
                                },
                                trailing = { RosterViewMenu(qualifierLevel) { vm.qualifierLevel = it; haptic() } },
                            )
                            if (isSearching || searchText.isNotEmpty()) {
                                Row(
                                    Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 8.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    SearchField(searchText, { searchText = it }, Modifier.weight(1f), focusOnAppear = true, prompt = "Search roster")
                                    TextAction("Cancel", HardwoodType.small, HardwoodPalette.court, {
                                        isSearching = false
                                        searchText = ""
                                    })
                                }
                            }
                        }

                        RosterSection(
                            abbr = abbr,
                            season = displaySeason,
                            players = players,
                            isHistoryLoading = vm.isHistoricalLoading,
                            filteredPlayers = filteredPlayers,
                            ranks = rosterRanks,
                            searchEmpty = searchText.isEmpty(),
                            position = rosterPosition,
                            qualifierActive = qualifierLevel != DashboardViewModel.QualifierLevel.ALL,
                            onClearFilters = { vm.qualifierLevel = DashboardViewModel.QualifierLevel.ALL },
                            isRosterRecent = isRosterRecent,
                            hasRecentData = hasRecentData,
                            recentError = vm.recentFormError,
                            onRetryRecent = { vm.loadRecentFormIfNeeded(rosterWindow) },
                            rosterWindow = rosterWindow,
                            sortLabel = sortLabel,
                            sortDescending = sortDescending,
                            rowLabel = rowLabel,
                            rowCategory = rowCategory,
                            onToggleDirection = {
                                sortDescending = !sortDescending
                                haptic()
                            },
                            recentDelta = ::recentDelta,
                            recentValueText = ::recentValueText,
                            volume = { p -> vm.volumeCaption(p, rowCategory) },
                            isSmallSample = ::isSmallSample,
                        )
                    }
                }

                Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
                // Lets content scroll under the floating tab bar.
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/** "56-26 · 2nd in the East · Power +5.3, 2nd": where the team stands, the first thing a fan wants. */
private fun seasonSummary(vm: DashboardViewModel, team: String): String? {
    val abbr = normalizedTeamAbbreviation(team)
    val table = vm.standings
    val row = table[abbr]?.takeIf { it.games > 0 } ?: return null
    val parts = mutableListOf(row.record)
    LeagueDivision.conferences.firstOrNull { abbr in it.second }?.let { (name, teams) ->
        val seed = StandingsRow.ordered(teams.mapNotNull { table[it] }).indexOfFirst { it.team == abbr }
        if (seed >= 0) parts += "${(seed + 1).ordinal} in the ${if (name.startsWith("East")) "East" else "West"}"
    }
    vm.teamRating(abbr)?.let { parts += "Power ${TeamRating.signed(it.rating)}, ${it.rank.ordinal}" }
    return parts.joinToString(" · ")
}

/** The Stats board's View menu, less what a single roster has no use for (conference, Best & Worst). */
@Composable
private fun RosterViewMenu(level: DashboardViewModel.QualifierLevel, onPick: (DashboardViewModel.QualifierLevel) -> Unit) {
    HardwoodMenu(
        listOf(MenuSection("Qualifier", DashboardViewModel.QualifierLevel.entries.map { l ->
            MenuItem("${l.label} · ${l.description}", checked = l == level) { onPick(l) }
        })),
        Modifier.testTag("rosterView"),
    ) { open ->
        ChipButton(open, description = "View options") {
            HardwoodChip(title = "View", icon = "slider.horizontal.3", trailing = ChipTrailing.Chevron, isActive = level != DashboardViewModel.QualifierLevel.ALL)
        }
    }
}

/**
 * The team name in the bar doubles as a switcher menu: tap to jump to any other
 * team without popping back to the Teams list.
 */
@Composable
private fun TeamSwitcher(team: String) {
    val navigator = LocalNavigator.current
    val teams = leagueTeamAbbreviations.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { teamFullName(it) })
    HardwoodMenu(
        sections = listOf(
            MenuSection(null, teams.map { abbr -> MenuItem(teamFullName(abbr), checked = abbr == team) { navigator.push(Route.Team(abbr)) } }),
        ),
    ) { open ->
        Row(
            Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(HardwoodGeo.radiusCard)).clickable(onClick = open)
                .semantics { contentDescription = "Team, ${teamFullName(team)}. Switch to another team" }
                .testTag("teamSwitcher"),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FitText(teamFullName(team), HardwoodType.bodyBold, Color.White, Modifier.widthIn(max = 170.dp), minScale = 0.8f)
            SfIcon("chevron.down", 14.dp, Color.White.copy(alpha = 0.85f))
        }
    }
}

/**
 * Mirrors the player profile's tab selector with equal-width court controls that
 * swap the card content below: the team's percentile profile, its traditional
 * line, and its sortable roster.
 */
@Composable
private fun TabSelector(selected: TeamTab, modifier: Modifier = Modifier, onSelect: (TeamTab) -> Unit) {
    val haptic = rememberHaptic()
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TeamTab.entries.forEach { tab ->
            val isSelected = tab == selected
            Box(
                Modifier.weight(1f).height(44.dp)
                    .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
                    .background(if (isSelected) HardwoodPalette.court else HardwoodPalette.surface)
                    .clickable {
                        onSelect(tab)
                        haptic()
                    }
                    .semantics {
                        this.selected = isSelected
                        role = Role.Tab
                    }
                    .testTag("teamTab_${tab.raw}"),
                contentAlignment = Alignment.Center,
            ) {
                FitText(
                    tab.raw, HardwoodType.smallBold, if (isSelected) Color.White else HardwoodPalette.ink,
                    Modifier.padding(horizontal = 4.dp), minScale = 0.85f, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun RosterSection(
    abbr: String,
    season: Int,
    players: List<Player>,
    isHistoryLoading: Boolean,
    filteredPlayers: List<Player>,
    ranks: Map<String, Int>?,
    searchEmpty: Boolean,
    position: PlayerPositionGroup,
    qualifierActive: Boolean,
    onClearFilters: () -> Unit,
    isRosterRecent: Boolean,
    hasRecentData: Boolean,
    recentError: String?,
    onRetryRecent: suspend () -> Unit,
    rosterWindow: RecentWindow,
    sortLabel: String,
    sortDescending: Boolean,
    rowLabel: String?,
    rowCategory: MetricCategory?,
    onToggleDirection: () -> Unit,
    recentDelta: (Player) -> Double?,
    recentValueText: (Player) -> String,
    volume: (Player) -> String?,
    isSmallSample: (Player) -> Boolean,
) {
    val navigator = LocalNavigator.current
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard()) {
        when {
            players.isEmpty() && isHistoryLoading -> GamesTeamsUi.Spinner("Loading ${SeasonLabel.display(season)}…", Modifier.padding(vertical = 40.dp))
            players.isEmpty() -> GamesTeamsUi.Unavailable(
                "person.2.slash", "No players tracked",
                "No players are tracked for ${teamFullName(abbr)} in the ${SeasonLabel.display(season)} season.",
                Modifier.padding(vertical = 48.dp),
            )
            isRosterRecent && !hasRecentData -> if (recentError != null) {
                EmptyState("Couldn't load recent form", "exclamationmark.triangle", recentError, Modifier.padding(vertical = 24.dp), "Try Again") {
                    scope.launch { onRetryRecent() }
                }
            } else GamesTeamsUi.InlineSpinner("Loading the ${rosterWindow.prose}…", Modifier.padding(vertical = 8.dp))
            filteredPlayers.isEmpty() && isRosterRecent && searchEmpty -> GamesTeamsUi.Unavailable(
                "calendar.badge.clock", "No recent games",
                "No ${teamFullName(abbr)} player has $sortLabel over the ${rosterWindow.prose}. Try Season or a longer window.",
                Modifier.padding(vertical = 48.dp),
            )
            filteredPlayers.isEmpty() && searchEmpty && qualifierActive -> EmptyState(
                "No players match these filters", "line.3.horizontal.decrease.circle",
                "Qualified hides players under the playing-time minimum.", Modifier.padding(vertical = 32.dp), "Clear Filters",
            ) { onClearFilters() }
            filteredPlayers.isEmpty() -> GamesTeamsUi.Unavailable(
                "magnifyingglass", "No players found",
                if (searchEmpty) "No ${if (position == PlayerPositionGroup.ALL) "" else position.noun + " "}players match this view. Try All or another position." else "Try a different search term.",
                Modifier.padding(vertical = 48.dp),
            )
            else -> {
                LeaderboardTableHeader(
                    sortDescending = sortDescending,
                    sortLabel = if (isRosterRecent) "$sortLabel · ${rosterWindow.segmentLabel}" else sortLabel,
                    onToggleDirection = onToggleDirection,
                )
                filteredPlayers.forEachIndexed { index, player ->
                    LeaderboardTableRow(
                        rank = ranks?.get(player.id) ?: (index + 1),
                        player = player,
                        stripe = index + 1,
                        metricLabel = rowLabel,
                        metricCategory = rowCategory,
                        trendDelta = if (isRosterRecent) recentDelta(player) else null,
                        trendDecimals = rowLabel?.let { RecentMetricKey.decimals(it) } ?: 3,
                        valueOverride = if (isRosterRecent) recentValueText(player) else null,
                        // Minutes beside the position, the Stats board's row.
                        volume = if (isRosterRecent) null else volume(player),
                        isSmallSample = !isRosterRecent && isSmallSample(player),
                        onClick = { navigator.push(Route.PlayerProfile(player)) },
                    )
                }
            }
        }
    }
}
