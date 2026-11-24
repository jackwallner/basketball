package com.jackwallner.basketball.ui.screens

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.jackwallner.basketball.data.StoreLinks
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricKind
import com.jackwallner.basketball.model.Player
import com.jackwallner.basketball.model.displayTeamFullName
import com.jackwallner.basketball.ui.components.FitText
import com.jackwallner.basketball.ui.components.HardwoodSubSectionBar
import com.jackwallner.basketball.ui.components.MetricBar
import com.jackwallner.basketball.ui.components.PlayerHeadshot
import com.jackwallner.basketball.ui.components.bottomHairline
import com.jackwallner.basketball.ui.theme.HardwoodGeo
import com.jackwallner.basketball.ui.theme.HardwoodPalette
import com.jackwallner.basketball.ui.theme.HardwoodType
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** What a shared percentile card says, kept out of the drawing so it can be tested. */
object PlayerShare {
    /** The card is laid out at this width and rendered at [SCALE], as on iOS (1170 px). */
    const val CARD_WIDTH_DP = 390
    const val SCALE = 3f

    /** The season board as the profile draws it, ranked rows only; a category with none is left out. */
    fun groups(player: Player): List<Pair<MetricCategory, List<Metric>>> {
        val grouped = player.metrics(MetricKind.ADVANCED).groupBy { it.category }
        return MetricCategory.entries.mapNotNull { category ->
            val ranked = grouped[category].orEmpty().filter { !it.isUnranked }
            if (ranked.isEmpty()) null else category to BasketballMetricRegistry.sorted(ranked)
        }
    }

    /** "Stephen-Curry-2025-26.png". */
    fun fileName(playerName: String, seasonLabel: String): String {
        val slug = playerName.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }.joinToString("-")
        return "$slug-${seasonLabel.replace(" ", "-")}.png"
    }

    fun message(playerName: String, seasonLabel: String): String =
        "$playerName, $seasonLabel percentiles on StatScout ${StoreLinks.PLAY_LISTING_URL}"

    /** A live board moves through the season, so it carries its date; a past season says what it is ranked against. */
    fun footnote(isCurrentSeason: Boolean, updatedAt: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        if (!isCurrentSeason) return "Ranked against NBA qualifiers"
        return "Through ${DateTimeFormatter.ofPattern("MMM d", Locale.US).format(updatedAt.atZone(zone))}"
    }

    fun identityLine(player: Player): String =
        listOf(displayTeamFullName(player.team), player.displayPosition.trim()).filter { it.isNotEmpty() }.joinToString(" · ")
}

/** One share in flight: the board to draw and the words that go with it. */
data class ShareRequest(
    val player: Player,
    val groups: List<Pair<MetricCategory, List<Metric>>>,
    val seasonLabel: String,
    val footnote: String,
)

/** The image a percentile board is shared as: the profile's own bars under a team header, the app named in the footer. */
@Composable
fun PlayerShareCard(request: ShareRequest) {
    val player = request.player
    Column(Modifier.requiredWidth(PlayerShare.CARD_WIDTH_DP.dp).background(HardwoodPalette.surface)) {
        Row(
            Modifier.fillMaxWidth().background(HardwoodPalette.midnight).padding(HardwoodGeo.padPage),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            PlayerHeadshot(player.team, player.initials, 52.dp, ring = Color.White)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                FitText(player.name, HardwoodType.playerName, HardwoodPalette.inkOnDark, minScale = 0.6f)
                FitText(PlayerShare.identityLine(player), HardwoodType.small, Color.White.copy(alpha = 0.75f))
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(request.seasonLabel, style = HardwoodType.statLarge, color = HardwoodPalette.inkOnDark, maxLines = 1)
                Text("PERCENTILES", style = HardwoodType.micro.copy(letterSpacing = 0.6.sp), color = HardwoodPalette.gold)
            }
        }
        request.groups.forEach { (category, metrics) ->
            HardwoodSubSectionBar(category.raw)
            metrics.forEachIndexed { index, metric ->
                Box(
                    Modifier.fillMaxWidth().background(if (index % 2 == 0) HardwoodPalette.surface else HardwoodPalette.surfaceAlt)
                        .padding(horizontal = HardwoodGeo.padCard, vertical = 7.dp),
                ) { MetricBar(metric) }
            }
        }
        Row(
            Modifier.fillMaxWidth().background(HardwoodPalette.surfaceAlt).padding(horizontal = HardwoodGeo.padCard, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("StatScout", style = HardwoodType.bodyBold.copy(fontSize = 16.sp, fontWeight = FontWeight.Black), color = HardwoodPalette.midnight)
            Spacer(Modifier.weight(1f).width(8.dp))
            Text(request.footnote, style = HardwoodType.small, color = HardwoodPalette.inkTertiary, maxLines = 1)
        }
    }
}

/**
 * Draws [request] off screen at a fixed density and font scale (an image has
 * one size; the reader's text setting must not decide it), then hands back the
 * bitmap. The card is recorded into a layer that is never drawn to the screen.
 */
@Composable
fun ShareCardCapture(request: ShareRequest, onCaptured: (ImageBitmap?) -> Unit) {
    val layer = rememberGraphicsLayer()
    Box(Modifier.size(0.dp).wrapContentSize(Alignment.TopStart, unbounded = true)) {
        CompositionLocalProvider(LocalDensity provides Density(PlayerShare.SCALE, 1f)) {
            Box(Modifier.drawWithContent { layer.record { this@drawWithContent.drawContent() } }) {
                PlayerShareCard(request)
            }
        }
    }
    LaunchedEffect(request) {
        // One frame to lay out and record, one more so the recording is complete.
        withFrameNanos { }
        withFrameNanos { }
        onCaptured(runCatching { layer.toImageBitmap() }.getOrNull())
    }
}

/** Writes the card to the app's cache and opens the share sheet with the Play listing link. */
suspend fun shareCard(context: Context, image: ImageBitmap, request: ShareRequest) {
    val name = request.player.name
    val uri = writeSharePng(context, image, PlayerShare.fileName(name, request.seasonLabel))
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "image/png"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_TEXT, PlayerShare.message(name, request.seasonLabel))
        putExtra(Intent.EXTRA_TITLE, "$name ${request.seasonLabel}")
        clipData = ClipData.newRawUri(null, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, null))
}

private suspend fun writeSharePng(context: Context, image: ImageBitmap, fileName: String): Uri = withContext(Dispatchers.IO) {
    val dir = File(context.cacheDir, "share").apply { mkdirs() }
    // Only the card being shared is kept.
    dir.listFiles()?.forEach { it.delete() }
    val file = File(dir, fileName)
    var bitmap = image.asAndroidBitmap()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && bitmap.config == Bitmap.Config.HARDWARE) {
        bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
    }
    file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    FileProvider.getUriForFile(context, "${context.packageName}.share", file)
}
