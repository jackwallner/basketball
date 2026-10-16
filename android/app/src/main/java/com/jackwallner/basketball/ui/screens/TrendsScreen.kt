package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.data.PaywallTrigger
import com.jackwallner.basketball.model.DateText
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.TrendStatMode
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.TrendMetric
import com.jackwallner.basketball.model.TrendSide
import com.jackwallner.basketball.model.TrendWindow
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.ui.HomeTopBar
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.SeasonPhaseNavPillFor
import com.jackwallner.basketball.ui.components.BlurGateUnlock
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.DataFreshnessView
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.HardwoodTabs
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatOption
import com.jackwallner.basketball.ui.components.StatPickerMenu
import com.jackwallner.basketball.ui.components.TrendArrow
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.cardSlice
import com.jackwallner.basketball.ui.components.gateBlur
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.time.Instant
import kotlinx.coroutines.launch

/**
 * League-wide recent form, ranked by change rather than by level: THEN to NOW
 * and the delta. Free users see the real leader, then the wall.
 */
@Composable
fun TrendsScreen(isActive: Boolean) {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    var showingCold by remember { mutableStateOf(false) }
    var side by remember { mutableStateOf(TrendSide.GUARD) }
    var metric by remember { mutableStateOf(TrendMetric.guardAdvanced[0]) }
    // A recent-seasons board: it opens on the live season whatever Stats points at.
    var selectedSeason by remember { mutableStateOf(vm.recentFormSeason) }
    var selectedPhase by remember { mutableStateOf(vm.selectedPhase) }

    LaunchedEffect(side) {
        // Keep the stat when the new position offers it.
        val options = TrendMetric.list(side, if (metric in TrendMetric.standard(side)) TrendStatMode.STANDARD else TrendStatMode.ADVANCED)
        metric = options.firstOrNull { it.key == metric.key } ?: options[0]
    }
    LaunchedEffect(vm.recentFormSeason) { selectedSeason = vm.recentFormSeason }
    LaunchedEffect(isActive, vm.recentWindow, selectedSeason, selectedPhase, vm.freshnessRevision) {
        if (isActive) vm.loadRecentFormIfNeeded(season = selectedSeason, phase = selectedPhase)
    }

    val forms = vm.recentFormRows(vm.recentWindow, side.playerType, selectedSeason, selectedPhase)
    val roster = remember(vm.playerHistories, selectedSeason, selectedPhase) {
        vm.players(selectedSeason, selectedPhase).associateBy { it.playerId }
    }
    // Falling numbers are the improvement for a turnover rate or a foul rate.
    fun improvement(form: RecentForm): Double? {
        val delta = form.delta[metric.key] ?: return null
        // A prior window of exactly zero means the player barely played in it, so the "rise" is the whole
        // value and tops every board. Shooting percentages are the exception: an honest 0-for-5 is a real zero.
        if (form.priorMetrics[metric.key] == 0.0 && metric.key !in ZERO_IS_REAL) return null
        return if (metric.lowerIsBetter) -delta else delta
    }
    // No prior window yet anywhere on the board: rank the current window by level instead.
    val isEarlySeason = forms.isNotEmpty() && forms.none { it.priorMetrics[metric.key] != null }
    val earlyRanked = forms.filter { it.metrics[metric.key] != null && !it.isSmallSample(1) }
        .sortedWith { a, b ->
            val x = a.metrics[metric.key] ?: 0.0
            val y = b.metrics[metric.key] ?: 0.0
            if (metric.lowerIsBetter) x.compareTo(y) else y.compareTo(x)
        }
    val earlyTitle = "${side.label.uppercase()} · ${vm.recentWindow.label.uppercase()} LEADERS"
    // Only movement in the board's direction is listed, so Heating up never ends in a run of fallers.
    val ranked = forms.filter { form ->
        val change = improvement(form)
        !form.isSmallSample && change != null && (if (showingCold) change < 0 else change > 0)
    }
        .sortedWith { a, b ->
            val x = improvement(a) ?: 0.0
            val y = improvement(b) ?: 0.0
            if (showingCold) x.compareTo(y) else y.compareTo(x)
        }
    val boardTitle = "${side.label.uppercase()} · ${if (showingCold) "COOLING OFF" else "HEATING UP"}"
    val through = vm.recentFormAsOf(vm.recentWindow, selectedSeason, selectedPhase)?.let { "Through ${DateText.gameDay(it)}" }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HomeTopBar(leading = {
            // Two seasons at most, not the full menu: older ones have no recent-form rows to rank.
            SeasonPhaseNavPillFor(
                seasons = vm.recentFormSeasons,
                selectedSeason = selectedSeason,
                selectedPhase = selectedPhase,
                onSelectSeason = { season ->
                    if (vm.supportsRecentForm(season)) {
                        if (vm.isSeasonLocked(season)) actions.openTrialPitch(PaywallTrigger.LockedSeason(season)) else selectedSeason = season
                    }
                },
                onSelectPhase = { selectedPhase = it },
            )
        })
        val header = @Composable {
            Column {
                HardwoodTabs(
                    TrendSide.entries.map { it.shortLabel },
                    side.shortLabel,
                    { label -> TrendSide.entries.firstOrNull { it.shortLabel == label }?.let { side = it } },
                    Modifier.padding(top = 8.dp).semantics { contentDescription = "Position" },
                )
                Column(Modifier.padding(horizontal = 12.dp).padding(top = HardwoodGeo.controlRowGap - 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StatPickerMenu(
                            activeLabel = metric.label,
                            advanced = StatOption.categorized(TrendMetric.advanced(side).map { it.label }, metric.label),
                            standard = TrendMetric.standard(side).map { StatOption(it.key, it.label, it.key == metric.key) },
                            onSelectAdvanced = { o -> TrendMetric.advanced(side).firstOrNull { it.label == o.id }?.let { metric = it } },
                            onSelectStandard = { o -> TrendMetric.standard(side).firstOrNull { it.key == o.id }?.let { metric = it } },
                        )
                        Spacer(Modifier.weight(1f))
                        through?.let { Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary) }
                    }
                    if (!isEarlySeason) {
                        HardwoodSegmented(
                            listOf(Segment(false, "Heating up", icon = "flame.fill"), Segment(true, "Cooling off", icon = "snowflake")),
                            showingCold,
                            { showingCold = it },
                            selectedFill = { if (it) HardwoodPalette.performanceLow else HardwoodPalette.performanceHigh },
                        )
                    }
                    HardwoodSegmented(TrendWindow.entries.map { Segment(it, it.segmentLabel) }, vm.recentWindow, { vm.recentWindow = it })
                    Text(
                        if (isEarlySeason) "Too early for movement: comparing the ${vm.recentWindow.prose} with the span before it needs twice as many games. Until then, the best of the ${vm.recentWindow.prose}."
                        else "The ${vm.recentWindow.prose} across the league, compared with the same span before it. Players with no games in it are excluded.",
                        style = HardwoodType.micro,
                        color = HardwoodPalette.inkTertiary,
                    )
                }
            }
        }

        if (store.isPro) {
            // Rows scroll under this block; the rule says where it ends.
            Box(Modifier.fillMaxWidth().bottomHairline(HardwoodPalette.divider).padding(bottom = 8.dp)) { header() }
            RefreshableBox({ vm.load() }, Modifier.fillMaxSize()) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = bottomBarPadding()) {
                    item { DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 6.dp), season = selectedSeason, phase = selectedPhase) }
                    when {
                        vm.isRecentFormLoading && forms.isEmpty() -> item {
                            Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = HardwoodPalette.inkTertiary) }
                        }
                        vm.recentFormError != null && forms.isEmpty() -> item {
                            val scope = rememberCoroutineScope()
                            EmptyState("Couldn't load recent form", "exclamationmark.triangle", vm.recentFormError, Modifier.padding(vertical = 16.dp), "Try Again") {
                                scope.launch { vm.reloadRecentForm(season = selectedSeason, phase = selectedPhase) }
                            }
                        }
                        // A season (or a playoffs) with no games yet ranks nobody, and no stat or window can change that.
                        forms.isEmpty() -> item {
                            EmptyState(
                                "No games yet",
                                "calendar.badge.clock",
                                "No ${SeasonLabel.display(selectedSeason, selectedPhase)} games yet. Form appears once the first games are played.",
                                Modifier.padding(vertical = 16.dp),
                            )
                        }
                        isEarlySeason && earlyRanked.isNotEmpty() -> {
                            item { Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).cardSlice(true, false)) { HardwoodSectionBar(earlyTitle) } }
                            val rows = earlyRanked.take(50)
                            itemsIndexed(rows, key = { _, f -> f.id }) { index, form ->
                                Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == rows.lastIndex)) {
                                    EarlyRow(form, index + 1, index, metric, roster[form.playerId])
                                }
                            }
                        }
                        ranked.isEmpty() -> item {
                            EmptyState(
                                "No movement to rank yet",
                                "chart.line.flattrend.xyaxis",
                                if (forms.any { it.priorMetrics[metric.key] != null }) "Nobody's ${metric.label} is ${if (showingCold) "falling" else "rising"} over this window. Try another stat or window."
                                else "${metric.label} doesn't have a prior window to compare against yet. Try another stat or a shorter window.",
                                Modifier.padding(vertical = 16.dp),
                            )
                        }
                        else -> {
                            item { Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).cardSlice(true, false)) { HardwoodSectionBar(boardTitle) } }
                            val rows = ranked.take(50)
                            itemsIndexed(rows, key = { _, f -> f.id }) { index, form ->
                                Box(Modifier.padding(horizontal = 12.dp).cardSlice(false, index == rows.lastIndex)) {
                                    MoveRow(form, index + 1, index, metric, roster[form.playerId])
                                }
                            }
                        }
                    }
                }
            }
        } else {
            DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 6.dp), season = selectedSeason, phase = selectedPhase)
            header()
            // The locked board does not scroll: there is nothing below the fold to scroll to. It ends
            // above the floating tab bar (78 dp with its margin), or "See all plans" sits under it on 16:9 phones.
            Column(Modifier.weight(1f).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottom = bottomBarPadding(88.dp).calculateBottomPadding()).fillMaxWidth().hardwoodCard()) {
                HardwoodSectionBar(if (isEarlySeason) earlyTitle else boardTitle)
                when {
                    isEarlySeason && earlyRanked.isNotEmpty() -> earlyRanked.first().let { EarlyRow(it, 1, 0, metric, roster[it.playerId]) }
                    ranked.isNotEmpty() -> ranked.first().let { MoveRow(it, 1, 0, metric, roster[it.playerId]) }
                    else -> Row(
                        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeight).background(HardwoodPalette.surface).bottomHairline().padding(horizontal = HardwoodGeo.padInline),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (vm.isRecentFormLoading) CircularProgressIndicator(Modifier.size(14.dp), color = HardwoodPalette.inkTertiary, strokeWidth = 2.dp)
                        Text(if (vm.isRecentFormLoading) "Loading the board…" else "No movement to rank yet", style = HardwoodType.small, color = HardwoodPalette.inkTertiary)
                    }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().clipToBounds()) {
                    // Everything under row one is invented: blur is not a security boundary.
                    Column(Modifier.gateBlur()) {
                        teaserRows(vm, metric, showingCold, selectedSeason, selectedPhase, side).drop(1).forEachIndexed { index, teaser ->
                            TeaserRowView(teaser, index + 1, metric, vm.recentWindow)
                        }
                    }
                    BlurGateUnlock(
                        if (isEarlySeason) "See the full board: every player's ${vm.recentWindow.prose} at every position, with movement once there is a span to compare"
                        else "See the full board: every position ranked by how far they've moved",
                        PaywallTrigger.RecentForm,
                        // Natural height, pinned to the bottom: on a short screen the fade clips at the
                        // top, never the CTA, disclosure or "See all plans" at the bottom.
                        Modifier.align(Alignment.BottomCenter).wrapContentHeight(Alignment.Bottom, unbounded = true),
                        compact = maxHeight < 260.dp,
                    )
                }
            }
        }
    }
}

private val ZERO_IS_REAL = setOf("fg_pct", "ft_pct", "ts_pct", "efg_pct", "rim_fg", "three_pct", "three_pm")

/** A level, not a change: the value and the volume behind it. */
@Composable
private fun EarlyRow(form: RecentForm, rank: Int, index: Int, metric: TrendMetric, player: Player?) {
    val navigator = LocalNavigator.current
    val value = form.metrics[metric.key]?.let(metric::format) ?: "-"
    Row(
        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).bottomHairline()
            .then(if (player != null) Modifier.combinedClickable(onClick = { navigator.push(Route.PlayerProfile(player)) }) else Modifier)
            .padding(horizontal = HardwoodGeo.padInline)
            .clearAndSetSemantics { contentDescription = "$rank. ${player?.name ?: "Player"}, ${metric.label} $value, ${volumeText(form)}" },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("$rank", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(26.dp))
        PlayerHeadshot(player?.team ?: form.team ?: "", player?.initials ?: "-", 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(player?.name ?: "Player ${form.playerId}", style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
            Text("${displayTeamAbbr(player?.team ?: form.team ?: "")} · ${volumeText(form)}", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, maxLines = 1)
        }
        Text(value, style = HardwoodType.statMed, color = HardwoodPalette.court, modifier = Modifier.width(72.dp), textAlign = TextAlign.End)
    }
}

private fun volumeText(form: RecentForm): String {
    val games = if (form.games == 1) "1 game" else "${form.games} games"
    return "$games · ${form.minutes} min"
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MoveRow(form: RecentForm, rank: Int?, index: Int, metric: TrendMetric, player: Player?) {
    val navigator = LocalNavigator.current
    val favorites = LocalGraph.current.favorites
    var menu by remember { mutableStateOf(false) }
    val delta = form.delta[metric.key] ?: 0.0
    val now = form.metrics[metric.key]
    val then = form.priorMetrics[metric.key]
    Box {
        Row(
            Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).bottomHairline()
                .combinedClickable(onClick = { player?.let { navigator.push(Route.PlayerProfile(it)) } }, onLongClick = { menu = true })
                .padding(horizontal = HardwoodGeo.padInline)
                .testTag("trendRow"),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            rank?.let { Text("$it", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(26.dp)) }
            PlayerHeadshot(player?.team ?: form.team ?: "", player?.initials ?: "-", 34.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(player?.name ?: "Player ${form.playerId}", style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
                    if (favorites.isFavorite(form.playerId)) SfIcon("star.fill", 11.dp, CrownYellow)
                }
                // THEN to NOW, plus the window and the games in it: "2 wk" says when, "7G" says how many.
                if (then != null && now != null) {
                    FitText(
                        "${metric.format(then)} → ${metric.format(now)} · ${form.windowLabel} · ${form.games}G",
                        HardwoodType.micro,
                        HardwoodPalette.inkTertiary,
                        minScale = 0.85f,
                    )
                }
            }
            Box(Modifier.width(56.dp), contentAlignment = Alignment.CenterEnd) { TrendArrow(delta, metric.decimals, metric.lowerIsBetter) }
        }
        DropdownMenu(menu, { menu = false }, containerColor = HardwoodPalette.surface) {
            val following = favorites.isFavorite(form.playerId)
            DropdownMenuItem(
                text = { Text(if (following) "Unfollow" else "Follow", style = HardwoodType.body, color = HardwoodPalette.ink) },
                leadingIcon = { SfIcon(if (following) "star.slash" else "star", 18.dp, HardwoodPalette.inkSecondary) },
                onClick = {
                    menu = false
                    favorites.toggleFavorite(form.playerId)
                },
            )
        }
    }
}

private data class TeaserRow(val name: String, val team: String, val initials: String, val then: Double, val now: Double, val games: Int)

@Composable
private fun TeaserRowView(teaser: TeaserRow, index: Int, metric: TrendMetric, window: RecentWindow) {
    Row(
        Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("${index + 1}", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(26.dp))
        PlayerHeadshot(teaser.team, teaser.initials, 34.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(teaser.name, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1)
            Text("${metric.format(teaser.then)} → ${metric.format(teaser.now)} · ${window.segmentLabel} · ${teaser.games}G", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, maxLines = 1)
        }
        Box(Modifier.width(56.dp), contentAlignment = Alignment.CenterEnd) { TrendArrow(teaser.now - teaser.then, metric.decimals, metric.lowerIsBetter) }
    }
}

/**
 * The invented rows behind the gate: real faces from the group's roster, ordered
 * and valued by a seed built from every control, so the board visibly redraws
 * when a picker moves.
 */
private fun teaserRows(vm: DashboardViewModel, metric: TrendMetric, showingCold: Boolean, season: Int, phase: SeasonPhase, side: TrendSide): List<TeaserRow> {
    val count = 18
    val seed = "${metric.key}-$showingCold-${vm.recentWindow.value}-$season-${phase.raw}"
    val roster = vm.players(season).filter { (it.playerType ?: "") == side.playerType }
    val names: List<Triple<String, String, String>> = if (roster.size >= count) {
        roster.map { it to stableSeed("$seed-${it.playerId}") }.sortedBy { it.second }.take(count).map { Triple(it.first.name, it.first.team, it.first.initials) }
    } else {
        listOf(
            Triple("Player One", "BOS", "PO"), Triple("Player Two", "OKC", "PT"), Triple("Player Three", "PHI", "PT"),
            Triple("Player Four", "GSW", "PF"), Triple("Player Five", "DAL", "PF"), Triple("Player Six", "NYK", "PS"),
            Triple("Player Seven", "DET", "PS"), Triple("Player Eight", "MIL", "PE"), Triple("Player Nine", "MIA", "PN"),
            Triple("Player Ten", "SAS", "PT"), Triple("Player Eleven", "CLE", "PE"), Triple("Player Twelve", "MIN", "PT"),
            Triple("Player Thirteen", "LAC", "PT"), Triple("Player Fourteen", "HOU", "PF"), Triple("Player Fifteen", "TOR", "PF"),
            Triple("Player Sixteen", "PHX", "PS"), Triple("Player Seventeen", "DEN", "PS"), Triple("Player Eighteen", "ORL", "PE"),
        ).map { it to stableSeed("$seed-${it.first}") }.sortedBy { it.second }.map { it.first }
    }
    // Centre and spread the invented values on the metric's own scale: a
    // percentage reads 56%→64% and a per-100 rate reads 21→26.
    val (scale, spread) = when (metric.decimals) {
        0 -> 12.0 to 8.0
        2 -> 0.45 to 0.25
        else -> if (metric.unit == "%") 56.0 to 10.0 else 21.0 to 6.0
    }
    val drift = (stableSeed(seed) % 1_000) / 1_000.0
    val base = scale * (0.9 + 0.2 * drift)
    val swing = spread * (0.85 + 0.3 * drift)
    // Cooling off inverts the movement; a lower-is-better metric inverts it again: heating up on TOV% means the number falls.
    val window = vm.recentWindow.value
    val sign = if (!showingCold != metric.lowerIsBetter) 1.0 else -1.0
    return names.mapIndexed { index, who ->
        val wobble = (stableSeed("$seed-${who.first}") % 100) / 100.0 * 0.03 - 0.015
        val decay = maxOf(0.15, 1.0 - index * 0.045 + wobble)
        val move = swing * decay
        val then = base - sign * move / 2
        val games = window * 3 + (index + stableSeed(seed)) % 2
        TeaserRow(who.first, who.second, who.third, then, then + sign * move, games)
    }
}

/** FNV-1a with a murmur3 finalizer, identical to iOS so the same controls draw the same teaser. */
internal fun stableSeed(text: String): Int {
    var hash = 0xcbf29ce484222325uL
    text.codePoints().forEach { cp ->
        hash = (hash xor cp.toULong()) * 0x100000001b3uL
    }
    hash = hash xor (hash shr 33)
    hash *= 0xff51afd7ed558ccduL
    hash = hash xor (hash shr 33)
    return (hash % 100_003uL).toInt()
}
