package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricCoverage
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.RecentWindow
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.StandardStatSemantics
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.metricNumericValue
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.DataFreshnessView
import com.jackwallner.basketball.ui.components.DualMetricBar
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.HardwoodMenu
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.HardwoodSegmented
import com.jackwallner.basketball.ui.components.HardwoodSubSectionBar
import com.jackwallner.basketball.ui.components.HardwoodTopBar
import com.jackwallner.basketball.ui.components.InfoNote
import com.jackwallner.basketball.ui.components.MenuItem
import com.jackwallner.basketball.ui.components.MenuSection
import com.jackwallner.basketball.ui.components.MetricBar
import com.jackwallner.basketball.ui.components.PlayerIdentityStrip
import com.jackwallner.basketball.ui.components.RefreshableBox
import com.jackwallner.basketball.ui.components.Segment
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.StatGlossaryLink
import com.jackwallner.basketball.ui.components.StatScoutSheet
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.components.rememberHaptic
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.nav.rememberRetained
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlinx.coroutines.launch

enum class FormDisplayMode(val label: String) { SEASON("Season"), RECENT("Recent"), BOTH("Both") }

enum class PlayerStatTab(val label: String) { ADVANCED("Advanced"), STANDARD("Standard"), YEAR_COMPARE("Year Compare") }

/** Resolves the row for the season and phase the route carries, as iOS `PlayerProfileDestination` does. */
@Composable
fun PlayerProfileRoute(player: Player) {
    val vm = LocalGraph.current.dashboard
    val history = vm.playerHistories[player.playerId].orEmpty()
    val seasonPlayer = history.firstOrNull { it.season == player.season && it.seasonPhase == player.seasonPhase } ?: player
    PlayerProfileScreen(seasonPlayer, history, vm)
}

/** Profile state that must survive pushing a drill-down on top of the page. */
@Stable
private class ProfileState {
    var selectedTab by mutableStateOf(PlayerStatTab.ADVANCED)
    var selectedSeason by mutableStateOf<Int?>(null)
    var formMode by mutableStateOf(FormDisplayMode.SEASON)
    var recentWindow by mutableStateOf(RecentWindow.TWO_WEEKS)
    var standardMode by mutableStateOf(FormDisplayMode.SEASON)
    var standardWindow by mutableStateOf(RecentWindow.TWO_WEEKS)
    /** The player's rolling rows by window length. */
    var recentForms by mutableStateOf<Map<Int, RecentForm>>(emptyMap())
    var recentFormsKey by mutableStateOf<String?>(null)
    var recentLoading by mutableStateOf(false)
    var recentLoadingKey: String? = null
    var recentLoadError by mutableStateOf<String?>(null)
    var countedOpen = false
}

@Composable
fun PlayerProfileScreen(player: Player, history: List<Player>, vm: DashboardViewModel) {
    val graph = LocalGraph.current
    val store = graph.subscriptions
    val favorites = graph.favorites
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val haptic = rememberHaptic()
    val scope = rememberCoroutineScope()
    val state = rememberRetained("profile-${player.id}") { ProfileState() }
    var showPercentileInfo by remember { mutableStateOf(false) }
    var showingPlayerPicker by remember { mutableStateOf(false) }
    val isPro = store.isPro

    val phaseHistory = history.filter { it.seasonPhase == player.seasonPhase }
    val activeSeason = state.selectedSeason ?: player.season
    val displayed = activeSeason?.let { s -> phaseHistory.firstOrNull { it.season == s } } ?: player
    val activePhase = player.seasonPhase
    val seasonLabel = activeSeason?.let { SeasonLabel.display(it, player.seasonPhase) } ?: "-"
    val recentFormSeasons = vm.recentFormSeasons
    val supportsRecentForm = (activeSeason ?: vm.freeSeason) in recentFormSeasons
    val allPlayers = remember(player.season, activePhase, vm.playerHistories) { vm.players(player.season ?: vm.selectedSeason, activePhase) }
    // Every percentile and comparison is measured against the season on screen, not the one the page opened in.
    val cohort = remember(activeSeason, allPlayers, vm.playerHistories) {
        if (activeSeason == null || activeSeason == player.season) allPlayers
        else vm.players(activeSeason, activePhase).ifEmpty { allPlayers }
    }
    // The ruler is the player's own cohort: a center's rebound rate is placed among centers.
    val curves = remember(cohort, displayed.positionGroup) {
        LeaguePercentileCurves(
            cohort.filter { it.positionGroup == displayed.positionGroup },
            MetricCategory.entries,
            MetricCategory.entries.flatMap { it.metricPriorityOrder },
        )
    }
    val liveProfile = vm.profile(displayed)
    val effectiveForm = if (supportsRecentForm) state.formMode else FormDisplayMode.SEASON
    val effectiveStandard = if (isPro && supportsRecentForm) state.standardMode else FormDisplayMode.SEASON

    // First-impression pitch from the second profile open; a positive moment from the third.
    LaunchedEffect(Unit) {
        if (state.countedOpen) return@LaunchedEffect
        state.countedOpen = true
        val opens = graph.defaults.getInt(PROFILE_OPEN_COUNT) + 1
        graph.defaults.putInt(PROFILE_OPEN_COUNT, opens)
        if (!store.isPro && opens >= 2 && graph.paywallGate.shouldPresent(PaywallTrigger.PlayerScouting)) {
            actions.openTrialPitch(PaywallTrigger.PlayerScouting)
        } else if (opens >= 3) {
            actions.positiveMoment()
        }
    }

    suspend fun loadRecentForms() {
        val season = activeSeason ?: return
        if (!store.isPro) return
        // Both cards read these rows; the phase belongs in the key, a regular season and its playoffs are two sets of games.
        val key = "${player.playerId}-$season-${activePhase.raw}-${vm.freshnessRevision ?: "none"}"
        if (state.recentFormsKey == key && state.recentForms.isNotEmpty()) return
        if (state.recentLoadingKey == key) return
        state.recentLoadingKey = key
        state.recentLoading = true
        state.recentLoadError = null
        try {
            val rows = vm.fetchPlayerRecentForm(player.playerId, season, activePhase)
            if (state.recentLoadingKey != key) return
            // A player ranked in two cohorts has a row per cohort; the one with more minutes describes him.
            val byWindow = mutableMapOf<Int, RecentForm>()
            for (row in rows) if ((byWindow[row.windowWeeks]?.touches ?: -1) < row.touches) byWindow[row.windowWeeks] = row
            state.recentForms = byWindow
            state.recentFormsKey = key
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            if (state.recentLoadingKey != key) return
            if (state.recentForms.isEmpty() || state.recentFormsKey != key) {
                state.recentForms = emptyMap()
                state.recentFormsKey = null
                state.recentLoadError = "Couldn't load recent form. Check your connection and try again."
            }
        }
        state.recentLoadingKey = null
        state.recentLoading = false
    }

    LaunchedEffect(effectiveForm, state.recentWindow, activeSeason, isPro, vm.freshnessRevision) {
        if (isPro && effectiveForm != FormDisplayMode.SEASON) loadRecentForms()
    }
    LaunchedEffect(effectiveStandard, state.standardWindow, activeSeason, isPro, vm.freshnessRevision) {
        if (isPro && effectiveStandard != FormDisplayMode.SEASON) loadRecentForms()
    }

    // Anyone in the league, closest overall percentile first.
    val comparable = remember(cohort, displayed) {
        val mine = displayed.overallPercentile
        cohort.filter { it.playerId != player.playerId }.sortedBy { abs(it.overallPercentile - mine) }
    }

    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTopBar(
            title = player.name,
            onBack = { navigator.pop() },
            trailing = {
                val isFavorite = favorites.isFavorite(player.playerId)
                Box(
                    Modifier.size(44.dp).clip(CircleShape).clickable {
                        favorites.toggleFavorite(player.playerId)
                        haptic()
                    }.semantics { contentDescription = if (isFavorite) "Unfollow ${player.name}" else "Follow ${player.name}" }.testTag("favoriteButton"),
                    contentAlignment = Alignment.Center,
                ) { SfIcon(if (isFavorite) "star.fill" else "star", 22.dp, if (isFavorite) CrownYellow else Color.White) }
                Box(
                    Modifier.size(44.dp).clip(CircleShape).clickable {
                        if (store.isPro) showingPlayerPicker = true else actions.openTrialPitch(PaywallTrigger.PlayerComparison)
                    }.semantics { contentDescription = "Compare with another player" }.testTag("compareButton"),
                    contentAlignment = Alignment.Center,
                ) { SfIcon("person.2.fill", 22.dp, Color.White) }
            },
        )
        RefreshableBox({
            vm.load()
            state.recentFormsKey = null
            if (store.isPro && (effectiveForm != FormDisplayMode.SEASON || effectiveStandard != FormDisplayMode.SEASON)) loadRecentForms()
        }, Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(bottomBarPadding())) {
                PlayerIdentityStrip(displayed, profile = liveProfile)
                DataFreshnessView(vm, Modifier.padding(horizontal = 12.dp).padding(top = 10.dp), season = activeSeason ?: player.season, phase = activePhase)
                val season = activeSeason ?: player.season
                if (season != null && season in recentFormSeasons) {
                    Box(Modifier.padding(horizontal = 12.dp)) { PlayerLastGameCard(viewModel = vm, player = displayed, season = season, phase = activePhase) }
                }
                Row(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PlayerStatTab.entries.forEach { tab ->
                        val selected = state.selectedTab == tab
                        Box(
                            Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(HardwoodGeo.radiusCard))
                                .background(if (selected) HardwoodPalette.court else HardwoodPalette.surface)
                                .clickable {
                                    state.selectedTab = tab
                                    if (tab == PlayerStatTab.YEAR_COMPARE && store.isPro && !vm.hasLoadedHistorical && !vm.isHistoricalLoading) {
                                        scope.launch { vm.loadHistoricalIfNeeded() }
                                    }
                                    haptic()
                                }
                                .testTag("profileTab_${tab.label}"),
                            contentAlignment = Alignment.Center,
                        ) { Text(tab.label, style = HardwoodType.bodyBold, color = if (selected) Color.White else HardwoodPalette.ink) }
                    }
                }

                val seasonMenu = @Composable {
                    val seasons = (phaseHistory.mapNotNull { it.season } + listOfNotNull(player.season)).distinct().sortedDescending()
                    if (seasons.size > 1) {
                        HardwoodMenu(listOf(MenuSection(null, seasons.map { s ->
                            val locked = s != vm.freeSeason && !store.isPro
                            MenuItem(SeasonLabel.display(s), checked = !locked && s == activeSeason, locked = locked) {
                                // An explicit tap on a locked season is always answered.
                                if (locked) actions.openTrialPitch(PaywallTrigger.LockedSeason(s)) else state.selectedSeason = s
                            }
                        }))) { open ->
                            Row(
                                Modifier.heightIn(min = 28.dp).clickable(onClick = open).semantics { contentDescription = "Season, $seasonLabel" },
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(seasonLabel, style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, maxLines = 1)
                                SfIcon("chevron.down", 11.dp, HardwoodPalette.inkSecondary)
                            }
                        }
                    } else Text(seasonLabel, style = HardwoodType.micro, color = HardwoodPalette.inkSecondary, maxLines = 1)
                }

                when (state.selectedTab) {
                    PlayerStatTab.ADVANCED -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PercentileCard(
                            displayed = displayed,
                            seasonLabel = seasonLabel,
                            seasonMenu = seasonMenu,
                            onInfo = { showPercentileInfo = true },
                            isPro = isPro,
                            supportsRecent = supportsRecentForm,
                            state = state,
                            effectiveForm = effectiveForm,
                            curves = curves,
                            freshnessStatus = vm.freshnessStatus,
                            onMetric = { m -> navigator.push(Route.Metric(m.label, m.category, activeSeason, activePhase, player.positionGroup)) },
                        )
                        coverageNote(displayed, vm)?.let { InfoNote(it, Modifier.padding(horizontal = 0.dp)) }
                        if (!isPro) {
                            RecentFormCard(
                                player = player,
                                season = activeSeason ?: player.season ?: vm.freeSeason,
                                leaguePlayers = cohort,
                                fetchRecentForm = { id, s, ph -> vm.fetchPlayerRecentForm(id, s, ph) },
                                freshnessRevision = vm.freshnessRevision,
                                freshnessStatus = vm.freshnessStatus,
                            )
                            ProUpsellCard(player.name) { actions.openTrialPitch(store.defaultUpgradeTrigger) }
                        }
                    }
                    PlayerStatTab.STANDARD -> Column(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        StandardStatsCard(
                            displayed = displayed,
                            cohort = cohort,
                            seasonMenu = seasonMenu,
                            supportsRecent = supportsRecentForm,
                            isPro = isPro,
                            state = state,
                            effectiveMode = effectiveStandard,
                            onLockedTap = { actions.openTrialPitch(PaywallTrigger.RecentForm) },
                            onStat = { label -> navigator.push(Route.StandardStat(label, displayed.positionGroup, activeSeason, activePhase)) },
                        )
                        if (season != null && season in recentFormSeasons) {
                            PlayerGameLogCard(viewModel = vm, player = displayed, season = season, phase = activePhase)
                        }
                    }
                    PlayerStatTab.YEAR_COMPARE -> when {
                        !isPro -> YearComparePreview(player.name)
                        vm.isHistoricalLoading -> HistoricalLoadingCard(vm.loadingMessage, vm.loadingProgress)
                        !vm.hasLoadedHistorical -> LoadHistoryCard { scope.launch { vm.loadHistoricalIfNeeded() } }
                        phaseHistory.mapNotNull { it.season }.filter { !StatScoutSeason.isAllTime(it) }.toSet().size < 2 ->
                            Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().hardwoodCard().padding(vertical = 24.dp)) {
                                EmptyState("Not enough history", "calendar.badge.clock", "${player.name} doesn't have multiple seasons of data to compare.")
                            }
                        else -> YearComparisonView(phaseHistory)
                    }
                }
                Box(Modifier.padding(horizontal = 12.dp).padding(top = 12.dp)) { StatGlossaryLink() }
            }
        }
    }

    StatScoutSheet(showPercentileInfo, { showPercentileInfo = false }) { PercentileInfoSheet { showPercentileInfo = false } }
    StatScoutSheet(showingPlayerPicker, { showingPlayerPicker = false }) {
        PlayerPickerSheet(comparable, "Compare With", onCancel = { showingPlayerPicker = false }) { selected ->
            showingPlayerPicker = false
            navigator.push(Route.Comparison(displayed, selected))
        }
    }
}

private const val PROFILE_OPEN_COUNT = "profileOpenCount"

/** What the page cannot say about this season: a metric the data predates, or a feed still catching up. */
private fun coverageNote(displayed: Player, vm: DashboardViewModel): String? {
    val season = displayed.season ?: return null
    val parts = mutableListOf<String>()
    MetricCoverage.note(season, phase = displayed.seasonPhase)?.let { parts += it }
    if (season == vm.freeSeason && displayed.seasonPhase == SeasonPhase.REGULAR) {
        MetricCoverage.pendingNote(null, vm.dataFreshness?.shotsStatus, vm.dataFreshness?.playByPlayStatus)?.let { parts += it }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" ")
}

@Composable
private fun PercentileCard(
    displayed: Player,
    seasonLabel: String,
    seasonMenu: @Composable () -> Unit,
    onInfo: () -> Unit,
    isPro: Boolean,
    supportsRecent: Boolean,
    state: ProfileState,
    effectiveForm: FormDisplayMode,
    curves: LeaguePercentileCurves,
    freshnessStatus: com.jackwallner.basketball.model.DataFreshnessStatus,
    onMetric: (Metric) -> Unit,
) {
    // One section per category, in the order they are read: Scoring first, Impact last.
    val grouped = displayed.metrics(MetricKind.ADVANCED).groupBy { it.category }
    val groups = MetricCategory.entries.mapNotNull { c -> grouped[c]?.takeIf { it.isNotEmpty() }?.let { c to BasketballMetricRegistry.sorted(it) } }
    val form = state.recentForms[state.recentWindow.value]

    // The window figure for a season metric, on the same league ruler as the season bar.
    // Season totals have no per-week equivalent there, so they keep their season bar.
    fun recentMetric(season: Metric): Metric? {
        val f = form ?: return null
        val key = RecentMetricKey.key(season.label) ?: return null
        if (RecentMetricKey.isSeasonTotal(season.label)) return null
        val v = f.metrics[key] ?: return null
        val pct = curves.curve(season.label)?.percentile(v) ?: return null
        return Metric(season.label, RecentMetricKey.format(v, season.label), pct, season.category, id = "recent-${season.label}")
    }

    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar(
            "ADVANCED PERCENTILES",
            trailing = {
                seasonMenu()
                Text(
                    "ⓘ",
                    style = HardwoodType.micro,
                    color = HardwoodPalette.linkBlue,
                    modifier = Modifier.padding(start = 4.dp).clip(CircleShape).clickable(onClick = onInfo).padding(6.dp)
                        .semantics { contentDescription = "About percentiles" },
                )
            },
        )
        if (isPro && supportsRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)) {
                HardwoodSegmented(FormDisplayMode.entries.map { Segment(it, it.label) }, state.formMode, { state.formMode = it })
            }
        }
        if (effectiveForm != FormDisplayMode.SEASON && isPro && supportsRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline).padding(bottom = 8.dp)) {
                HardwoodSegmented(RecentWindow.entries.map { Segment(it, it.segmentLabel) }, state.recentWindow, { state.recentWindow = it })
            }
            when {
                state.recentLoading -> Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = HardwoodPalette.inkTertiary, strokeWidth = 2.dp)
                    Text("Loading recent form…", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
                state.recentLoadError != null -> Text(state.recentLoadError!!, style = HardwoodType.small, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(16.dp))
                form == null -> Text(recentEmptyText(freshnessStatus, state.recentWindow), style = HardwoodType.small, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(16.dp))
            }
        }
        if (groups.isEmpty()) {
            Box(Modifier.padding(vertical = 24.dp)) {
                EmptyState("No metrics available", "chart.bar", "Percentile rankings are not available for this player in the $seasonLabel season.")
            }
        } else groups.forEach { (category, rows) ->
            HardwoodSubSectionBar(category.raw.uppercase())
            rows.forEachIndexed { index, metric ->
                val recent = recentMetric(metric)
                val bg = if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt
                val rowModifier = Modifier.fillMaxWidth().background(bg).bottomHairline()
                when (effectiveForm) {
                    FormDisplayMode.SEASON -> Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp)) { MetricBar(metric) }
                    // No window figure for this metric: fall back to the season bar so every bar still shows.
                    FormDisplayMode.RECENT -> if (recent != null) Box(rowModifier.padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp)) { MetricBar(recent) }
                    else Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp)) { MetricBar(metric) }
                    FormDisplayMode.BOTH -> Box(rowModifier.clickable { onMetric(metric) }.padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp)) {
                        DualMetricBar(metric, recent, state.recentWindow.segmentLabel)
                    }
                }
            }
        }
    }
}

/** The metric category a traditional stat reads under. */
private fun standardCategory(label: String): MetricCategory = when (label.uppercase()) {
    "PPG", "FG", "3P", "FT" -> MetricCategory.SCORING
    "APG", "TOV" -> MetricCategory.PLAYMAKING
    "RPG" -> MetricCategory.REBOUNDING
    "SPG", "BPG", "PF" -> MetricCategory.DEFENSE
    else -> MetricCategory.IMPACT
}

/** Averages and shooting lines are rates; these are counts, ranked honestly but playing-time driven. */
private val COUNTING_STATS = setOf("G", "GS", "TOV", "PF", "+/-", "MIN")

/** Standard stat label to its rolling-window column. Only the per-game averages have one. */
private val STANDARD_RECENT_KEYS = mapOf(
    "PPG" to "ppg", "RPG" to "rpg", "APG" to "apg", "SPG" to "spg", "BPG" to "bpg", "MPG" to "mpg",
)

@Composable
private fun StandardStatsCard(
    displayed: Player,
    cohort: List<Player>,
    seasonMenu: @Composable () -> Unit,
    supportsRecent: Boolean,
    isPro: Boolean,
    state: ProfileState,
    effectiveMode: FormDisplayMode,
    onLockedTap: () -> Unit,
    onStat: (String) -> Unit,
) {
    val group = displayed.positionGroup
    fun peerValues(label: String): List<String> {
        val key = label.uppercase()
        return cohort.mapNotNull { other ->
            if (other.positionGroup != group) null else other.standardStats?.firstOrNull { it.label.uppercase() == key }?.value
        }
    }
    fun percentile(label: String, value: String) = StandardStatSemantics.percentile(label, value, peerValues(label))
    fun metrics(counting: Boolean): List<Metric> = displayed.standardStats.orEmpty()
        .filter { (it.label.uppercase() in COUNTING_STATS) == counting }
        .map { stat ->
            Metric(
                label = stat.label.uppercase(),
                value = stat.value,
                percentile = percentile(stat.label, stat.value),
                category = standardCategory(stat.label),
                // A zero count has no honest rank, except where fewer is better: a bench player's 0 PF ranks at the top.
                rankable = if (counting && StandardStatSemantics.higherIsBetter(stat.label) && metricNumericValue(stat.value) == 0.0) false else null,
                id = "std-${stat.label}",
            )
        }
    val form = state.recentForms[state.standardWindow.value]
    val caption = form?.let { "${state.standardWindow.segmentLabel} · ${it.games}G" } ?: state.standardWindow.segmentLabel
    // The window's per-game average, ranked on the same league season distribution as the season row.
    fun recent(season: Metric): Metric? {
        val key = STANDARD_RECENT_KEYS[season.label] ?: return null
        val value = form?.metrics?.get(key) ?: return null
        val text = String.format(Locale.US, "%.1f", value)
        return Metric(season.label, text, percentile(season.label, text), season.category, id = "std-recent-${season.label}")
    }
    fun statKey(display: String) = displayed.standardStats.orEmpty().firstOrNull { it.label.uppercase() == display }?.label ?: display

    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar("STANDARD STATS", trailing = { seasonMenu() })
        if (supportsRecent) {
            Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline, vertical = 10.dp)) {
                HardwoodSegmented(
                    FormDisplayMode.entries.map { Segment(it, it.label, isLocked = !isPro && it != FormDisplayMode.SEASON) },
                    state.standardMode,
                    { state.standardMode = it },
                    onLockedTap = { onLockedTap() },
                )
            }
            if (effectiveMode != FormDisplayMode.SEASON) {
                Box(Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padInline).padding(bottom = 8.dp)) {
                    HardwoodSegmented(RecentWindow.entries.map { Segment(it, it.segmentLabel) }, state.standardWindow, { state.standardWindow = it })
                }
            }
        }
        if (displayed.standardStats.isNullOrEmpty()) {
            Box(Modifier.padding(vertical = 24.dp)) { EmptyState("Standard stats unavailable", "chart.bar", "Standard stats are not available for this player.") }
        } else {
            val rates = metrics(false)
            val counts = metrics(true)
            // Only label the two groups when there are two of them.
            val labelled = rates.isNotEmpty() && counts.isNotEmpty()
            @Composable
            fun Rows(list: List<Metric>, start: Int) {
                list.forEachIndexed { offset, metric ->
                    val r = recent(metric)
                    Box(
                        Modifier.fillMaxWidth().background(if ((start + offset) % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                            .bottomHairline().clickable { onStat(statKey(metric.label)) }
                            .padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp),
                    ) {
                        when (effectiveMode) {
                            FormDisplayMode.SEASON -> MetricBar(metric)
                            FormDisplayMode.RECENT -> MetricBar(r ?: metric)
                            FormDisplayMode.BOTH -> DualMetricBar(metric, r, caption)
                        }
                    }
                }
            }
            if (rates.isNotEmpty()) {
                if (labelled) HardwoodSubSectionBar("PER GAME & SHOOTING")
                Rows(rates, 0)
            }
            if (counts.isNotEmpty()) {
                if (labelled) HardwoodSubSectionBar("TOTALS")
                Rows(counts, rates.size)
            }
        }
    }
}

@Composable
private fun ProUpsellCard(name: String, onTap: () -> Unit) {
    val store = LocalGraph.current.subscriptions
    Column(Modifier.fillMaxWidth().hardwoodCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SfIcon("crown.fill", 16.dp, CrownYellow)
            Text("StatScout+", style = HardwoodType.smallBold, color = HardwoodPalette.ink)
        }
        Text("Get the full scouting picture on $name.", style = HardwoodType.body, color = HardwoodPalette.ink)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(
                "chart.line.uptrend.xyaxis" to "Year-over-year trends across every metric",
                "person.2.fill" to "Head-to-head comparisons vs any player",
                "calendar.badge.clock" to "Every past season, not just this one",
                "chart.bar.fill" to "Last week, 2 week and 4 week form on every player",
            ).forEach { (icon, text) ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { SfIcon(icon, 14.dp, HardwoodPalette.court) }
                    Text(text, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(12.dp)).background(HardwoodPalette.court).clickable(onClick = onTap),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(store.paywallBlurCTA, style = HardwoodType.bodyBold, color = Color.White)
            SfIcon("arrow.right", 14.dp, Color.White)
        }
        store.paywallBlurSubtext?.let { Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
    }
}

@Composable
private fun HistoricalLoadingCard(message: String, progress: Double) {
    Column(
        Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().hardwoodCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        val value = progress.coerceIn(0.0, 1.0).toFloat()
        LinearProgressIndicator(progress = { value }, color = HardwoodPalette.court, trackColor = HardwoodPalette.surfaceSunk, modifier = Modifier.fillMaxWidth())
        Text(message, style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
        Text("${(value * 100).toInt()}%", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary)
    }
}

@Composable
private fun LoadHistoryCard(onLoad: () -> Unit) {
    Column(
        Modifier.padding(horizontal = 12.dp).padding(top = 12.dp).fillMaxWidth().hardwoodCard().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SfIcon("clock.arrow.circlepath", 36.dp, HardwoodPalette.court)
        Text("Load past seasons", style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
        Text("Year Compare loads historical data only when you need it.", style = HardwoodType.body, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center)
        Box(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(HardwoodPalette.court).clickable(onClick = onLoad).padding(horizontal = 18.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Load History", style = HardwoodType.bodyBold, color = Color.White) }
    }
}

@Composable
fun PercentileInfoSheet(onDone: () -> Unit) {
    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        HardwoodTopBar(title = "About Percentiles", trailing = { TextAction("Done", HardwoodType.smallBold, Color.White, onDone) })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Percentile Rankings", style = HardwoodType.playerName, color = HardwoodPalette.ink)
            Text(
                "Percentile rankings compare a player to others in his position group: guards, forwards or centers. A 90th percentile means the player ranks in the top 10% of his group for that metric.",
                style = HardwoodType.body,
                color = HardwoodPalette.inkSecondary,
            )
            Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    Triple("flame.fill", "Elite (75-100): Green bars", HardwoodPalette.performanceHigh),
                    Triple("minus", "Average (25-75): Charcoal bars", HardwoodPalette.inkSecondary),
                    Triple("snowflake", "Below Average (0-25): Rust bars", HardwoodPalette.performanceLow),
                    Triple("circle.lefthalf.filled", "Shot profile: Blue bars", HardwoodPalette.linkBlue),
                ).forEach { (icon, text, color) ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SfIcon(icon, 16.dp, color)
                        Text(text, style = HardwoodType.bodyBold, color = color)
                    }
                }
            }
            Text(
                "Shot profile stats (3PT Rate, the Rim, Short Mid and Long Mid frequencies, Assisted FG%) describe how a player plays rather than how well, so a high or low rank is neither good nor bad.",
                style = HardwoodType.small,
                color = HardwoodPalette.inkSecondary,
            )
            Text(
                "Stats update after new source data is validated. Advanced metrics may arrive later than game totals. Not every metric is tracked for every player.",
                style = HardwoodType.small,
                color = HardwoodPalette.inkTertiary,
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}
