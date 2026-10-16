package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel.MetricExtreme
import com.jackwallner.basketball.data.DashboardViewModel.MetricLeaderEntry
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType

/** Best & Worst: the league leader and trailer on every metric, by category. */
@Composable
fun MetricLeadersView(metrics: List<MetricLeaderEntry>, interactive: Boolean = true) {
    val grouped = MetricCategory.entries.mapNotNull { cat -> metrics.filter { it.category == cat }.takeIf { it.isNotEmpty() }?.let { cat to it } }
    Column(Modifier.fillMaxSize().background(HardwoodPalette.canvas).verticalScroll(rememberScrollState(), enabled = interactive).padding(bottomBarPadding())) {
        if (metrics.isEmpty()) {
            EmptyState("No metric data", "chart.bar", "No metrics are available for the current season.", Modifier.padding(vertical = 24.dp))
        } else {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                grouped.forEach { (category, items) -> CategoryCard(category, items, interactive) }
            }
        }
    }
}

@Composable
private fun CategoryCard(category: MetricCategory, items: List<MetricLeaderEntry>, interactive: Boolean) {
    val navigator = LocalNavigator.current
    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar(category.raw.uppercase())
        Row(
            Modifier.fillMaxWidth().height(HardwoodGeo.rowHeightHeader).background(HardwoodPalette.surfaceAlt).bottomHairline()
                .padding(horizontal = HardwoodGeo.padInline),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("METRIC", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(88.dp))
            Text("BEST", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
            Text("WORST", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
        }
        items.forEachIndexed { index, item ->
            Row(
                Modifier.fillMaxWidth().height(52.dp).background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                    .bottomHairline().padding(horizontal = HardwoodGeo.padInline),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.width(88.dp).clickable(enabled = interactive) { navigator.push(Route.Metric(item.label, item.category)) },
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    FitText(item.label, HardwoodType.smallBold, HardwoodPalette.ink, Modifier.weight(1f, fill = false), minScale = 0.7f)
                    SfIcon("chevron.right", 11.dp, HardwoodPalette.inkTertiary)
                }
                Extreme(item.best, "No qualified players", interactive, Modifier.weight(1f))
                Extreme(item.worst, "Only qualifier", interactive, Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Extreme(entry: MetricExtreme?, empty: String, interactive: Boolean, modifier: Modifier) {
    val navigator = LocalNavigator.current
    if (entry == null) {
        Text(empty, style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, maxLines = 1, modifier = modifier)
        return
    }
    Row(
        modifier.clickable(enabled = interactive) { navigator.push(Route.PlayerProfile(entry.player)) },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PlayerHeadshot(entry.player.team, entry.player.initials, 24.dp)
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            FitText(entry.player.name, HardwoodType.smallBold, HardwoodPalette.ink, minScale = 0.7f)
            // Some metrics ship a percentile and a blank value: show the rank rather than an empty cell.
            val value = entry.actualValue.trim().ifEmpty { "${entry.percentile.ordinal} pct" }
            Text(value, style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, maxLines = 1)
        }
    }
}
