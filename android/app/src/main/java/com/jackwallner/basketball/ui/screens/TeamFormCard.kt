package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.MetricValueFormat
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.TeamAggregation
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.DualMetricBar
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.ui.components.MetricBar
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType

private enum class FormMode(val raw: String) {
    SEASON("Season"), RECENT("Recent"), BOTH("Both");

    val usesRecent: Boolean get() = this != SEASON
}

/**
 * Team "percentile rankings" card, the team-level analogue of the player
 * profile's percentile card. Pools the roster into one number per metric and
 * ranks it against the other twenty-nine teams, with a Season / Recent toggle
 * that mirrors the player page. Recent pools the league's 1 / 2 / 4 week
 * rolling windows the same way and is StatScout+ only.
 *
 * @param loadRecent the league's rows for one rolling window, loaded on demand.
 * @param supportsRecent false on a historical season, where Recent and Both are hidden.
 */
@Composable
fun TeamRankingsCard(
    team: String,
    season: Int,
    players: List<Player>,
    leaguePlayers: List<Player>,
    loadRecent: (suspend (RecentWindow) -> List<RecentForm>)?,
    onUpgradeTap: () -> Unit,
    seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    freshnessRevision: String? = null,
    freshnessStatus: DataFreshnessStatus? = null,
    supportsRecent: Boolean = true,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    var category by rememberSaveable { mutableStateOf(MetricCategory.SCORING) }
    var mode by rememberSaveable { mutableStateOf(FormMode.SEASON) }
    var window by rememberSaveable { mutableStateOf(RecentWindow.TWO_WEEKS) }
    var rowsByWindow by remember(team, season, seasonPhase, freshnessRevision) { mutableStateOf<Map<Int, List<RecentForm>>>(emptyMap()) }
    var loading by remember { mutableStateOf(false) }

    // The mode actually rendered: a historical season would otherwise sit in front of a permanently empty window.
    val effectiveMode = if (supportsRecent) mode else FormMode.SEASON

    LaunchedEffect(team, season, seasonPhase, effectiveMode, window, isPro, freshnessRevision ?: "none") {
        // Free users see a static teaser, never real team rows.
        val fetch = loadRecent ?: return@LaunchedEffect
        if (!effectiveMode.usesRecent || !isPro) return@LaunchedEffect
        val target = window
        loading = rowsByWindow[target.value] == null
        val rows = fetch(target)
        rowsByWindow = rowsByWindow + (target.value to rows)
        loading = false
    }

    val labels = remember(category) {
        BasketballMetricRegistry.definitions
            .filter { it.category == category && it.kind == MetricKind.ADVANCED }
            .sortedBy { it.priority }
            .map { it.label }
    }
    val seasonRows = remember(category, players, leaguePlayers) { seasonRows(labels, category, players, leaguePlayers) }
    val leagueRows = rowsByWindow[window.value].orEmpty()
    val recentByTeam = remember(leagueRows) { TeamAggregation.recentRosters(leagueRows) }
    val teamRows = recentByTeam[normalizedTeamAbbreviation(team)].orEmpty()

    // The recent bar for a label, or null when the window has no figure for it.
    fun recentMetric(label: String): Metric? {
        val key = RecentMetricKey.key(label) ?: return null
        if (RecentMetricKey.isSeasonTotal(label)) return null
        val own = TeamAggregation.recentValue(key, teamRows, label) ?: return null
        val others = recentByTeam.values.mapNotNull { TeamAggregation.recentValue(key, it, label) }
        return Metric(
            label = label,
            value = RecentMetricKey.format(own, label),
            percentile = TeamAggregation.percentile(own, others, higherIsBetter = !RecentMetricKey.lowerIsBetter(label)),
            category = category,
            id = "team-recent-$key",
        )
    }

    Column(Modifier.fillMaxWidth().hardwoodCard().testTag("teamRankingsCard")) {
        HardwoodSectionBar("TEAM ADVANCED STATS", trailing = if (isPro) null else ({ ProBadge() }))
        HardwoodTabs(
            MetricCategory.entries.map { it.raw },
            category.raw,
            { raw -> category = MetricCategory.from(raw) ?: category },
            Modifier.background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline),
        )
        if (supportsRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline, vertical = 8.dp)) {
                HardwoodSegmented(
                    FormMode.entries.map { Segment(it, it.raw, isLocked = !isPro && it != FormMode.SEASON) },
                    mode, { mode = it },
                    onLockedTap = { onUpgradeTap() },
                )
            }
        }
        if (effectiveMode.usesRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline).padding(bottom = 8.dp)) {
                HardwoodSegmented(RecentWindow.entries.map { Segment(it, it.segmentLabel) }, window, { window = it })
            }
        }

        when (effectiveMode) {
            FormMode.SEASON -> SeasonBars(seasonRows, players.isEmpty(), category)
            FormMode.RECENT -> if (!isPro) LockedRecent() else when {
                loading -> GamesTeamsUi.InlineSpinner("Loading recent form…")
                teamRows.isEmpty() -> Column(
                    Modifier.fillMaxWidth().padding(vertical = 22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SfIcon("calendar.badge.exclamationmark", 22.dp, HardwoodPalette.inkTertiary)
                    Text(emptyStateText(freshnessStatus, window), style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
                else -> {
                    val rows = labels.mapNotNull { recentMetric(it) }
                    // Season totals leave some categories with nothing to draw; say so rather than show a bare header.
                    if (rows.isEmpty()) EmptyAggregate(players.isEmpty(), category)
                    else {
                        rows.forEachIndexed { index, metric -> BarRow(metric, index) }
                        val games = teamRows.maxOfOrNull { it.games } ?: 0
                        Caption("${window.label} · ${if (games == 1) "1 game" else "$games games"}, ranked among the 30 teams")
                    }
                }
            }
            FormMode.BOTH -> when {
                !isPro -> LockedRecent()
                loading -> GamesTeamsUi.InlineSpinner("Loading recent form…")
                else -> seasonRows.forEachIndexed { index, metric ->
                    Box(
                        Modifier.fillMaxWidth()
                            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                            .bottomHairline(HardwoodPalette.divider)
                            .padding(horizontal = HardwoodGeo.padCard, vertical = 10.dp),
                    ) { DualMetricBar(metric, recentMetric(metric.label), window.segmentLabel) }
                }
            }
        }
    }
}

/** One bar per metric: the roster's pooled value, ranked among the teams. */
private fun seasonRows(labels: List<String>, category: MetricCategory, players: List<Player>, leaguePlayers: List<Player>): List<Metric> {
    if (players.isEmpty()) return emptyList()
    val league = TeamAggregation.rosters(leaguePlayers)
    return labels.mapNotNull { label ->
        val own = TeamAggregation.value(label, category, players) ?: return@mapNotNull null
        val others = league.values.mapNotNull { TeamAggregation.value(label, category, it) }
        val format = MetricValueFormat.inferred(
            players.mapNotNull { p -> p.metrics.firstOrNull { it.label == label && it.category == category }?.value },
        )
        Metric(
            label = label,
            value = format.string(own),
            percentile = TeamAggregation.percentile(
                own,
                others,
                higherIsBetter = BasketballMetricRegistry.definition(label, category)?.higherIsBetter ?: true,
            ),
            category = category,
            id = "teamavg-$label",
        )
    }
}

private fun emptyStateText(status: DataFreshnessStatus?, window: RecentWindow): String = when (status) {
    DataFreshnessStatus.PENDING, DataFreshnessStatus.PARTIAL, DataFreshnessStatus.CHECKING -> "Recent team data is still arriving"
    DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> "Recent team data is unavailable right now"
    else -> "No games in the ${window.prose}"
}

@Composable
private fun ProBadge() {
    Row(
        Modifier.clip(CircleShape).background(CrownYellow).padding(horizontal = 7.dp, vertical = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon("crown.fill", 11.dp, HardwoodPalette.midnight)
        Text("STATSCOUT+", style = HardwoodType.micro.copy(fontWeight = FontWeight.Bold), color = HardwoodPalette.midnight)
    }
}

@Composable
private fun SeasonBars(rows: List<Metric>, rosterEmpty: Boolean, category: MetricCategory) {
    val navigator = LocalNavigator.current
    if (rows.isEmpty()) {
        EmptyAggregate(rosterEmpty, category)
        return
    }
    Column {
        rows.forEachIndexed { index, metric ->
            BarRow(
                metric, index,
                Modifier.clickable(onClickLabel = "See the league leaderboard for ${metric.label}") {
                    navigator.push(Route.Metric(metric.label, metric.category))
                },
            )
        }
    }
    Caption("Season to date, the roster's rates weighted by minutes and ranked among the 30 teams")
}

@Composable
private fun Caption(text: String) {
    Text(
        text,
        style = HardwoodType.micro,
        color = HardwoodPalette.inkTertiary,
        modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 10.dp),
    )
}

@Composable
private fun BarRow(metric: Metric, index: Int, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth()
            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
            .bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp),
    ) { MetricBar(metric) }
}

@Composable
private fun EmptyAggregate(rosterEmpty: Boolean, category: MetricCategory) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        SfIcon("chart.bar.xaxis", 22.dp, HardwoodPalette.inkTertiary)
        Text(
            if (rosterEmpty) "No games played yet this season" else "No ${category.raw.lowercase()} numbers to rank for this roster",
            style = HardwoodType.small,
            color = HardwoodPalette.inkSecondary,
        )
    }
}

/**
 * Static, non-fetching preview for free users: illustrative team bars. No rows
 * are fetched and no real team data is shown, so the blur can't leak anything.
 */
@Composable
private fun LockedRecent() {
    val sample = listOf(
        Metric(id = "tt_ortg", label = "Pts/100", value = "121.4", percentile = 84, category = MetricCategory.SCORING),
        Metric(id = "tt_ts", label = "TS%", value = "60.1%", percentile = 77, category = MetricCategory.SCORING),
        Metric(id = "tt_ast", label = "AST%", value = "61.2%", percentile = 71, category = MetricCategory.PLAYMAKING),
        Metric(id = "tt_reb", label = "REB%", value = "52.8%", percentile = 66, category = MetricCategory.REBOUNDING),
    )
    Box(Modifier.fillMaxWidth()) {
        // The blurred sample is hidden from screen readers: it is illustrative, not real.
        Column(Modifier.blur(8.dp).clearAndSetSemantics { }) { sample.forEachIndexed { index, metric -> BarRow(metric, index) } }
        BlurGateUnlock(
            "See every team's last week, 2 week and 4 week form", PaywallTrigger.TeamView,
            Modifier.align(Alignment.BottomCenter),
        )
    }
}
