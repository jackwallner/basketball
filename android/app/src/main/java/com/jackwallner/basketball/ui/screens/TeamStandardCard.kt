package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.TeamAggregation
import com.jackwallner.basketball.model.metricNumericValue
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.HardwoodSubSectionBar
import com.jackwallner.basketball.ui.components.MetricBar
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.TrendArrow
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.util.Locale
import kotlin.math.abs

/** Shooting lines, ranked by percentage. Made and attempted are summed across the roster before dividing. */
private val SHOOTING_LABELS = listOf("FG%", "3P%", "FT%")

/** Per-game lines, in reading order. */
private val PER_GAME_LABELS = listOf("PPG", "RPG", "APG", "SPG", "BPG", "TOV", "PF")

private val LOWER_IS_BETTER = setOf("TOV", "PF")

/** The rolling-window column behind each per-game line. PF has none, so it stays a season line. */
private val RECENT_KEYS = mapOf("PPG" to "ppg", "RPG" to "rpg", "APG" to "apg", "SPG" to "spg", "BPG" to "bpg", "TOV" to "tov_pg")

/**
 * The traditional line for a whole team, percentile-mapped against the other 29.
 *
 * The percentile card next to it answers "how good is this team's scoring and
 * rebounding"; this answers "what actually happened". The ruler is the league's
 * thirty teams, not its several hundred players.
 *
 * @param loadRecent the league's rows for one rolling window, loaded on demand.
 * @param supportsRecent false on a historical season, where the Recent control is hidden.
 */
@Composable
fun TeamStandardCard(
    team: String,
    season: Int,
    players: List<Player>,
    leaguePlayers: List<Player>,
    loadRecent: (suspend (RecentWindow) -> List<RecentForm>)?,
    onUpgradeTap: () -> Unit,
    seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    supportsRecent: Boolean = true,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    var showingRecent by rememberSaveable { mutableStateOf(false) }
    var window by rememberSaveable { mutableStateOf(RecentWindow.TWO_WEEKS) }
    var rowsByWindow by remember(team, season, seasonPhase) { mutableStateOf<Map<Int, List<RecentForm>>>(emptyMap()) }
    var loading by remember { mutableStateOf(false) }

    // The toggle survives a season change, so on a historical season it would otherwise face an empty window.
    val isRecent = showingRecent && supportsRecent
    val line = remember(players) { teamLine(players) }

    LaunchedEffect(team, season, seasonPhase, isRecent, window, isPro) {
        val fetch = loadRecent ?: return@LaunchedEffect
        if (!isRecent || !isPro) return@LaunchedEffect
        val target = window
        loading = rowsByWindow[target.value] == null
        val rows = fetch(target)
        rowsByWindow = rowsByWindow + (target.value to rows)
        loading = false
    }

    Column(Modifier.fillMaxWidth().hardwoodCard().testTag("teamStandardCard")) {
        HardwoodSectionBar("TEAM STANDARD STATS")
        if (supportsRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline, vertical = 8.dp)) {
                HardwoodSegmented(
                    listOf(Segment(false, "Season"), Segment(true, "Recent", isLocked = !isPro)),
                    showingRecent, { showingRecent = it },
                    onLockedTap = { onUpgradeTap() },
                )
            }
        }
        if (isRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline).padding(bottom = 8.dp)) {
                HardwoodSegmented(RecentWindow.entries.map { Segment(it, it.segmentLabel) }, window, { window = it })
            }
            RecentContent(team, isPro, loading, window, line, rowsByWindow[window.value].orEmpty())
        } else {
            SeasonContent(line, leaguePlayers)
        }
    }
}

@Composable
private fun SeasonContent(line: Map<String, Double>, leaguePlayers: List<Player>) {
    if (line.isEmpty()) {
        EmptyLine("No standard stats for this roster")
        return
    }
    val league = remember(leaguePlayers) { TeamAggregation.rosters(leaguePlayers).values.map { teamLine(it) }.filter { it.isNotEmpty() } }
    BarGroup("SHOOTING", SHOOTING_LABELS, line, league, 0)
    BarGroup("PER GAME", PER_GAME_LABELS, line, league, SHOOTING_LABELS.size)
    Text(
        "Totals add up the current roster's season lines, so a player traded at the deadline brings his whole year with him. Ranked among the 30 teams.",
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 10.dp),
    )
}

@Composable
private fun BarGroup(title: String, labels: List<String>, line: Map<String, Double>, league: List<Map<String, Double>>, startIndex: Int) {
    val present = labels.filter { line[it] != null }
    if (present.isEmpty()) return
    HardwoodSubSectionBar(title)
    present.forEachIndexed { offset, label ->
        val value = line[label] ?: 0.0
        val metric = Metric(
            label = label,
            value = format(label, value),
            percentile = TeamAggregation.percentile(value, league.mapNotNull { it[label] }, higherIsBetter = label !in LOWER_IS_BETTER),
            category = category(label),
            id = "team-std-$label",
        )
        Box(
            Modifier.fillMaxWidth()
                .background(if ((startIndex + offset) % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                .bottomHairline(HardwoodPalette.divider)
                .padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp),
        ) { MetricBar(metric) }
    }
}

@Composable
private fun RecentContent(team: String, isPro: Boolean, loading: Boolean, window: RecentWindow, seasonLine: Map<String, Double>, leagueRows: List<RecentForm>) {
    if (!isPro) {
        Box(Modifier.fillMaxWidth()) {
            Column(Modifier.blur(8.dp).clearAndSetSemantics { }) {
                HardwoodSubSectionBar("PER GAME · ${window.label.uppercase()}")
                teaserRows(team, window, seasonLine).forEachIndexed { index, (label, then, now) ->
                    MoveLine(label, then, now, index, lowerIsBetter = false, hairline = false)
                }
            }
            BlurGateUnlock("See every team's last week, 2 week and 4 week form", PaywallTrigger.TeamView, Modifier.align(Alignment.BottomCenter))
        }
        return
    }
    if (loading) {
        GamesTeamsUi.InlineSpinner("Loading recent form…")
        return
    }
    val rows = teamRecentRows(team, leagueRows)
    if (rows.isEmpty()) {
        EmptyLine("No games in the ${window.prose}")
        return
    }
    // Season to window, not a percentile bar: a few weeks of team rebounds sits outside the
    // spread of thirty season figures more often than not, so the move is the real information.
    HardwoodSubSectionBar("PER GAME · ${window.label.uppercase()}")
    rows.forEachIndexed { index, (label, now) ->
        MoveLine(label, seasonLine[label], now, index, lowerIsBetter = label in LOWER_IS_BETTER, hairline = true)
    }
    Text(
        "Compared with the same team's season line.",
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 8.dp),
    )
}

@Composable
private fun MoveLine(label: String, then: Double?, now: Double, index: Int, lowerIsBetter: Boolean, hairline: Boolean) {
    Row(
        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeight)
            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
            .then(if (hairline) Modifier.bottomHairline(HardwoodPalette.divider) else Modifier)
            .padding(horizontal = HardwoodGeo.padCard),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, modifier = Modifier.width(68.dp))
        Text(
            if (then != null) "${format(label, then)} → ${format(label, now)}" else format(label, now),
            style = HardwoodType.small.copy(fontFeatureSettings = "tnum"),
            color = HardwoodPalette.inkSecondary,
        )
        Spacer(Modifier.weight(1f))
        if (then != null) TrendArrow(now - then, 1, lowerIsBetter)
    }
}

@Composable
private fun EmptyLine(message: String) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SfIcon("list.bullet.rectangle", 22.dp, HardwoodPalette.inkTertiary)
        Text(message, style = HardwoodType.small, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center)
    }
}

/**
 * Season line to an invented window, built from this team's real season rates so the
 * preview is the team on screen and redraws with the window picker. Only the window
 * column is fictional, and it stays behind the blur.
 */
private fun teaserRows(team: String, window: RecentWindow, seasonLine: Map<String, Double>): List<Triple<String, Double, Double>> {
    val base = if (seasonLine.isEmpty()) listOf("PPG" to 114.2, "RPG" to 44.3, "APG" to 26.1, "SPG" to 7.4)
    else listOf("PPG", "RPG", "APG", "SPG").mapNotNull { label -> seasonLine[label]?.let { label to it } }
    return base.map { (label, season) ->
        val seed = teaserSeed("$label-${window.value}-$team")
        // Plus or minus 6% of the season figure, the size of a real two-week swing.
        val swing = season * (seed % 13 - 6) / 100.0
        Triple(label, season, season + swing)
    }
}

/** Deterministic across launches, identical to iOS. */
private fun teaserSeed(text: String): Int {
    var acc = 7L
    text.codePoints().forEach { acc = (acc * 31 + it) % 100_003 }
    return abs(acc.toInt())
}

private fun category(label: String): MetricCategory = when (label) {
    "FG%", "3P%", "FT%", "PPG" -> MetricCategory.SCORING
    "APG", "TOV" -> MetricCategory.PLAYMAKING
    "RPG" -> MetricCategory.REBOUNDING
    else -> MetricCategory.DEFENSE
}

/**
 * One team's standard line: shooting rebuilt from summed makes and attempts,
 * points from the makes (2 x FGM + 3PM + FTM), and the other per-game lines
 * from each player's average times his games over the team's game count.
 */
internal fun teamLine(roster: List<Player>): Map<String, Double> {
    if (roster.isEmpty()) return emptyMap()
    val made = mutableMapOf<String, Double>()
    val attempts = mutableMapOf<String, Double>()
    val totals = mutableMapOf<String, Double>()
    var teamGames = 0.0
    for (player in roster) {
        val stats = player.standardStats.orEmpty().groupBy { it.label.uppercase() }.mapValues { it.value.first().value }
        val games = stats["G"]?.let(::metricNumericValue) ?: 0.0
        // Games played is per player; the maximum is the team's own count.
        teamGames = maxOf(teamGames, games)
        for (label in listOf("FG", "3P", "FT")) {
            val raw = stats[label] ?: continue
            val parts = raw.split("/", limit = 2).mapNotNull { metricNumericValue(it) }
            if (parts.size != 2) continue
            made[label] = (made[label] ?: 0.0) + parts[0]
            attempts[label] = (attempts[label] ?: 0.0) + parts[1]
        }
        for (label in listOf("RPG", "APG", "SPG", "BPG")) {
            stats[label]?.let(::metricNumericValue)?.let { totals[label] = (totals[label] ?: 0.0) + it * games }
        }
        for (label in listOf("TOV", "PF")) {
            stats[label]?.let(::metricNumericValue)?.let { totals[label] = (totals[label] ?: 0.0) + it }
        }
    }
    if (teamGames <= 0) return emptyMap()
    val line = mutableMapOf<String, Double>()
    for ((label, key) in listOf("FG%" to "FG", "3P%" to "3P", "FT%" to "FT")) {
        val a = attempts[key] ?: continue
        if (a > 0) line[label] = (made[key] ?: 0.0) / a * 100
    }
    val fg = made["FG"]
    val three = made["3P"]
    val ft = made["FT"]
    if (fg != null && three != null && ft != null && attempts.containsKey("FG") && attempts.containsKey("3P") && attempts.containsKey("FT")) {
        line["PPG"] = (2 * fg + three + ft) / teamGames
    }
    for ((label, total) in totals) line[label] = total / teamGames
    return line
}

/** This team's per-game lines over the window: each player's average times his games, over the team's games. */
private fun teamRecentRows(team: String, leagueRows: List<RecentForm>): List<Pair<String, Double>> {
    val rows = TeamAggregation.recentRosters(leagueRows)[normalizedTeamAbbreviation(team)].orEmpty()
    val teamGames = (rows.maxOfOrNull { it.games } ?: 0).toDouble()
    if (teamGames <= 0) return emptyList()
    return PER_GAME_LABELS.mapNotNull { label ->
        val key = RECENT_KEYS[label] ?: return@mapNotNull null
        if (rows.none { it.metrics[key] != null }) return@mapNotNull null
        label to rows.sumOf { (it.metrics[key] ?: 0.0) * it.games } / teamGames
    }
}

private fun format(label: String, value: Double): String =
    if (label in SHOOTING_LABELS) String.format(Locale.US, "%.1f%%", value) else String.format(Locale.US, "%.1f", value)
