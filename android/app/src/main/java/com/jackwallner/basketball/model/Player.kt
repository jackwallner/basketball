package com.jackwallner.basketball.model

import java.text.NumberFormat
import java.time.Instant
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.serialization.json.JsonObject

data class Player(
    val playerId: Int,
    val name: String,
    val team: String,
    val position: String,
    val handedness: String,
    val updatedAt: Instant,
    val season: Int?,
    val seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    val playerType: String? = null,
    val source: String? = null,
    val metrics: List<Metric>,
    val standardStats: List<StandardStat>?,
    val games: List<GameTrend> = emptyList(),
) {
    val id: String get() = "$playerId-${season ?: 0}-${seasonPhase.raw}"

    /** Metrics that carry a real rank. See [Metric.isUnranked]. */
    val rankedMetrics: List<Metric> get() = metrics.filter { !it.isUnranked }

    /** Ranked metrics where higher means better: the shot-profile stats say how he plays, so they stay out of any grade. */
    val gradedMetrics: List<Metric> get() = rankedMetrics.filter { !it.isShotProfile }

    val overallPercentile: Int
        get() {
            val metrics = gradedMetrics
            if (metrics.isEmpty()) return 0
            // A rim protector's scoring bars shouldn't drag down his defense: the
            // headline number is the best category average.
            val categories = metrics.map { it.category }.toSet()
            if (categories.size > 1) {
                val best = metrics.groupBy { it.category }.values
                    .maxOf { group -> group.sumOf { it.percentile }.toDouble() / group.size }
                return swiftRound(best)
            }
            return swiftRound(metrics.sumOf { it.percentile }.toDouble() / metrics.size)
        }

    val headlineMetric: Metric? get() = gradedMetrics.sortedByDescending { it.percentile }.firstOrNull()

    val latestGame: GameTrend? get() = games.maxByOrNull { it.date }

    val shareSummary: String
        get() {
            val headline = headlineMetric?.let { metric ->
                val valueText = if (metric.value.isEmpty()) "${metric.percentile.ordinal} percentile"
                else "${metric.value}, ${metric.percentile.ordinal} percentile"
                "${metric.label} $valueText"
            } ?: "${overallPercentile.ordinal} overall percentile"
            return "$name · $team $displayPosition\nOverall: ${overallPercentile.ordinal} percentile\nTop stat: $headline\nHardwood StatScout"
        }

    fun percentile(category: MetricCategory): Int? {
        val categoryMetrics = gradedMetrics.filter { it.category == category }
        if (categoryMetrics.isEmpty()) return null
        return swiftRound(categoryMetrics.sumOf { it.percentile }.toDouble() / categoryMetrics.size)
    }

    /**
     * Every player type (g, f, c, unknown) is eligible for every category: a
     * center is still a scorer and a guard still rebounds.
     */
    @Suppress("UNUSED_PARAMETER")
    fun matchesPlayerType(category: MetricCategory?): Boolean = true

    /** The category a player is strongest in, by average ranked percentile. */
    val primaryCategory: MetricCategory
        get() = rankedMetrics.groupBy { it.category }
            .maxByOrNull { (_, group) -> group.sumOf { it.percentile }.toDouble() / group.size }?.key
            ?: MetricCategory.SCORING

    /**
     * Position to surface in the UI. When the box score left it blank but the
     * player has metrics, fall back to the player-type label so a blank never
     * sits next to real stats.
     */
    val displayPosition: String
        get() {
            val trimmed = position.trim().uppercase()
            if (trimmed.isNotEmpty() && trimmed != "TBD" && trimmed != "\u2014" && trimmed != "-") return position
            val type = playerType?.uppercase() ?: return ""
            return if (type == "UNKNOWN") "" else type
        }

    val initials: String
        get() {
            val parts = name.split(" ").filter { it.isNotEmpty() }
            val first = parts.firstOrNull() ?: return ""
            if (parts.size == 1) return first.take(1)
            val last = parts.last()
            val suffix = last.trim { !it.isLetterOrDigit() }.uppercase()
            if (suffix in SUFFIXES && parts.size > 2) {
                return first.take(1) + parts[parts.size - 2].take(1)
            }
            return first.take(1) + last.take(1)
        }

    /** "Jackson" for "Jaren Jackson Jr.": the surname, skipping a suffix. */
    val lastName: String
        get() {
            val parts = name.split(" ").filter { it.isNotEmpty() }
            if (parts.size <= 1) return name
            val last = parts.last()
            val suffix = last.trim { !it.isLetterOrDigit() }.uppercase()
            if (suffix in SUFFIXES && parts.size > 2) return parts[parts.size - 2]
            return last
        }

    /**
     * The cohort the feed ranked this player in. A handful of box scores carry
     * no position; those fold into forwards, the likeliest home for a role-less player.
     */
    val positionGroup: PlayerPositionGroup
        get() = when (playerType?.lowercase()) {
            "g" -> PlayerPositionGroup.GUARD
            "f" -> PlayerPositionGroup.FORWARD
            "c" -> PlayerPositionGroup.CENTER
            else -> when (displayPosition.uppercase()) {
                "G", "PG", "SG" -> PlayerPositionGroup.GUARD
                "C" -> PlayerPositionGroup.CENTER
                else -> PlayerPositionGroup.FORWARD
            }
        }

    /** The volume a category's rates were measured over: "1,820 min". Null when the line has none. */
    @Suppress("UNUSED_PARAMETER")
    fun volumeCaption(category: MetricCategory): String? =
        MetricWeight.MINUTES.value(this)?.let { "${NumberFormat.getIntegerInstance(Locale.US).format(it.toLong())} min" }

    /** Season minutes: the regulars before the two-way call-ups. */
    val minutesPlayed: Double get() = MetricWeight.MINUTES.value(this) ?: 0.0

    /** The line every fan quotes first: "27.7 PTS · 12.9 REB · 10.7 AST". Null when the season carries none. */
    val perGameSlashLine: String?
        get() {
            val parts = listOf("PPG" to "PTS", "RPG" to "REB", "APG" to "AST").mapNotNull { (label, short) ->
                val value = metrics.firstOrNull { it.label == label }?.value
                if (value.isNullOrEmpty()) null else "$value $short"
            }
            return if (parts.isEmpty()) null else parts.joinToString(" · ")
        }

    fun metrics(kind: MetricKind): List<Metric> =
        BasketballMetricRegistry.sorted(metrics.filter { BasketballMetricRegistry.kind(it) == kind })

    fun preferredHeadlineMetric(kind: MetricKind): Metric? {
        val candidates = metrics(kind)
        val preferred = if (kind == MetricKind.ADVANCED) positionGroup.preferredAdvancedMetrics else positionGroup.preferredTraditionalMetrics
        for (label in preferred) candidates.firstOrNull { it.label == label }?.let { return it }
        return candidates.firstOrNull()
    }

    companion object {
        private val SUFFIXES = setOf("JR", "SR", "II", "III", "IV", "V")

        /** Column headings for two players side by side: surnames, or full names when the surnames match. */
        fun columnNames(a: Player, b: Player): Pair<String, String> =
            if (a.lastName == b.lastName && a.name != b.name) a.name to b.name else a.lastName to b.lastName
        private val labelPool = HashMap<String, String>()

        /** Labels repeat across thousands of rows; share one copy of each. */
        @Synchronized
        internal fun intern(value: String): String = labelPool.getOrPut(value) { value }

        /**
         * Mirrors `Player.init(from:)`: required id/name/team/position/handedness/
         * updated_at/metrics; one undecodable metric fails the row, as on iOS.
         */
        fun fromJson(o: JsonObject): Player {
            val metrics = o.array("metrics") ?: throw RowDecodeException("missing metrics")
            val updated = o.requireString("updated_at")
            return Player(
                playerId = o.requireInt("id"),
                name = o.requireString("name"),
                team = intern(o.requireString("team")),
                position = intern(o.requireString("position")),
                handedness = intern(o.requireString("handedness")),
                updatedAt = parseDate(updated) ?: throw RowDecodeException("bad updated_at"),
                season = o.int("season"),
                seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad season_type") }
                    ?: SeasonPhase.REGULAR,
                playerType = o.string("player_type")?.let(::intern),
                source = o.string("source")?.let(::intern),
                metrics = metrics.map { Metric.fromJson(it as? JsonObject ?: throw RowDecodeException("bad metric")) },
                standardStats = o.array("standard_stats")?.map {
                    StandardStat.fromJson(it as? JsonObject ?: throw RowDecodeException("bad stat"))
                },
                games = o.array("games")?.map { GameTrend.fromJson(it as? JsonObject ?: throw RowDecodeException("bad game")) }
                    ?: emptyList(),
            )
        }
    }
}

/** Swift's `round` (half away from zero) on a non-negative mean. */
internal fun swiftRound(value: Double): Int = swiftRoundDouble(value).toInt()

/** C `printf("%.Nf")`: rounds the exact binary value (0.155 prints 0.15), where Java's `String.format` rounds the shortest decimal (0.16). */
internal fun cFixed(value: Double, decimals: Int): String =
    java.math.BigDecimal(value).setScale(decimals, java.math.RoundingMode.HALF_EVEN).toPlainString()

/** Swift's `.rounded()`: half away from zero (Java's `Math.round` rounds -0.5 up). */
internal fun swiftRoundDouble(value: Double): Double = if (value < 0) -Math.floor(-value + 0.5) else Math.floor(value + 0.5)

enum class SeasonPhase(val raw: String) {
    REGULAR("REG"),
    PLAYOFFS("POST");

    /** One name everywhere: "Regular Season", never the bare adjective. */
    val label: String get() = if (this == REGULAR) "Regular Season" else "Playoffs"

    companion object {
        fun from(raw: String): SeasonPhase? = entries.firstOrNull { it.raw == raw }
    }
}

data class Metric(
    val label: String,
    val value: String,
    val percentile: Int,
    val category: MetricCategory,
    /** Live season only: whether the player clears the prorated bar. Null means it qualified. */
    val qualified: Boolean? = null,
    /** False for counting stats built outside the registry, so a zero there is unranked too. */
    val rankable: Boolean? = null,
    val id: String = derivedId(category, label),
) {
    /**
     * Describes a player's shot diet rather than grading it: where his shots
     * come from and how many are assisted. A style, not an achievement, so
     * these draw in a neutral colour and stay out of any grade.
     */
    val isShotProfile: Boolean get() = label in SHOT_PROFILE_LABELS

    /**
     * A traditional counting stat at zero (0 blocks, 0 3PM). The feed ranks the
     * tie's midpoint, so most of the league read 47th percentile at something
     * they had never done. The value shows; the rank is left out.
     */
    val isUnranked: Boolean
        get() {
            if (rankable == false) return true
            val definition = BasketballMetricRegistry.definition(label, category) ?: return false
            if (definition.kind != MetricKind.TRADITIONAL) return false
            if (BasketballMetricRegistry.aggregation(label, category) != MetricAggregation.Sum) return false
            val number = metricNumericValue(value) ?: return false
            return number == 0.0
        }

    /** Below the prorated playing-time bar for this metric. */
    val isSmallSample: Boolean get() = qualified == false

    companion object {
        val SHOT_PROFILE_LABELS = setOf("3PT Rate", "Rim Freq", "Short Mid Freq", "Long Mid Freq", "Assisted FG%")

        /** The bundle leaves the id out; it is fully determined by category and label. */
        fun derivedId(category: MetricCategory, label: String): String =
            category.raw.lowercase().replace(" ", "-") + "-" + label

        fun fromJson(o: JsonObject): Metric {
            val category = MetricCategory.from(o.requireString("category")) ?: throw RowDecodeException("bad category")
            return Metric(
                label = Player.intern(o.requireString("label")),
                value = o.requireString("value").let { if (it.length <= 6) Player.intern(it) else it },
                percentile = o.requireInt("percentile"),
                category = category,
                qualified = o.bool("qualified"),
                rankable = o.bool("rankable"),
                id = o.string("id") ?: Player.intern(derivedId(category, o.requireString("label"))),
            )
        }
    }
}

data class StandardStat(val label: String, val value: String, val id: String = "std-$label") {
    companion object {
        fun fromJson(o: JsonObject) = StandardStat(
            label = Player.intern(o.requireString("label")),
            value = o.requireString("value").let { if (it.length <= 6) Player.intern(it) else it },
            id = o.string("id") ?: Player.intern("std-${o.requireString("label")}"),
        )
    }
}

data class GameTrend(
    val id: String,
    val date: Instant,
    val opponent: String,
    val summary: String,
    val percentileDelta: Int,
    val keyMetric: String,
) {
    companion object {
        fun fromJson(o: JsonObject) = GameTrend(
            id = o.requireString("id"),
            date = parseDate(o.requireString("date")) ?: throw RowDecodeException("bad date"),
            opponent = o.requireString("opponent"),
            summary = o.requireString("summary"),
            percentileDelta = o.requireInt("percentile_delta"),
            keyMetric = o.requireString("key_metric"),
        )
    }
}

/**
 * Shared meaning for `standard_stats` values. Field goals, threes and free
 * throws are display-ready made/attempted pairs ("612/1,250") and rank by
 * percentage; turnovers and fouls are the two lines where less is better.
 */
object StandardStatSemantics {
    enum class Winner { LEFT, RIGHT }

    fun numericValue(label: String, value: String): Double? = when (label.uppercase()) {
        "FG", "3P", "FT" -> {
            val parts = value.split("/", limit = 2)
            if (parts.size != 2) null
            else {
                val made = metricNumericValue(parts[0])
                val attempted = metricNumericValue(parts[1])
                if (made == null || attempted == null || attempted <= 0) null else made / attempted * 100
            }
        }
        else -> metricNumericValue(value)
    }

    fun higherIsBetter(label: String): Boolean {
        val key = label.uppercase()
        return key != "TOV" && key != "PF"
    }

    /** Midpoint rank against every peer carrying the same stat. */
    fun percentile(label: String, value: String, peerValues: List<String>): Int {
        val current = numericValue(label, value) ?: return 50
        var values = peerValues.mapNotNull { numericValue(label, it) }
        if (values.isEmpty()) values = listOf(current)
        val below = values.count { it < current }
        val equal = values.count { it == current }
        val raw = (below + equal / 2.0) / values.size * 100
        val oriented = if (higherIsBetter(label)) raw else 100 - raw
        return swiftRound(oriented).coerceIn(1, 100)
    }

    fun winner(label: String, left: String?, right: String?): Winner? {
        val l = left?.let { numericValue(label, it) } ?: return null
        val r = right?.let { numericValue(label, it) } ?: return null
        if (l == r) return null
        val leftWins = if (higherIsBetter(label)) l > r else l < r
        return if (leftWins) Winner.LEFT else Winner.RIGHT
    }
}

/**
 * The leading number in a formatted feed value: "6.2%" -> 6.2, "3,322" -> 3322,
 * "+2.3" -> 2.3. Matches Foundation's `Scanner.scanDouble` on these inputs.
 */
fun metricNumericValue(value: String): Double? {
    var s = value.trim().replace(",", "")
    if (s.startsWith(".")) s = "0$s"
    if (s.startsWith("-.")) s = "-0" + s.drop(1)
    val match = NUMBER_PREFIX.find(s) ?: return null
    return match.value.toDoubleOrNull()
}

/**
 * Shared ranks for ties (1, 2, 2, 4), the way a stat sheet prints them: two
 * guards on 25.1 PPG are not 21st and 22nd. [values] is in display
 * order; a null never ties.
 */
fun competitionRanks(values: List<Double?>): List<Int> {
    val ranks = ArrayList<Int>(values.size)
    for (index in values.indices) {
        if (index > 0 && values[index] != null && values[index] == values[index - 1]) ranks += ranks[index - 1]
        else ranks += index + 1
    }
    return ranks
}

/** A player's value for one metric, as a number, for ranking. */
fun metricValue(player: Player, label: String, category: MetricCategory): Double? =
    player.metrics.firstOrNull { it.label == label && it.category == category }?.let { metricNumericValue(it.value) }

private val NUMBER_PREFIX = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?")

/**
 * The display shape of a metric value, inferred from the feed's own strings so
 * an aggregate of "6.2%" renders as a percentage with the same precision.
 */
data class MetricValueFormat(
    val decimals: Int = 0,
    val isPercent: Boolean = false,
    val isSigned: Boolean = false,
    val hasGrouping: Boolean = false,
) {
    fun string(value: Double): String {
        var text = when {
            decimals == 0 && hasGrouping -> NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
            decimals == 0 -> swiftRoundDouble(value).toLong().toString()
            else -> cFixed(value, decimals)
        }
        if (isSigned && value > 0) text = "+$text"
        if (isPercent) text += "%"
        return text
    }

    companion object {
        fun inferred(samples: List<String>): MetricValueFormat {
            var format = MetricValueFormat()
            for (sample in samples) {
                val trimmed = sample.trim()
                if (trimmed.endsWith("%")) format = format.copy(isPercent = true)
                if (trimmed.startsWith("+")) format = format.copy(isSigned = true)
                if (trimmed.contains(",")) format = format.copy(hasGrouping = true)
                val dot = trimmed.indexOf('.')
                val digits = if (dot < 0) 0 else trimmed.substring(dot + 1).takeWhile { it.isDigit() }.length
                format = format.copy(decimals = maxOf(format.decimals, digits))
            }
            return format
        }
    }
}

enum class MetricCategory(val raw: String) {
    SCORING("Scoring"),
    SHOOTING("Shooting"),
    PLAYMAKING("Playmaking"),
    REBOUNDING("Rebounding"),
    DEFENSE("Defense"),
    IMPACT("Impact");

    /** Label for segmented controls and chips: the category names are already short. */
    val shortLabel: String get() = raw

    /** Registry-driven display order: advanced first, then traditional. */
    val metricPriorityOrder: List<String>
        get() = BasketballMetricRegistry.definitions.filter { it.category == this }.sortedBy { it.priority }.map { it.label }

    fun sortMetrics(a: String, b: String): Boolean {
        val order = metricPriorityOrder
        val ia = order.indexOf(a).let { if (it < 0) order.size else it }
        val ib = order.indexOf(b).let { if (it < 0) order.size else it }
        return ia < ib
    }

    companion object {
        fun from(raw: String): MetricCategory? = entries.firstOrNull { it.raw.equals(raw, ignoreCase = true) }
    }
}

/**
 * The position cohort a board is drawn for. [ALL] is a view over the whole
 * league; the other three are the cohorts the feed ranks percentiles inside
 * (the Cleaning the Glass convention), so a center's rebounding is judged
 * against centers.
 */
enum class PlayerPositionGroup(val raw: String) {
    ALL("All"), GUARD("G"), FORWARD("F"), CENTER("C");

    val cohortDescription: String
        get() = when (this) {
            ALL -> "Among every player"
            GUARD -> "Among guards"
            FORWARD -> "Among forwards"
            CENTER -> "Among centers"
        }

    /** Singular noun for captions: "every guard with a line this season". */
    val noun: String
        get() = when (this) {
            ALL -> "player"
            GUARD -> "guard"
            FORWARD -> "forward"
            CENTER -> "center"
        }

    /** "Guards", "Forwards", "Centers", "All". */
    val displayName: String get() = if (this == ALL) "All" else noun.replaceFirstChar { it.uppercase() } + "s"

    fun includes(player: Player): Boolean = this == ALL || player.positionGroup == this

    /** The `player_type` the feed ranks this cohort under. */
    val playerType: String?
        get() = when (this) {
            ALL -> null
            GUARD -> "g"
            FORWARD -> "f"
            CENTER -> "c"
        }

    /**
     * Every board opens on On-Off, the one number that counts offense and
     * defense together (the Cleaning the Glass headline). Seasons without the
     * replay fall back to On-Court +/-, and pre-2009 seasons to the cohort's own lead stat.
     */
    val preferredAdvancedMetrics: List<String>
        get() {
            val impact = listOf("On-Off", "On-Court +/-")
            return impact + when (this) {
                ALL -> listOf("Pts/100", "TS%", "USG%")
                GUARD -> listOf("AST%", "TS%", "USG%")
                FORWARD -> listOf("Pts/100", "TS%", "USG%")
                CENTER -> listOf("REB%", "Rim FG%", "BLK%")
            }
        }

    val preferredTraditionalMetrics: List<String>
        get() = when (this) {
            ALL -> listOf("PPG", "RPG", "APG")
            GUARD -> listOf("APG", "PPG", "SPG")
            FORWARD -> listOf("PPG", "RPG", "3PM")
            CENTER -> listOf("RPG", "BPG", "FG%")
        }

    companion object {
        /** The three real cohorts, without the [ALL] view. */
        val cohorts: List<PlayerPositionGroup> = listOf(GUARD, FORWARD, CENTER)
    }
}

enum class MetricKind(val label: String) { ADVANCED("Advanced"), TRADITIONAL("Standard") }

enum class MetricFamily(val label: String) {
    EFFICIENCY("Efficiency"), USAGE("Usage"), SHOOTING("Shooting"), FREQUENCY("Frequency"), ACCURACY("Accuracy"),
    PLAYMAKING("Playmaking"), TURNOVERS("Turnovers"), REBOUNDING("Rebounding"), RIM_PROTECTION("Rim Protection"),
    STEALS("Steals"), IMPACT("Impact"), PLAYING_TIME("Playing Time"), PRODUCTION("Production"),
}

data class MetricDefinition(
    val label: String,
    val category: MetricCategory,
    val kind: MetricKind,
    val family: MetricFamily,
    val positions: Set<PlayerPositionGroup>,
    val higherIsBetter: Boolean,
    val priority: Int,
    val description: String,
)

/** How several players' values for one metric collapse into one number. */
sealed interface MetricAggregation {
    data object Sum : MetricAggregation
    data class Weighted(val weight: MetricWeight) : MetricAggregation
}

/** The denominator a rate was computed against, read off the standard line. */
enum class MetricWeight {
    MINUTES, GAMES;

    /** Null when the player has no volume, which drops him from a weighted mean. */
    fun value(player: Player): Double? = when (this) {
        MINUTES -> plain("MIN", player)
        GAMES -> plain("G", player)
    }

    private fun plain(label: String, player: Player): Double? {
        val raw = player.standardStats?.firstOrNull { it.label == label }?.value ?: return null
        return metricNumericValue(raw)?.takeIf { it > 0 }
    }
}

/** Last name for a narrow column header, without a generational suffix. */
val Player.surname: String get() = lastName

/**
 * Mirrors the metric table in `handoff/NBA_CONTRACT.md` label for label. The
 * backend writes these exact strings into `metrics[].label`.
 */
object BasketballMetricRegistry {
    private val ALL_COHORTS = setOf(PlayerPositionGroup.GUARD, PlayerPositionGroup.FORWARD, PlayerPositionGroup.CENTER)

    private fun d(
        label: String, category: MetricCategory, kind: MetricKind, family: MetricFamily,
        priority: Int, description: String, higherIsBetter: Boolean = true,
    ) = MetricDefinition(label, category, kind, family, ALL_COHORTS, higherIsBetter, priority, description)

    private val SC = MetricCategory.SCORING
    private val SH = MetricCategory.SHOOTING
    private val PM = MetricCategory.PLAYMAKING
    private val RB = MetricCategory.REBOUNDING
    private val DF = MetricCategory.DEFENSE
    private val IM = MetricCategory.IMPACT
    private val A = MetricKind.ADVANCED
    private val T = MetricKind.TRADITIONAL

    val definitions: List<MetricDefinition> = listOf(
        // Scoring
        d("Pts/100", SC, A, MetricFamily.PRODUCTION, 10, "Points scored per 100 team possessions while he is on the floor."),
        d("USG%", SC, A, MetricFamily.USAGE, 20, "Share of his team's possessions he ends with a shot, a free throw trip or a turnover while on the floor."),
        d("TS%", SC, A, MetricFamily.EFFICIENCY, 30, "Points per shooting possession, counting threes and free throws: points divided by twice his field goal attempts plus 0.44 free throw attempts."),
        d("eFG%", SC, A, MetricFamily.EFFICIENCY, 40, "Field goal percentage that gives a three-pointer its extra half a point."),
        d("FT Rate", SC, A, MetricFamily.FREQUENCY, 50, "Free throw attempts per field goal attempt."),
        d("3PT Rate", SC, A, MetricFamily.FREQUENCY, 60, "Share of his field goal attempts that are three-pointers."),
        d("PPG", SC, T, MetricFamily.PRODUCTION, 110, "Points per game."),
        d("FG%", SC, T, MetricFamily.ACCURACY, 120, "Field goals made divided by field goals attempted."),
        d("3P%", SC, T, MetricFamily.ACCURACY, 130, "Three-pointers made divided by attempted. Needs at least 50 attempts (prorated early in a season) to be ranked."),
        d("FT%", SC, T, MetricFamily.ACCURACY, 140, "Free throws made divided by attempted. Needs at least 50 attempts (prorated early in a season) to be ranked."),
        d("3PM", SC, T, MetricFamily.PRODUCTION, 150, "Total three-pointers made."),

        // Shooting: where the shots come from and how often they go in.
        d("Rim Freq", SH, A, MetricFamily.FREQUENCY, 10, "Share of his field goal attempts taken within four feet of the basket."),
        d("Rim FG%", SH, A, MetricFamily.ACCURACY, 20, "Field goal percentage on shots within four feet of the basket. Needs at least 40 rim attempts."),
        d("Short Mid Freq", SH, A, MetricFamily.FREQUENCY, 30, "Share of his field goal attempts from four to fourteen feet that are not threes."),
        d("Short Mid FG%", SH, A, MetricFamily.ACCURACY, 40, "Field goal percentage on two-point shots from four to fourteen feet. Needs at least 40 attempts."),
        d("Long Mid Freq", SH, A, MetricFamily.FREQUENCY, 50, "Share of his field goal attempts from fourteen feet out to the three-point line."),
        d("Long Mid FG%", SH, A, MetricFamily.ACCURACY, 60, "Field goal percentage on two-point shots from fourteen feet out. Needs at least 40 attempts."),
        d("Corner 3%", SH, A, MetricFamily.ACCURACY, 70, "Three-point percentage from the corners, the shortest three on the floor. Needs at least 30 attempts."),
        d("Non-Corner 3%", SH, A, MetricFamily.ACCURACY, 80, "Three-point percentage from the wings and the top of the arc. Needs at least 50 attempts."),
        d("Assisted FG%", SH, A, MetricFamily.SHOOTING, 90, "Share of his made field goals that a teammate assisted. A lower number means more self-created shots."),

        // Playmaking
        d("AST%", PM, A, MetricFamily.PLAYMAKING, 10, "Share of his teammates' made field goals he assisted while on the floor."),
        d("AST/100", PM, A, MetricFamily.PLAYMAKING, 20, "Assists per 100 team possessions while he is on the floor."),
        d("TOV%", PM, A, MetricFamily.TURNOVERS, 30, "Turnovers per 100 of his shooting and turnover possessions. Lower is better.", higherIsBetter = false),
        d("AST:TO", PM, A, MetricFamily.PLAYMAKING, 40, "Assists for every turnover."),
        d("AST:USG", PM, A, MetricFamily.PLAYMAKING, 50, "Assist percentage divided by usage: how much he creates for others relative to how much he uses."),
        d("APG", PM, T, MetricFamily.PLAYMAKING, 110, "Assists per game."),
        d("AST", PM, T, MetricFamily.PRODUCTION, 120, "Total assists."),
        d("TOV/G", PM, T, MetricFamily.TURNOVERS, 130, "Turnovers per game. Lower is better.", higherIsBetter = false),

        // Rebounding
        d("OREB%", RB, A, MetricFamily.REBOUNDING, 10, "Share of the available offensive rebounds he grabs while on the floor."),
        d("DREB%", RB, A, MetricFamily.REBOUNDING, 20, "Share of the available defensive rebounds he grabs while on the floor."),
        d("REB%", RB, A, MetricFamily.REBOUNDING, 30, "Share of all available rebounds he grabs while on the floor."),
        d("RPG", RB, T, MetricFamily.REBOUNDING, 110, "Rebounds per game."),
        d("OREB", RB, T, MetricFamily.PRODUCTION, 120, "Total offensive rebounds."),
        d("DREB", RB, T, MetricFamily.PRODUCTION, 130, "Total defensive rebounds."),

        // Defense
        d("STL%", DF, A, MetricFamily.STEALS, 10, "Share of opponent possessions that end in his steal while he is on the floor."),
        d("BLK%", DF, A, MetricFamily.RIM_PROTECTION, 20, "Share of opponent two-point attempts he blocks while on the floor."),
        d("Stocks/100", DF, A, MetricFamily.PRODUCTION, 30, "Steals plus blocks per 100 team possessions while he is on the floor."),
        d("Fouls/100", DF, A, MetricFamily.PRODUCTION, 40, "Personal fouls per 100 team possessions while he is on the floor. Lower is better.", higherIsBetter = false),
        d("SPG", DF, T, MetricFamily.STEALS, 110, "Steals per game."),
        d("BPG", DF, T, MetricFamily.RIM_PROTECTION, 120, "Blocks per game."),
        d("STL", DF, T, MetricFamily.STEALS, 130, "Total steals."),
        d("BLK", DF, T, MetricFamily.RIM_PROTECTION, 140, "Total blocks."),

        // Impact
        d("On-Court +/-", IM, A, MetricFamily.IMPACT, 10, "Points the team outscores opponents by per 100 possessions while he is on the floor."),
        d("On-Off", IM, A, MetricFamily.IMPACT, 20, "The team's net rating with him on the floor minus its net rating with him on the bench, per 100 possessions."),
        d("Min%", IM, A, MetricFamily.PLAYING_TIME, 30, "Share of his team's available minutes he plays."),
        d("MPG", IM, T, MetricFamily.PLAYING_TIME, 110, "Minutes per game."),
        d("GS", IM, T, MetricFamily.PLAYING_TIME, 120, "Games started."),
        d("+/-", IM, T, MetricFamily.IMPACT, 130, "Total plus/minus: the team's scoring margin while he is on the floor, summed over the season."),
    )

    private val byKey: Map<Pair<String, MetricCategory>, MetricDefinition> =
        definitions.associateBy { it.label to it.category }

    fun definition(label: String, category: MetricCategory): MetricDefinition? = byKey[label to category]

    private val SUMS = setOf(
        SC to "PPG", SC to "3PM",
        PM to "APG", PM to "AST", PM to "TOV/G",
        RB to "RPG", RB to "OREB", RB to "DREB",
        DF to "SPG", DF to "BPG", DF to "STL", DF to "BLK",
        IM to "GS", IM to "+/-",
    )

    /**
     * Counting stats and per-game lines add up (a roster's PPG is the team's
     * scoring); minutes per game weights by games; every other metric is a
     * rate over the minutes he was on the floor.
     */
    fun aggregation(label: String, category: MetricCategory): MetricAggregation = when {
        (category to label) in SUMS -> MetricAggregation.Sum
        category == IM && label == "MPG" -> MetricAggregation.Weighted(MetricWeight.GAMES)
        else -> MetricAggregation.Weighted(MetricWeight.MINUTES)
    }

    fun kind(metric: Metric): MetricKind = definition(metric.label, metric.category)?.kind ?: MetricKind.ADVANCED

    fun isSupported(metric: Metric, position: PlayerPositionGroup): Boolean =
        position == PlayerPositionGroup.ALL || (definition(metric.label, metric.category)?.positions?.contains(position) ?: true)

    fun sorted(metrics: List<Metric>): List<Metric> = metrics.sortedWith { lhs, rhs ->
        val left = definition(lhs.label, lhs.category)?.priority ?: Int.MAX_VALUE
        val right = definition(rhs.label, rhs.category)?.priority ?: Int.MAX_VALUE
        if (left == right) lhs.label.compareTo(rhs.label) else left.compareTo(right)
    }
}

data class TeamRoute(val abbr: String)

/** "1st", "22nd", "113th". */
val Int.ordinal: String
    get() {
        val mod100 = this % 100
        val suffix = if (mod100 in 11..13) "th" else when (this % 10) {
            1 -> "st"
            2 -> "nd"
            3 -> "rd"
            else -> "th"
        }
        return "$this$suffix"
    }

internal fun Double.roundToIntSafe(): Int = if (isNaN()) 0 else roundToInt()
