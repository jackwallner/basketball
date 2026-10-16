package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamRating
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.util.Locale

internal data class GlanceTile(val label: String, val value: String, val rank: Int)

/** 1-based rank of `value` among `values`, best first. */
private fun rank(value: Double, values: List<Double>, higherIsBetter: Boolean = true): Int =
    values.count { if (higherIsBetter) it > value else it < value } + 1

/**
 * The six numbers a fan checks first: scoring both ways, the margin, and the
 * power rating split into offense and defense, each with its league rank. A
 * rank means little until every team has a few games, so nothing shows before.
 */
internal fun glanceTiles(
    team: String,
    standings: Map<String, StandingsRow>,
    ratings: Map<String, TeamRating>,
    liveSeason: Int,
): List<GlanceTile> {
    val abbr = normalizedTeamAbbreviation(team)
    val rows = standings.values.toList()
    if (rows.size < 30 || rows.any { it.games < 3 }) return emptyList()
    val row = standings[abbr] ?: return emptyList()
    fun perGame(total: Int, games: Int) = total.toDouble() / games
    fun tenths(value: Double) = String.format(Locale.US, "%.1f", value)
    val myScored = perGame(row.pointsFor, row.games)
    val myAllowed = perGame(row.pointsAgainst, row.games)
    val myMargin = perGame(row.differential, row.games)
    val out = mutableListOf(
        GlanceTile("Points / game", tenths(myScored), rank(myScored, rows.map { perGame(it.pointsFor, it.games) })),
        GlanceTile("Allowed / game", tenths(myAllowed), rank(myAllowed, rows.map { perGame(it.pointsAgainst, it.games) }, higherIsBetter = false)),
        GlanceTile("Margin", TeamRating.signed(myMargin), rank(myMargin, rows.map { perGame(it.differential, it.games) })),
    )
    // Only the season this card is titled with; a rating a season behind waits for its own.
    val rating = ratings[abbr]
    if (rating != null && rating.season == liveSeason) {
        val all = ratings.values.toList()
        out += GlanceTile("Offense", TeamRating.signed(rating.offense), rank(rating.offense, all.map { it.offense }))
        out += GlanceTile("Defense", TeamRating.signed(rating.defense), rank(rating.defense, all.map { it.defense }))
        out += GlanceTile("Power", TeamRating.signed(rating.rating), rank(rating.rating, all.map { it.rating }))
    }
    return out
}

@Composable
fun TeamSeasonGlance(viewModel: DashboardViewModel, team: String) {
    val tiles = glanceTiles(team, viewModel.standings, viewModel.teamRatings, viewModel.freeSeason)
    if (tiles.isEmpty()) return
    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar("${SeasonLabel.display(viewModel.freeSeason)} AT A GLANCE")
        tiles.chunked(3).forEach { row ->
            Row(Modifier.fillMaxWidth()) {
                row.forEach { TileView(it, Modifier.weight(1f)) }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Text(
            "League rank under each number, 1st is best. Offense, defense and power are StatScout Power Ratings: points per 100 possessions against an average team, adjusted for schedule.",
            style = HardwoodType.micro,
            color = HardwoodPalette.inkTertiary,
            modifier = Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padCard, vertical = 8.dp),
        )
    }
}

@Composable
private fun TileView(tile: GlanceTile, modifier: Modifier = Modifier) {
    // 1st reads as the 100th percentile, 30th as the 0th, on the app's ramp.
    val percentile = Math.round((30 - tile.rank).toDouble() / 29 * 100).toInt().coerceIn(0, 100)
    Column(
        modifier.padding(vertical = 10.dp).clearAndSetSemantics {
            contentDescription = "${tile.label} ${tile.value}, ${tile.rank.ordinal} in the league"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(tile.value, style = HardwoodType.statMed, color = HardwoodPalette.ink)
        FitText(tile.label, HardwoodType.micro, HardwoodPalette.inkTertiary, minScale = 0.8f, textAlign = TextAlign.Center)
        Text(tile.rank.ordinal, style = HardwoodType.smallBold, color = HardwoodPalette.textColor(percentile))
    }
}
