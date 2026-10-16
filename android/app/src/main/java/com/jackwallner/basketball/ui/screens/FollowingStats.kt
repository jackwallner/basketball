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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.FanStatsSelection
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.model.matchesSearch
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.HardwoodMenu
import com.jackwallner.basketball.ui.components.HardwoodInlinePill
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodTopBar
import com.jackwallner.basketball.ui.components.MenuItem
import com.jackwallner.basketball.ui.components.MenuSection
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatScoutSheet
import com.jackwallner.basketball.ui.components.TeamColorDot
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.components.CrownYellow

/** Your team and the players you follow, in the selected season and phase. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FollowingStatsView(vm: DashboardViewModel) {
    val favorites = LocalGraph.current.favorites
    val navigator = LocalNavigator.current
    var showingPlayers by remember { mutableStateOf(false) }
    val players = FanStatsSelection.players(favorites.playerIds, vm.seasonPlayers, vm.selectedSeason, vm.selectedPhase)
    val missing = favorites.playerIds.toSet().size - players.size
    RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 12.dp), contentPadding = bottomBarPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { Spacer(Modifier.height(0.dp)) }
            val team = favorites.team
            if (team != null && !StatScoutSeason.isAllTime(vm.selectedSeason)) item {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(HardwoodPalette.surface)
                        .clickable { navigator.push(Route.Team(team)) }.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TeamColorDot(team, 12.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("YOUR TEAM", style = HardwoodType.micro, color = HardwoodPalette.inkSecondary)
                        Text(teamFullName(team), style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                    }
                    SfIcon("chevron.right", 18.dp, HardwoodPalette.inkTertiary)
                }
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Your players", style = HardwoodType.cardTitle, color = HardwoodPalette.ink, modifier = Modifier.weight(1f))
                    TextAction(if (players.isEmpty()) "Follow players" else "Manage", HardwoodType.smallBold, HardwoodPalette.court, { showingPlayers = true })
                }
            }
            if (favorites.playerIds.isEmpty()) item {
                EmptyState(
                    "Keep your players close",
                    "star",
                    "Follow your favorites for their season stats and a shortcut to every profile. Following is free.",
                    actionTitle = "Choose players",
                ) { showingPlayers = true }
            }
            itemsIndexed(players, key = { _, p -> p.playerId }) { _, player ->
                var menu by remember { mutableStateOf(false) }
                Box {
                    PlayerCard(player, Modifier.combinedClickable(onClick = { navigator.push(Route.PlayerProfile(player)) }, onLongClick = { menu = true }))
                    DropdownMenu(menu, { menu = false }, containerColor = HardwoodPalette.surface) {
                        DropdownMenuItem(
                            text = { Text("Unfollow ${player.name}", style = HardwoodType.body, color = HardwoodPalette.ink) },
                            leadingIcon = { SfIcon("star.slash", 18.dp, HardwoodPalette.inkSecondary) },
                            onClick = {
                                menu = false
                                favorites.toggleFavorite(player.playerId)
                            },
                        )
                    }
                }
            }
            if (missing > 0) item {
                Text(
                    "$missing followed ${if (missing == 1) "player has" else "players have"} no published stats for this season and phase yet. They stay on your list.",
                    style = HardwoodType.small,
                    color = HardwoodPalette.inkSecondary,
                )
            }
        }
    }
    StatScoutSheet(showingPlayers, { showingPlayers = false }) { FollowPlayersSheet(vm) { showingPlayers = false } }
}

@Composable
private fun PlayerCard(player: Player, modifier: Modifier) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(HardwoodPalette.surface).then(modifier).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerHeadshot(player.team, player.initials, 36.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(player.name, style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
            }
            SfIcon("chevron.right", 18.dp, HardwoodPalette.inkTertiary)
        }
        val stats = FanStatsSelection.summary(player)
        if (stats.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                stats.forEach { stat ->
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(stat.value, style = HardwoodType.statMed, color = HardwoodPalette.court)
                        Text(stat.label, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                    }
                }
            }
        } else {
            Text("Open profile for available metrics", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
        }
    }
}

/** Pick the players you follow, in bulk. Free: following is what makes the app yours. */
@Composable
fun FollowPlayersSheet(vm: DashboardViewModel, onDone: () -> Unit) {
    val favorites = LocalGraph.current.favorites
    val haptic = rememberHaptic()
    var searchText by remember { mutableStateOf("") }
    var position by remember { mutableStateOf(PlayerPositionGroup.ALL) }
    // The live regular season, whatever season or phase the tab behind is on:
    // following is about current players.
    val all = vm.players(vm.freeSeason, SeasonPhase.REGULAR)
    // Ordered by when they were followed. A player missing from the live season
    // still shows (his latest season) so he can be unfollowed.
    val followed = favorites.playerIds.mapNotNull { id ->
        all.firstOrNull { it.playerId == id }
            ?: vm.playerHistories[id].orEmpty()
                .filter { it.seasonPhase == SeasonPhase.REGULAR && (it.season ?: 0) > 0 }
                .maxByOrNull { it.season ?: 0 }
    }
    val query = searchText.trim()
    // A search looks across every position: typing a center's name while the
    // Guards tab is up answered "No players match".
    val candidates = (if (query.isEmpty()) all.filter { position.includes(it) } else all.filter { it.matchesSearch(query) })
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    @Composable
    fun FollowRow(player: Player, index: Int) {
        val following = favorites.isFavorite(player.playerId)
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                .clickable {
                    favorites.toggleFavorite(player.playerId)
                    haptic()
                }
                .semantics { contentDescription = if (following) "Unfollow ${player.name}" else "Follow ${player.name}" }
                .padding(horizontal = HardwoodGeo.padInline),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlayerHeadshot(player.team, player.initials, 34.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(player.name, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
                Text("${displayTeamAbbr(player.team)} · ${player.displayPosition}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
            }
            SfIcon(if (following) "star.fill" else "star", 20.dp, if (following) CrownYellow else HardwoodPalette.inkTertiary)
        }
    }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTopBar(title = "Follow Players", trailing = { TextAction("Done", HardwoodType.smallBold, androidx.compose.ui.graphics.Color.White, onDone) })
        LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
            item {
                Row(
                    Modifier.padding(12.dp).fillMaxWidth().height(44.dp).clip(CircleShape).background(HardwoodPalette.surface)
                        .border(0.5.dp, HardwoodPalette.hairline, CircleShape).padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SfIcon("magnifyingglass", 16.dp, HardwoodPalette.inkTertiary)
                    Box(Modifier.weight(1f)) {
                        if (searchText.isEmpty()) Text("Search players", style = HardwoodType.body, color = HardwoodPalette.inkTertiary)
                        BasicTextField(
                            searchText, { searchText = it }, singleLine = true,
                            textStyle = HardwoodType.body.copy(color = HardwoodPalette.ink),
                            cursorBrush = SolidColor(HardwoodPalette.court),
                            modifier = Modifier.fillMaxWidth().testTag("followSearch"),
                        )
                    }
                    if (searchText.isNotEmpty()) SfIcon("xmark.circle.fill", 18.dp, HardwoodPalette.inkTertiary, Modifier.clickable { searchText = "" })
                }
            }
            // Always present, even at zero, so the list below never jumps under the next tap.
            item {
                Column(Modifier.padding(horizontal = 12.dp).fillMaxWidth().hardwoodCard()) {
                    HardwoodSectionBar("FOLLOWING (${followed.size})")
                    if (followed.isEmpty()) {
                        Box(Modifier.fillMaxWidth().height(HardwoodGeo.rowHeight), contentAlignment = Alignment.Center) {
                            Text("Nobody yet. Tap a star to follow.", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                        }
                    } else followed.forEachIndexed { i, p -> FollowRow(p, i) }
                }
            }
            item {
                Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().hardwoodCard()) {
                    // The same position tabs as the Stats board.
                    if (query.isEmpty()) {
                        HardwoodTabs(
                            PlayerPositionGroup.entries.map { it.raw },
                            position.raw,
                            { raw -> PlayerPositionGroup.entries.firstOrNull { it.raw == raw }?.let { position = it } },
                            Modifier.padding(top = 4.dp).semantics { contentDescription = "Position" },
                        )
                    }
                    if (candidates.isEmpty()) {
                        Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                            Text("No players match “$searchText”.", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                        }
                    } else candidates.forEachIndexed { i, p -> FollowRow(p, i) }
                }
            }
            item { Spacer(Modifier.windowInsetsPadding(WindowInsets.navigationBars)) }
        }
    }
}
