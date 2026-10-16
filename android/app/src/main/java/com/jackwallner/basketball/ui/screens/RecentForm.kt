package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.metricNumericValue
import com.jackwallner.basketball.model.swiftRoundDouble
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.InlineLoadError
import com.jackwallner.basketball.ui.components.MetricBar
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.gateBlur
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.launch

/**
 * Maps a raw value onto the league's season percentile scale by interpolating
 * the feed's own (value, percentile) pairs, so a recent-window bar sits on the
 * same ruler as the season bar. Direction lives in the points themselves.
 */
class LeaguePercentileCurve private constructor(private val points: List<Pair<Double, Double>>) {
    fun percentile(v: Double): Int {
        if (v <= points.first().first) return clamp(points.first().second)
        if (v >= points.last().first) return clamp(points.last().second)
        for (i in 1 until points.size) {
            if (v <= points[i].first) {
                val (v0, p0) = points[i - 1]
                val (v1, p1) = points[i]
                val t = if (v1 == v0) 0.0 else (v - v0) / (v1 - v0)
                return clamp(p0 + t * (p1 - p0))
            }
        }
        return clamp(points.last().second)
    }

    private fun clamp(p: Double): Int = swiftRoundDouble(p).toInt().coerceIn(1, 100)

    companion object {
        /** Two points are enough to interpolate, and two is what an opening week provides. */
        fun of(raw: List<Pair<Double, Double>>): LeaguePercentileCurve? {
            val sorted = raw.sortedBy { it.first }
            return if (sorted.size >= 2) LeaguePercentileCurve(sorted) else null
        }
    }
}

/** Per-metric curves for one population, keyed by season metric label. */
class LeaguePercentileCurves(players: List<Player>, categories: List<MetricCategory>, labels: List<String>) {
    private val byLabel: Map<String, LeaguePercentileCurve>

    init {
        val pool = players.filter { p -> categories.any { p.matchesPlayerType(it) } }
        byLabel = labels.mapNotNull { label ->
            val pts = pool.mapNotNull { p ->
                val m = p.metrics.firstOrNull { it.label == label && it.category in categories } ?: return@mapNotNull null
                val v = metricNumericValue(m.value) ?: return@mapNotNull null
                v to m.percentile.toDouble()
            }
            LeaguePercentileCurve.of(pts)?.let { label to it }
        }.toMap()
    }

    fun curve(label: String): LeaguePercentileCurve? = byLabel[label]
}

/** The empty-window line shared by the profile's recent cards. */
fun recentEmptyText(status: DataFreshnessStatus?, window: RecentWindow): String = when (status) {
    DataFreshnessStatus.PENDING, DataFreshnessStatus.PARTIAL, DataFreshnessStatus.CHECKING -> "Recent game data is still arriving"
    DataFreshnessStatus.OFFLINE, DataFreshnessStatus.FAILED -> "Recent game data is unavailable right now"
    else -> "No games in the ${window.prose}"
}

/** The recent bars, in the order the categories are read in. Season totals have no per-week figure on the season's ruler. */
private val barLabels = listOf("PPG", "TS%", "3P%", "APG", "TOV/G", "RPG", "SPG", "BPG", "MPG")

/**
 * Rolling 1 / 2 / 4 week form for one player. Free users see a blurred static
 * teaser with no fetch; StatScout+ loads the player's rolling rows once, then
 * switches windows locally.
 */
@Composable
fun RecentFormCard(
    player: Player,
    season: Int,
    leaguePlayers: List<Player>,
    fetchRecentForm: (suspend (Int, Int, SeasonPhase) -> List<RecentForm>)?,
    freshnessRevision: String?,
    freshnessStatus: DataFreshnessStatus?,
) {
    val isPro = LocalGraph.current.subscriptions.isPro
    val scope = rememberCoroutineScope()
    var forms by remember { mutableStateOf<Map<Int, RecentForm>>(emptyMap()) }
    var loading by remember { mutableStateOf(false) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var window by remember { mutableStateOf(RecentWindow.TWO_WEEKS) }
    val curves = remember(isPro, leaguePlayers.size, player.positionGroup) {
        if (isPro) LeaguePercentileCurves(
            leaguePlayers.filter { it.positionGroup == player.positionGroup },
            MetricCategory.entries,
            barLabels,
        ) else null
    }

    suspend fun load() {
        // Free users see a static teaser: no fetch, no battery cost.
        if (!isPro || fetchRecentForm == null) return
        loading = true
        loadError = null
        try {
            val rows = fetchRecentForm(player.playerId, season, player.seasonPhase)
            val byWindow = HashMap<Int, RecentForm>()
            for (row in rows) if ((byWindow[row.windowWeeks]?.touches ?: -1) < row.touches) byWindow[row.windowWeeks] = row
            forms = byWindow
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            loadError = "Couldn't load recent form."
        }
        loading = false
    }
    LaunchedEffect(player.playerId, season, player.seasonPhase, freshnessRevision, isPro) { load() }

    val form = forms[window.value]

    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        Column(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).bottomHairline(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.padding(horizontal = HardwoodGeo.padInline).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                SfIcon("flame.fill", 14.dp, HardwoodPalette.court)
                Text("RECENT FORM", style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, modifier = Modifier.weight(1f))
                if (!isPro) {
                    Row(
                        Modifier.clip(CircleShape).background(CrownYellow).padding(horizontal = 7.dp, vertical = 3.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SfIcon("crown.fill", 10.dp, HardwoodPalette.midnight)
                        Text("STATSCOUT+", style = HardwoodType.micro.copy(fontWeight = FontWeight.Bold), color = HardwoodPalette.midnight)
                    }
                }
            }
            HardwoodSegmented(
                RecentWindow.entries.map { Segment(it, it.segmentLabel) },
                window,
                { window = it },
                Modifier.padding(horizontal = HardwoodGeo.padInline).padding(bottom = 10.dp),
            )
        }
        if (isPro) {
            when {
                loading -> Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = HardwoodPalette.inkTertiary, strokeWidth = 2.dp)
                    Text("Loading recent form…", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
                loadError != null -> InlineLoadError(loadError!!) { scope.launch { load() } }
                form != null -> StatsBody(form, recentRows(form, curves))
                else -> Column(Modifier.fillMaxWidth().padding(vertical = 22.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SfIcon("calendar.badge.exclamationmark", 24.dp, HardwoodPalette.inkTertiary)
                    Text(recentEmptyText(freshnessStatus, window), style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
            }
        } else {
            Box {
                Column(Modifier.gateBlur()) { Teaser() }
                BlurGateUnlock("See last week, 2 week and 4 week form for any player", PaywallTrigger.RecentForm, Modifier.align(Alignment.BottomCenter))
            }
        }
    }
}

/** Static, non-fetching preview for free users: illustrative bars in the season format. */
@Composable
private fun Teaser() {
    val sample = listOf(
        Metric("PPG", "27.4", 94, MetricCategory.SCORING, id = "t_ppg"),
        Metric("TS%", "61.8%", 88, MetricCategory.SCORING, id = "t_ts"),
        Metric("APG", "7.1", 81, MetricCategory.PLAYMAKING, id = "t_apg"),
        Metric("RPG", "5.9", 76, MetricCategory.REBOUNDING, id = "t_rpg"),
    )
    Row(Modifier.padding(HardwoodGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Summary("G", "4")
        Summary("MIN", "138")
    }
    MetricBarList(sample)
}

@Composable
private fun StatsBody(form: RecentForm, rows: List<Metric>) {
    Row(Modifier.fillMaxWidth().padding(HardwoodGeo.padInline), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Summary("G", "${form.games}")
        Summary("MIN", "${form.minutes}")
        Spacer(Modifier.weight(1f))
        if (form.isSmallSample) {
            Text(
                "SMALL SAMPLE",
                style = HardwoodType.micro,
                color = Color.White,
                modifier = Modifier.clip(CircleShape).background(HardwoodPalette.inkTertiary).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
    MetricBarList(rows)
}

@Composable
fun MetricBarList(rows: List<Metric>) {
    rows.forEachIndexed { index, metric ->
        Box(
            Modifier.fillMaxWidth().background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).bottomHairline()
                .padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp),
        ) { MetricBar(metric) }
    }
}

@Composable
private fun Summary(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Text(label, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
        Text(value, style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
    }
}

/**
 * Window metrics as Metrics on the league season curve, so the recent bar sits
 * on the same ruler as the season card. Nothing is drawn that can't be placed.
 */
private fun recentRows(form: RecentForm, curves: LeaguePercentileCurves?): List<Metric> =
    barLabels.mapNotNull { label ->
        val key = RecentMetricKey.key(label) ?: return@mapNotNull null
        val value = form.metrics[key] ?: return@mapNotNull null
        val pct = curves?.curve(label)?.percentile(value) ?: return@mapNotNull null
        val definition = BasketballMetricRegistry.definitions.firstOrNull { it.label == label } ?: return@mapNotNull null
        Metric(label, RecentMetricKey.format(value, label), pct, definition.category, id = "recent-$key")
    }
