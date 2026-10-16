package com.jackwallner.basketball.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.RecentMetricKey
import com.jackwallner.basketball.model.PlayerPositionGroup
import com.jackwallner.basketball.model.PlayerProfile
import com.jackwallner.basketball.model.SeasonLabel
import com.jackwallner.basketball.model.StatScoutSeason
import com.jackwallner.basketball.model.displayTeamAbbr
import com.jackwallner.basketball.model.displayTeamFullName
import com.jackwallner.basketball.model.normalizedTeamAbbreviation
import com.jackwallner.basketball.model.ordinal
import com.jackwallner.basketball.model.teamFullName
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import com.jackwallner.basketball.ui.theme.TeamColor
import com.jackwallner.basketball.ui.theme.sf
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.pow

private val TEXT_SHADOW = Shadow(Color.Black.copy(alpha = 0.35f), Offset(0f, 1f), 2f)

/** A single-line label that shrinks (down to [minScale]) before it truncates, like iOS `minimumScaleFactor`. */
@Composable
fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.8f,
    textAlign: TextAlign? = null,
) {
    BoxWithConstraints(modifier) {
        val measurer = androidx.compose.ui.text.rememberTextMeasurer()
        val maxPx = constraints.maxWidth
        val fitted = remember(text, style, maxPx) {
            if (maxPx == Int.MAX_VALUE) return@remember style
            var scale = 1f
            while (scale > minScale) {
                val width = measurer.measure(text, style.copy(fontSize = style.fontSize * scale), maxLines = 1).size.width
                if (width <= maxPx) break
                scale -= 0.05f
            }
            style.copy(fontSize = style.fontSize * scale.coerceAtLeast(minScale))
        }
        Text(text, style = fitted, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = textAlign, softWrap = false)
    }
}

@Composable
fun SfIcon(name: String, size: Dp, tint: Color, modifier: Modifier = Modifier, contentDescription: String? = null) {
    Icon(sf(name), contentDescription = contentDescription, tint = tint, modifier = modifier.size(size))
}

@Composable
fun SfIcon(icon: ImageVector, size: Dp, tint: Color, modifier: Modifier = Modifier) {
    Icon(icon, contentDescription = null, tint = tint, modifier = modifier.size(size))
}

/** Initials in the team colour: the app never renders player photos. */
@Composable
fun PlayerHeadshot(team: String, initials: String, size: Dp, modifier: Modifier = Modifier, ring: Color? = null) {
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(TeamColor.color(team))
            .border(if (ring != null) 2.dp else 0.5.dp, ring ?: Color.White.copy(alpha = 0.25f), CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(initials, color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.34f).sp)
    }
}

@Composable
fun OverallPercentileBadge(percentile: Int, size: Dp = 64.dp) {
    val tier = when {
        percentile >= 90 -> "Elite"
        percentile >= 75 -> "Excellent"
        percentile >= 50 -> "Above Average"
        percentile >= 25 -> "Below Average"
        else -> "Poor"
    }
    Column(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(HardwoodGeo.radiusBadge))
            .background(HardwoodPalette.color(percentile))
            .clearAndSetSemantics { contentDescription = "Overall ${percentile.ordinal} percentile, $tier" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("$percentile", style = HardwoodType.statHero.copy(shadow = TEXT_SHADOW), color = Color.White)
        Text(percentile.ordinal, style = HardwoodType.micro.copy(shadow = TEXT_SHADOW), color = Color.White.copy(alpha = 0.9f))
    }
}

@Composable
fun TeamColorDot(abbr: String, size: Dp = 8.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(TeamColor.color(abbr)))
}

/** One percentile row: label, coloured track with the rank bubble, value. */
@Composable
fun MetricBar(metric: Metric, modifier: Modifier = Modifier, showValue: Boolean = true) {
    val description = if (metric.isUnranked) "${metric.label}: ${metric.value}, not ranked" else {
        val valueText = if (metric.value.isEmpty()) "${metric.percentile.ordinal} percentile" else "${metric.value}, ${metric.percentile.ordinal} percentile"
        "${metric.label}: $valueText${if (metric.isSmallSample) ", small sample" else ""}"
    }
    Row(
        modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.width(104.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            // Basketball labels run long ("Non-Corner 3%"): two lines before shrinking.
            Text(metric.label, style = HardwoodType.bodyBold, color = HardwoodPalette.ink, maxLines = 2)
            if (metric.isSmallSample && !metric.isUnranked) {
                Text("Small sample", fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = HardwoodPalette.inkTertiary, maxLines = 1)
            }
        }
        Box(Modifier.weight(1f).height(28.dp), contentAlignment = Alignment.CenterStart) {
            if (metric.isUnranked) {
                Box(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(4.dp)).background(HardwoodPalette.surfaceSunk))
                Text(
                    "Not ranked",
                    style = HardwoodType.micro,
                    color = HardwoodPalette.inkTertiary,
                    modifier = Modifier.padding(start = 8.dp).clip(CircleShape).background(HardwoodPalette.surfaceSunk).padding(horizontal = 6.dp),
                )
            } else {
                PercentileTrack(metric.percentile.coerceIn(0, 100), dimmed = metric.isSmallSample, shotProfile = metric.isShotProfile)
            }
        }
        Box(Modifier.width(72.dp), contentAlignment = Alignment.CenterEnd) {
            if (showValue && metric.value.isNotEmpty()) {
                FitText(
                    metric.value,
                    HardwoodType.statMed,
                    if (metric.isSmallSample || metric.isUnranked) HardwoodPalette.inkSecondary else HardwoodPalette.ink,
                    minScale = 0.7f,
                    textAlign = TextAlign.End,
                )
            }
        }
    }
}

@Composable
private fun PercentileTrack(percentile: Int, dimmed: Boolean, shotProfile: Boolean = false) {
    // Good-to-bad colour, except for a shot-profile stat, where a rank says how a player plays and not how well.
    val color = if (shotProfile) HardwoodPalette.linkBlue else HardwoodPalette.color(percentile)
    val alpha = if (dimmed) 0.45f else 1f
    BoxWithConstraints(Modifier.fillMaxWidth().height(28.dp)) {
        val circle = 28.dp
        val trackWidth = maxWidth - circle
        val offset = circle / 2 + trackWidth * (percentile / 100f)
        Box(
            Modifier.align(Alignment.CenterStart).fillMaxWidth().height(10.dp).clip(RoundedCornerShape(4.dp))
                .background(HardwoodPalette.surfaceSunk.copy(alpha = alpha)),
        )
        Box(Modifier.align(Alignment.CenterStart).width(offset).height(10.dp).clip(RoundedCornerShape(4.dp)).background(color.copy(alpha = alpha)))
        Box(
            Modifier.offset(x = offset - circle / 2).size(circle).clip(CircleShape).background(color.copy(alpha = alpha)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "$percentile",
                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum", shadow = TEXT_SHADOW),
                color = Color.White,
            )
        }
    }
}

/** Season and recent bars stacked; a missing window says so rather than vanishing. */
@Composable
fun DualMetricBar(season: Metric, recent: Metric?, recentCaption: String = "Recent") {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Season", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(52.dp))
            MetricBar(season)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                recentCaption,
                style = HardwoodType.micro,
                color = if (recent == null) HardwoodPalette.inkTertiary else HardwoodPalette.court,
                modifier = Modifier.width(52.dp),
            )
            if (recent != null) MetricBar(recent)
            else Text("Not available per week", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
fun SearchField(
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    focusOnAppear: Boolean = false,
    prompt: String = "Search players or teams",
) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(focusOnAppear) { if (focusOnAppear) runCatching { focus.requestFocus() } }
    Row(
        modifier
            .fillMaxWidth()
            .height(40.dp)
            .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
            .background(HardwoodPalette.surface)
            .border(1.dp, HardwoodPalette.hairline, RoundedCornerShape(HardwoodGeo.radiusCard))
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        SfIcon("magnifyingglass", 18.dp, HardwoodPalette.inkSecondary)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) Text(prompt, style = HardwoodType.body, color = HardwoodPalette.inkSecondary)
            BasicTextField(
                value = text,
                onValueChange = onTextChange,
                singleLine = true,
                textStyle = HardwoodType.body.copy(color = HardwoodPalette.ink),
                cursorBrush = SolidColor(HardwoodPalette.court),
                modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("searchField"),
            )
        }
        if (text.isNotEmpty()) {
            SfIcon("xmark.circle.fill", 18.dp, HardwoodPalette.inkTertiary, Modifier.clickable { onTextChange("") }, "Clear search")
        }
    }
}

@Composable
fun SectionHeader(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = HardwoodType.sectionTitle, color = HardwoodPalette.ink)
        Text(subtitle, style = HardwoodType.small, color = HardwoodPalette.inkSecondary)
    }
}

/**
 * Recent-vs-prior change: the arrow points the way the number moved; green
 * always means better. Below half the last shown digit it is flat.
 */
@Composable
fun TrendArrow(delta: Double, decimals: Int = 1, lowerIsBetter: Boolean = false, modifier: Modifier = Modifier) {
    val isFlat = abs(delta) < 5 * 10.0.pow(-(decimals + 1).toDouble())
    val tint = when {
        isFlat -> HardwoodPalette.inkTertiary
        (if (lowerIsBetter) delta < 0 else delta > 0) -> HardwoodPalette.performanceHigh
        else -> HardwoodPalette.performanceLow
    }
    val text = if (isFlat) "0" else String.format(java.util.Locale.US, "%.${decimals}f", abs(delta))
    Row(
        modifier.clearAndSetSemantics { contentDescription = if (isFlat) "No recent change" else "${if (delta > 0) "Up" else "Down"} $text recently" },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!isFlat) SfIcon(if (delta > 0) "arrow.up" else "arrow.down", 10.dp, tint)
        Text(text, style = HardwoodType.micro.copy(fontFeatureSettings = "tnum"), color = tint)
    }
}

@Composable
fun PercentileBarMini(percentile: Int, modifier: Modifier = Modifier, height: Dp = 7.dp, tint: Color? = null) {
    BoxWithConstraints(modifier.height(height)) {
        Box(Modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(height / 2)).background(HardwoodPalette.surfaceSunk))
        Box(
            Modifier.width(maxWidth * (percentile.coerceIn(0, 100) / 100f)).height(height).clip(RoundedCornerShape(height / 2))
                .background(tint ?: HardwoodPalette.color(percentile)),
        )
    }
}

@Composable
fun InlineLoadError(message: String, retry: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = HardwoodGeo.padInline, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(message, style = HardwoodType.small, color = HardwoodPalette.inkSecondary, textAlign = TextAlign.Center)
        TextAction("Try Again", HardwoodType.smallBold, HardwoodPalette.court, retry)
    }
}

/** A plain text button with an Android-sized touch target. */
@Composable
fun TextAction(title: String, style: TextStyle, color: Color, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Box(
        modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 8.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = style, color = color.copy(alpha = if (enabled) 1f else 0.5f), textAlign = TextAlign.Center)
    }
}

/**
 * The leaderboard header: RANK / PLAYER / TEAM, then the sorted stat. A label,
 * not controls: the whole header is the sort toggle, the same as the Standard board's.
 */
@Composable
fun LeaderboardTableHeader(
    sortDescending: Boolean,
    sortLabel: String = "OVERALL",
    onToggleDirection: () -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeightHeader).background(HardwoodPalette.surfaceAlt)
            .bottomHairline(HardwoodPalette.divider)
            .clickable(onClickLabel = "Reverse ranking order", onClick = onToggleDirection)
            .padding(horizontal = HardwoodGeo.padInline),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("RANK", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(42.dp))
        Text("PLAYER", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.weight(1f))
        Text("TEAM", style = HardwoodType.micro, color = HardwoodPalette.inkTertiary, modifier = Modifier.width(50.dp))
        Row(
            Modifier.width(104.dp).clearAndSetSemantics {
                contentDescription = "$sortLabel, ${if (sortDescending) "highest first" else "lowest first"}"
            },
            horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.End),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FitText(sortLabel.uppercase(), HardwoodType.micro, HardwoodPalette.court, Modifier.weight(1f, fill = false), minScale = 0.7f)
            SfIcon(if (sortDescending) "arrow.down" else "arrow.up", 9.dp, HardwoodPalette.court)
        }
    }
}

/**
 * One banded leaderboard row. A player without the sorted metric gets a muted
 * dash, never a bar drawn from a different number.
 */
@Composable
fun LeaderboardTableRow(
    rank: Int,
    player: Player,
    /** Row position for the zebra band: Android ranks ties as 1, 2, 2, 4, so the rank repeats. */
    stripe: Int? = null,
    metricLabel: String? = null,
    metricCategory: MetricCategory? = null,
    trendDelta: Double? = null,
    trendDecimals: Int = 3,
    valueOverride: String? = null,
    volume: String? = null,
    isSmallSample: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val metric = metricLabel?.let { label ->
        if (metricCategory != null) player.metrics.firstOrNull { it.label == label && it.category == metricCategory }
        else player.metrics.firstOrNull { it.label == label }
    }
    val percentile = metric?.percentile ?: 0
    val valueText = valueOverride ?: metric?.let { if (it.value.isNotEmpty()) it.value else it.percentile.ordinal } ?: "-"
    val valueColor = when {
        isSmallSample || metric?.isUnranked == true -> HardwoodPalette.inkTertiary
        valueOverride == null && metric?.isShotProfile != true -> HardwoodPalette.textColor(percentile)
        else -> HardwoodPalette.ink
    }
    val subtitle = listOfNotNull(player.displayPosition, volume, if (isSmallSample) "small sample" else null).joinToString(" · ")
    Row(
        Modifier.fillMaxWidth().height(52.dp)
            .background(if ((stripe ?: (rank - 1)) % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = HardwoodGeo.padInline)
            .testTag("leaderboardRow"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(if (rank > 0) "$rank" else "-", style = HardwoodType.statSmall, color = HardwoodPalette.inkSecondary, modifier = Modifier.width(42.dp))
        Row(Modifier.weight(1f).padding(end = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            PlayerHeadshot(player.team, player.initials, 36.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                FitText(player.name, HardwoodType.bodyBold, HardwoodPalette.ink, minScale = 0.6f)
                FitText(subtitle, HardwoodType.micro, HardwoodPalette.inkTertiary, minScale = 0.85f)
            }
        }
        Row(Modifier.width(50.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            TeamColorDot(player.team, 6.dp)
            Text(displayTeamAbbr(player.team), style = HardwoodType.small, color = HardwoodPalette.inkSecondary, maxLines = 1)
        }
        Row(
            Modifier.width(if (trendDelta == null) 92.dp else 56.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (metric != null || valueOverride != null) {
                if (valueOverride == null) {
                    if (metric?.isUnranked == true) Spacer(Modifier.width(40.dp))
                    else PercentileBarMini(
                        percentile,
                        Modifier.width(40.dp).alphaIf(isSmallSample, 0.35f),
                        tint = if (metric?.isShotProfile == true) HardwoodPalette.linkBlue else null,
                    )
                }
                FitText(valueText, HardwoodType.statSmall, valueColor, Modifier.width(48.dp), minScale = 0.7f, textAlign = TextAlign.End)
            } else {
                Text("-", style = HardwoodType.statSmall, color = HardwoodPalette.inkTertiary, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth())
            }
        }
        if (trendDelta != null) {
            Box(Modifier.width(46.dp), contentAlignment = Alignment.CenterEnd) {
                TrendArrow(trendDelta, trendDecimals, lowerIsBetter = metricLabel?.let(RecentMetricKey::lowerIsBetter) ?: false)
            }
        }
    }
}

fun Modifier.alphaIf(condition: Boolean, alpha: Float): Modifier =
    if (condition) this.then(Modifier.graphicsAlpha(alpha)) else this

private fun Modifier.graphicsAlpha(alpha: Float): Modifier = this.alpha(alpha)

/** A hairline along the bottom edge, drawn rather than laid out. */
fun Modifier.bottomHairline(color: Color = HardwoodPalette.divider, width: Dp = HardwoodGeo.hairline): Modifier = drawBehind {
    val stroke = width.toPx()
    drawRect(color, topLeft = Offset(0f, size.height - stroke), size = androidx.compose.ui.geometry.Size(size.width, stroke))
}

fun Modifier.topHairline(color: Color = HardwoodPalette.divider, width: Dp = HardwoodGeo.hairline): Modifier = drawBehind {
    drawRect(color, size = androidx.compose.ui.geometry.Size(size.width, width.toPx()))
}

/** The card surface every module sits on. */
fun Modifier.hardwoodCard(stroke: Color = HardwoodPalette.hairline): Modifier = this
    .clip(RoundedCornerShape(HardwoodGeo.radiusCard))
    .background(HardwoodPalette.surface)
    .border(HardwoodGeo.hairline, stroke, RoundedCornerShape(HardwoodGeo.radiusCard))

@Composable
fun HardwoodSectionBar(title: String, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().height(HardwoodGeo.rowHeightHeader).background(HardwoodPalette.surfaceSunk),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.uppercase(), style = HardwoodType.sectionTitle, color = HardwoodPalette.ink, modifier = Modifier.padding(start = HardwoodGeo.padCard))
        Spacer(Modifier.weight(1f))
        if (trailing != null) Row(Modifier.padding(end = 12.dp), verticalAlignment = Alignment.CenterVertically, content = trailing)
    }
}

@Composable
fun HardwoodSubSectionBar(title: String, trailing: String? = null, trailingColor: Color = HardwoodPalette.inkSecondary) {
    Row(
        Modifier.fillMaxWidth().height(26.dp).background(HardwoodPalette.surfaceAlt).bottomHairline().padding(horizontal = HardwoodGeo.padCard),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.uppercase(), style = HardwoodType.micro, color = HardwoodPalette.inkSecondary)
        Spacer(Modifier.weight(1f))
        if (trailing != null) Text(trailing, style = HardwoodType.statSmall, color = trailingColor)
    }
}

/** Underlined text tabs: the metric-category tier. */
@Composable
fun HardwoodTabs(tabs: List<String>, selected: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    val haptic = rememberHaptic()
    // Six basketball categories do not fit as equal columns at phone width, so a
    // long set scrolls and each tab keeps its natural width.
    val scrolls = tabs.size > 4
    val scroll = rememberScrollState()
    Row(
        modifier.fillMaxWidth().background(HardwoodPalette.surface).bottomHairline(HardwoodPalette.hairline)
            .then(if (scrolls) Modifier.horizontalScroll(scroll) else Modifier),
    ) {
        tabs.forEach { tab ->
            val isSelected = selected == tab
            Column(
                (if (scrolls) Modifier.width(IntrinsicSize.Max) else Modifier.weight(1f)).clickable {
                    onSelect(tab)
                    haptic()
                }.semantics {
                    contentDescription = spokenTab(tab)
                    this.selected = isSelected
                }.testTag("tab_$tab"),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    (if (scrolls) Modifier else Modifier.fillMaxWidth()).height(44.dp).padding(horizontal = if (scrolls) 14.dp else 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (scrolls) Text(tab.uppercase(), style = HardwoodType.smallBold, color = if (isSelected) HardwoodPalette.ink else HardwoodPalette.inkTertiary, maxLines = 1)
                    else FitText(tab.uppercase(), HardwoodType.smallBold, if (isSelected) HardwoodPalette.ink else HardwoodPalette.inkTertiary, minScale = 0.75f)
                }
                Box(Modifier.fillMaxWidth().height(3.dp).background(if (isSelected) HardwoodPalette.court else Color.Transparent))
            }
        }
    }
}

/** TalkBack reads "G" as a letter; the position tabs say what they are. */
private fun spokenTab(tab: String): String = when (tab) {
    "G" -> "Guards"
    "F" -> "Forwards"
    "C" -> "Centers"
    else -> tab
}

/** Player header on the midnight band: name, team, bio, draft and the per-game slash line. */
@Composable
fun PlayerIdentityStrip(player: Player, showOverallBadge: Boolean = false, profile: PlayerProfile? = null) {
    // "#11 · G · 24 yrs · 6-1, 196".
    val bioLine = if (profile == null) player.displayPosition.trim() else listOfNotNull(
        profile.jersey?.let { "#$it" },
        player.displayPosition,
        profile.age(LocalDate.now())?.let { "$it yrs" },
        profile.sizeLabel,
    ).joinToString(" · ")
    // "2023 R1 #20", or "Undrafted".
    val originLine = profile?.draftLabel
    Row(
        Modifier.fillMaxWidth().background(HardwoodPalette.midnight).padding(HardwoodGeo.padPage),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PlayerHeadshot(player.team, player.initials, 72.dp, ring = Color.White)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(player.name, HardwoodType.playerName, HardwoodPalette.inkOnDark, minScale = 0.7f)
            FitText(displayTeamFullName(player.team), HardwoodType.bodyBold, Color.White.copy(alpha = 0.85f), minScale = 0.8f)
            FitText(bioLine, HardwoodType.small, Color.White.copy(alpha = 0.65f), minScale = 0.8f)
            originLine?.let { FitText(it, HardwoodType.small, Color.White.copy(alpha = 0.65f), minScale = 0.8f) }
            player.perGameSlashLine?.let {
                FitText(it, HardwoodType.bodyBold.copy(fontFeatureSettings = "tnum"), HardwoodPalette.inkOnDark, Modifier.padding(top = 2.dp), minScale = 0.8f)
            }
        }
        if (showOverallBadge) OverallPercentileBadge(player.overallPercentile)
    }
}


@Composable
fun TeamIdentityStrip(team: String, season: Int? = null) {
    val abbr = normalizedTeamAbbreviation(team)
    Row(
        Modifier.fillMaxWidth().background(HardwoodPalette.midnight).padding(HardwoodGeo.padPage),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(56.dp).clip(CircleShape).background(TeamColor.color(abbr)), contentAlignment = Alignment.Center) {
            Text(abbr, style = HardwoodType.pageTitle, color = Color.White)
        }
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            FitText(teamFullName(abbr), HardwoodType.playerName, HardwoodPalette.inkOnDark, minScale = 0.7f)
            Text(SeasonLabel.display(season ?: StatScoutSeason.calendarSeason()) + " Season", style = HardwoodType.small, color = Color.White.copy(alpha = 0.65f))
        }
    }
}

@Composable
fun rememberHaptic(): () -> Unit {
    val haptic = androidx.compose.ui.platform.LocalHapticFeedback.current
    return remember(haptic) { { haptic.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.SegmentTick) } }
}

/**
 * One slice of a card drawn as separate lazy items: the outline's sides on every
 * slice, its top edge and corners on the first, its bottom on the last.
 */
fun Modifier.cardSlice(first: Boolean, last: Boolean, stroke: Color = HardwoodPalette.hairline): Modifier {
    val radius = HardwoodGeo.radiusCard
    val shape = RoundedCornerShape(
        topStart = if (first) radius else 0.dp,
        topEnd = if (first) radius else 0.dp,
        bottomStart = if (last) radius else 0.dp,
        bottomEnd = if (last) radius else 0.dp,
    )
    return this.clip(shape).background(HardwoodPalette.surface).drawWithContent {
        drawContent()
        val w = HardwoodGeo.hairline.toPx()
        val r = radius.toPx()
        drawRect(stroke, topLeft = Offset(0f, if (first) r else 0f), size = androidx.compose.ui.geometry.Size(w, size.height - (if (first) r else 0f) - (if (last) r else 0f)))
        drawRect(stroke, topLeft = Offset(size.width - w, if (first) r else 0f), size = androidx.compose.ui.geometry.Size(w, size.height - (if (first) r else 0f) - (if (last) r else 0f)))
        if (first) {
            drawRect(stroke, topLeft = Offset(r, 0f), size = androidx.compose.ui.geometry.Size(size.width - 2 * r, w))
            drawArc(stroke, 180f, 90f, false, topLeft = Offset(w / 2, w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
            drawArc(stroke, 270f, 90f, false, topLeft = Offset(size.width - 2 * r - w / 2, w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        }
        if (last) {
            drawRect(stroke, topLeft = Offset(r, size.height - w), size = androidx.compose.ui.geometry.Size(size.width - 2 * r, w))
            drawArc(stroke, 90f, 90f, false, topLeft = Offset(w / 2, size.height - 2 * r - w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
            drawArc(stroke, 0f, 90f, false, topLeft = Offset(size.width - 2 * r - w / 2, size.height - 2 * r - w / 2), size = androidx.compose.ui.geometry.Size(2 * r, 2 * r), style = androidx.compose.ui.graphics.drawscope.Stroke(w))
        }
    }
}


/** A player picker row's second line: "DEN · C · 27.7 PPG". */
fun pickerSubtitle(player: Player): String {
    val points = player.metrics.firstOrNull { it.label == "PPG" }?.value
    return listOfNotNull(displayTeamAbbr(player.team), player.displayPosition, points?.let { "$it PPG" }).joinToString(" · ")
}
