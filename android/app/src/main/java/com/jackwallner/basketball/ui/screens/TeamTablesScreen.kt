package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.model.LeagueDivision
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.model.teamNickname
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.TeamColorDot
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType

/** Conference standings as their own pushed page. */
@Composable
fun StandingsScreen() {
    val vm = LocalGraph.current.dashboard
    PushedScreen("Standings") {
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
                StandingsTable()
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/** The league ranked by power rating as its own pushed page. */
@Composable
fun PowerRankingsScreen() {
    val vm = LocalGraph.current.dashboard
    PushedScreen("Power Rankings") {
        GamesTeamsUi.RefreshBox(onRefresh = { vm.load() }) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
                PowerRankingsTable()
                Spacer(Modifier.padding(bottomBarPadding()))
            }
        }
    }
}

/** Conference standings from posted finals, with each team's power rating beside its record. */
@Composable
internal fun StandingsTable() {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val table = remember(vm.games) { vm.standings }
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        LeagueDivision.conferences.forEach { (name, teams) ->
            val rows = StandingsRow.ordered(teams.mapNotNull { table[it] })
            // Games back counts from the best win-loss gap, so it is never
            // negative when a team with more games sits behind on percentage.
            val leader = rows.maxByOrNull { it.wins - it.losses }
            Column(Modifier.fillMaxWidth().hardwoodCard().testTag("conference_$name")) {
                StandingsHeader(name)
                rows.forEachIndexed { index, row ->
                    StandingsLine(
                        row, index + 1, leader, vm.teamRating(row.team),
                        Modifier
                            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                            .clickable { navigator.push(Route.Team(row.team)) }
                            // The playoff line under 6th and the play-in line under 10th.
                            .then(if (index == 5 || index == 9) Modifier.bottomHairline(HardwoodPalette.inkTertiary, 1.5.dp) else Modifier),
                    )
                }
            }
        }
        Text(
            "Lines mark the top six, who go straight to the playoffs, and the play-in through 10th. GB is games behind the conference leader; DIFF is average scoring margin. Ordered by win percentage, then point differential, not the NBA's full tiebreakers. PWR is the StatScout Power Rating: points per 100 possessions better or worse than an average team, adjusted for schedule.",
            style = HardwoodType.micro,
            color = HardwoodPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        )
    }
}

@Composable
private fun StandingsHeader(title: String) {
    Row(
        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeightHeader).background(HardwoodPalette.surfaceAlt)
            .bottomHairline(HardwoodPalette.divider).padding(horizontal = HardwoodGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FitText(title.uppercase(), HardwoodType.micro, HardwoodPalette.inkTertiary, Modifier.weight(1f), minScale = 0.8f)
        HeaderCell("W-L", 44.dp)
        HeaderCell("GB", 34.dp)
        HeaderCell("DIFF", 40.dp)
        HeaderCell("STRK", 36.dp)
        HeaderCell("PWR", 40.dp)
    }
}

@Composable
private fun HeaderCell(text: String, width: Dp) {
    Text(text, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(width))
}

@Composable
private fun StandingsLine(row: StandingsRow, seed: Int, leader: StandingsRow?, rating: TeamRating?, modifier: Modifier = Modifier) {
    val gamesBack = leader?.let { row.gamesBack(it) } ?: 0.0
    val diffColor = when {
        row.differential > 0 -> HardwoodPalette.performanceHigh
        row.differential < 0 -> HardwoodPalette.performanceLow
        else -> HardwoodPalette.inkSecondary
    }
    val description = "$seed. ${teamFullName(row.team)}, ${row.record}" +
        (if (gamesBack == 0.0) "" else ", ${StandingsRow.formatGamesBack(gamesBack)} games back") +
        (row.marginLabel?.let { ", average margin $it" } ?: "") +
        (rating?.let { ", power rating ${TeamRating.signed(it.rating)}" } ?: "")
    Row(
        modifier.fillMaxWidth().height(44.dp).bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline)
            .clearAndSetSemantics { contentDescription = description }
            .testTag("teamRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("$seed", style = HardwoodType.statSmall, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.End, modifier = Modifier.width(18.dp))
            TeamColorDot(row.team, 10.dp)
            Text(displayTeamAbbr(row.team), style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 1, softWrap = false, modifier = Modifier.width(40.dp))
            FitText(teamNickname(row.team), HardwoodType.small, HardwoodPalette.inkTertiary, minScale = 0.7f)
        }
        NumberCell(row.record, 44.dp, HardwoodPalette.ink)
        NumberCell(if (gamesBack == 0.0) "-" else StandingsRow.formatGamesBack(gamesBack), 34.dp, HardwoodPalette.inkSecondary)
        NumberCell(row.marginLabel ?: "-", 40.dp, diffColor)
        NumberCell(row.streak ?: "-", 36.dp, HardwoodPalette.inkSecondary)
        NumberCell(rating?.let { TeamRating.signed(it.rating) } ?: "-", 40.dp, HardwoodPalette.ink)
    }
}

@Composable
private fun NumberCell(text: String, width: Dp, color: Color, bold: Boolean = false) {
    FitText(text, if (bold) HardwoodType.statMed else HardwoodType.statSmall, color, Modifier.width(width), minScale = 0.7f, textAlign = TextAlign.End)
}

/**
 * The league ranked by power rating: what a team scores minus what it allows
 * per 100 possessions, adjusted for who it played.
 */
@Composable
internal fun PowerRankingsTable() {
    val vm = LocalGraph.current.dashboard
    val navigator = LocalNavigator.current
    val ratings = vm.teamRatings.values.sortedBy { it.rank }
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (ratings.isEmpty()) {
            Column(Modifier.fillMaxWidth().background(HardwoodPalette.surface, androidx.compose.foundation.shape.RoundedCornerShape(HardwoodGeo.radiusCard)).padding(vertical = 32.dp)) {
                GamesTeamsUi.Unavailable("chart.bar.xaxis", "Power ratings loading", "Ratings arrive with the next update. Pull to refresh.")
            }
        } else {
            val standings = remember(vm.games) { vm.standings }
            Column(Modifier.fillMaxWidth().hardwoodCard()) {
                PowerHeader()
                ratings.forEachIndexed { index, rating ->
                    PowerLine(
                        rating,
                        standings[normalizedTeamAbbreviation(rating.team)]?.record,
                        Modifier
                            .background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                            .clickable { navigator.push(Route.Team(rating.team)) },
                    )
                }
            }
        }
        Text(
            powerFootnote(ratings),
            style = HardwoodType.micro,
            color = HardwoodPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        )
    }
}

private fun powerFootnote(ratings: List<TeamRating>): String {
    val preseason = ratings.firstOrNull()?.let { it.games == 0 } ?: false
    val lead = if (preseason) "Preseason: last season's ratings, regressed. " else ""
    return lead + "Points per 100 possessions better or worse than an average team: what a team scores plus what it holds opponents under, adjusted for schedule. Early in the season, last season's rating carries part of the weight. Read two ratings like a spread, with about two and a half points for home court."
}

@Composable
private fun PowerHeader() {
    Row(
        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeightHeader).background(HardwoodPalette.surfaceAlt)
            .bottomHairline(HardwoodPalette.divider).padding(horizontal = HardwoodGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("#", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(28.dp))
        Text("TEAM", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
        HeaderCell("OFF", 44.dp)
        HeaderCell("DEF", 44.dp)
        HeaderCell("RATING", 60.dp)
    }
}

@Composable
private fun PowerLine(rating: TeamRating, record: String?, modifier: Modifier = Modifier) {
    val description = "${rating.rank}. ${teamFullName(rating.team)}, rating ${TeamRating.signed(rating.rating)}, " +
        "offense ${TeamRating.signed(rating.offense)}, defense ${TeamRating.signed(rating.defense)}"
    Row(
        modifier.fillMaxWidth().height(HardwoodGeo.rowHeight).bottomHairline(HardwoodPalette.divider)
            .padding(horizontal = HardwoodGeo.padInline)
            .clearAndSetSemantics { contentDescription = description }
            .testTag("powerRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("${rating.rank}", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(28.dp))
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(rating.team, 10.dp)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                FitText(teamFullName(rating.team), HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.8f)
                record?.let { Text(it, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary) }
            }
        }
        Text(TeamRating.signed(rating.offense), style = HardwoodType.statSmall, color = tint(rating.offense), textAlign = TextAlign.End, modifier = Modifier.width(44.dp))
        Text(TeamRating.signed(rating.defense), style = HardwoodType.statSmall, color = tint(rating.defense), textAlign = TextAlign.End, modifier = Modifier.width(44.dp))
        Text(TeamRating.signed(rating.rating), style = HardwoodType.statMed, color = tint(rating.rating), textAlign = TextAlign.End, modifier = Modifier.width(60.dp))
    }
}

/** Ratings are points per 100 possessions: a point either way is a clearly good or bad team. */
private fun tint(value: Double): Color = when {
    value >= 1 -> HardwoodPalette.performanceHigh
    value <= -1 -> HardwoodPalette.performanceLow
    else -> HardwoodPalette.inkSecondary
}
