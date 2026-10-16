package com.jackwallner.basketball.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.competitionRanks
import com.jackwallner.basketball.model.matchesSearch
import com.jackwallner.basketball.model.metricValue
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.ui.components.LeaderboardTableHeader
import com.jackwallner.basketball.ui.components.LeaderboardTableRow
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.StatOption
import com.jackwallner.basketball.ui.components.StatPickerMenu
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.cardSlice
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodPalette

/**
 * One metric's league leaderboard, reached from a percentile bar. Carries the
 * Stats board's controls (position tabs, stat picker, sort arrow, search) so a
 * drill-down reads like the board it came from.
 */
@Composable
fun MetricRankingRoute(route: Route.Metric) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val season = route.season ?: vm.selectedSeason
    val phase = route.phase ?: vm.selectedPhase
    var label by rememberSaveable { mutableStateOf(route.label) }
    var category by rememberSaveable { mutableStateOf(route.category) }
    // Best first for the active metric (descending for higher-is-better, ascending for TOV% and Fouls/100).
    var descending by rememberSaveable { mutableStateOf(DashboardViewModel.defaultSortDescending(route.label, route.category)) }
    var position by rememberSaveable { mutableStateOf(route.position ?: PlayerPositionGroup.ALL) }
    var isSearching by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }
    val players = vm.players(season, phase)

    // Every metric this cohort carries, one per label, in registry order.
    val seen = HashSet<String>()
    val cohortMetrics = BasketballMetricRegistry.sorted(
        players.filter { position.includes(it) }.flatMap { it.metrics }.filter { BasketballMetricRegistry.isSupported(it, position) },
    ).filter { seen.add(it.label) }
    fun options(kind: MetricKind): List<StatOption> {
        val labels = cohortMetrics.filter { BasketballMetricRegistry.definition(it.label, it.category)?.kind == kind }.map { it.label }
        return if (kind == MetricKind.ADVANCED) StatOption.categorized(labels, label) else labels.map { StatOption(it, it, it == label) }
    }
    fun select(option: StatOption) {
        val metric = cohortMetrics.firstOrNull { it.label == option.id } ?: return
        label = metric.label
        category = metric.category
        descending = DashboardViewModel.defaultSortDescending(metric.label, metric.category)
    }
    fun isSmallSample(player: Player): Boolean {
        val metric = player.metrics.firstOrNull { it.label == label && it.category == category } ?: return false
        return !vm.isQualified(player, metric)
    }
    val sorted = players.filter { p -> position.includes(p) && p.metrics.any { it.label == label && it.category == category } }
        .sortedWith(DashboardViewModel.metricComparator(label, category, descending, acrossCohorts = position == PlayerPositionGroup.ALL))
    // Same rule as the Stats board: small samples stay listed, below.
    val ranked = sorted.filterNot(::isSmallSample) + sorted.filter(::isSmallSample)
    val query = searchText.trim()
    val ranks = competitionRanks(ranked.map { metricValue(it, label, category) })
    val shown = ranked.withIndex().filter { query.isEmpty() || it.value.matchesSearch(query) }
    // The phase only earns title space when it isn't the default, the Standard drill-down's rule.
    val title = label + " · " + if (phase == SeasonPhase.REGULAR) SeasonLabel.display(season) else SeasonLabel.display(season, phase)

    PushedScreen(title) {
        Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
            HardwoodTabs(
                PlayerPositionGroup.entries.map { it.raw },
                position.raw,
                { raw -> PlayerPositionGroup.entries.firstOrNull { it.raw == raw }?.let { position = it } },
                Modifier.padding(top = 8.dp).semantics { contentDescription = "Position" },
            )
            BoardControlRow(
                picker = {
                    StatPickerMenu(
                        activeLabel = label,
                        advanced = options(MetricKind.ADVANCED),
                        standard = options(MetricKind.TRADITIONAL),
                        onSelectAdvanced = ::select,
                        onSelectStandard = ::select,
                    )
                },
                descending = descending,
                statLabel = label,
                onToggleDirection = { descending = !descending },
                isSearchActive = isSearching,
                onToggleSearch = {
                    isSearching = !isSearching
                    if (!isSearching) searchText = ""
                },
            )
            AnimatedVisibility(isSearching) {
                SearchRow(searchText, { searchText = it }) {
                    isSearching = false
                    searchText = ""
                }
            }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                item { Spacer(Modifier.height(8.dp)) }
                if (ranked.isEmpty()) {
                    item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, true).padding(vertical = 12.dp)) {
                            val who = if (position == PlayerPositionGroup.ALL) "" else position.noun + " "
                            EmptyState("No rankings found", "chart.bar", "No ${who}players have $label for this season.")
                        }
                    }
                } else {
                    item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(true, shown.isEmpty() && query.isEmpty())) {
                            LeaderboardTableHeader(descending, label) { descending = !descending }
                        }
                    }
                    if (shown.isEmpty()) {
                        item {
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true)) {
                                EmptyState("No Results for \u201c$searchText\u201d", "magnifyingglass", "Check the spelling or try a new search.")
                            }
                        }
                    }
                    itemsIndexed(shown, key = { _, it -> it.value.id }) { row, (index, player) ->
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, row == shown.lastIndex)) {
                            LeaderboardTableRow(
                                rank = ranks[index],
                                player = player,
                                stripe = row,
                                metricLabel = label,
                                metricCategory = category,
                                volume = vm.volumeCaption(player, category),
                                isSmallSample = isSmallSample(player),
                            ) { navigator.push(Route.PlayerProfile(player)) }
                        }
                    }
                }
            }
        }
    }
}
