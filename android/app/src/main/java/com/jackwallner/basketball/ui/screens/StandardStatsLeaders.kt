package com.jackwallner.basketball.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StandardStat
import com.jackwallner.basketball.model.StandardStatSemantics
import com.jackwallner.basketball.model.competitionRanks
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.metricNumericValue
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.model.matchesSearch
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.ui.components.InfoNote
import com.jackwallner.basketball.ui.components.PercentileBarMini
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatOption
import com.jackwallner.basketball.ui.components.StatPickerMenu
import com.jackwallner.basketball.ui.components.TeamColorDot
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.cardSlice
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType

/**
 * Traditional leaderboard with the same position tabs and control vocabulary
 * as the Advanced board. [viewModel] and [boardState] are present on the Stats
 * tab and absent on a drill-down.
 */
@Composable
fun StandardStatsLeadersView(
    players: List<Player>,
    selectedStat: String,
    onSelectStat: (String) -> Unit,
    selectedPosition: PlayerPositionGroup,
    onSelectPosition: (PlayerPositionGroup) -> Unit,
    sortDescending: Boolean,
    onSortDescending: (Boolean) -> Unit,
    boardState: StatsBoardState? = null,
    viewModel: DashboardViewModel? = null,
) {
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    var isSearching by remember { mutableStateOf(false) }
    var searchText by remember { mutableStateOf("") }

    // A stat the new position does not offer falls back to its default.
    LaunchedEffect(selectedPosition) {
        if (selectedStat !in StandardStatCatalog.stats(selectedPosition)) {
            val next = StandardStatCatalog.defaultStat(selectedPosition)
            onSelectStat(next)
            onSortDescending(StandardStatCatalog.defaultDescending(next, selectedPosition))
        }
    }

    fun standardStat(player: Player): StandardStat? = player.standardStats?.firstOrNull { it.label.equals(selectedStat, ignoreCase = true) }
    fun numericStat(player: Player): Double? = standardStat(player)?.let { StandardStatSemantics.numericValue(it.label, it.value) }
    fun games(player: Player): Double = player.standardStats?.firstOrNull { it.label == "G" }?.value?.let(::metricNumericValue) ?: 0.0

    // Over the playing-time bar, and for a shooting line over its attempts bar
    // too (the 3P% and FT% rows carry the prorated attempt gate).
    fun countsForBoard(player: Player): Boolean {
        val gate = mapOf("FG" to "FG%", "3P" to "3P%", "FT" to "FT%")[selectedStat.uppercase()]
        if (gate != null) return player.metrics.any { it.label == gate && it.qualified != false }
        return DashboardViewModel.hasQualifyingMetric(player, null)
    }

    val filtered = players.filter { selectedPosition.includes(it) && numericStat(it) != null }
    // Sort keys are read once per player. Players under the bar sort below
    // everyone over it, the Advanced board's rule: otherwise a 1-for-1 shooter
    // leads 3P at 100% and the fewest turnovers belong to whoever barely played.
    data class Keyed(val player: Player, val value: Double, val games: Double, val counts: Boolean)
    val sorted = filtered.map { Keyed(it, numericStat(it) ?: 0.0, games(it), countsForBoard(it)) }
        .sortedWith { a, b ->
            when {
                a.counts != b.counts -> if (a.counts) -1 else 1
                a.value != b.value -> if (sortDescending) b.value.compareTo(a.value) else a.value.compareTo(b.value)
                else -> b.games.compareTo(a.games)
            }
        }.map { it.player }
    val sampleLabel = when {
        viewModel == null -> "PLAYER"
        viewModel.qualifierLevel == DashboardViewModel.QualifierLevel.QUALIFIED -> "QUALIFIED PLAYERS"
        else -> "ALL PLAYERS"
    }
    // Shooting lines rank by percentage, not by the made count in front of the slash.
    val rankingNote = if (selectedStat.uppercase() in setOf("FG", "3P", "FT")) "Ranked by shooting percentage, not by makes." else null

    // The volume behind the headline number: games, or minutes when the stat is
    // the game count itself. A 40% three-point mark means little over three games.
    fun volumeText(player: Player): String? {
        val stats = player.standardStats.orEmpty()
        fun value(label: String) = stats.firstOrNull { it.label.equals(label, ignoreCase = true) }?.value
        if (selectedStat.uppercase() == "G") return value("MIN")?.let { "$it min" }
        val g = value("G") ?: return null
        return if (g == "1") "1 game" else "$g games"
    }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTabs(
            PlayerPositionGroup.entries.map { it.raw },
            selectedPosition.raw,
            { raw -> PlayerPositionGroup.entries.firstOrNull { it.raw == raw }?.let(onSelectPosition) },
            Modifier.padding(top = 8.dp).semantics { contentDescription = "Position" },
        )
        BoardControlRow(
            picker = {
                if (boardState != null && viewModel != null) StatsBoardStatPicker(viewModel, boardState)
                else StatPickerMenu(
                    activeLabel = selectedStat,
                    standard = StandardStatCatalog.stats(selectedPosition).map { StatOption(it, it, it == selectedStat) },
                    onSelectStandard = {
                        onSelectStat(it.id)
                        onSortDescending(StandardStatCatalog.defaultDescending(it.id, selectedPosition))
                    },
                )
            },
            descending = sortDescending,
            statLabel = selectedStat,
            onToggleDirection = { onSortDescending(!sortDescending) },
            isSearchActive = isSearching,
            onToggleSearch = {
                isSearching = !isSearching
                if (!isSearching) searchText = ""
            },
            trailing = if (boardState != null && viewModel != null) ({ StatsViewMenu(viewModel, boardState) }) else null,
        )
        AnimatedVisibility(isSearching) {
            SearchRow(searchText, { searchText = it }) {
                isSearching = false
                searchText = ""
            }
        }
        RefreshableBox({ viewModel?.load() }, Modifier.fillMaxSize()) {
            val query = searchText.trim()
            val ranked = sorted.withIndex().filter { (_, p) ->
                query.isEmpty() || p.matchesSearch(query)
            }
            val peerValues = filtered.mapNotNull { standardStat(it)?.value }
            val ranks = competitionRanks(sorted.map { numericStat(it) })
            LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                item { Spacer(Modifier.height(8.dp)) }
                item {
                    Row(
                        Modifier.padding(horizontal = 12.dp).cardSlice(first = true, last = false).fillMaxWidth().height(HardwoodGeo.rowHeightHeader)
                            .background(HardwoodPalette.surfaceAlt).bottomHairline()
                            .clickable {
                                onSortDescending(!sortDescending)
                                haptic()
                            }
                            .padding(horizontal = HardwoodGeo.padInline),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("RANK", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(36.dp))
                        FitText(sampleLabel, HardwoodType.micro, HardwoodPalette.inkTertiary, Modifier.weight(1f), minScale = 0.75f)
                        Text("TEAM", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(50.dp))
                        Row(Modifier.width(100.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
                            FitText(selectedStat.uppercase(), HardwoodType.micro, HardwoodPalette.court, minScale = 0.7f)
                            SfIcon(if (sortDescending) "arrow.down" else "arrow.up", 10.dp, HardwoodPalette.court)
                        }
                    }
                }
                when {
                    viewModel?.isLoading == true && players.isEmpty() -> item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                CircularProgressIndicator(color = HardwoodPalette.inkTertiary)
                                Text("Loading player stats…", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                            }
                        }
                    }
                    sorted.isEmpty() && viewModel?.hasActiveBoardFilters == true -> item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).padding(vertical = 24.dp)) {
                            EmptyState(
                                "No players match these filters",
                                "line.3.horizontal.decrease.circle",
                                "The View menu's filters leave nobody on this board.",
                                actionTitle = "Clear Filters",
                                action = { viewModel.clearBoardFilters() },
                            )
                        }
                    }
                    sorted.isEmpty() -> item {
                        Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true).padding(vertical = 24.dp)) {
                            val who = if (selectedPosition == PlayerPositionGroup.ALL) "" else selectedPosition.noun + " "
                            EmptyState("No data available", "chart.bar", "No ${who}players have $selectedStat data for this season.")
                        }
                    }
                    else -> {
                        if (ranked.isEmpty()) item {
                            Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, true)) {
                                EmptyState("No Results for “$searchText”", "magnifyingglass", "Check the spelling or try a new search.")
                            }
                        }
                        itemsIndexed(ranked, key = { _, it -> it.value.id }) { position, (index, player) ->
                            val rank = ranks[index]
                            val stat = standardStat(player)
                            val pct = stat?.let { StandardStatSemantics.percentile(it.label, it.value, peerValues) } ?: 50
                            // A zero count has no honest rank; a bench player's 0 PF is the best line, not an absence.
                            val isZero = numericStat(player) == 0.0 && StandardStatSemantics.higherIsBetter(selectedStat)
                            val display = stat?.value ?: "-"
                            Row(
                                Modifier.padding(horizontal = 12.dp).cardSlice(false, position == ranked.lastIndex).fillMaxWidth().height(52.dp)
                                    .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                                    .bottomHairline()
                                    .clickable { navigator.push(Route.PlayerProfile(player)) }
                                    .padding(horizontal = HardwoodGeo.padInline)
                                    .testTag("standardRow"),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text("$rank", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(36.dp))
                                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                    PlayerHeadshot(player.team, player.initials, 36.dp)
                                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        FitText(player.name, HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.6f)
                                        Text(listOfNotNull(player.displayPosition, volumeText(player)).joinToString(" · "), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, maxLines = 1)
                                    }
                                }
                                Row(Modifier.width(50.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                    TeamColorDot(player.team, 6.dp)
                                    Text(displayTeamAbbr(player.team), style = HardwoodType.small, color = HardwoodPalette.inkSecondary, maxLines = 1)
                                }
                                Row(
                                    Modifier.clearAndSetSemantics {
                                        contentDescription = if (isZero) "$selectedStat: $display, not ranked" else "$selectedStat: $display, ${pct.ordinal} percentile"
                                    },
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    if (isZero) Spacer(Modifier.width(34.dp)) else PercentileBarMini(pct, Modifier.width(34.dp))
                                    FitText(display, HardwoodType.statMed, if (isZero) HardwoodPalette.inkTertiary else HardwoodPalette.court, Modifier.width(58.dp), minScale = 0.7f, textAlign = TextAlign.End)
                                }
                            }
                        }
                    }
                }
                item { Spacer(Modifier.height(12.dp)) }
                rankingNote?.let { note -> item { InfoNote(note, Modifier.padding(horizontal = 4.dp)) } }
            }
        }
    }
}

/** Standalone traditional-stat drill-down reached from a player or team page. */
@Composable
fun StandardStatRoute(route: Route.StandardStat) {
    val vm = LocalGraph.current.dashboard
    val season = route.season ?: vm.selectedSeason
    val phase = route.phase ?: vm.selectedPhase
    var stat by rememberSaveable { mutableStateOf(route.stat) }
    var position by rememberSaveable { mutableStateOf(route.position) }
    var descending by rememberSaveable { mutableStateOf(StandardStatCatalog.defaultDescending(route.stat, route.position)) }
    val title = route.stat + " · " + if (phase == SeasonPhase.REGULAR) SeasonLabel.display(season) else SeasonLabel.display(season, phase)
    PushedScreen(title) {
        StandardStatsLeadersView(
            players = vm.players(season, phase),
            selectedStat = stat,
            onSelectStat = { stat = it },
            selectedPosition = position,
            onSelectPosition = { position = it },
            sortDescending = descending,
            onSortDescending = { descending = it },
        )
    }
}
