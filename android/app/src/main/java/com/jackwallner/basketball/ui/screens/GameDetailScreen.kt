package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameBoxScore
import com.jackwallner.basketball.model.GameDetail
import com.jackwallner.basketball.model.GameProjection
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.RatedValue
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.isScorePending
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.model.startedLabel
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.PercentileBarMini
import com.jackwallner.basketball.ui.components.PlusCTAStyle
import com.jackwallner.basketball.ui.components.PlusDirectCTA
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatGlossaryLink
import com.jackwallner.basketball.ui.components.TeamColorDot
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.nav.rememberRetained
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.theme.TeamColor
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.launch

/**
 * One game: the score first, then how the margin moved, the four factors, the
 * plays that decided it and the box score.
 */
@Composable
fun GameDetailScreen(gameId: String) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val game = vm.game(gameId)
    val scope = rememberCoroutineScope()

    // Fetched data outlives a pushed player profile, like SwiftUI view state.
    var detail by rememberRetained("detail") { mutableStateOf<GameDetail?>(null) }
    var isDetailLoading by rememberRetained("detailLoading") { mutableStateOf(false) }
    var detailFailed by rememberRetained("detailFailed") { mutableStateOf(false) }
    var logs by rememberRetained("logs") { mutableStateOf<List<PlayerGameLog>>(emptyList()) }
    var isLoading by rememberRetained("logsLoading") { mutableStateOf(false) }
    var loadError by rememberRetained("logsError") { mutableStateOf<String?>(null) }
    var boxTeam by rememberRetained("boxTeam") { mutableStateOf("") }

    /** Tracked apart from the box score, so a request in flight or one that failed never reads as "not published yet". */
    suspend fun loadDetail() {
        val current = vm.game(gameId)
        if (current == null || current.status() == GameStatus.UPCOMING) return
        isDetailLoading = detail == null
        try {
            vm.fetchGameDetail(gameId)?.let { detail = it }
            detailFailed = false
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            if (detail == null) detailFailed = true
        } finally {
            isDetailLoading = false
        }
    }

    suspend fun loadLogs(force: Boolean) {
        val current = vm.game(gameId) ?: return
        if (current.status() != GameStatus.FINAL && !vm.hasStats(current)) return
        if (!force && logs.isNotEmpty() && vm.hasStats(current)) return
        isLoading = logs.isEmpty()
        try {
            logs = vm.fetchGameLogs(gameId)
            loadError = null
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            if (logs.isEmpty()) loadError = "Couldn't load the box score. Pull to try again."
        }
        if (boxTeam.isEmpty()) boxTeam = current.awayTeam
        isLoading = false
    }

    LaunchedEffect(Unit) { vm.loadGames() }
    GamesTeamsUi.LiveScorePolling()
    LaunchedEffect(gameId, game?.let { vm.hasStats(it) } ?: false, vm.freshnessRevision ?: "none") {
        val details = async { loadDetail() }
        val lines = async { loadLogs(force = false) }
        details.await()
        lines.await()
    }

    val title = game?.let { "${displayTeamAbbr(it.awayTeam)} at ${displayTeamAbbr(it.homeTeam)}" } ?: "Game"
    PushedScreen(title) {
        GamesTeamsUi.RefreshBox(onRefresh = {
            vm.loadGames(force = true)
            loadLogs(force = true)
            loadDetail()
        }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                when {
                    game != null -> {
                        Header(game)
                        DetailBody(
                            game = game,
                            detail = detail,
                            isDetailLoading = isDetailLoading,
                            detailFailed = detailFailed,
                            logs = logs,
                            isLoading = isLoading,
                            loadError = loadError,
                            boxTeam = boxTeam,
                            onBoxTeam = { boxTeam = it },
                            onRetryDetail = { scope.launch { loadDetail() } },
                        )
                    }
                    vm.isGamesLoading -> GamesTeamsUi.Spinner(modifier = Modifier.padding(vertical = 64.dp))
                    else -> GamesTeamsUi.Unavailable("calendar.badge.exclamationmark", "Game not found", modifier = Modifier.padding(vertical = 48.dp))
                }
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

// MARK: - Header

@Composable
private fun Header(game: Game) {
    val vm = LocalGraph.current.dashboard
    val status = game.status()
    val live = vm.liveScore(game)
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard()
            .padding(vertical = 18.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColumn(game.awayTeam, game, "Away", Modifier.weight(1f))
            Column(
                Modifier.widthIn(min = 110.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                when {
                    game.isFinal -> ScoreLine(game.awayScore, game.result(game.awayTeam) != "L", game.homeScore, game.result(game.homeTeam) != "L")
                    live != null -> ScoreLine(
                        live.awayScore, !live.isFinal || live.awayScore > live.homeScore,
                        live.homeScore, !live.isFinal || live.homeScore > live.awayScore,
                    )
                    else -> Text(
                        if (status == GameStatus.UPCOMING) game.tipoffLabel() else game.startedLabel(null),
                        style = HardwoodType.cardTitle,
                        color = if (status == GameStatus.UPCOMING) HardwoodPalette.ink else HardwoodPalette.performanceLow,
                    )
                }
                Text(statusLine(game, status), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.Center)
            }
            TeamColumn(game.homeTeam, game, "Home", Modifier.weight(1f))
        }
        game.contextLine(vm.seriesStatus(game))?.let { context ->
            Text(context.uppercase(), style = HardwoodType.smallBold, color = HardwoodPalette.court, textAlign = TextAlign.Center)
        }
        Text(
            listOfNotNull(
                if (game.seasonPhase == SeasonPhase.PLAYOFFS && game.playoffRoundName == null) "Playoffs" else null,
                SeasonLabel.display(game.season),
                game.dayLabel(),
                game.stadium,
            ).joinToString(" · "),
            style = HardwoodType.micro,
            color = HardwoodPalette.inkTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ScoreLine(away: Int?, awayWinner: Boolean, home: Int?, homeWinner: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        ScoreText(away, awayWinner)
        Text("-", style = HardwoodType.statLarge, color = HardwoodPalette.inkTertiary)
        ScoreText(home, homeWinner)
    }
}

@Composable
private fun TeamColumn(team: String, game: Game, label: String, modifier: Modifier = Modifier) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val record = if (game.countsInStandings) vm.record(team, game) else null
    Column(
        modifier
            .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
            .clickable(onClickLabel = "Opens the team") { navigator.push(Route.Team(normalizedTeamAbbreviation(team))) }
            .padding(vertical = 4.dp)
            .testTag("gameTeam_$label"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(48.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
            FitText(
                displayTeamAbbr(team), HardwoodType.smallBold, Color.White,
                Modifier.padding(horizontal = 4.dp), minScale = 0.7f, textAlign = TextAlign.Center,
            )
        }
        // Two lines reserved either way, so "Portland Trail Blazers" and "Miami Heat" keep their badges level.
        Text(teamFullName(team), style = HardwoodType.smallBold, color = HardwoodPalette.ink, textAlign = TextAlign.Center, maxLines = 2, minLines = 2)
        Text((listOf(label) + listOfNotNull(record)).joinToString(" · "), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
    }
}

@Composable
private fun ScoreText(score: Int?, winner: Boolean) {
    Text(score?.toString() ?: "-", style = HardwoodType.statHero, color = if (winner) HardwoodPalette.ink else HardwoodPalette.inkTertiary)
}

@Composable
private fun statusLine(game: Game, status: GameStatus): String {
    val vm = LocalGraph.current.dashboard
    vm.liveScore(game)?.let { live -> return if (live.isFinal) live.clockLabel else "Live · ${live.clockLabel}" }
    return when (status) {
        GameStatus.FINAL -> if (game.overtime) "Final/OT" else "Final"
        GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> if (game.isScorePending()) "No score posted yet" else "Score updates live"
        // The date is on the line below; the projection is the news here.
        GameStatus.UPCOMING -> vm.projection(game)?.label(game.homeTeam, game.awayTeam) ?: ""
    }
}

// MARK: - Body

/**
 * Advanced first, the way analytics box scores read: how the game swung, how
 * each team played, the plays that decided it, who drove it. The traditional
 * box score follows for the counts.
 */
@Composable
private fun DetailBody(
    game: Game,
    detail: GameDetail?,
    isDetailLoading: Boolean,
    detailFailed: Boolean,
    logs: List<PlayerGameLog>,
    isLoading: Boolean,
    loadError: String?,
    boxTeam: String,
    onBoxTeam: (String) -> Unit,
    onRetryDetail: () -> Unit,
) {
    val vm = LocalGraph.current.dashboard
    when {
        detail != null || logs.isNotEmpty() -> {
            when {
                detail != null -> {
                    if (detail.margin.size > 2) MarginCard(detail, game)
                    FactorsCard(detail, game)
                    if (detail.bigPlays.isNotEmpty()) BigPlaysCard(detail, game)
                    PlayerLinesCards(detail, game, boxTeam, onBoxTeam)
                }
                isDetailLoading -> GamesTeamsUi.Spinner("Loading advanced breakdown…", Modifier.padding(vertical = 40.dp))
                detailFailed -> Notice(
                    "wifi.exclamationmark",
                    "Couldn't load the advanced breakdown",
                    "The score margin and four factors didn't load. Check your connection and try again.",
                    action = "Try Again" to onRetryDetail,
                )
                else -> Notice(
                    "chart.xyaxis.line",
                    "Advanced breakdown on the way",
                    "The score margin, four factors and player ratings post once play-by-play is published, usually within a few hours of the final.",
                )
            }
            if (logs.isNotEmpty()) {
                val box = GameBoxScore(logs)
                SectionHeading("Box score")
                LeadersCard(box, game)
                TeamStatsCard(box, game)
                BoxScoreCard(box, game, boxTeam, onBoxTeam, showPicker = !LocalGraph.current.subscriptions.isPro || detail == null)
            }
            Footnote(
                "Percentiles rank each number against every team game (or every player game of ten minutes or more) this season, and update as new games arrive. The four factors are eFG%, turnover rate, offensive rebound rate and free throw rate.",
            )
            Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
        }
        isLoading -> GamesTeamsUi.Spinner("Loading box score…", Modifier.padding(vertical = 40.dp))
        loadError != null -> Footnote(loadError)
        else -> when (game.status()) {
            GameStatus.FINAL -> Notice(
                "clock.arrow.circlepath",
                "Stats arriving",
                "The final score is in. Player stats usually post within a few hours of the final buzzer.",
            )
            GameStatus.IN_PROGRESS, GameStatus.AWAITING_SCORE -> when {
                vm.liveScore(game)?.isFinal == true -> Notice(
                    "clock.arrow.circlepath",
                    "Stats arriving",
                    "The game is final. Player stats usually post within a few hours of the final buzzer.",
                )
                game.isScorePending() -> Notice(
                    "clock.arrow.circlepath",
                    "Score pending",
                    "No score has posted for this game yet. It shows here once the final is in.",
                )
                else -> Notice("basketball.fill", "Game in progress", "The score updates live. The box score posts after the final.")
            }
            GameStatus.UPCOMING -> UpcomingCard(game)
        }
    }
}

@Composable
private fun SectionHeading(title: String) {
    Text(
        title.uppercase(),
        style = HardwoodType.sectionTitle,
        color = HardwoodPalette.inkSecondary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 24.dp),
    )
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp),
    )
}

@Composable
private fun FootnoteRow(text: String) {
    Text(
        text,
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 10.dp),
    )
}

/** A titled card: the section bar, then rows. */
@Composable
private fun CardBlock(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard()) {
        HardwoodSectionBar(title)
        content()
    }
}

@Composable
private fun Notice(icon: String, title: String, text: String, action: Pair<String, () -> Unit>? = null) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SfIcon(icon, 24.dp, HardwoodPalette.inkTertiary)
        Text(title, style = HardwoodType.cardTitle, color = HardwoodPalette.ink, textAlign = TextAlign.Center)
        Text(text, style = HardwoodType.small, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center)
        action?.let { (label, perform) ->
            Box(
                Modifier.padding(top = 4.dp).heightIn(min = 44.dp).clip(CircleShape).background(HardwoodPalette.surfaceSunk)
                    .clickable(onClick = perform).padding(horizontal = 18.dp),
                contentAlignment = Alignment.Center,
            ) { Text(label, style = HardwoodType.smallBold, color = HardwoodPalette.court) }
        }
    }
}

@Composable
private fun TeamLabel(team: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        TeamColorDot(team, 8.dp)
        Text(displayTeamAbbr(team), style = HardwoodType.smallBold, color = HardwoodPalette.ink)
    }
}

private fun stripe(index: Int): Color = if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt

/** "S. Gilgeous-Alexander" from "Shai Gilgeous-Alexander": a box score row has no room for a full first name. */
internal fun shortName(name: String): String {
    val parts = name.split(" ").filter { it.isNotEmpty() }
    if (parts.size <= 1) return name
    return "${parts.first().first()}. " + parts.drop(1).joinToString(" ")
}

// MARK: - Box score

@Composable
private fun boxPlayer(game: Game, line: GameBoxScore.PlayerLine): Player? =
    LocalGraph.current.dashboard.player(line.playerId, game.season, game.seasonPhase)

/** A tappable row when the player is in the dataset, a plain one if not. */
@Composable
private fun PlayerRow(game: Game, line: GameBoxScore.PlayerLine, index: Int, height: Dp? = null, content: @Composable () -> Unit) {
    val navigator = LocalNavigator.current
    val player = boxPlayer(game, line)
    Box(
        Modifier.fillMaxWidth()
            .then(if (height != null) Modifier.height(height) else Modifier.heightIn(min = 40.dp))
            .background(stripe(index))
            .then(if (player != null) Modifier.clickable { navigator.push(Route.PlayerProfile(player)) } else Modifier)
            .padding(horizontal = HardwoodGeo.padInline, vertical = if (height == null) 8.dp else 0.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

@Composable
private fun NameText(game: Game, line: GameBoxScore.PlayerLine) {
    FitText(
        boxPlayer(game, line)?.let { shortName(it.name) } ?: "Player ${line.playerId}",
        HardwoodType.smallBold,
        HardwoodPalette.ink,
        minScale = 0.85f,
    )
}

@Composable
private fun LeadersCard(box: GameBoxScore, game: Game) {
    CardBlock("Game leaders") {
        box.leaders.forEachIndexed { index, leader ->
            PlayerRow(game, leader.line, index) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        TeamColorDot(leader.line.team, 6.dp)
                        Text("${leader.title.uppercase()} · ${displayTeamAbbr(leader.line.team)}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
                    }
                    NameText(game, leader.line)
                    Text(leader.summary, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
            }
        }
    }
}

private fun percentText(value: Double): String = String.format(Locale.US, "%.1f%%", value)

private fun countText(value: Double): String = NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundLong(value))

private fun swiftRoundLong(value: Double): Long = if (value < 0) -Math.floor(-value + 0.5).toLong() else Math.floor(value + 0.5).toLong()

@Composable
private fun TeamStatsCard(box: GameBoxScore, game: Game) {
    val away = box.totals(game.awayTeam)
    val home = box.totals(game.homeTeam)
    CardBlock("Team stats") {
        Row(
            Modifier.fillMaxWidth().height(30.dp).background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padCard),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(displayTeamAbbr(game.awayTeam), style = HardwoodType.smallBold, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(64.dp))
            Spacer(Modifier.weight(1f))
            Text(displayTeamAbbr(game.homeTeam), style = HardwoodType.smallBold, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(64.dp), textAlign = TextAlign.End)
        }
        ComparisonRow(game, "Field goals", away.fieldGoalPercentage ?: 0.0, home.fieldGoalPercentage ?: 0.0, true, ::percentText)
        ComparisonRow(game, "Threes", away.threePointPercentage ?: 0.0, home.threePointPercentage ?: 0.0, true, ::percentText)
        ComparisonRow(game, "Free throws", away.freeThrowPercentage ?: 0.0, home.freeThrowPercentage ?: 0.0, true, ::percentText)
        ComparisonRow(game, "Rebounds", away.rebounds, home.rebounds, true, ::countText)
        ComparisonRow(game, "Assists", away.assists, home.assists, true, ::countText)
        ComparisonRow(game, "Steals", away.steals, home.steals, true, ::countText)
        ComparisonRow(game, "Blocks", away.blocks, home.blocks, true, ::countText)
        ComparisonRow(game, "Turnovers", away.turnovers, home.turnovers, false, ::countText)
        ComparisonRow(game, "Fouls", away.fouls, home.fouls, false, ::countText)
        FootnoteRow("Totals add up each team's player lines.")
    }
}

@Composable
private fun ComparisonRow(game: Game, label: String, away: Double, home: Double, higherIsBetter: Boolean, format: (Double) -> String) {
    val awayBetter = if (higherIsBetter) away > home else away < home
    val homeBetter = if (higherIsBetter) home > away else home < away
    Row(
        Modifier.fillMaxWidth().height(36.dp).padding(horizontal = HardwoodGeo.padCard)
            .clearAndSetSemantics {
                contentDescription = "$label: ${teamFullName(game.awayTeam)} ${format(away)}, ${teamFullName(game.homeTeam)} ${format(home)}"
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            format(away),
            style = HardwoodType.statMed.copy(fontWeight = if (awayBetter) FontWeight.Bold else FontWeight.Normal),
            color = if (awayBetter) HardwoodPalette.ink else HardwoodPalette.inkSecondary,
            modifier = Modifier.width(64.dp),
        )
        Text(label, style = HardwoodType.small, color = HardwoodPalette.inkSecondary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
        Text(
            format(home),
            style = HardwoodType.statMed.copy(fontWeight = if (homeBetter) FontWeight.Bold else FontWeight.Normal),
            color = if (homeBetter) HardwoodPalette.ink else HardwoodPalette.inkSecondary,
            modifier = Modifier.width(64.dp),
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun TeamPicker(game: Game, team: String, onSelect: (String) -> Unit) {
    HardwoodSegmented(
        segments = listOf(
            Segment(game.awayTeam, teamFullName(game.awayTeam)),
            Segment(game.homeTeam, teamFullName(game.homeTeam)),
        ),
        selection = team,
        onSelect = onSelect,
        modifier = Modifier.padding(horizontal = 12.dp).padding(top = 16.dp),
    )
}

private data class BoxColumn(val title: String, val width: Int, val value: (GameBoxScore.PlayerLine) -> String)

private val boxColumns = listOf(
    BoxColumn("MIN", 34) { "${it.minutes}" },
    BoxColumn("PTS", 34) { "${it.int("pts")}" },
    BoxColumn("REB", 34) { "${it.int("reb")}" },
    BoxColumn("AST", 34) { "${it.int("ast")}" },
    BoxColumn("FG", 50) { it.made("fgm", "fga") },
    BoxColumn("3P", 44) { it.made("fg3m", "fg3a") },
    BoxColumn("FT", 44) { it.made("ftm", "fta") },
    BoxColumn("STL", 34) { "${it.int("stl")}" },
    BoxColumn("BLK", 34) { "${it.int("blk")}" },
    BoxColumn("TO", 30) { "${it.int("tov")}" },
    BoxColumn("PF", 30) { "${it.int("pf")}" },
    BoxColumn("+/-", 40) { it.plusMinusText },
)

@Composable
private fun BoxScoreCard(box: GameBoxScore, game: Game, boxTeam: String, onBoxTeam: (String) -> Unit, showPicker: Boolean) {
    val team = boxTeam.ifEmpty { game.awayTeam }
    // The advanced player ratings carry their own picker for StatScout+; the traditional box score always needs one.
    if (showPicker) TeamPicker(game, team, onBoxTeam)
    val lines = box.rotation(team)
    CardBlock("${teamFullName(team)} box score") {
        FullBoxScore(game, lines)
        FootnoteRow(
            "Starters first, then the bench by minutes. Swipe the table for steals, blocks, turnovers and fouls." +
                if (lines.any { it.metrics["plus_minus"] != null }) "" else " Plus/minus starts in 2008-09.",
        )
    }
}

/** Every box-score column, the way a box score reads: names pinned on the left, the counts scrolling sideways. */
@Composable
private fun FullBoxScore(game: Game, lines: List<GameBoxScore.PlayerLine>) {
    val rowHeight = 40.dp
    Row(Modifier.fillMaxWidth()) {
        Column(Modifier.width(108.dp)) {
            Box(Modifier.fillMaxWidth().height(26.dp).background(HardwoodPalette.surfaceAlt).padding(start = HardwoodGeo.padInline), contentAlignment = Alignment.CenterStart) {
                Text("PLAYER", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
            }
            lines.forEachIndexed { index, line -> PlayerRow(game, line, index, rowHeight) { NameText(game, line) } }
        }
        Column(Modifier.weight(1f).horizontalScroll(rememberScrollState())) {
            Row(Modifier.height(26.dp).background(HardwoodPalette.surfaceAlt).padding(end = HardwoodGeo.padInline), verticalAlignment = Alignment.CenterVertically) {
                boxColumns.forEach { column ->
                    Text(column.title, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(column.width.dp), textAlign = TextAlign.End)
                }
            }
            lines.forEachIndexed { index, line ->
                Row(Modifier.height(rowHeight).background(stripe(index)).padding(end = HardwoodGeo.padInline), verticalAlignment = Alignment.CenterVertically) {
                    boxColumns.forEach { column ->
                        Text(column.value(line), style = HardwoodType.statSmall, color = HardwoodPalette.ink, maxLines = 1, modifier = Modifier.width(column.width.dp), textAlign = TextAlign.End)
                    }
                }
            }
        }
    }
}

// MARK: - Margin

/** "Q1".."Q4", then "OT", "2OT"... for the overtime periods. */
internal fun periodLabel(startingAt: Double): String {
    if (startingAt < 2880) return "Q${(startingAt / 720).toInt() + 1}"
    return quarterLabel(((startingAt - 2880) / 300).toInt() + 5)
}

/** The period number a play carries (5 is the first overtime). */
internal fun quarterLabel(period: Int): String = when {
    period <= 4 -> "Q$period"
    period == 5 -> "OT"
    else -> "${period - 4}OT"
}

/**
 * How the score margin moved: home ahead above the line, away ahead below it.
 * A step line, because the margin only changes when someone scores.
 */
@Composable
private fun MarginCard(detail: GameDetail, game: Game) {
    val points = detail.margin
    // Regulation is 48 minutes; each overtime adds five.
    val end = max(2880.0, points.lastOrNull()?.elapsed ?: 2880.0)
    val reach = max(6.0, ceil(points.maxOfOrNull { abs(it.homeMargin) } ?: 6.0))
    val homeColor = TeamColor.color(game.homeTeam)
    val awayColor = TeamColor.color(game.awayTeam)
    val leads = detail.largestLeads
    CardBlock("Margin") {
        Column(Modifier.padding(HardwoodGeo.padCard), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            MarginChart(
                points, end, reach, homeColor, awayColor, game,
                Modifier.fillMaxWidth().height(160.dp).semantics {
                    contentDescription = "Score margin chart, ${teamFullName(game.homeTeam)} against ${teamFullName(game.awayTeam)}"
                },
            )
            Text(
                "Score margin, play by play. Up is ${displayTeamAbbr(game.homeTeam)} ahead, down is ${displayTeamAbbr(game.awayTeam)} ahead." +
                    " Biggest leads: ${displayTeamAbbr(game.homeTeam)} ${leads.second}, ${displayTeamAbbr(game.awayTeam)} ${leads.first}.",
                style = HardwoodType.micro,
                color = HardwoodPalette.inkTertiary,
            )
        }
    }
}

@Composable
private fun MarginChart(
    points: List<GameDetail.MarginPoint>,
    end: Double,
    reach: Double,
    homeColor: Color,
    awayColor: Color,
    game: Game,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    val labelStyle = HardwoodType.micro.copy(color = HardwoodPalette.inkTertiary)
    val periodStarts = listOf(0.0, 720.0, 1440.0, 2160.0) +
        if (end > 2880) generateSequence(2880.0) { it + 300 }.takeWhile { it < end }.toList() else emptyList()
    Canvas(modifier) {
        val left = 34.dp.toPx()
        val bottom = 18.dp.toPx()
        val topPad = 6.dp.toPx()
        val right = 4.dp.toPx()
        val plotW = size.width - left - right
        val plotH = size.height - topPad - bottom
        fun x(elapsed: Double) = left + (elapsed / end).toFloat() * plotW
        fun y(margin: Double) = topPad + ((reach - margin) / (2 * reach)).toFloat() * plotH

        for (start in periodStarts) {
            drawLine(HardwoodPalette.divider, Offset(x(start), topPad), Offset(x(start), topPad + plotH), strokeWidth = 1f)
            drawText(measurer, periodLabel(start), Offset(x(start) + 2.dp.toPx(), topPad + plotH + 2.dp.toPx()), style = labelStyle)
        }
        for (level in listOf(-reach, 0.0, reach)) {
            val label = when {
                level > 0 -> displayTeamAbbr(game.homeTeam)
                level < 0 -> displayTeamAbbr(game.awayTeam)
                else -> "Even"
            }
            val layout = measurer.measure(label, labelStyle)
            val ty = (y(level) - layout.size.height / 2f).coerceIn(0f, size.height - bottom - layout.size.height)
            drawText(layout, topLeft = Offset(0f, ty))
        }

        // Filled areas either side of even, then the margin line over them.
        fun area(clamp: (Double) -> Double): Path {
            val path = Path()
            path.moveTo(x(points.first().elapsed), y(0.0))
            points.forEachIndexed { index, point ->
                if (index > 0) path.lineTo(x(point.elapsed), y(clamp(points[index - 1].homeMargin)))
                path.lineTo(x(point.elapsed), y(clamp(point.homeMargin)))
            }
            path.lineTo(x(points.last().elapsed), y(0.0))
            path.close()
            return path
        }
        drawPath(area { max(it, 0.0) }, homeColor.copy(alpha = 0.28f))
        drawPath(area { min(it, 0.0) }, awayColor.copy(alpha = 0.28f))
        drawLine(
            HardwoodPalette.inkTertiary, Offset(left, y(0.0)), Offset(left + plotW, y(0.0)), strokeWidth = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())),
        )
        val line = Path()
        points.forEachIndexed { index, point ->
            val px = x(point.elapsed)
            if (index == 0) line.moveTo(px, y(point.homeMargin))
            else {
                // stepEnd: hold the previous margin until this point, then jump.
                line.lineTo(px, y(points[index - 1].homeMargin))
                line.lineTo(px, y(point.homeMargin))
            }
        }
        drawPath(line, HardwoodPalette.ink, style = Stroke(width = 1.5.dp.toPx()))
    }
}

// MARK: - Four factors

internal enum class RateStyle {
    DECIMAL, PERCENT, RATIO, COUNT;

    fun format(value: Double): String = when (this) {
        DECIMAL -> String.format(Locale.US, "%.1f", value)
        PERCENT -> String.format(Locale.US, "%.1f", value) + "%"
        RATIO -> String.format(Locale.US, "%.2f", value)
        COUNT -> NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundLong(value))
    }
}

private data class FactorMetric(val label: String, val key: String, val style: RateStyle)

/** The four factors first, then the ratings and the points that explain them. */
private val factorMetrics = listOf(
    FactorMetric("Points", "pts", RateStyle.COUNT),
    FactorMetric("Off. rating", "ortg", RateStyle.DECIMAL),
    FactorMetric("Def. rating", "drtg", RateStyle.DECIMAL),
    FactorMetric("Pace", "pace", RateStyle.DECIMAL),
    FactorMetric("eFG%", "efg_pct", RateStyle.PERCENT),
    FactorMetric("TOV%", "tov_pct", RateStyle.PERCENT),
    FactorMetric("OREB%", "oreb_pct", RateStyle.PERCENT),
    FactorMetric("FT rate", "ft_rate", RateStyle.RATIO),
    FactorMetric("Points in paint", "points_in_paint", RateStyle.COUNT),
    FactorMetric("Fast-break points", "fast_break_points", RateStyle.COUNT),
    FactorMetric("Bench points", "bench_points", RateStyle.COUNT),
    FactorMetric("Biggest lead", "largest_lead", RateStyle.COUNT),
)

@Composable
private fun FactorsCard(detail: GameDetail, game: Game) {
    val away = detail.stats(game.awayTeam)
    val home = detail.stats(game.homeTeam)
    CardBlock("Four factors & ratings") {
        Row(
            Modifier.fillMaxWidth().height(30.dp).background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padCard),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TeamLabel(game.awayTeam)
            Text("Bars: percentile vs all team games", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            TeamLabel(game.homeTeam)
        }
        factorMetrics.forEachIndexed { index, metric ->
            if (away[metric.key] != null || home[metric.key] != null) FactorRow(metric, away, home, index, game)
        }
    }
}

@Composable
private fun FactorRow(metric: FactorMetric, away: Map<String, RatedValue>, home: Map<String, RatedValue>, index: Int, game: Game) {
    fun text(side: Map<String, RatedValue>): String = side[metric.key]?.let { metric.style.format(it.value) } ?: "-"
    fun pct(side: Map<String, RatedValue>): String = side[metric.key]?.percentile?.let { ", ${it.ordinal} percentile" } ?: ""
    Row(
        Modifier.fillMaxWidth().height(40.dp).background(stripe(index)).padding(horizontal = HardwoodGeo.padCard)
            .clearAndSetSemantics {
                contentDescription = "${metric.label}: ${teamFullName(game.awayTeam)} ${text(away)}${pct(away)}, ${teamFullName(game.homeTeam)} ${text(home)}${pct(home)}"
            },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RatedCell(text(away), away[metric.key]?.percentile, leading = true)
        FitText(metric.label, HardwoodType.small, HardwoodPalette.inkSecondary, Modifier.weight(1f), minScale = 0.8f, textAlign = TextAlign.Center)
        RatedCell(text(home), home[metric.key]?.percentile, leading = false)
    }
}

/** A value over a thin percentile bar, the value tinted by its rank. */
@Composable
private fun RatedCell(text: String, percentile: Int?, leading: Boolean) {
    Column(Modifier.width(64.dp), horizontalAlignment = if (leading) Alignment.Start else Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(text, style = HardwoodType.statMed, color = percentile?.let { HardwoodPalette.textColor(it) } ?: HardwoodPalette.ink)
        if (percentile != null) {
            PercentileBarMini(percentile, Modifier.width(44.dp).graphicsLayer { scaleX = if (leading) 1f else -1f }, height = 4.dp)
        } else {
            Spacer(Modifier.width(44.dp).height(4.dp))
        }
    }
}

// MARK: - Plays

/** "BOS +4", "Tied": the margin after a play, named for the side ahead. */
private fun marginText(homeMargin: Int, game: Game): String {
    if (homeMargin == 0) return "Tied"
    val ahead = if (homeMargin > 0) game.homeTeam else game.awayTeam
    return "${displayTeamAbbr(ahead)} +${abs(homeMargin)}"
}

@Composable
private fun BigPlaysCard(detail: GameDetail, game: Game) {
    CardBlock("Plays that decided it") {
        detail.bigPlays.forEachIndexed { index, play ->
            Row(
                Modifier.fillMaxWidth().background(stripe(index))
                    .padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)
                    .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Column(Modifier.width(66.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("${quarterLabel(play.qtr)} ${play.clock}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, maxLines = 1)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        TeamColorDot(play.team, 6.dp)
                        Text(displayTeamAbbr(play.team), style = HardwoodType.micro, color = HardwoodPalette.inkSecondary)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    play.kind?.let { kind ->
                        Text(
                            if (kind == GameDetail.BigPlay.Kind.LEAD_CHANGE) "LEAD CHANGE" else "LATE SCORE",
                            style = HardwoodType.micro,
                            color = HardwoodPalette.inkTertiary,
                        )
                    }
                    Text(play.description, style = HardwoodType.small, color = HardwoodPalette.ink, maxLines = 3)
                }
                Text(
                    marginText(play.homeMargin, game),
                    style = HardwoodType.statSmall,
                    color = HardwoodPalette.ink,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(54.dp),
                )
            }
        }
        FootnoteRow("The right-hand figure is the score margin after the play. Late scores are baskets in the last five minutes of the fourth quarter or overtime with the game inside five points.")
    }
}

// MARK: - Player ratings

@Composable
private fun PlayerLinesCards(detail: GameDetail, game: Game, boxTeam: String, onBoxTeam: (String) -> Unit) {
    val isPro = LocalGraph.current.subscriptions.isPro
    if (isPro) {
        val team = boxTeam.ifEmpty { game.awayTeam }
        val lines = detail.players(team)
        if (lines.isEmpty()) return
        TeamPicker(game, team, onBoxTeam)
        CardBlock("Player ratings") {
            Row(
                Modifier.fillMaxWidth().height(26.dp).background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("PLAYER", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
                listOf("MIN", "PTS", "REB", "AST", "TS%", "USG%", "+/-").forEach {
                    FitText(it, HardwoodType.micro, HardwoodPalette.inkTertiary, Modifier.width(40.dp), minScale = 0.8f, textAlign = TextAlign.End)
                }
            }
            lines.forEachIndexed { index, line -> RatingRow(line, index, game) }
            FootnoteRow("Bars rank each night against every player game of ten minutes or more this season.")
        }
    } else {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 12.dp).hardwoodCard().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SfIcon("lock.fill", 18.dp, HardwoodPalette.inkTertiary)
            Text("Every player's night, ranked", style = HardwoodType.cardTitle, color = HardwoodPalette.ink)
            Text(
                "Points, rebounds, assists, TS%, usage and plus/minus for every player, each ranked against the season.",
                style = HardwoodType.small,
                color = HardwoodPalette.inkSecondary,
                textAlign = TextAlign.Center,
            )
            PlusDirectCTA(PaywallTrigger.AdvancedBoxScore, PlusCTAStyle.CAPSULE)
        }
    }
}

@Composable
private fun RatingRow(line: GameDetail.PlayerLine, index: Int, game: Game) {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val player = vm.player(line.playerId, game.season, game.seasonPhase)
    fun rated(value: RatedValue?, style: RateStyle, signed: Boolean = false): Pair<String, Int?> {
        value ?: return "-" to null
        var text = style.format(value.value)
        if (signed && value.value > 0) text = "+$text"
        return text to value.percentile
    }
    val cells = listOf(
        (line.minutes?.toString() ?: "-") to null,
        rated(line.points, RateStyle.COUNT),
        rated(line.rebounds, RateStyle.COUNT),
        rated(line.assists, RateStyle.COUNT),
        rated(line.trueShooting, RateStyle.DECIMAL),
        rated(line.usage, RateStyle.DECIMAL),
        rated(line.plusMinus, RateStyle.COUNT, signed = true),
    )
    Row(
        Modifier.fillMaxWidth().heightIn(min = 40.dp).background(stripe(index))
            .then(if (player != null) Modifier.clickable { navigator.push(Route.PlayerProfile(player)) } else Modifier)
            .padding(horizontal = HardwoodGeo.padInline)
            .testTag("playerLineRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(line.team, 7.dp)
            FitText(shortName(player?.name ?: line.name ?: "Player"), HardwoodType.smallBold, HardwoodPalette.ink, minScale = 0.8f)
        }
        cells.forEach { (text, percentile) ->
            FitText(
                text,
                HardwoodType.statSmall.copy(fontWeight = if (percentile == null) FontWeight.Normal else FontWeight.SemiBold),
                percentile?.let { HardwoodPalette.textColor(it) } ?: HardwoodPalette.ink,
                Modifier.width(40.dp),
                minScale = 0.8f,
                textAlign = TextAlign.End,
            )
        }
    }
}

// MARK: - Upcoming

private data class MatchupRowData(val label: String, val away: String, val home: String, val edge: Int)

/** The preview a fan opens before tip-off: who is favoured, how the two teams compare, and the season series so far. */
@Composable
private fun UpcomingCard(game: Game) {
    val vm = LocalGraph.current.dashboard
    val rows = matchupRows(game)
    val projection = vm.projection(game)
    if (projection == null && rows.isEmpty()) {
        Notice(
            "calendar",
            "Not started yet",
            "The score updates live from tip-off, and the box score posts after the final. Scout both rosters from the team pages above.",
        )
        return
    }
    CardBlock("Matchup") {
        projection?.let { WinChance(it, game) }
        if (rows.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().height(26.dp).background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(displayTeamAbbr(game.awayTeam), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(96.dp))
                Spacer(Modifier.weight(1f))
                Text(displayTeamAbbr(game.homeTeam), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(96.dp), textAlign = TextAlign.End)
            }
            rows.forEachIndexed { index, row -> MatchupRow(row, index) }
        }
        seasonSeries(game)?.let { series ->
            Text(
                series,
                style = HardwoodType.smallBold,
                color = HardwoodPalette.ink,
                modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard).padding(top = 10.dp),
            )
        }
        FootnoteRow(matchupFootnote(game))
    }
}

@Composable
private fun matchupRows(game: Game): List<MatchupRowData> {
    val vm = LocalGraph.current.dashboard
    val rows = mutableListOf<MatchupRowData>()
    fun edge(away: Double, home: Double, higherIsBetter: Boolean = true): Int {
        if (away == home) return 0
        return if ((home > away) == higherIsBetter) 1 else -1
    }
    // Records and scoring belong to the season being played; a game from a season that hasn't started has neither.
    val away = vm.standings[normalizedTeamAbbreviation(game.awayTeam)]
    val home = vm.standings[normalizedTeamAbbreviation(game.homeTeam)]
    if (game.season == vm.freeSeason && away != null && home != null && away.games > 0 && home.games > 0) {
        rows += MatchupRowData("Record", away.record, home.record, edge(away.winPercentage, home.winPercentage))
        fun tenths(value: Double) = String.format(Locale.US, "%.1f", value)
        val ap = away.pointsFor.toDouble() / away.games
        val hp = home.pointsFor.toDouble() / home.games
        rows += MatchupRowData("PTS/G", tenths(ap), tenths(hp), edge(ap, hp))
        val aa = away.pointsAgainst.toDouble() / away.games
        val ha = home.pointsAgainst.toDouble() / home.games
        rows += MatchupRowData("OPP PTS/G", tenths(aa), tenths(ha), edge(aa, ha, higherIsBetter = false))
        if (away.streak != null && home.streak != null) rows += MatchupRowData("Streak", away.streak, home.streak, 0)
    }
    val ratings = vm.teamRatings.values.toList()
    val awayRating = vm.teamRating(game.awayTeam)
    val homeRating = vm.teamRating(game.homeTeam)
    if (awayRating != null && homeRating != null) {
        fun rank(value: Double, key: (TeamRating) -> Double): String = (ratings.count { key(it) > value } + 1).ordinal
        fun pair(label: String, key: (TeamRating) -> Double) {
            rows += MatchupRowData(
                label,
                "${TeamRating.signed(key(awayRating))} · ${rank(key(awayRating), key)}",
                "${TeamRating.signed(key(homeRating))} · ${rank(key(homeRating), key)}",
                edge(key(awayRating), key(homeRating)),
            )
        }
        pair("Power") { it.rating }
        pair("Offense") { it.offense }
        pair("Defense") { it.defense }
    }
    return rows
}

@Composable
private fun MatchupRow(row: MatchupRowData, index: Int) {
    Row(
        Modifier.fillMaxWidth().height(36.dp).background(stripe(index)).padding(horizontal = HardwoodGeo.padInline)
            .clearAndSetSemantics { contentDescription = "${row.label}: away ${row.away}, home ${row.home}" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FitText(
            row.away,
            if (row.edge < 0) HardwoodType.smallBold else HardwoodType.small,
            if (row.edge < 0) HardwoodPalette.ink else HardwoodPalette.inkSecondary,
            Modifier.width(96.dp),
            minScale = 0.8f,
        )
        Text(row.label, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f), textAlign = TextAlign.Center, maxLines = 1)
        FitText(
            row.home,
            if (row.edge > 0) HardwoodType.smallBold else HardwoodType.small,
            if (row.edge > 0) HardwoodPalette.ink else HardwoodPalette.inkSecondary,
            Modifier.width(96.dp),
            minScale = 0.8f,
            textAlign = TextAlign.End,
        )
    }
}

/** Two blues (PHI at NYK) read as one bar; the home side goes neutral when the colours are too close. */
private fun isClose(a: Color, b: Color): Boolean {
    val dr = a.red - b.red
    val dg = a.green - b.green
    val db = a.blue - b.blue
    return sqrt(dr * dr + dg * dg + db * db) < 0.3f
}

@Composable
private fun WinChance(projection: GameProjection, game: Game) {
    val home = projection.homeWinProbability
    val awayPct = swiftRoundLong((1 - home) * 100)
    val homePct = swiftRoundLong(home * 100)
    val awayColor = TeamColor.color(game.awayTeam)
    val homeColor = TeamColor.color(game.homeTeam).let { if (isClose(awayColor, it)) HardwoodPalette.inkTertiary else it }
    val label = projection.label(game.homeTeam, game.awayTeam)
    Column(
        Modifier.fillMaxWidth().padding(HardwoodGeo.padCard).clearAndSetSemantics {
            contentDescription = "Win chance: ${teamFullName(game.awayTeam)} $awayPct percent, ${teamFullName(game.homeTeam)} $homePct percent. Projected $label"
        },
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${displayTeamAbbr(game.awayTeam)} $awayPct%", style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
            Spacer(Modifier.weight(1f))
            Text("WIN CHANCE", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
            Spacer(Modifier.weight(1f))
            Text("$homePct% ${displayTeamAbbr(game.homeTeam)}", style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
        }
        BoxWithConstraints(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape)) {
            val awayWidth = max(0f, (maxWidth.value - 2f) * (1 - home).toFloat()).dp
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Box(Modifier.width(awayWidth).fillMaxHeight().background(awayColor))
                Box(Modifier.weight(1f).fillMaxHeight().background(homeColor))
            }
        }
        Text("Projected: $label", style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
    }
}

/** "Season series: NYK leads 2-1", from this season's finals between them. */
@Composable
private fun seasonSeries(game: Game): String? {
    if (game.seasonPhase != SeasonPhase.REGULAR) return null
    val meetings = LocalGraph.current.dashboard.schedule(game.awayTeam).filter {
        it.isFinal && it.season == game.season && it.countsInStandings && it.involves(game.homeTeam)
    }
    if (meetings.isEmpty()) return null
    val awayWins = meetings.count { it.result(game.awayTeam) == "W" }
    val homeWins = meetings.size - awayWins
    if (awayWins == homeWins) return "Season series tied $awayWins-$homeWins"
    val leader = if (awayWins > homeWins) game.awayTeam else game.homeTeam
    return "Season series: ${displayTeamAbbr(leader)} leads ${max(awayWins, homeWins)}-${min(awayWins, homeWins)}"
}

@Composable
private fun matchupFootnote(game: Game): String {
    // Ratings can trail the schedule; say which season they describe when it isn't this game's.
    val rated = LocalGraph.current.dashboard.teamRating(game.homeTeam)?.season ?: game.season
    val ratingSeason = if (rated == game.season) "" else " Ratings are from ${SeasonLabel.display(rated)} until this season has games."
    return "Win chance and margin come from StatScout Power Ratings: points per 100 possessions against an average team, adjusted for schedule, plus home court. Ranks are among all 30 teams." +
        ratingSeason + " The score updates live from tip-off."
}
