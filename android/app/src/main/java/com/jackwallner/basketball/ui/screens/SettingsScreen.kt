package com.jackwallner.basketball.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.basketball.BuildConfig
import com.jackwallner.basketball.data.StoreLinks
import com.jackwallner.basketball.model.DateText
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.searchMatches
import com.jackwallner.basketball.ui.LocalAppActions
import com.jackwallner.basketball.ui.LocalGraph
import com.jackwallner.basketball.ui.components.CrownYellow
import com.jackwallner.basketball.ui.components.EmptyState
import com.jackwallner.basketball.ui.components.HardwoodSectionBar
import com.jackwallner.basketball.ui.components.Hairline
import com.jackwallner.basketball.ui.components.PushedScreen
import com.jackwallner.basketball.ui.components.SearchField
import com.jackwallner.basketball.ui.components.SfIcon
import com.jackwallner.basketball.ui.components.bottomBarPadding
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.components.hardwoodCard
import com.jackwallner.basketball.ui.nav.LocalNavigator
import com.jackwallner.basketball.ui.nav.Route
import com.jackwallner.basketball.ui.openMail
import com.jackwallner.basketball.ui.openPlayListing
import com.jackwallner.basketball.ui.openUrl
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.launch

private val LONG_DATE = DateTimeFormatter.ofPattern("MMMM d, yyyy 'at' h:mm a", Locale.US)

/**
 * Settings, a place in the app rather than a modal. Rate and Send Feedback are
 * separate rows with no question in front of either: Google forbids gating the
 * Play review behind one.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen() {
    val graph = LocalGraph.current
    val vm = graph.dashboard
    val store = graph.subscriptions
    val actions = LocalAppActions.current
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showReviewerCode by remember { mutableStateOf(false) }
    var isRestoring by remember { mutableStateOf(false) }
    var restoreConfirmed by remember { mutableStateOf(false) }
    val freshness = vm.freshnessForDisplay
    val coverage = freshness?.coverage ?: vm.dataCoverage
    val gamesThrough = coverage?.let { c ->
        DateText.gameDay(c.asOf)
    } ?: "-"
    val checked = (freshness?.checkedAt ?: vm.lastUpdated)?.let { LONG_DATE.format(it.atZone(ZoneId.systemDefault())) } ?: "-"
    val sourcePublished = freshness?.sourcePublishedAt?.let { LONG_DATE.format(it.atZone(ZoneId.systemDefault())) }

    PushedScreen("Settings") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottomBarPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card("STATSCOUT+") {
                Row(Modifier.padding(HardwoodGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfIcon("crown.fill", 26.dp, if (store.isPro) CrownYellow else HardwoodPalette.inkTertiary)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(if (store.isPro) "StatScout+ Unlocked" else "Free Version", style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                        Text(
                            if (store.isPro) "All StatScout+ features are active." else "Unlock Trends, recent form, head-to-head and every season back to 2002-03.",
                            style = HardwoodType.small,
                            color = HardwoodPalette.inkSecondary,
                        )
                    }
                    if (!store.isPro) {
                        Box(
                            Modifier.heightIn(min = 36.dp).clip(RoundedCornerShape(8.dp)).background(HardwoodPalette.court)
                                .clickable { actions.openPaywall(store.defaultUpgradeTrigger) }.padding(horizontal = 12.dp, vertical = 8.dp)
                                .testTag("settingsUpgrade"),
                            contentAlignment = Alignment.Center,
                        ) { Text(if (store.isLapsed) "Renew" else store.upgradeCTALabel, style = HardwoodType.smallBold, color = Color.White) }
                    }
                }
                Hairline()
                // The paywall's feedback, here too: a tap that showed nothing read as a dead button.
                LinkRow(
                    if (restoreConfirmed) "checkmark.circle.fill" else "arrow.clockwise",
                    if (isRestoring) "Restoring…" else if (restoreConfirmed) "StatScout+ restored" else "Restore Purchases",
                ) {
                    if (!isRestoring) scope.launch {
                        isRestoring = true
                        restoreConfirmed = false
                        store.restorePurchases()
                        isRestoring = false
                        restoreConfirmed = store.isPro
                    }
                }
                store.activeProductId?.let { productId ->
                    Hairline()
                    LinkRow("slider.horizontal.3", "Manage Subscription") { context.openUrl(StoreLinks.manageSubscriptionURL(productId)) }
                }
                store.lastError?.let {
                    Hairline()
                    Text(it, style = HardwoodType.small, color = HardwoodPalette.court, modifier = Modifier.fillMaxWidth().padding(HardwoodGeo.padCard))
                }
            }
            Card("REFERENCE") {
                Row(Modifier.clickable { navigator.push(Route.Glossary) }) {
                    InfoRow("text.book.closed.fill", "Stat Glossary", "Definitions and formulas for every stat in StatScout.")
                }
            }
            Card("SUPPORT & PRIVACY") {
                // The native rating sheet is rate-limited and may show nothing, so this is the way to leave a review.
                Row(Modifier.clickable {
                    graph.review.markOpenedWriteReview()
                    context.openPlayListing()
                }.testTag("rateRow")) { InfoRow("square.and.pencil", "Rate on Google Play", "Opens Google Play to write a review.") }
                Hairline()
                Row(Modifier.clickable {
                    graph.review.markFeedbackSent()
                    // No mail app: the support page carries the same address.
                    if (!context.openMail(StoreLinks.feedbackMail("StatScout feedback"))) context.openUrl(StoreLinks.SUPPORT_URL)
                }.testTag("feedbackRow")) { InfoRow("envelope.fill", "Contact Support", StoreLinks.FEEDBACK_EMAIL) }
                Hairline()
                Row(Modifier.clickable { context.openUrl(StoreLinks.PRIVACY_URL) }) { InfoRow("shield.lefthalf.filled", "Privacy Policy", "No ads or tracking.") }
            }
            Card("DATA") {
                InfoRow("arrow.triangle.2.circlepath", "Data Updates", "Checks for new NBA player data throughout the season.")
                Hairline()
                InfoRow("calendar.badge.clock", "Games Through", gamesThrough)
                Hairline()
                InfoRow("clock.arrow.circlepath", "Last Checked", checked)
                sourcePublished?.let {
                    Hairline()
                    InfoRow("cloud.sun.fill", "Source Published", it)
                }
            }
            Card("STATSCOUT") {
                Row(Modifier.padding(HardwoodGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    SfIcon("basketball.fill", 26.dp, HardwoodPalette.court)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Percentile Rankings", style = HardwoodType.cardTitle, color = HardwoodPalette.ink)
                        Text("Percentile rankings and leaderboards for every NBA player, ranked within guards, forwards and centers.", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                    }
                }
            }
            Card("VERSION") {
                // Long press opens the private reviewer access for Google Play's review team.
                Row(
                    Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { showReviewerCode = true }).padding(HardwoodGeo.padCard)
                        .testTag("versionRow"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("App Version", style = HardwoodType.bodyBold, color = HardwoodPalette.ink, modifier = Modifier.weight(1f))
                    Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary)
                }
            }
            Card("DISCLAIMER") {
                Text(
                    "Not affiliated with, endorsed by, or sponsored by the National Basketball Association, its teams, or the NBPA. Team names and abbreviations are used for identification only. All trademarks are property of their respective owners.",
                    style = HardwoodType.small,
                    color = HardwoodPalette.inkSecondary,
                    modifier = Modifier.fillMaxWidth().padding(HardwoodGeo.padCard),
                )
            }
        }
    }
    if (showReviewerCode) ReviewerCodeDialog { showReviewerCode = false }
}

@Composable
private fun Card(title: String, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().hardwoodCard()) {
        HardwoodSectionBar(title)
        content()
    }
}

@Composable
private fun InfoRow(icon: String, title: String, subtitle: String) {
    Row(Modifier.fillMaxWidth().padding(HardwoodGeo.padCard), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(28.dp), contentAlignment = Alignment.Center) { SfIcon(icon, 24.dp, HardwoodPalette.court) }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
            Text(subtitle, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
        }
    }
}

@Composable
private fun LinkRow(icon: String, title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onClick).padding(HardwoodGeo.padCard),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SfIcon(icon, 14.dp, HardwoodPalette.linkBlue)
        Text(title, style = HardwoodType.smallBold, color = HardwoodPalette.linkBlue)
    }
}

/** Google Play reviewers reach StatScout+ without paying; only a hash of the code is in the app. */
@Composable
private fun ReviewerCodeDialog(onDismiss: () -> Unit) {
    val store = LocalGraph.current.subscriptions
    var code by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = HardwoodPalette.surface,
        title = { Text("Reviewer Access", style = HardwoodType.cardTitle, color = HardwoodPalette.ink) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Enter the reviewer code provided with this app's review notes.", style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                OutlinedTextField(
                    code,
                    { code = it; failed = false },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = HardwoodPalette.court, cursorColor = HardwoodPalette.court),
                    modifier = Modifier.testTag("reviewerCode"),
                )
                if (failed) Text("That code isn't valid.", style = HardwoodType.small, color = HardwoodPalette.performanceLow)
            }
        },
        confirmButton = {
            TextButton(onClick = { if (store.activateReviewAccess(code)) onDismiss() else failed = true }) {
                Text("Unlock", style = HardwoodType.bodyBold, color = HardwoodPalette.court)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", style = HardwoodType.body, color = HardwoodPalette.inkSecondary) } },
    )
}

private data class GlossaryEntry(val id: String, val label: String, val category: String, val description: String, val detail: String? = null)

private val SUPPLEMENTAL = listOf(
    GlossaryEntry("general-games", "G", "Standard Stats", "Games in which the player appeared."),
    GlossaryEntry("standard-fg", "FG", "Standard Stats", "Field goals made and attempted. Ranked by shooting percentage, not by makes."),
    GlossaryEntry("standard-3p", "3P", "Standard Stats", "Three-pointers made and attempted. Ranked by shooting percentage."),
    GlossaryEntry("standard-ft", "FT", "Standard Stats", "Free throws made and attempted. Ranked by shooting percentage."),
    GlossaryEntry("standard-tov", "TOV", "Standard Stats", "Total turnovers. Lower is better."),
    GlossaryEntry("standard-pf", "PF", "Standard Stats", "Total personal fouls. Lower is better."),
    GlossaryEntry("standard-min", "MIN", "Standard Stats", "Total minutes played. Every rate on a roster is weighted by it."),
    GlossaryEntry("general-power", "Power Rating", "General", "Points per 100 possessions better or worse than an average team, from offensive and defensive rating adjusted for schedule. Early in the season last season's rating carries part of the weight. Two ratings read like a point spread, with about two and a half points for home court."),
    GlossaryEntry("general-small-sample", "Small sample", "General", "Below the playing-time minimum for that stat, prorated by how much of the season the typical team has played. A full-season player needs about 870 minutes and 20 games."),
    GlossaryEntry("general-not-ranked", "Not ranked", "General", "A counting stat at zero. When most of the league has none of something, a tie at zero has no honest percentile, so the value shows and the bar does not."),
    GlossaryEntry("general-groups", "Position groups", "General", "Guards (G), forwards (F) and centers (C), as the box score lists them. A center's rebounding is ranked against centers, so a percentile always means \"among players who play where he plays\"."),
    GlossaryEntry("percentile", "Percentile", "General", "A 1\u2013100 rank among players in the same position group, season, and season type. Higher is always better after lower-is-better stats are inverted."),
)

@Composable
fun StatGlossaryScreen() {
    val context = LocalContext.current
    var searchText by remember { mutableStateOf("") }
    val all = (SUPPLEMENTAL + BasketballMetricRegistry.definitions.map { GlossaryEntry("${it.category.raw}-${it.label}", it.label, it.category.raw, it.description, "${it.kind.label} · ${it.family.label}") })
        .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.label })
    val entries = if (searchText.isEmpty()) all else all.filter {
        it.label.searchMatches(searchText) || it.category.searchMatches(searchText) || it.description.searchMatches(searchText)
    }
    val categories = (listOf("General") + MetricCategory.entries.map { it.raw } + "Standard Stats").filter { c -> entries.any { it.category == c } }
    PushedScreen("Stat Glossary") {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).padding(top = 12.dp).padding(bottomBarPadding()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SearchField(searchText, { searchText = it }, prompt = "Search stats")
            Text(
                "Values come from ESPN box scores, play-by-play and shot charts via hoopR. Percentiles are calculated within each position group, separately for each season and season type. Each player is ranked against the qualified players at his position; in the current season, players under the playing-time minimum are placed against that pool without joining it.",
                style = HardwoodType.small,
                color = HardwoodPalette.inkSecondary,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
            if (entries.isEmpty()) {
                EmptyState("No stats found", "magnifyingglass", "Nothing matches \"$searchText\". Try a stat's abbreviation, like TS% or AST%.", Modifier.padding(vertical = 24.dp))
            } else categories.forEach { category ->
                Column(Modifier.fillMaxWidth().hardwoodCard()) {
                    HardwoodSectionBar(category.uppercase())
                    entries.filter { it.category == category }.forEachIndexed { index, entry ->
                        Column(
                            Modifier.fillMaxWidth().background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt).bottomHairline()
                                .padding(HardwoodGeo.padCard),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                                Text(entry.label, style = HardwoodType.bodyBold, color = HardwoodPalette.ink)
                                entry.detail?.let { Text(it.uppercase(), style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.padding(bottom = 2.dp)) }
                            }
                            Text(entry.description, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
                        }
                    }
                }
            }
            Column(Modifier.fillMaxWidth().hardwoodCard()) {
                HardwoodSectionBar("SOURCES")
                listOf(
                    "hoopR NBA data (ESPN box scores, play-by-play, shots)" to "https://hoopr.sportsdataverse.org/",
                    "Basketball-Reference Glossary" to "https://www.basketball-reference.com/about/glossary.html",
                ).forEachIndexed { index, (title, url) ->
                    if (index > 0) Hairline()
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { context.openUrl(url) }.padding(HardwoodGeo.padCard),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(title, style = HardwoodType.small, color = HardwoodPalette.court, modifier = Modifier.weight(1f))
                        SfIcon("arrow.up.right", 13.dp, HardwoodPalette.inkTertiary)
                    }
                }
            }
        }
    }
}

/** A build without its feed configuration says so instead of showing an empty league. */
@Composable
fun ConfigMissingScreen() {
    val context = LocalContext.current
    Column(
        Modifier.fillMaxSize().background(HardwoodPalette.canvas).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        SfIcon("exclamationmark.triangle.fill", 44.dp, HardwoodPalette.court)
        Text("StatScout can't load", style = HardwoodType.playerName, color = HardwoodPalette.ink)
        Text(
            "This build is missing its data-feed configuration. Please install the latest version from Google Play or contact support.",
            style = HardwoodType.body,
            color = HardwoodPalette.inkSecondary,
            textAlign = TextAlign.Center,
        )
        Box(
            Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(10.dp)).background(HardwoodPalette.court).clickable { context.openUrl(StoreLinks.SUPPORT_URL) }
                .padding(horizontal = 18.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Contact Support", style = HardwoodType.bodyBold, color = Color.White) }
        Spacer(Modifier.height(8.dp))
    }
}
