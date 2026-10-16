package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.DateText
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameBoxScore
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.isScorePending
import com.jackwallner.basketball.model.startedLabel
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.ChipTrailing
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodChip
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.PushedScreen
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
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CancellationException

/** Which game the team card shows, and why it is the one shown. */
private enum class FeaturedKind(val title: String) { LIVE("Live"), LAST("Last game"), NEXT("Next game") }

/**
 * In progress beats everything; a final from the last day beats the next game
 * (the result is what people open the page for the morning after); otherwise
 * the next tip-off, or the latest final once the schedule runs out.
 */
private fun featured(viewModel: DashboardViewModel, team: String, now: Instant = Instant.now()): Pair<FeaturedKind, Game>? {
    val games = viewModel.schedule(team)
    games.firstOrNull { it.status(now) == GameStatus.IN_PROGRESS || it.status(now) == GameStatus.AWAITING_SCORE }?.let { live ->
        val over = viewModel.liveScore(live)?.isFinal == true || live.isScorePending(now)
        return (if (over) FeaturedKind.LAST else FeaturedKind.LIVE) to live
    }
    val finals = games.filter { it.status(now) == GameStatus.FINAL }
    val last = finals.lastOrNull()
    val tip = last?.tipoff
    if (last != null && tip != null && Duration.between(tip, now).seconds < 24 * 3_600) return FeaturedKind.LAST to last
    games.firstOrNull { it.status(now) == GameStatus.UPCOMING }?.let { return FeaturedKind.NEXT to it }
    return last?.let { FeaturedKind.LAST to it }
}

/**
 * The game a team page leads with: the live one, last night's result, the next
 * tip-off, or, in the offseason, how the team's season ended. It sits above the
 * roster cards so the first thing a team page says is what happened on the
 * court. Under it: follow the team, open its schedule.
 */
@Composable
fun TeamGameCard(viewModel: DashboardViewModel = LocalGraph.current.dashboard, team: String) {
    val navigator = LocalNavigator.current
    val pick = featured(viewModel, team)
    GamesTeamsUi.LiveScorePolling()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (pick != null) {
            val (kind, game) = pick
            GameShell(
                heading(viewModel, team, kind, game),
                Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) }.testTag("teamGame"),
            ) {
                TeamColorDot(game.opponent(team), 10.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FitText(
                        "${game.matchupLabel(team)} · ${teamFullName(game.opponent(team))}",
                        HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.85f,
                    )
                    Text(gameDetail(viewModel, game), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
                }
                val line = game.resultLine(team)
                val live = viewModel.liveScore(game)
                if (line != null) {
                    Text(line, style = HardwoodType.statMed, color = GamesTeamsUi.resultColor(game.result(team)))
                } else if (live != null) {
                    Text(
                        "${live.score(game.isHome(team))}-${live.score(!game.isHome(team))}",
                        style = HardwoodType.statMed.copy(fontFeatureSettings = "tnum"),
                        color = HardwoodPalette.ink,
                    )
                }
                SfIcon("chevron.right", 14.dp, HardwoodPalette.inkTertiary)
            }
        }
        TeamActions(team)
    }
}

/**
 * "LAST GAME · 2025-26 · 56-26": the record belongs to the live season, so a
 * 2026-27 game has none yet. A playoff game says where its series stands instead.
 */
private fun heading(viewModel: DashboardViewModel, team: String, kind: FeaturedKind, game: Game): String {
    val record = if (game.season == viewModel.freeSeason) viewModel.record(team) else null
    val context = game.contextLine(viewModel.seriesStatus(game))
    return listOfNotNull(kind.title, SeasonLabel.display(game.season), context ?: record).joinToString(" · ").uppercase()
}

@Composable
private fun TeamActions(team: String) {
    val favorites = LocalGraph.current.favorites
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val abbr = normalizedTeamAbbreviation(team)
    val following = favorites.isFavoriteTeam(abbr)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        ChipLink(
            hint = if (following) "Stops pinning this team's games" else "Pins this team's games at the top of Games",
            modifier = Modifier.testTag("followTeam"),
            onClick = {
                favorites.setFavoriteTeam(if (following) null else abbr)
                haptic()
            },
        ) {
            HardwoodChip(
                title = if (following) "Following" else "Follow Team",
                icon = if (following) "star.fill" else "star",
                isActive = following,
            )
        }
        ChipLink(hint = "Opens the schedule", modifier = Modifier.testTag("teamSchedule"), onClick = { navigator.push(Route.TeamSchedule(abbr)) }) {
            HardwoodChip(title = "Schedule", icon = "calendar", trailing = ChipTrailing.None)
        }
    }
}

/** A chip with a 48dp touch target and an accessibility action label. */
@Composable
private fun ChipLink(hint: String, onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.heightIn(min = 44.dp).clip(CircleShape).clickable(onClickLabel = hint, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

private fun gameDetail(viewModel: DashboardViewModel, game: Game): String {
    viewModel.liveScore(game)?.let { live ->
        return if (live.isFinal) "${live.clockLabel} · stats arriving" else "Live · ${live.clockLabel}"
    }
    return when (game.status()) {
        GameStatus.FINAL -> "${game.dayLabel()} · " + if (viewModel.hasStats(game)) "box score" else "stats arriving"
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> game.startedLabel(null)
        GameStatus.UPCOMING -> "${game.dayLabel()}, ${game.tipoff?.let { GamesTeamsUi.shortTime(it) } ?: "time TBD"}"
    }
}

@Composable
private fun GameShell(
    heading: String,
    modifier: Modifier = Modifier,
    content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit,
) {
    Column(
        modifier.fillMaxWidth().hardwoodCard().padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(heading, style = HardwoodType.micro, color = HardwoodPalette.inkSecondary)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically, content = content)
    }
}

/** Games numbered within their phase: 1 to 82, then "P1", "P2"... The Cup final counts toward no record. */
internal fun numberedGames(games: List<Game>): List<Pair<Game, String>> {
    val counts = mutableMapOf<SeasonPhase, Int>()
    return games.map { game ->
        if (game.isCupFinal) return@map game to "Cup"
        val n = (counts[game.seasonPhase] ?: 0) + 1
        counts[game.seasonPhase] = n
        game to if (game.seasonPhase == SeasonPhase.REGULAR) "$n" else "P$n"
    }
}

/**
 * One team's schedule: every game, the opponent, the result or the tip-off.
 * The live season, then the upcoming one while it is pending, in the order
 * they happen. Opens on the next game not yet final.
 */
@Composable
fun TeamScheduleScreen(team: String) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val sections = vm.schedule(team).groupBy { it.season }.toSortedMap().map { it.key to it.value }
    val all = sections.flatMap { it.second }
    val nextId = (all.firstOrNull { !it.isFinal } ?: all.lastOrNull())?.id
    val listState = rememberLazyListState()
    var didScroll by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { vm.loadGames() }
    GamesTeamsUi.LiveScorePolling()
    // Index of the next game among the flattened lazy items (each section adds a header).
    LaunchedEffect(nextId) {
        if (didScroll || nextId == null) return@LaunchedEffect
        var index = 0
        for ((_, games) in sections) {
            index += 1
            val at = games.indexOfFirst { it.id == nextId }
            if (at >= 0) {
                listState.scrollToItem((index + at - 3).coerceAtLeast(0))
                didScroll = true
                return@LaunchedEffect
            }
            index += games.size + 1
        }
    }
    PushedScreen(teamFullName(team)) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 12.dp)) {
            sections.forEach { (season, games) ->
                val isLive = season == vm.freeSeason
                item(key = "header-$season") {
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = HardwoodGeo.radiusCard, topEnd = HardwoodGeo.radiusCard))) {
                        HardwoodSectionBar("${SeasonLabel.display(season)} schedule", trailing = (if (isLive) vm.record(team) else null)?.let { record ->
                            { Text(record, style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary) }
                        })
                    }
                }
                val numbered = numberedGames(games)
                itemsIndexed(numbered, key = { _, entry -> entry.first.id }) { index, (game, number) ->
                    val background = if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt
                    ScheduleRow(
                        vm, game, team, number,
                        Modifier.background(background).clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) },
                    )
                }
                item(key = "footer-$season") { Spacer(Modifier.height(12.dp)) }
            }
            if (sections.isEmpty()) {
                item {
                    Text(
                        if (vm.isGamesLoading) "Loading schedule…" else "Schedule not published yet",
                        style = HardwoodType.small,
                        color = HardwoodPalette.inkTertiary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp),
                    )
                }
            }
            item { Spacer(Modifier.padding(bottomBarPadding())) }
        }
    }
}

@Composable
private fun ScheduleRow(vm: DashboardViewModel, game: Game, team: String, number: String, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline).testTag("scheduleRow"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(number, style = HardwoodType.statSmall, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(30.dp))
        TeamColorDot(game.opponent(team), 10.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FitText(
                "${game.matchupLabel(team)} · ${teamFullName(game.opponent(team))}",
                HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.85f,
            )
            FitText(
                listOfNotNull(game.dayLabel(), vm.seriesStatus(game)?.gameLabel).joinToString(" · "),
                HardwoodType.micro, HardwoodPalette.inkTertiary, minScale = 0.85f,
            )
        }
        val line = game.resultLine(team)
        if (line != null) {
            Text(line, style = HardwoodType.statMed, color = GamesTeamsUi.resultColor(game.result(team)))
        } else {
            Text(
                if (game.status() == GameStatus.UPCOMING) game.tipoff?.let { GamesTeamsUi.shortTime(it) } ?: "TBD" else game.startedLabel(vm.liveScore(game)),
                style = HardwoodType.small,
                color = HardwoodPalette.inkSecondary,
            )
        }
        SfIcon("chevron.right", 14.dp, HardwoodPalette.inkTertiary)
    }
}

/**
 * A player's most recent game on his profile: opponent, result, his line, and
 * a way into the box score. Free, and real: the one-game answer to "how did he
 * look?" that the recent-form cards can't give until there are several games.
 *
 * @param viewModel the shared dashboard model, for the schedule and game logs.
 * @param player the player whose latest game is shown.
 * @param season the season the profile is reading.
 * @param phase the season type the profile is reading.
 */
@Composable
fun PlayerLastGameCard(
    viewModel: DashboardViewModel = LocalGraph.current.dashboard,
    player: Player,
    season: Int,
    phase: SeasonPhase,
) {
    val navigator = LocalNavigator.current
    var log by remember { mutableStateOf<PlayerGameLog?>(null) }
    var loadedKey by remember { mutableStateOf<String?>(null) }
    val key = "${player.playerId}-$season-${phase.raw}-${viewModel.freshnessRevision ?: "none"}"

    LaunchedEffect(key) {
        if (loadedKey == key) return@LaunchedEffect
        try {
            val logs = viewModel.fetchGameLogs(player.playerId, season, phase)
            log = logs.maxByOrNull { it.gameDate }
            loadedKey = key
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            loadedKey = null
        }
    }

    val current = log ?: return
    val game = current.gameId?.let { viewModel.game(it) }
    val team = current.team ?: player.team
    val line = GameBoxScore(listOf(current)).lines[0]
    val summary = GameBoxScore.summary(line)
    Column(
        Modifier.padding(top = 10.dp).fillMaxWidth().hardwoodCard()
            .then(
                if (game != null) Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) }
                else Modifier,
            )
            .padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)
            .testTag("lastGameCard"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            val series = game?.let { viewModel.seriesStatus(it) }
            val title = when {
                series != null -> "Last game · ${series.gameLabel}"
                game != null -> "Last game · ${game.dayLabel()}"
                else -> "Last game · ${DateText.gameDay(current.gameDate)}"
            }
            Text(title.uppercase(), style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, modifier = Modifier.weight(1f))
            if (game != null) {
                Text("Box score", style = HardwoodType.micro, color = HardwoodPalette.court)
                SfIcon("chevron.right", 12.dp, HardwoodPalette.court)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val matchup = if (game != null) game.matchupLabel(team) else "vs ${displayTeamAbbr(current.opponent ?: "")}"
            Text(matchup, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            game?.resultLine(team)?.let {
                Text(it, style = HardwoodType.statSmall, color = GamesTeamsUi.resultColor(game.result(team)))
            }
        }
        if (summary.isNotEmpty()) {
            Text(summary, style = HardwoodType.small.copy(fontFeatureSettings = "tnum"), color = HardwoodPalette.inkSecondary)
        }
        val shooting = GameBoxScore.shootingLine(line)
        if (shooting.isNotEmpty()) {
            FitText(shooting, HardwoodType.small.copy(fontFeatureSettings = "tnum"), HardwoodPalette.inkSecondary, minScale = 0.85f)
        }
    }
}

/**
 * Every game this season, newest first: opponent, result, and the player's
 * line. The night-by-night view an 82-game season is read in, free, and the
 * natural companion to the Pro rolling windows.
 *
 * @param viewModel the shared dashboard model, for the schedule and game logs.
 * @param player the player whose games are listed.
 * @param season the season the profile is reading.
 * @param phase the season type the profile is reading.
 */
@Composable
fun PlayerGameLogCard(
    viewModel: DashboardViewModel = LocalGraph.current.dashboard,
    player: Player,
    season: Int,
    phase: SeasonPhase,
) {
    var entries by remember { mutableStateOf<List<GameLogEntry>>(emptyList()) }
    var loadedKey by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf(false) }
    val key = "${player.playerId}-$season-${phase.raw}-${viewModel.freshnessRevision ?: "none"}"

    LaunchedEffect(key) {
        if (loadedKey == key) return@LaunchedEffect
        try {
            val logs = viewModel.fetchGameLogs(player.playerId, season, phase)
            entries = gameLogEntries(logs, player.team)
            loadedKey = key
            failed = false
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            failed = true
        }
    }

    Column(Modifier.fillMaxWidth().hardwoodCard().testTag("gameLogCard")) {
        HardwoodSectionBar("GAME LOG")
        if (entries.isEmpty()) {
            Text(
                if (failed) "Couldn't load games. Pull to refresh." else if (loadedKey == null) "Loading games…" else "No games yet this season.",
                style = HardwoodType.small,
                color = HardwoodPalette.inkSecondary,
                modifier = Modifier.align(Alignment.CenterHorizontally).padding(vertical = 20.dp),
            )
        } else {
            entries.forEachIndexed { index, entry ->
                GameLogRow(entry, viewModel, Modifier.background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt))
            }
        }
    }
}

/** One game in a player's log. */
private data class GameLogEntry(
    val id: String,
    val gameId: String?,
    val gameDate: java.time.Instant,
    val team: String,
    val opponent: String?,
    val summary: String,
    val shooting: String,
)

/**
 * One entry per game; a player with two rows in a game (a player ranked in two
 * position cohorts) reads as one line. Both rows carry the same box score, so
 * the first one speaks for the game.
 */
private fun gameLogEntries(logs: List<PlayerGameLog>, fallbackTeam: String): List<GameLogEntry> =
    logs.groupBy { it.gameId ?: it.gameDate.toString() }
        .map { (id, rows) ->
            val first = rows[0]
            val line = GameBoxScore(listOf(first)).lines.firstOrNull()
            GameLogEntry(
                id, first.gameId, first.gameDate, first.team ?: fallbackTeam, first.opponent,
                line?.let { GameBoxScore.summary(it) }.orEmpty(),
                line?.let { GameBoxScore.shootingLine(it) }.orEmpty(),
            )
        }
        .sortedByDescending { it.gameDate }

@Composable
private fun GameLogRow(entry: GameLogEntry, viewModel: DashboardViewModel, modifier: Modifier = Modifier) {
    val navigator = LocalNavigator.current
    val game = entry.gameId?.let { viewModel.game(it) }
    Row(
        modifier.fillMaxWidth()
            .then(if (game != null) Modifier.clickable(onClickLabel = "Opens the game") { navigator.push(Route.Game(game.id)) } else Modifier)
            .bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)
            .testTag("gameLogRow"),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            DateText.gameDay(entry.gameDate),
            style = HardwoodType.statSmall.copy(fontFeatureSettings = "tnum"),
            color = HardwoodPalette.inkTertiary,
            modifier = Modifier.width(44.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    game?.matchupLabel(entry.team) ?: "vs ${displayTeamAbbr(entry.opponent ?: "")}",
                    style = HardwoodType.bodyBold,
                    color = HardwoodPalette.ink,
                )
                game?.resultLine(entry.team)?.let {
                    Text(it, style = HardwoodType.statSmall, color = GamesTeamsUi.resultColor(game.result(entry.team)))
                }
            }
            Text(
                entry.summary.ifEmpty { "No box score line" },
                style = HardwoodType.small.copy(fontFeatureSettings = "tnum"),
                color = HardwoodPalette.inkSecondary,
            )
            if (entry.shooting.isNotEmpty()) {
                FitText(entry.shooting, HardwoodType.small.copy(fontFeatureSettings = "tnum"), HardwoodPalette.inkSecondary, minScale = 0.85f)
            }
        }
    }
}
