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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.MetricValueFormat
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.TeamAggregation
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.TextAction
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.theme.TeamColor
import java.text.NumberFormat
import java.util.Locale

/**
 * The team chooser sheet for Compare: every team alphabetically, with search.
 *
 * Present it inside a full-height `StatScoutSheet`; it calls [onDismiss] and
 * then [onSelect] when a team is tapped, and [onDismiss] alone from Cancel.
 */
@Composable
fun CompareTeamPicker(teams: List<String>, onSelect: (String) -> Unit, onDismiss: () -> Unit) {
    var searchText by rememberSaveable { mutableStateOf("") }
    val filteredTeams = remember(teams, searchText) {
        val sorted = teams.sortedBy { teamFullName(it) }
        if (searchText.isEmpty()) sorted
        else sorted.filter { it.contains(searchText, ignoreCase = true) || teamFullName(it).contains(searchText, ignoreCase = true) }
    }
    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas)) {
        Box(Modifier.fillMaxWidth().height(52.dp)) {
            TextAction("Cancel", HardwoodType.body, HardwoodPalette.court, onDismiss, Modifier.align(Alignment.CenterStart).padding(start = 4.dp).testTag("pickerCancel"))
            Text("Select Team", style = HardwoodType.cardTitle, color = HardwoodPalette.ink, modifier = Modifier.align(Alignment.Center))
        }
        SearchField(searchText, { searchText = it }, Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp), prompt = "Search teams")
        LazyColumn(Modifier.fillMaxSize()) {
            items(filteredTeams, key = { it }) { team ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp)
                        .background(HardwoodPalette.surface)
                        .bottomHairline(HardwoodPalette.divider)
                        .clickable {
                            onDismiss()
                            onSelect(team)
                        }
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .testTag("pickTeam_$team"),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
                        Text(displayTeamAbbr(team), style = HardwoodType.micro, color = Color.White)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(teamFullName(team), style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                        Text(displayTeamAbbr(team), style = HardwoodType.small, color = HardwoodPalette.inkTertiary)
                    }
                }
            }
        }
    }
}

private data class StatRow(
    val id: String,
    val label: String,
    val aText: String,
    val bText: String,
    /** Comparison values, sign-flipped for lower-is-better metrics so the trophy always goes to the greater number. Null means "show the value, don't declare a winner". */
    val aValue: Double?,
    val bValue: Double?,
)

private data class StatGroup(val title: String, val rows: List<StatRow>)

/** A team's own live regular season: its standings line and power rating. */
private data class ClubSeason(val standing: StandingsRow?, val rating: TeamRating?)

/**
 * Two teams side by side: advanced rows from `metrics`, standard rows from
 * `standard_stats`, interleaved category by category. Each team carries its own
 * season and phase, as on the Compare tab.
 */
@Composable
fun TeamComparisonScreen(route: Route.TeamComparison) {
    val vm = LocalGraph.current.dashboard
    val a = route.teamA
    val b = route.teamB
    val sA = route.seasonA
    val pA = route.phaseA
    val sB = route.seasonB
    val pB = route.phaseB
    val rosterA = vm.players(sA, pA).filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(a) }
    val rosterB = vm.players(sB, pB).filter { normalizedTeamAbbreviation(it.team) == normalizedTeamAbbreviation(b) }
    // The team's own numbers exist only for the live regular season.
    fun clubSeason(team: String, season: Int, phase: SeasonPhase): ClubSeason? {
        if (season != vm.freeSeason || phase != SeasonPhase.REGULAR) return null
        val abbr = normalizedTeamAbbreviation(team)
        val rating = vm.teamRating(abbr)
        return ClubSeason(vm.standings[abbr], rating?.takeIf { it.season == season })
    }
    val clubRows = clubRows(clubSeason(a, sA, pA), clubSeason(b, sB, pB))
    val teamTitle = "TEAM · " + if (sA == sB) SeasonLabel.display(sA) else "${SeasonLabel.display(sA)} vs ${SeasonLabel.display(sB)}"
    val groups = remember(rosterA, rosterB, clubRows, teamTitle) { statGroups(rosterA, rosterB, clubRows, teamTitle) }

    PushedScreen("Team Comparison") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TeamHeader(a, rosterA.size, sA, pA, Modifier.weight(1f))
                SfIcon("arrow.left.arrow.right", 18.dp, HardwoodPalette.inkTertiary)
                TeamHeader(b, rosterB.size, sB, pB, Modifier.weight(1f))
            }

            if (groups.isEmpty()) {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(HardwoodGeo.radiusCard)).background(HardwoodPalette.surface).padding(vertical = 32.dp)) {
                    GamesTeamsUi.Unavailable("sum", "No aggregate stats", "Neither selected roster has standard stats for this context.")
                }
            } else {
                groups.forEach { group ->
                    Column(Modifier.fillMaxWidth().hardwoodCard().testTag("compareGroup")) {
                        HardwoodSectionBar(group.title)
                        group.rows.forEachIndexed { index, row -> StatRowView(row, index) }
                    }
                }
            }

            Text(
                (if (clubRows.isEmpty()) "" else "The team section is each team's own record, scoring and StatScout Power Rating. ") +
                    "The other sections sum the selected roster's player season lines, with rates weighted by minutes. Traded players bring their full-season line, so those are roster aggregates rather than official team totals.",
                style = HardwoodType.micro,
                color = HardwoodPalette.inkTertiary,
            )
            Spacer(Modifier.padding(bottomBarPadding()))
        }
    }
}

private fun statGroups(rosterA: List<Player>, rosterB: List<Player>, clubRows: List<StatRow>, teamTitle: String): List<StatGroup> =
    listOf(StatGroup(teamTitle, clubRows)) + MetricCategory.entries.flatMap { category ->
        listOf(
            StatGroup(category.raw.uppercase() + " · ADVANCED", advancedRows(category, rosterA, rosterB)),
            StatGroup(category.raw.uppercase() + " · STANDARD", standardRows(category, rosterA, rosterB)),
        )
    }
        .map { group -> StatGroup(group.title, group.rows.filter { it.aText != "-" || it.bText != "-" }) }
        .filter { it.rows.isNotEmpty() }

/** The teams' own results, not roster sums. Only when both sides are the live regular season with games played. */
private fun clubRows(a: ClubSeason?, b: ClubSeason?): List<StatRow> {
    val sa = a?.standing ?: return emptyList()
    val sb = b?.standing ?: return emptyList()
    if (sa.games <= 0 || sb.games <= 0) return emptyList()
    fun perGame(total: Int, games: Int) = total.toDouble() / games
    fun tenths(v: Double) = String.format(Locale.US, "%.1f", v)
    fun row(label: String, x: Double?, y: Double?, higherIsBetter: Boolean = true, format: (Double) -> String): StatRow {
        val sign = if (higherIsBetter) 1.0 else -1.0
        return StatRow("team-$label", label, x?.let(format) ?: "-", y?.let(format) ?: "-", x?.times(sign), y?.times(sign))
    }
    return listOf(
        StatRow("team-record", "Record", sa.record, sb.record, sa.winPercentage, sb.winPercentage),
        row("PTS/G", perGame(sa.pointsFor, sa.games), perGame(sb.pointsFor, sb.games), format = ::tenths),
        row("OPP PTS/G", perGame(sa.pointsAgainst, sa.games), perGame(sb.pointsAgainst, sb.games), higherIsBetter = false, format = ::tenths),
        row("Margin", perGame(sa.differential, sa.games), perGame(sb.differential, sb.games)) { TeamRating.signed(it) },
        row("Power", a.rating?.rating, b.rating?.rating) { TeamRating.signed(it) },
        row("Offense", a.rating?.offense, b.rating?.offense) { TeamRating.signed(it) },
        row("Defense", a.rating?.defense, b.rating?.defense) { TeamRating.signed(it) },
    )
}

/** Every advanced metric that either roster has for this category, in the registry's own display order. */
private fun advancedRows(category: MetricCategory, rosterA: List<Player>, rosterB: List<Player>): List<StatRow> {
    val labels = BasketballMetricRegistry.definitions
        .filter { it.category == category && it.kind == MetricKind.ADVANCED }
        .sortedBy { it.priority }
        .map { it.label }
    return labels.mapNotNull { label ->
        val a = TeamAggregation.value(label, category, rosterA)
        val b = TeamAggregation.value(label, category, rosterB)
        if (a == null && b == null) return@mapNotNull null
        val format = MetricValueFormat.inferred(
            (rosterA + rosterB).mapNotNull { p -> p.metrics.firstOrNull { it.label == label && it.category == category }?.value },
        )
        // Lower-is-better metrics (TOV%, Fouls/100) must not hand the trophy to the bigger number.
        val higherIsBetter = BasketballMetricRegistry.definition(label, category)?.higherIsBetter ?: true
        val sign = if (higherIsBetter) 1.0 else -1.0
        // Shot diet is a style, not a grade: shown, never awarded.
        val graded = label !in Metric.SHOT_PROFILE_LABELS
        StatRow(
            id = category.raw + "-adv-" + label,
            label = label,
            aText = a?.let { format.string(it) } ?: "-",
            bText = b?.let { format.string(it) } ?: "-",
            aValue = if (graded) a?.times(sign) else null,
            bValue = if (graded) b?.times(sign) else null,
        )
    }
}

private fun standardRows(category: MetricCategory, rosterA: List<Player>, rosterB: List<Player>): List<StatRow> = when (category) {
    MetricCategory.SCORING -> listOf(
        totalRow("PPG", rosterA, rosterB),
        pairedRow("FG", rosterA, rosterB),
        pairedRow("3P", rosterA, rosterB),
        pairedRow("FT", rosterA, rosterB),
    )
    MetricCategory.SHOOTING -> emptyList()
    MetricCategory.PLAYMAKING -> listOf(totalRow("APG", rosterA, rosterB), totalRow("TOV", rosterA, rosterB, "TOV/G", higherIsBetter = false))
    MetricCategory.REBOUNDING -> listOf(totalRow("RPG", rosterA, rosterB))
    MetricCategory.DEFENSE -> listOf(
        totalRow("SPG", rosterA, rosterB),
        totalRow("BPG", rosterA, rosterB),
        totalRow("PF", rosterA, rosterB, "PF/G", higherIsBetter = false),
    )
    MetricCategory.IMPACT -> listOf(totalRow("+/-", rosterA, rosterB, "Margin/G"))
}

/** `higherIsBetter = false` flips which side gets the trophy: turnovers and fouls. */
private fun totalRow(label: String, rosterA: List<Player>, rosterB: List<Player>, title: String? = null, higherIsBetter: Boolean = true): StatRow {
    val a = total(label, rosterA)
    val b = total(label, rosterB)
    val sign = if (higherIsBetter) 1.0 else -1.0
    return StatRow(label, title ?: label, format(a, label), format(b, label), a?.times(sign), b?.times(sign))
}

/** Made over attempted, ranked by the percentage it works out to. */
private fun pairedRow(label: String, rosterA: List<Player>, rosterB: List<Player>): StatRow =
    StatRow(label, label, pairedTotal(label, rosterA), pairedTotal(label, rosterB), pairedPercentage(label, rosterA), pairedPercentage(label, rosterB))

private fun pairs(label: String, roster: List<Player>): List<Pair<Double, Double>> = roster.mapNotNull { player ->
    val raw = player.standardStats?.firstOrNull { it.label == label }?.value ?: return@mapNotNull null
    val parts = raw.split("/", limit = 2)
    if (parts.size != 2) return@mapNotNull null
    val made = DashboardViewModel.rawNumeric(parts[0]) ?: return@mapNotNull null
    val attempted = DashboardViewModel.rawNumeric(parts[1]) ?: return@mapNotNull null
    made to attempted
}

private fun pairedPercentage(label: String, roster: List<Player>): Double? {
    val p = pairs(label, roster)
    val attempts = p.sumOf { it.second }
    return if (attempts > 0) p.sumOf { it.first } / attempts else null
}

private fun pairedTotal(label: String, roster: List<Player>): String {
    val p = pairs(label, roster)
    if (p.isEmpty()) return "-"
    return format(p.sumOf { it.first }, label) + "/" + format(p.sumOf { it.second }, label)
}

private val PER_GAME_LABELS = setOf("PPG", "RPG", "APG", "SPG", "BPG")

/**
 * The team's per-game line for one stat. Each player's average is weighted by
 * his games and divided by the team's (the most any player on the roster
 * played); five players share every point of margin, so summed +/- is over five.
 */
private fun total(label: String, roster: List<Player>): Double? {
    var sum = 0.0
    var found = false
    var teamGames = 0.0
    for (player in roster) {
        val stats = player.standardStats.orEmpty()
        val games = stats.firstOrNull { it.label == "G" }?.let { DashboardViewModel.rawNumeric(it.value) } ?: 0.0
        teamGames = maxOf(teamGames, games)
        val value = stats.firstOrNull { it.label == label }?.let { DashboardViewModel.rawNumeric(it.value) } ?: continue
        found = true
        sum += if (label in PER_GAME_LABELS) value * games else value
    }
    if (!found || teamGames <= 0) return null
    return (if (label == "+/-") sum / 5 else sum) / teamGames
}

private fun format(value: Double?, label: String): String {
    value ?: return "-"
    if (label in PER_GAME_LABELS || label == "TOV" || label == "PF") return String.format(Locale.US, "%.1f", value)
    if (label == "+/-") {
        val text = String.format(Locale.US, "%.1f", value)
        return if (value > 0.05) "+$text" else text
    }
    return NumberFormat.getIntegerInstance(Locale.US).format(Math.round(value))
}

@Composable
private fun TeamHeader(team: String, rosterCount: Int, season: Int, phase: SeasonPhase, modifier: Modifier = Modifier) {
    Column(
        modifier.hardwoodCard().padding(vertical = 14.dp, horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(58.dp).clip(CircleShape).background(TeamColor.color(team)), contentAlignment = Alignment.Center) {
            Text(displayTeamAbbr(team), style = HardwoodType.smallBold, color = Color.White)
        }
        FitText(teamFullName(team), HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.7f, textAlign = TextAlign.Center)
        Text(
            "$rosterCount tracked · ${SeasonLabel.display(season)} ${phase.label}",
            style = HardwoodType.micro,
            color = HardwoodPalette.inkTertiary,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun StatRowView(row: StatRow, index: Int) {
    Row(
        Modifier.fillMaxWidth().height(56.dp)
            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
            .bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StatValue(row.aText, row.aValue, row.bValue, Modifier.weight(1f))
        Text(row.label, style = HardwoodType.smallBold, color = HardwoodPalette.ink, textAlign = TextAlign.Center, modifier = Modifier.width(88.dp))
        StatValue(row.bText, row.bValue, row.aValue, Modifier.weight(1f))
    }
}

@Composable
private fun StatValue(text: String, value: Double?, other: Double?, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
        if (value != null && other != null && value > other) SfIcon("trophy.fill", 13.dp, CrownYellow)
        Text(
            text,
            style = HardwoodType.statMed,
            color = if (text == "-") HardwoodPalette.inkTertiary else HardwoodPalette.court,
            maxLines = 1,
        )
    }
}
