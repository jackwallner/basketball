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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.LeagueDivision
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.isScorePending
import com.jackwallner.basketball.model.startedLabel
import com.jackwallner.basketball.model.leagueTeamAbbreviations
import com.jackwallner.basketball.model.searchMatches
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.HomeTopBar
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.SeasonPhaseNavPill
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.DataFreshnessView
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodMenu
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.MenuItem
import com.jackwallner.basketball.ui.components.MenuSection
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.theme.TeamColor

private enum class TeamsMode(val raw: String) {
    TEAMS("teams"), STANDINGS("standings"), POWER("power");

    companion object {
        fun from(raw: String?): TeamsMode = entries.firstOrNull { it.raw == raw } ?: TEAMS
    }
}

private const val MODE_KEY = "teams.view"

@Composable
fun TeamsScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    val navigator = LocalNavigator.current
    val actions = LocalAppActions.current
    var searchText by rememberSaveable { mutableStateOf("") }
    // Auto-enter the favorite team once per launch; popping back must not
    // re-push it, or the user can never reach the list.
    var didAutoEnterFavorite by rememberSaveable { mutableStateOf(false) }
    var mode by remember { mutableStateOf(TeamsMode.from(graph.defaults.getString(MODE_KEY))) }

    // Standings and power ratings are built from this season's games, so they
    // only exist on the live season.
    val showsLeagueTables = vm.selectedSeason == vm.freeSeason && vm.selectedPhase == SeasonPhase.REGULAR
    val isInitiallyLoading = (vm.isLoading || vm.isHistoricalLoading || vm.isRefreshing) && vm.teamsWithData.isEmpty()

    // On first Teams visit, drop the user straight into their favorite team (the
    // back button returns to the alphabetical list). Guarded so popping back or
    // revisiting the tab doesn't trap them by re-pushing.
    LaunchedEffect(isActive) {
        val favorite = favorites.team
        // A career selection has no franchise view to push into; the explanatory
        // state stays on screen instead.
        if (isActive && !didAutoEnterFavorite && !StatScoutSeason.isAllTime(vm.selectedSeason) && favorite != null && navigator.depth == 1) {
            didAutoEnterFavorite = true
            navigator.push(Route.Team(favorite))
        }
    }

    Column(Modifier.fillMaxSize()) {
        // Same header as Stats and Trends, so the season you are reading never
        // moves when you change tabs. No All Time here: a career row carries the
        // player's last team, so a franchise's "all time" list would credit it
        // with points scored elsewhere.
        HomeTopBar(leading = {
            SeasonPhaseNavPill(vm.seasonsExcludingAllTime, onLockedSeason = { actions.openTrialPitch(PaywallTrigger.LockedSeason(it)) })
        })
        GamesTeamsUi.LiveScorePolling()
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
                if (showsLeagueTables) {
                    DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp))
                }
                when {
                    StatScoutSeason.isAllTime(vm.selectedSeason) -> AllTimeUnavailableState()
                    isInitiallyLoading -> TeamsLoadingState()
                    else -> {
                        if (showsLeagueTables) {
                            HardwoodSegmented(
                                segments = listOf(
                                    Segment(TeamsMode.TEAMS, "Teams"),
                                    Segment(TeamsMode.STANDINGS, "Standings"),
                                    Segment(TeamsMode.POWER, "Power"),
                                ),
                                selection = mode,
                                onSelect = {
                                    mode = it
                                    graph.defaults.putString(MODE_KEY, it.raw)
                                },
                                modifier = Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp),
                            )
                        }
                        when (if (showsLeagueTables) mode else TeamsMode.TEAMS) {
                            TeamsMode.TEAMS -> AllTeamsSection(searchText) { searchText = it }
                            TeamsMode.STANDINGS -> StandingsTable()
                            TeamsMode.POWER -> PowerRankingsTable()
                        }
                    }
                }
                // Scroll-under spacer so the last grid row isn't trapped behind the floating tab bar.
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/**
 * The season is chosen once and shared across tabs, so picking All Time on
 * Stats and then opening Teams lands here. Rather than silently reinterpret the
 * selection (a franchise list built from career rows would credit each team
 * with points its players scored elsewhere) or silently change it back, this
 * says what it can't do and offers the one tap that fixes it.
 */
@Composable
private fun AllTimeUnavailableState() {
    val vm = LocalGraph.current.dashboard
    val haptic = rememberHaptic()
    // Newest season this user can actually open, so a free user isn't sent to a
    // paywalled year by a button labelled as the fix.
    val latestUnlockedSeason = vm.seasonsExcludingAllTime.firstOrNull { !vm.isSeasonLocked(it) } ?: vm.freeSeason
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).hardwoodCard().padding(vertical = 36.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SfIcon("shield.lefthalf.filled.slash", 32.dp, HardwoodPalette.inkTertiary)
        Text("Teams needs a single season", style = HardwoodType.cardTitle, color = HardwoodPalette.ink, textAlign = TextAlign.Center)
        Text(
            "Career totals follow the player, not the team: a career line carries whichever team he finished with, so an all-time roster would credit a franchise with points scored somewhere else. Pick a season to see its teams.",
            style = HardwoodType.small,
            color = HardwoodPalette.inkSecondary,
            textAlign = TextAlign.Center,
        )
        Box(
            Modifier.heightIn(min = 44.dp).clip(CircleShape)
                .clickable {
                    vm.selectedSeason = latestUnlockedSeason
                    haptic()
                }
                .testTag("showLatestSeason"),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Show " + SeasonLabel.display(latestUnlockedSeason),
                style = HardwoodType.smallBold,
                color = Color.White,
                modifier = Modifier.clip(CircleShape).background(HardwoodPalette.court).padding(horizontal = 18.dp, vertical = 9.dp),
            )
        }
    }
}

@Composable
private fun TeamsLoadingState() {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).hardwoodCard().padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(6) {
            Row(Modifier.fillMaxWidth().height(56.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(HardwoodPalette.surfaceAlt))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.size(width = 140.dp, height = 12.dp).clip(RoundedCornerShape(4.dp)).background(HardwoodPalette.surfaceAlt))
                    Box(Modifier.size(width = 40.dp, height = 10.dp).clip(RoundedCornerShape(4.dp)).background(HardwoodPalette.surfaceAlt))
                }
            }
        }
    }
}

/**
 * The division grid, with the pinned favorite above it. Each tile is a colour
 * disk with the abbreviation, a corner star for the favorite, and a long-press
 * menu to toggle it so the tile stays one-tap-to-navigate.
 */
@Composable
private fun AllTeamsSection(searchText: String, onSearchText: (String) -> Unit) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    val haptic = rememberHaptic()

    // The division grid always draws all 30 teams, so search and the count cover
    // them too. Filtering to teams with published rows meant that on opening night,
    // with two teams played, "Celtics" found nothing and the header read "2 teams"
    // above a grid of 30. Plain alphabetical by full team name; the favorite is
    // lifted into its own pinned section above the grid.
    val filteredTeams = if (vm.teamsWithData.isEmpty()) emptyList() else {
        val teams = if (searchText.isEmpty()) leagueTeamAbbreviations else leagueTeamAbbreviations.filter {
            teamFullName(it).searchMatches(searchText) || it.searchMatches(searchText)
        }
        teams.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { teamFullName(it) })
    }
    // The favorite, shown only when not actively searching so search results stay a single uninterrupted list.
    val pinnedFavorite = if (searchText.isEmpty()) favorites.team else null
    val gridTeams = if (pinnedFavorite == null) filteredTeams else filteredTeams.filter { it != pinnedFavorite }

    Column {
        SearchField(searchText, onSearchText, Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp), prompt = "Search teams")

        if (pinnedFavorite != null) {
            FavoriteTeamCard(
                abbr = pinnedFavorite,
                onRemove = {
                    favorites.setFavoriteTeam(null)
                    haptic()
                },
                modifier = Modifier.padding(horizontal = 12.dp).padding(bottom = 16.dp),
            )
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("ALL TEAMS", style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, modifier = Modifier.weight(1f))
            if (searchText.isEmpty()) {
                Text("${filteredTeams.size} teams", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
            } else {
                TextAction("Clear", HardwoodType.micro, HardwoodPalette.inkSecondary, { onSearchText("") })
            }
        }

        when {
            filteredTeams.isEmpty() -> {
                val noDataForSeason = searchText.isEmpty() && vm.teamsWithData.isEmpty()
                GamesTeamsUi.Unavailable(
                    icon = "magnifyingglass",
                    title = if (noDataForSeason) "No teams available" else "No teams found",
                    // Names the control, not a tab: the fix is the pill at the top of this screen.
                    description = if (noDataForSeason) {
                        "No team data yet for ${vm.selectedSeasonPhrase}. Pick another season from the pill at the top of the screen."
                    } else "Try a different search term.",
                    modifier = Modifier.padding(vertical = 48.dp),
                )
            }
            searchText.isEmpty() -> DivisionGrid()
            else -> {
                // A search result has no meaningful division shape, so it falls back to a flat run of whatever matched.
                Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    gridTeams.chunked(5).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { abbr -> Box(Modifier.weight(1f)) { TeamDot(abbr) } }
                            repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

/** The franchise's code in the season on screen: the 2007-08 Thunder played as the SuperSonics, and their rows say SEA. */
private val PREDECESSORS = mapOf("OKC" to listOf("SEA"), "BKN" to listOf("NJN"), "NOP" to listOf("NOH", "NOK"), "MEM" to listOf("VAN"))

internal fun seasonCode(abbr: String, present: Set<String>): String {
    if (abbr in present) return abbr
    return PREDECESSORS[abbr]?.firstOrNull { it in present } ?: abbr
}

/** Six labelled rows of five. Sized so the whole league sits on one screen. */
@Composable
private fun DivisionGrid() {
    val present = LocalGraph.current.dashboard.teamsWithData.toSet()
    Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LeagueDivision.entries.forEach { division ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(division.label.uppercase(), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    division.teams.forEach { abbr -> Box(Modifier.weight(1f)) { TeamDot(seasonCode(abbr, present)) } }
                }
            }
        }
    }
}

private data class RecordStatus(val text: String, val spoken: String, val color: Color)

/**
 * The team's record under each disk, or the score while it is playing. The
 * record is the live season's, so while the next season is pending it is the
 * finished one's, which the Teams header says.
 */
@Composable
private fun teamStatus(abbr: String): RecordStatus? {
    val vm = LocalGraph.current.dashboard
    if (vm.selectedSeason != vm.freeSeason || vm.selectedPhase != SeasonPhase.REGULAR) return null
    val game = vm.currentGame(abbr)
    if (game != null && (game.status() == GameStatus.IN_PROGRESS || game.status() == GameStatus.AWAITING_SCORE)) {
        vm.liveScore(game)?.let { live ->
            val mine = live.score(game.isHome(abbr))
            val theirs = live.score(!game.isHome(abbr))
            if (live.isFinal) {
                val result = if (mine > theirs) "W" else "L"
                return RecordStatus("$result $mine-$theirs", "${if (result == "W") "won" else "lost"} $mine to $theirs", HardwoodPalette.inkSecondary)
            }
            return RecordStatus("$mine-$theirs", "playing ${game.matchupLabel(abbr)}, $mine to $theirs", HardwoodPalette.performanceLow)
        }
        if (game.status() == GameStatus.IN_PROGRESS && !game.isScorePending()) {
            return RecordStatus("Live", "playing ${game.matchupLabel(abbr)}", HardwoodPalette.performanceLow)
        }
        val label = game.startedLabel(null)
        return RecordStatus(label, "${game.matchupLabel(abbr)}, ${label.lowercase()}", HardwoodPalette.inkSecondary)
    }
    vm.record(abbr)?.let { return RecordStatus(it, "record $it", HardwoodPalette.inkSecondary) }
    return null
}

/**
 * One team: the colour disk with its abbreviation, a favorite star when set,
 * and a long-press to toggle it. No full team name, at five across there isn't
 * room, and the team colours plus abbreviation are how people recognise a
 * team anyway.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TeamDot(abbr: String) {
    val favorites = LocalGraph.current.favorites
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val isFavorite = favorites.isFavoriteTeam(abbr)
    val status = teamStatus(abbr)
    HardwoodMenu(
        sections = listOf(
            MenuSection(
                null,
                listOf(
                    MenuItem(if (isFavorite) "Unfollow Team" else "Follow Team", icon = if (isFavorite) "star.slash" else "star.fill") {
                        favorites.setFavoriteTeam(if (isFavorite) null else abbr)
                        haptic()
                    },
                ),
            ),
        ),
    ) { openMenu ->
        Column(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
                .combinedClickable(
                    onClick = { navigator.push(Route.Team(abbr)) },
                    onLongClick = {
                        haptic()
                        openMenu()
                    },
                    onLongClickLabel = if (isFavorite) "Unfollow Team" else "Follow Team",
                )
                .clearAndSetSemantics {
                    contentDescription = listOfNotNull(teamFullName(abbr), status?.spoken).joinToString(", ")
                }
                .testTag("teamTile_$abbr"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Box(Modifier.heightIn(min = 48.dp).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(contentAlignment = Alignment.TopEnd) {
                    TeamAbbrDisk(abbr)
                    if (isFavorite) {
                        Box(
                            Modifier.offset(x = 3.dp, y = (-3).dp).size(16.dp).clip(CircleShape).background(HardwoodPalette.surface),
                            contentAlignment = Alignment.Center,
                        ) { SfIcon("star.fill", 11.dp, CrownYellow) }
                    }
                }
            }
            status?.let {
                FitText(it.text, HardwoodType.micro.copy(fontFeatureSettings = "tnum"), it.color, minScale = 0.75f, textAlign = TextAlign.Center)
            }
        }
    }
}

/** Team colour disk with the abbreviation centred, the compact unit the division grid is built from. */
@Composable
private fun TeamAbbrDisk(abbr: String) {
    Box(
        Modifier.size(48.dp).clip(CircleShape).background(TeamColor.color(abbr)).border(0.5.dp, Color.White.copy(alpha = 0.25f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        FitText(
            displayTeamAbbr(abbr), HardwoodType.smallBold, Color.White,
            Modifier.padding(horizontal = 2.dp), minScale = 0.6f, textAlign = TextAlign.Center,
        )
    }
}

// MARK: - Favorite Team Card

/**
 * Full-width "hero" row for the pinned favorite team. Reads as a featured item
 * distinct from the grid below: tap anywhere to open the team, tap the star to
 * unpin. This is what makes Favorite do something visible: your team is always
 * one tap away at the top of the list.
 */
@Composable
fun FavoriteTeamCard(abbr: String, modifier: Modifier = Modifier, onRemove: (() -> Unit)? = null) {
    val navigator = LocalNavigator.current
    Box(modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
                .background(HardwoodPalette.surfaceAlt)
                .border(1.5.dp, HardwoodPalette.court, RoundedCornerShape(HardwoodGeo.radiusCard))
                .clickable { navigator.push(Route.Team(abbr)) }
                .padding(14.dp)
                .testTag("favoriteTeamCard"),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.shadow(4.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f))
                    .size(52.dp).clip(CircleShape).background(TeamColor.color(abbr)),
                contentAlignment = Alignment.Center,
            ) { Text(abbr, color = Color.White, fontSize = 16.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("YOUR TEAM", style = HardwoodType.micro, color = HardwoodPalette.court)
                FitText(teamFullName(abbr), HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.8f)
            }
            Box(Modifier.padding(end = 36.dp)) { SfIcon("chevron.right", 16.dp, HardwoodPalette.inkTertiary) }
        }
        Box(
            Modifier.align(Alignment.TopEnd).padding(2.dp).size(48.dp).clip(CircleShape)
                .clickable { onRemove?.invoke() }
                .semantics { contentDescription = "Unfollow team" }
                .testTag("removeFavorite"),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(34.dp).clip(CircleShape).background(HardwoodPalette.surface).border(0.5.dp, HardwoodPalette.hairline, CircleShape),
                contentAlignment = Alignment.Center,
            ) { SfIcon("star.fill", 16.dp, CrownYellow) }
        }
    }
}

// MARK: - Team Row

/** A list row for one team: colour disk, full name, abbreviation, chevron. */
@Composable
fun TeamRowContent(abbr: String, isFavorite: Boolean, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().height(56.dp)
            .background(if (isFavorite) HardwoodPalette.surfaceAlt else HardwoodPalette.surface)
            .padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(TeamColor.color(abbr)), contentAlignment = Alignment.Center) {
            Text(abbr, style = HardwoodType.smallBold, color = Color.White)
        }
        Column(Modifier.weight(1f).padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(teamFullName(abbr), style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
            Text(abbr, style = HardwoodType.small, color = HardwoodPalette.inkTertiary)
        }
        Box(Modifier.padding(end = 12.dp)) { SfIcon("chevron.right", 14.dp, HardwoodPalette.inkTertiary) }
    }
}

// MARK: - Legacy Team Tile (for reference)

/** The older tile: a disk over the full team name, outlined in court green when favorited. */
@Composable
fun TeamTile(abbr: String, modifier: Modifier = Modifier, isFavorite: Boolean = false) {
    val shape = RoundedCornerShape(HardwoodGeo.radiusCard)
    Column(
        modifier.fillMaxWidth().clip(shape)
            .background(if (isFavorite) HardwoodPalette.surfaceAlt else HardwoodPalette.surface)
            .border(if (isFavorite) 2.dp else 0.5.dp, if (isFavorite) HardwoodPalette.court else HardwoodPalette.hairline, shape)
            .padding(vertical = 12.dp, horizontal = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(TeamColor.color(abbr)), contentAlignment = Alignment.Center) {
                Text(abbr, style = HardwoodType.smallBold, color = Color.White)
            }
            if (isFavorite) {
                Box(Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp)) { SfIcon("star.fill", 12.dp, CrownYellow) }
            }
        }
        FitText(
            teamFullName(abbr), HardwoodType.smallBold,
            if (isFavorite) HardwoodPalette.court else HardwoodPalette.ink,
            minScale = 0.7f, textAlign = TextAlign.Center,
        )
    }
}
