package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameProjection
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.GameDay
import com.jackwallner.basketball.model.LiveScore
import com.jackwallner.basketball.model.isScorePending
import com.jackwallner.basketball.model.startedLabel
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.HomeTopBar
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.TeamColorDot
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The night's slate: who played whom, the finals, what is on next.
 *
 * This is the front door. Scores, schedule and box scores are free for
 * everyone; the analysis layers stay where they were.
 */
@Composable
fun GamesScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    var selectedDayId by rememberSaveable { mutableStateOf<String?>(null) }

    val days = vm.slateDays
    val selectedDay = days.firstOrNull { it.id == selectedDayId } ?: vm.currentGameDay
    val slate = selectedDay?.let { Game.slateOrder(vm.slateGames(it)) } ?: emptyList()
    val heading = dayHeading(selectedDay, slate)
    val favoriteGame = favorites.team?.let { team -> slate.firstOrNull { it.involves(team) } }

    // A day picked yesterday is not today's slate: when the current game day moves on, so does the tab.
    val currentDayId = vm.currentGameDay?.id
    var lastCurrentDayId by rememberSaveable { mutableStateOf(currentDayId) }
    LaunchedEffect(currentDayId) {
        if (currentDayId != lastCurrentDayId) {
            selectedDayId = null
            lastCurrentDayId = currentDayId
        }
    }

    Column(Modifier.fillMaxSize()) {
        HomeTopBar("Games · ${SeasonLabel.display(vm.slateGames.firstOrNull()?.season ?: vm.upcomingSeason ?: vm.freeSeason)}")
        GamesTeamsUi.RefreshBox(onRefresh = { vm.loadGames(force = true) }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                if (vm.slateGames.isEmpty()) {
                    EmptyState()
                } else {
                    DaySelector(days, selectedDay?.id, Modifier.padding(top = 10.dp)) { selectedDayId = it }
                    heading?.let {
                        Text(
                            it,
                            style = HardwoodType.micro,
                            color = HardwoodPalette.inkTertiary,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 8.dp),
                        )
                    }
                    SlateContent(slate, favoriteGame, selectedDay)
                }
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }

    // Re-reads the schedule while this tab is on screen: every two minutes while a
    // final is still waiting on its stats, every ten otherwise. Live scores come
    // from the league scoreboard every thirty seconds while a game is under way;
    // the backend itself only posts a score at the final.
    LaunchedEffect(isActive) {
        if (!isActive) return@LaunchedEffect
        while (true) {
            vm.loadGames()
            vm.refreshLiveScores()
            val now = Instant.now()
            if (vm.hasGamesUnderway(now)) {
                delay(30_000L)
                continue
            }
            val busy = vm.games.any { game ->
                when (game.status(now)) {
                    GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> true
                    GameStatus.FINAL -> {
                        val tipoff = game.tipoff
                        tipoff != null && !vm.hasStats(game) && java.time.Duration.between(tipoff, now).seconds < 12 * 3_600
                    }
                    GameStatus.UPCOMING -> false
                }
            }
            // Wake for the next tip-off rather than sleeping through it.
            val untilTip = vm.nextTipoff(now)?.let { java.time.Duration.between(now, it).toMillis() + 5_000 } ?: Long.MAX_VALUE
            delay(minOf(if (busy) 120_000L else 600_000L, maxOf(30_000L, untilTip)))
        }
    }
}

/** "Tue, Oct 20 · 2026-27 · 3 games". */
private fun dayHeading(day: GameDay?, slate: List<Game>): String? {
    day ?: return null
    val season = slate.firstOrNull()?.let { SeasonLabel.display(it.season) }
    val count = if (slate.size == 1) "1 game" else "${slate.size} games"
    return listOfNotNull(day.label, season, count).joinToString(" · ")
}

@Composable
private fun EmptyState() {
    val vm = LocalGraph.current.dashboard
    val scope = rememberCoroutineScope()
    if (vm.isGamesLoading) {
        GamesTeamsUi.Spinner("Loading games…", Modifier.padding(vertical = 64.dp))
        return
    }
    val failed = vm.gamesError != null
    GamesTeamsUi.Unavailable(
        icon = if (failed) "wifi.slash" else "calendar",
        title = if (failed) "Couldn't load games" else "No games scheduled",
        description = vm.gamesError ?: "The ${SeasonLabel.display(vm.upcomingSeason ?: vm.freeSeason)} schedule isn't published yet.",
        modifier = Modifier.padding(vertical = 48.dp),
    ) {
        Box(
            Modifier.heightIn(min = 44.dp).clip(CircleShape).background(HardwoodPalette.court)
                .clickable { scope.launch { vm.loadGames(force = true) } }
                .testTag("gamesRetry").padding(horizontal = 18.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Try Again", style = HardwoodType.smallBold, color = Color.White) }
    }
}

// MARK: - Day selector

@Composable
private fun DaySelector(days: List<GameDay>, selectedId: String?, modifier: Modifier = Modifier, onSelect: (String) -> Unit) {
    val haptic = rememberHaptic()
    val listState = rememberLazyListState()
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val viewportPx = with(LocalDensity.current) { maxWidth.roundToPx() }
        val halfChipPx = with(LocalDensity.current) { 40.dp.roundToPx() }
        // Keep the chosen day centred, on arrival and whenever it changes.
        LaunchedEffect(selectedId, days.size, viewportPx) {
            val index = days.indexOfFirst { it.id == selectedId }
            if (index >= 0) listState.animateScrollToItem(index, scrollOffset = -(viewportPx / 2 - halfChipPx))
        }
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(horizontal = 12.dp),
        ) {
            itemsIndexed(days, key = { _, day -> day.id }) { _, day ->
                val isSelected = day.id == selectedId
                Box(
                    Modifier.heightIn(min = 44.dp).clip(CircleShape)
                        .clickable {
                            onSelect(day.id)
                            haptic()
                        }
                        .semantics {
                            contentDescription = day.label
                            selected = isSelected
                            role = Role.Button
                        }
                        .testTag("dayChip_${day.id}"),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.height(32.dp).clip(CircleShape)
                            .background(if (isSelected) HardwoodPalette.court else HardwoodPalette.surface)
                            .border(0.5.dp, if (isSelected) Color.Transparent else HardwoodPalette.hairline, CircleShape)
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            day.shortLabel,
                            style = HardwoodType.smallBold,
                            color = if (isSelected) Color.White else HardwoodPalette.inkSecondary,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Slate

@Composable
private fun SlateContent(slate: List<Game>, favoriteGame: Game?, selectedDay: GameDay?) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val favorites = graph.favorites
    if (favoriteGame != null) GameSection("Your team", listOf(favoriteGame))
    val now = Instant.now()
    val remaining = slate.filter { it.id != favoriteGame?.id }
    // A game the scoreboard calls final sits with the finals before the schedule catches up.
    val started = remaining.filter { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }
    fun isDone(game: Game) = vm.liveScore(game)?.isFinal == true || game.isScorePending(now)
    val live = started.filter { !isDone(it) }
    val finals = started.filter { isDone(it) } + remaining.filter { it.status(now) == GameStatus.FINAL }
    val upcoming = remaining.filter { it.status(now) == GameStatus.UPCOMING }
    if (live.isNotEmpty()) GameSection("In progress", live)
    if (finals.isNotEmpty()) GameSection("Final", finals)
    if (upcoming.isNotEmpty()) GameSection("Upcoming", upcoming)

    if (upcoming.any { vm.projection(it) != null }) {
        Footnote(
            "Projected margins come from StatScout Power Ratings: each team's points per 100 possessions against an average team, adjusted for schedule, plus two and a half points for home court. Details on the Teams tab.",
            top = 12,
        )
    }

    // How last season ended, under the first night of the new one, until that night
    // tips off. Never when the slate is last season itself, which listed the Finals twice.
    if (vm.isSeasonPending && vm.upcomingGames.isNotEmpty() &&
        selectedDay?.id == vm.currentGameDay?.id &&
        slate.none { it.status() != GameStatus.UPCOMING } &&
        vm.lastPlayedGames.isNotEmpty()
    ) {
        GameSection("Last played · ${SeasonLabel.display(vm.freeSeason)}", vm.lastPlayedGames)
    }

    Footnote(
        if (favorites.team == null) "Scores update live while a game is on. Player stats usually follow within a few hours of the final. Follow a team from its page to pin its game here."
        else "Scores update live while a game is on. Player stats usually follow within a few hours of the final.",
        top = 8,
    )
}

@Composable
private fun Footnote(text: String, top: Int) {
    Text(
        text,
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = top.dp),
    )
}

@Composable
private fun GameSection(title: String, games: List<Game>) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard()) {
        HardwoodSectionBar(title)
        games.forEachIndexed { index, game ->
            // A playoff game reads by its series, not the regular-season record.
            val series = vm.seriesStatus(game)
            GameRow(
                game = game,
                hasStats = vm.hasStats(game),
                highlight = graph.favorites.team,
                awayRecord = if (series == null) vm.record(game.awayTeam, game) else null,
                homeRecord = if (series == null) vm.record(game.homeTeam, game) else null,
                projection = vm.projection(game),
                context = game.contextLine(series),
                live = vm.liveScore(game),
                modifier = Modifier
                    .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                    .clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) },
            )
        }
    }
}

// MARK: - Row

/**
 * Two stacked team lines with scores, and the status on the right.
 *
 * [awayRecord] and [homeRecord] are each team's record through this game: after
 * it for a final, going into it for one still to be played. [projection] is the
 * power ratings' projected margin, upcoming games only; [context] the series or
 * cup line above the teams; [live] the scoreboard's running score for a game
 * the schedule has no final for.
 */
@Composable
fun GameRow(
    game: Game,
    hasStats: Boolean,
    modifier: Modifier = Modifier,
    highlight: String? = null,
    awayRecord: String? = null,
    homeRecord: String? = null,
    projection: GameProjection? = null,
    context: String? = null,
    live: LiveScore? = null,
) {
    val status = game.status()
    val isUnderway = live?.isUnderway ?: (status == GameStatus.IN_PROGRESS)
    Column(
        modifier
            .fillMaxWidth()
            .bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)
            .clearAndSetSemantics {
                contentDescription = (listOfNotNull(context) + accessibilityText(game, status, hasStats, projection, live)).joinToString(", ")
            }
            .testTag("gameRow"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        context?.let { FitText(it.uppercase(), HardwoodType.micro, HardwoodPalette.court, minScale = 0.8f) }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                TeamLine(game, game.awayTeam, game.awayScore ?: live?.awayScore, status, awayRecord, highlight, live)
                TeamLine(game, game.homeTeam, game.homeScore ?: live?.homeScore, status, homeRecord, highlight, live)
            }
            Column(Modifier.width(104.dp), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    statusTitle(game, status, live),
                    style = HardwoodType.smallBold,
                    color = if (isUnderway) HardwoodPalette.performanceLow else HardwoodPalette.ink,
                    textAlign = TextAlign.End,
                )
                statusDetail(game, status, hasStats, projection, live)?.let {
                    Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.End)
                }
            }
            SfIcon("chevron.right", 14.dp, HardwoodPalette.inkTertiary)
        }
    }
}

@Composable
private fun TeamLine(game: Game, team: String, score: Int?, status: GameStatus, record: String?, highlight: String?, live: LiveScore?) {
    val isWinner = game.result(team) == "W"
    var dim = status == GameStatus.FINAL && !isWinner && game.result(team) != "T"
    if (live != null && live.isFinal) {
        val isHome = normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(game.homeTeam)
        dim = live.score(isHome) < live.score(!isHome)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        TeamColorDot(team, 10.dp)
        Text(
            displayTeamAbbr(team),
            style = HardwoodType.bodyBold,
            color = if (dim) HardwoodPalette.inkTertiary else HardwoodPalette.ink,
            modifier = Modifier.width(40.dp),
        )
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // The full name plus a record does not fit beside the score, so a row that carries a record shows the nickname.
            val name = if (record == null) teamFullName(team) else teamFullName(team).split(" ").lastOrNull() ?: team
            FitText(name, HardwoodType.small, HardwoodPalette.inkTertiary, Modifier.weight(1f, fill = false), minScale = 0.85f)
            record?.let {
                Text(it, style = HardwoodType.micro.copy(fontFeatureSettings = "tnum"), color = HardwoodPalette.inkTertiary, maxLines = 1, softWrap = false)
            }
            if (highlight != null && normalizedTeamAbbreviation(highlight) == normalizedTeamAbbreviation(team)) {
                SfIcon("star.fill", 10.dp, CrownYellow)
            }
        }
        if (score != null) {
            Text("$score", style = HardwoodType.statMed.copy(fontFeatureSettings = "tnum"), color = if (dim) HardwoodPalette.inkTertiary else HardwoodPalette.ink)
        }
    }
}

private fun statusTitle(game: Game, status: GameStatus, live: LiveScore?): String = when (status) {
    GameStatus.FINAL -> if (game.overtime) "Final/OT" else "Final"
    GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> game.startedLabel(live)
    GameStatus.UPCOMING -> game.tipoffLabel()
}

private fun statusDetail(game: Game, status: GameStatus, hasStats: Boolean, projection: GameProjection?, live: LiveScore?): String? {
    if (live != null) return if (live.isFinal) "Stats arriving" else "Live"
    return when (status) {
        GameStatus.FINAL -> if (hasStats) game.dayLabel() else "Stats arriving"
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> if (game.isScorePending()) "No score posted yet" else "Score updates live"
        GameStatus.UPCOMING -> projection?.label(game.homeTeam, game.awayTeam) ?: game.tipoff?.let { GamesTeamsUi.monthDay(it) }
    }
}

private fun accessibilityText(game: Game, status: GameStatus, hasStats: Boolean, projection: GameProjection?, live: LiveScore?): String {
    val away = teamFullName(game.awayTeam)
    val home = teamFullName(game.homeTeam)
    return when (status) {
        GameStatus.FINAL -> {
            val score = "$away ${game.awayScore ?: 0}, $home ${game.homeScore ?: 0}"
            "$score, ${statusTitle(game, status, live)}" + if (hasStats) "" else ", stats arriving"
        }
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE ->
            if (live != null) "$away ${live.awayScore}, $home ${live.homeScore}, ${if (live.isFinal) live.clockLabel else "live, ${live.clockLabel}"}"
            else "$away at $home, ${if (game.isScorePending()) "score pending" else "in progress"}"
        GameStatus.UPCOMING -> {
            val projected = projection?.let { ", projected ${it.label(game.homeTeam, game.awayTeam)}" } ?: ""
            "$away at $home, ${game.dayLabel()} at ${game.tipoff?.let { GamesTeamsUi.shortTime(it) } ?: "time TBD"}$projected"
        }
    }
}
