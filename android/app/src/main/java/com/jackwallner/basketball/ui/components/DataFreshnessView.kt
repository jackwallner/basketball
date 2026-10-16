package com.jackwallner.basketball.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.data.DashboardViewModel
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.DateText
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * One quiet caption: "Through Nov 12 · 189 games · Updated 2h ago". Between a
 * season's last game and the next one's opening night it says so instead:
 * "2025-26 final · 2026-27 starts Oct 20". Only a real
 * problem earns an icon and colour; tapping it checks for new data.
 */
@Composable
fun DataFreshnessView(viewModel: DashboardViewModel, modifier: Modifier = Modifier, season: Int? = null, phase: SeasonPhase? = null) {
    val isCurrentScope = when {
        season == null -> true
        season != viewModel.freeSeason -> false
        phase == null -> true
        else -> phase == SeasonPhase.REGULAR
    }
    if (!isCurrentScope) return
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(60_000)
            now = Instant.now()
        }
    }
    val scope = rememberCoroutineScope()
    val text = freshnessCaption(viewModel, now)
    val icon = problemIcon(effectiveStatus(viewModel))
    val tint = if (icon == null) HardwoodPalette.inkTertiary else HardwoodPalette.performanceLow
    val a11y = text.replace(" · ", ", ").replace("m ago", " minutes ago").replace("h ago", " hours ago")
    Row(
        modifier.fillMaxWidth().heightIn(min = 32.dp)
            .clickable(enabled = !viewModel.isRefreshing) { scope.launch { viewModel.load() } }
            .semantics { contentDescription = "$a11y. Checks for new game data" },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let { SfIcon(it, 12.dp, tint) }
        FitText(text, HardwoodType.micro, tint, Modifier.weight(1f, fill = false), minScale = 0.85f)
        if (viewModel.isRefreshing) CircularProgressIndicator(Modifier.size(10.dp), color = HardwoodPalette.inkTertiary, strokeWidth = 1.5.dp)
    }
}

private fun effectiveStatus(vm: DashboardViewModel): DataFreshnessStatus {
    val raw = vm.freshnessStatus
    // Every game is in and only optional enrichment (shot zones or on/off) is late: a normal overnight state.
    if (raw == DataFreshnessStatus.PARTIAL && !isWaitingOnGames(vm)) return DataFreshnessStatus.READY
    return raw
}

private fun isWaitingOnGames(vm: DashboardViewModel): Boolean {
    val coverage = vm.freshnessForDisplay?.coverage ?: return false
    val expected = coverage.expectedGames ?: return false
    val included = coverage.gamesIncluded ?: return false
    return included < expected
}

private fun problemIcon(status: DataFreshnessStatus): String? = when (status) {
    DataFreshnessStatus.OFFLINE -> "wifi.slash"
    DataFreshnessStatus.FAILED -> "exclamationmark.triangle.fill"
    DataFreshnessStatus.STALE -> "arrow.clockwise"
    else -> null
}

fun freshnessCaption(vm: DashboardViewModel, now: Instant): String {
    val coverageText = coverageText(vm)
    return when (effectiveStatus(vm)) {
        DataFreshnessStatus.OFFLINE -> "Offline · Showing saved stats"
        DataFreshnessStatus.FAILED -> "Couldn't update · Showing saved stats"
        DataFreshnessStatus.STALE -> "Newer stats available · Tap to load"
        DataFreshnessStatus.CHECKING -> if (coverageText == null) "Checking for new stats" else joined(coverageText, updatedText(vm, now))
        else -> if (vm.isSeasonPending) {
            // Nothing updates until opening night, so the last revision's age would only read as staleness.
            listOfNotNull("${SeasonLabel.display(vm.freeSeason)} final", vm.upcomingSeasonStartsText).joinToString(" · ")
        } else joined(coverageText, updatedText(vm, now))
    }
}

private fun joined(vararg parts: String?): String =
    parts.filterNotNull().ifEmpty { listOf("Checking for new stats") }.joinToString(" · ")

/** "Through Nov 12 · 189 games", or "... · 12 of 14 games in" while a slate is still arriving. */
private fun coverageText(vm: DashboardViewModel): String? {
    val coverage = vm.freshnessForDisplay?.coverage ?: vm.dataCoverage ?: return null
    // "Through": the game count after it is cumulative, and "Nov 12 · 189 games"
    // read as a hundred and eighty-nine games on Nov 12.
    val parts = mutableListOf("Through ${DateText.gameDay(coverage.asOf)}")
    coverage.gamesIncluded?.let { included ->
        val expected = coverage.expectedGames
        parts += if (expected != null && included < expected) "${grouped(included)} of ${grouped(expected)} games in"
        else if (included == 1) "1 game" else "${grouped(included)} games"
    }
    return parts.joinToString(" · ")
}

private fun updatedText(vm: DashboardViewModel, now: Instant): String? {
    val date = vm.freshnessForDisplay?.publishedAt ?: vm.lastCheckedAt ?: return null
    return "Updated ${shortAge(date, now)}"
}

fun shortAge(date: Instant, now: Instant = Instant.now()): String {
    val seconds = maxOf(0L, Duration.between(date, now).seconds)
    return when {
        seconds < 60 -> "just now"
        seconds < 3_600 -> "${seconds / 60}m ago"
        seconds < 86_400 -> "${seconds / 3_600}h ago"
        else -> DateTimeFormatter.ofPattern("MMM d", Locale.US).format(date.atZone(ZoneId.systemDefault()))
    }
}

private fun grouped(value: Int): String = java.text.NumberFormat.getIntegerInstance(java.util.Locale.US).format(value)
