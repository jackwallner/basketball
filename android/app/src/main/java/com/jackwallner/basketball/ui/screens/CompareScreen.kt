package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.HomeTopBar
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.ChipButton
import com.jackwallner.basketball.ui.components.ChipTrailing
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodChip
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodTopBar
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.SeasonPhaseMenu
import com.jackwallner.basketball.ui.components.SeasonPhasePicker
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatScoutSheet
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
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

private enum class PickerTarget { PLAYER_A, PLAYER_B, YEAR_PLAYER, TEAM_A, TEAM_B }

@Stable
private class CompareState(vm: DashboardViewModel) {
    var playerA by mutableStateOf<Player?>(null)
    var playerB by mutableStateOf<Player?>(null)
    // Null follows the live season, so a slot never sticks on last year after a rollover.
    var seasonA by mutableStateOf<Int?>(null)
    var seasonB by mutableStateOf<Int?>(null)
    var phaseA by mutableStateOf(vm.selectedPhase)
    var phaseB by mutableStateOf(vm.selectedPhase)
    var yearPhase by mutableStateOf(vm.selectedPhase)
    var teamA by mutableStateOf<String?>(null)
    var teamB by mutableStateOf<String?>(null)
    var teamSeasonA by mutableStateOf<Int?>(null)
    var teamSeasonB by mutableStateOf<Int?>(null)
    var teamPhaseA by mutableStateOf(vm.selectedPhase)
    var teamPhaseB by mutableStateOf(vm.selectedPhase)
}

private fun resolved(vm: DashboardViewModel, player: Player?, season: Int, phase: SeasonPhase): Player? {
    player ?: return null
    if (player.season == season && player.seasonPhase == phase) return player
    return vm.playerHistories[player.playerId]?.firstOrNull { it.season == season && it.seasonPhase == phase }
}

/**
 * The Compare tab and the home of the players you follow. Following is free;
 * only the comparison cards below it are behind StatScout+.
 */
@Composable
fun CompareScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val favorites = graph.favorites
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    val haptic = rememberHaptic()
    val state = rememberRetained("compare") { CompareState(vm) }
    var picker by remember { mutableStateOf<PickerTarget?>(null) }
    var showingFollowSheet by remember { mutableStateOf(false) }
    val seasonA = state.seasonA ?: vm.freeSeason
    val seasonB = state.seasonB ?: vm.freeSeason
    val teamSeasonA = state.teamSeasonA ?: vm.freeSeason
    val teamSeasonB = state.teamSeasonB ?: vm.freeSeason

    val resolvedA = resolved(vm, state.playerA, seasonA, state.phaseA)
    val resolvedB = resolved(vm, state.playerB, seasonB, state.phaseB)
    val canCompare = resolvedA != null && resolvedB != null
    val slotWarning = when {
        vm.isHistoricalLoading && (resolvedA == null || resolvedB == null) -> "Loading past seasons…"
        state.playerA != null && resolvedA == null -> "No ${SeasonLabel.display(seasonA)} ${state.phaseA.label.lowercase()} data for ${state.playerA!!.name}."
        state.playerB != null && resolvedB == null -> "No ${SeasonLabel.display(seasonB)} ${state.phaseB.label.lowercase()} data for ${state.playerB!!.name}."
        else -> null
    }
    val isSameTeam = state.teamA != null && state.teamB != null &&
        normalizedTeamAbbreviation(state.teamA!!) == normalizedTeamAbbreviation(state.teamB!!) &&
        teamSeasonA == teamSeasonB && state.teamPhaseA == state.teamPhaseB
    val canCompareTeams = state.teamA != null && state.teamB != null && !isSameTeam
    val teamWarning = if (isSameTeam) "Both sides are ${teamFullName(state.teamA!!)} in ${SeasonLabel.display(teamSeasonA)} ${state.teamPhaseA.label.lowercase()}. Change one side's season or season type to compare." else null
    val roster = vm.players(vm.freeSeason, SeasonPhase.REGULAR)
    val followed = favorites.playerIds.mapNotNull { id ->
        roster.firstOrNull { it.playerId == id }
            ?: vm.playerHistories[id].orEmpty()
                .filter { it.seasonPhase == SeasonPhase.REGULAR && !StatScoutSeason.isAllTime(it.season ?: 0) }
                .maxByOrNull { it.season ?: 0 }
    }

    // Preload history once the tab is actually opened, never at launch.
    LaunchedEffect(isActive, store.isPro) {
        if (isActive && store.isPro && !vm.hasLoadedHistorical && !vm.isHistoricalLoading) vm.loadHistoricalIfNeeded()
    }
    LaunchedEffect(seasonA, state.phaseA, seasonB, state.phaseB, teamSeasonA, state.teamPhaseA, teamSeasonB, state.teamPhaseB) {
        val sel = vm.selectedSeason
        if (store.isPro && (seasonA != sel || seasonB != sel || teamSeasonA != sel || teamSeasonB != sel)) vm.loadHistoricalIfNeeded()
    }

    fun loadIntoSlot(player: Player) {
        val a = state.playerA
        val b = state.playerB
        if (a == null || a.playerId == player.playerId) state.playerA = player else state.playerB = player
    }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HomeTopBar(title = "Compare")
        RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp)
                    .padding(bottomBarPadding(104.dp)),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                YourPlayersCard(
                    followed = followed,
                    isEmpty = favorites.playerIds.isEmpty(),
                    isPro = store.isPro,
                    inSlot = { p -> state.playerA?.playerId == p.playerId || state.playerB?.playerId == p.playerId },
                    onEdit = { showingFollowSheet = true },
                    onTap = { p ->
                        if (store.isPro) {
                            loadIntoSlot(p)
                            haptic()
                        } else navigator.push(Route.PlayerProfile(p))
                    },
                    onOpen = { p -> navigator.push(Route.PlayerProfile(p)) },
                    onUnfollow = { p -> favorites.toggleFavorite(p.playerId) },
                )
                Box {
                    // Only the comparison cards blur: following stays usable for free.
                    Column(
                        Modifier.then(if (store.isPro) Modifier else Modifier.gateBlur()),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        val locked: (Int) -> Unit = { s -> actions.openTrialPitch(PaywallTrigger.LockedSeason(s)) }
                        Column(Modifier.fillMaxWidth().hardwoodCard()) {
                            HardwoodSectionBar("PLAYER VS PLAYER")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    SlotColumn(vm, state.playerA, "Player A", seasonA, state.phaseA, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.PLAYER_A }, { state.seasonA = it }, { state.phaseA = it }, locked)
                                    Text("vs", style = HardwoodType.smallBold, color = HardwoodPalette.inkTertiary, modifier = Modifier.padding(top = 40.dp))
                                    SlotColumn(vm, state.playerB, "Player B", seasonB, state.phaseB, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.PLAYER_B }, { state.seasonB = it }, { state.phaseB = it }, locked)
                                }
                                slotWarning?.let { Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                                BigButton("Compare", enabled = canCompare && store.isPro, tag = "compareGo") {
                                    if (resolvedA != null && resolvedB != null) navigator.push(Route.Comparison(resolvedA, resolvedB))
                                }
                            }
                        }
                        Column(Modifier.fillMaxWidth().hardwoodCard()) {
                            HardwoodSectionBar("TEAM VS TEAM")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    TeamSlotColumn(vm, state.teamA, "Team A", teamSeasonA, state.teamPhaseA, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.TEAM_A }, { state.teamSeasonA = it }, { state.teamPhaseA = it }, locked)
                                    Text("vs", style = HardwoodType.smallBold, color = HardwoodPalette.inkTertiary, modifier = Modifier.padding(top = 40.dp))
                                    TeamSlotColumn(vm, state.teamB, "Team B", teamSeasonB, state.teamPhaseB, Modifier.weight(1f), store.isPro,
                                        { picker = PickerTarget.TEAM_B }, { state.teamSeasonB = it }, { state.teamPhaseB = it }, locked)
                                }
                                teamWarning?.let { Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                                BigButton("Compare Teams", enabled = canCompareTeams && store.isPro, tag = "compareTeamsGo") {
                                    val a = state.teamA ?: return@BigButton
                                    val b = state.teamB ?: return@BigButton
                                    navigator.push(Route.TeamComparison(a, b, teamSeasonA, state.teamPhaseA, teamSeasonB, state.teamPhaseB))
                                }
                            }
                        }
                        Column(Modifier.fillMaxWidth().hardwoodCard()) {
                            HardwoodSectionBar("YEAR OVER YEAR")
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Text("Pick a player and season type to compare their aggregated stats across years.", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    SeasonPhaseMenu(state.yearPhase, { state.yearPhase = it }) { open ->
                                        ChipButton(open, description = "Season type, ${state.yearPhase.label}") {
                                            HardwoodChip(title = state.yearPhase.label, icon = "basketball.fill", trailing = ChipTrailing.Chevron)
                                        }
                                    }
                                    Row(
                                        Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(12.dp)).background(HardwoodPalette.court)
                                            .clickable(enabled = store.isPro) { picker = PickerTarget.YEAR_PLAYER },
                                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        SfIcon("calendar.badge.clock", 16.dp, Color.White)
                                        Text("Choose a player", style = HardwoodType.bodyBold, color = Color.White)
                                    }
                                }
                            }
                        }
                    }
                    if (!store.isPro) {
                        BlurGateUnlock(
                            "Stack any two players, or any player against his own past seasons",
                            PaywallTrigger.PlayerComparison,
                            Modifier.align(Alignment.BottomCenter).clip(RoundedCornerShape(HardwoodGeo.radiusCard)),
                        )
                    }
                }
            }
        }
    }

    StatScoutSheet(showingFollowSheet, { showingFollowSheet = false }) { FollowPlayersSheet(vm) { showingFollowSheet = false } }
    StatScoutSheet(picker != null, { picker = null }) {
        when (val target = picker) {
            PickerTarget.TEAM_A, PickerTarget.TEAM_B -> {
                val season = if (target == PickerTarget.TEAM_A) teamSeasonA else teamSeasonB
                val phase = if (target == PickerTarget.TEAM_A) state.teamPhaseA else state.teamPhaseB
                // Every team with data, including the one in the other slot: a franchise against its own past.
                TeamPickerSheet(vm.players(season, phase).map { normalizedTeamAbbreviation(it.team) }.toSortedSet().toList(), { picker = null }) { team ->
                    picker = null
                    if (target == PickerTarget.TEAM_A) state.teamA = team else state.teamB = team
                }
            }
            null -> Unit
            else -> {
                val (season, phase) = when (target) {
                    PickerTarget.PLAYER_A -> seasonA to state.phaseA
                    PickerTarget.PLAYER_B -> seasonB to state.phaseB
                    else -> seasonA to state.yearPhase
                }
                val candidates = vm.players(season, phase).filter { c ->
                    when (target) {
                        PickerTarget.PLAYER_A -> (c.playerId != state.playerB?.playerId || season != seasonB || phase != state.phaseB)
                                        PickerTarget.PLAYER_B -> (c.playerId != state.playerA?.playerId || season != seasonA || phase != state.phaseA)
                                        else -> true
                    }
                }.sortedWith(compareByDescending<Player> { it.minutesPlayed }.thenBy { it.name })
                PlayerPickerSheet(candidates, "Select Player · " + SeasonLabel.display(season), season, vm.isHistoricalLoading, onCancel = { picker = null }) { selected ->
                    picker = null
                    when (target) {
                        PickerTarget.PLAYER_A -> state.playerA = selected
                        PickerTarget.PLAYER_B -> state.playerB = selected
                        else -> navigator.push(Route.YearCompareRoute(selected.playerId, selected.name, state.yearPhase))
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun YourPlayersCard(
    followed: List<Player>,
    isEmpty: Boolean,
    isPro: Boolean,
    inSlot: (Player) -> Boolean,
    onEdit: () -> Unit,
    onTap: (Player) -> Unit,
    onOpen: (Player) -> Unit,
    onUnfollow: (Player) -> Unit,
) {
    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar("YOUR PLAYERS", trailing = {
            Row(
                Modifier.heightIn(min = 28.dp).clip(CircleShape).clickable(onClick = onEdit).padding(horizontal = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SfIcon("star", 12.dp, HardwoodPalette.court)
                Text(if (isEmpty) "Add" else "Edit", style = HardwoodType.micro, color = HardwoodPalette.court)
            }
        })
        if (followed.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(vertical = 18.dp, horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Follow players to keep them one tap from a comparison, and to spot them on the Trends board.",
                    style = HardwoodType.small,
                    color = HardwoodPalette.inkSecondary,
                    textAlign = TextAlign.Center,
                )
                Box(
                    Modifier.heightIn(min = 44.dp).clickable(onClick = onEdit),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Follow players",
                        style = HardwoodType.smallBold,
                        color = Color.White,
                        modifier = Modifier.clip(CircleShape).background(HardwoodPalette.court).padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
        } else {
            followed.forEachIndexed { index, player ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    Row(
                        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).bottomHairline(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            Modifier.weight(1f).fillMaxSize().combinedClickable(onClick = { onTap(player) }, onLongClick = { menu = true })
                                .padding(start = HardwoodGeo.padInline, end = if (isPro) 6.dp else HardwoodGeo.padInline)
                                .semantics { contentDescription = if (isPro) "${player.name}. Loads ${player.name} into a comparison slot" else "${player.name}. Opens ${player.name}'s stats" },
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            PlayerHeadshot(player.team, player.initials, 34.dp)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(player.name, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
                                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
                            }
                            if (inSlot(player)) {
                                Text(
                                    "IN SLOT",
                                    style = HardwoodType.micro,
                                    color = Color.White,
                                    modifier = Modifier.clip(CircleShape).background(HardwoodPalette.court).padding(horizontal = 8.dp, vertical = 4.dp),
                                )
                            } else SfIcon(if (isPro) "plus.circle" else "chevron.right", 18.dp, HardwoodPalette.inkTertiary)
                        }
                        if (isPro) {
                            Box(
                                Modifier.width(44.dp).fillMaxSize().clickable { onOpen(player) }.semantics { contentDescription = "Open ${player.name}'s page" },
                                contentAlignment = Alignment.Center,
                            ) { SfIcon("chevron.right", 16.dp, HardwoodPalette.inkTertiary) }
                        }
                    }
                    DropdownMenu(menu, { menu = false }, containerColor = HardwoodPalette.surface) {
                        DropdownMenuItem(
                            text = { Text("Open player page", style = HardwoodType.body, color = HardwoodPalette.ink) },
                            leadingIcon = { SfIcon("person.text.rectangle", 18.dp, HardwoodPalette.inkSecondary) },
                            onClick = {
                                menu = false
                                onOpen(player)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Unfollow", style = HardwoodType.body, color = HardwoodPalette.performanceLow) },
                            leadingIcon = { SfIcon("star.slash", 18.dp, HardwoodPalette.performanceLow) },
                            onClick = {
                                menu = false
                                onUnfollow(player)
                            },
                        )
                    }
                }
            }
            Text(
                if (isPro) "Tap a player to load them into a slot below." else "Tap a player to see their stats. Head-to-head needs StatScout+.",
                style = HardwoodType.micro,
                color = HardwoodPalette.inkTertiary,
                modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun BigButton(title: String, enabled: Boolean, tag: String, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(12.dp))
            .background(if (enabled) HardwoodPalette.court else HardwoodPalette.inkTertiary)
            .clickable(enabled = enabled, onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, style = HardwoodType.bodyBold, color = Color.White) }
}

@Composable
private fun SeasonPill(
    vm: DashboardViewModel,
    seasons: List<Int>,
    season: Int,
    phase: SeasonPhase,
    label: String,
    enabled: Boolean,
    onSeason: (Int) -> Unit,
    onPhase: (SeasonPhase) -> Unit,
    onLocked: (Int) -> Unit,
) {
    SeasonPhasePicker(
        seasons = seasons,
        selectedSeason = season,
        selectedPhase = phase,
        isSeasonLocked = vm::isSeasonLocked,
        onSelectSeason = { if (vm.isSeasonLocked(it)) onLocked(it) else onSeason(it) },
        onSelectPhase = onPhase,
    ) { open ->
        ChipButton(if (enabled) open else ({}), Modifier.fillMaxWidth(), description = "Season and season type for $label") {
            Row(
                Modifier.fillMaxWidth().height(32.dp).clip(CircleShape).background(HardwoodPalette.surface)
                    .border(0.5.dp, HardwoodPalette.hairline, CircleShape).padding(horizontal = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FitText(SeasonLabel.display(season) + if (phase == SeasonPhase.PLAYOFFS) " · Playoffs" else "", HardwoodType.smallBold, HardwoodPalette.ink, Modifier.weight(1f, fill = false), minScale = 0.75f)
                SfIcon("chevron.down", 13.dp, HardwoodPalette.inkSecondary)
            }
        }
    }
}

@Composable
private fun SlotColumn(
    vm: DashboardViewModel,
    player: Player?,
    placeholder: String,
    season: Int,
    phase: SeasonPhase,
    modifier: Modifier,
    enabled: Boolean,
    onPickPlayer: () -> Unit,
    onPickSeason: (Int) -> Unit,
    onPickPhase: (SeasonPhase) -> Unit,
    onLocked: (Int) -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(HardwoodGeo.radiusCard)).background(HardwoodPalette.surfaceAlt)
                .clickable(enabled = enabled, onClick = onPickPlayer).padding(vertical = 12.dp).testTag("slot_$placeholder"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (player != null) {
                PlayerHeadshot(player.team, player.initials, 44.dp)
                FitText(player.name, HardwoodType.smallBold, HardwoodPalette.ink, minScale = 0.7f)
            } else {
                Box(Modifier.size(44.dp).clip(CircleShape).background(HardwoodPalette.surfaceAlt), contentAlignment = Alignment.Center) {
                    SfIcon("plus", 18.dp, HardwoodPalette.inkTertiary)
                }
                Text(placeholder, style = HardwoodType.small, color = HardwoodPalette.inkTertiary)
            }
        }
        SeasonPill(vm, vm.availableSeasons, season, phase, player?.name ?: placeholder, enabled, onPickSeason, onPickPhase, onLocked)
    }
}

@Composable
private fun TeamSlotColumn(
    vm: DashboardViewModel,
    team: String?,
    placeholder: String,
    season: Int,
    phase: SeasonPhase,
    modifier: Modifier,
    enabled: Boolean,
    onPickTeam: () -> Unit,
    onPickSeason: (Int) -> Unit,
    onPickPhase: (SeasonPhase) -> Unit,
    onLocked: (Int) -> Unit,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(HardwoodGeo.radiusCard)).background(HardwoodPalette.surfaceAlt)
                .clickable(enabled = enabled, onClick = onPickTeam).padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                Modifier.size(44.dp).clip(CircleShape).background(team?.let { TeamColor.color(it) } ?: HardwoodPalette.surfaceAlt),
                contentAlignment = Alignment.Center,
            ) {
                if (team != null) Text(displayTeamAbbr(team), style = HardwoodType.smallBold, color = Color.White)
                else SfIcon("plus", 16.dp, HardwoodPalette.inkTertiary)
            }
            FitText(team?.let(::teamFullName) ?: placeholder, if (team == null) HardwoodType.small else HardwoodType.smallBold, if (team == null) HardwoodPalette.inkTertiary else HardwoodPalette.ink, minScale = 0.7f)
        }
        // Team-scoped, so no All Time: a career line carries the last team and would miscredit the franchise.
        SeasonPill(vm, vm.seasonsExcludingAllTime, season, phase, team ?: placeholder, enabled, onPickSeason, onPickPhase, onLocked)
    }
}

@Composable
private fun TeamPickerSheet(teams: List<String>, onCancel: () -> Unit, onSelect: (String) -> Unit) {
    var searchText by remember { mutableStateOf("") }
    val filtered = if (searchText.isEmpty()) teams else teams.filter { teamFullName(it).contains(searchText, true) || it.contains(searchText, true) }
    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTopBar(title = "Select Team", leading = { TextAction("Cancel", HardwoodType.body, Color.White, onCancel) })
        SearchField(searchText, { searchText = it }, Modifier.padding(12.dp), prompt = "Search teams")
        LazyColumn(Modifier.fillMaxSize()) {
            items(filtered, key = { it }) { team ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).background(HardwoodPalette.surface).bottomHairline().clickable { onSelect(team) }
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(32.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                        FitText(displayTeamAbbr(team), HardwoodType.micro, Color.White, minScale = 0.6f)
                    }
                    Text(teamFullName(team), style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

/** A player's seasons side by side, reached from the Compare tab. */
@Composable
fun YearCompareDestination(route: Route.YearCompareRoute) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    var current by remember { mutableStateOf(route) }
    var picking by remember { mutableStateOf(false) }
    val history = vm.playerHistories[current.playerId].orEmpty()
        .filter { it.seasonPhase == current.phase && !StatScoutSeason.isAllTime(it.season ?: 0) }
    val latest = history.maxByOrNull { it.season ?: 0 }
    PushedScreen(current.playerName) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottomBarPadding())) {
            Row(
                Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().hardwoodCard().padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (latest != null) {
                    Row(
                        Modifier.weight(1f).clickable { navigator.push(Route.PlayerProfile(latest)) },
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        PlayerHeadshot(latest.team, latest.initials, 34.dp)
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(current.playerName, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
                            Text("${displayTeamAbbr(latest.team)} · ${latest.displayPosition}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
                        }
                    }
                } else Text(current.playerName, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, modifier = Modifier.weight(1f))
                ChipButton({ picking = true }, description = "Compare a different player's seasons") {
                    HardwoodChip(title = "Change", icon = "arrow.triangle.2.circlepath", trailing = ChipTrailing.Chevron)
                }
            }
            if (history.size < 2) {
                EmptyState(
                    "Not enough history",
                    "calendar.badge.clock",
                    if (vm.isHistoricalLoading) "Loading past seasons for ${current.playerName}…" else "${current.playerName} doesn't have multiple seasons of data to compare.",
                    Modifier.padding(vertical = 40.dp),
                )
            } else YearComparisonView(history)
        }
    }
    StatScoutSheet(picking, { picking = false }) {
        PlayerPickerSheet(vm.players(vm.selectedSeason, current.phase), "Select Player · " + SeasonLabel.display(vm.selectedSeason), vm.selectedSeason, vm.isHistoricalLoading, onCancel = { picking = false }) { p ->
            picking = false
            current = Route.YearCompareRoute(p.playerId, p.name, current.phase)
        }
    }
}
