package com.jackwallner.basketball.model

import java.text.NumberFormat
import java.util.Locale

/**
 * What the data can and cannot say about a season. StatScout carries every
 * season from 2002-03, but the advanced metrics do not all reach that far:
 * ESPN's box score has no plus/minus before 2008-09, the shot feed tracks
 * nearly every attempt only from 2003-04, and On-Off needs a play-by-play
 * replay that reproduces the box plus/minus, which it does only in some
 * seasons. Naming the limit is what keeps the rest of the board credible.
 * Mirrors the constants in `backend/ingest.py`.
 */
object MetricCoverage {
    const val BOX_SCORE_FIRST_SEASON = 2003
    const val ON_COURT_FIRST_SEASON = 2009
    const val SHOT_ZONES_FIRST_SEASON = 2004
    const val ON_OFF_ALWAYS_FIRST_SEASON = 2021
    val onOffRegularSeasons: Set<Int> = setOf(2014, 2015)
    val onOffPostseasons: Set<Int> = setOf(2009, 2010, 2012, 2013, 2014, 2015)

    fun hasOnOff(season: Int, phase: SeasonPhase = SeasonPhase.REGULAR): Boolean {
        if (StatScoutSeason.isAllTime(season)) return false
        if (season >= ON_OFF_ALWAYS_FIRST_SEASON) return true
        return when (phase) {
            SeasonPhase.REGULAR -> season in onOffRegularSeasons
            SeasonPhase.PLAYOFFS -> season in onOffPostseasons
        }
    }

    private fun phaseNoun(phase: SeasonPhase) = if (phase == SeasonPhase.REGULAR) "season" else "postseason"

    /** One short sentence explaining what this season is missing, or null when it has the full set. */
    fun note(season: Int, category: MetricCategory? = null, phase: SeasonPhase = SeasonPhase.REGULAR): String? {
        if (StatScoutSeason.isAllTime(season)) {
            return "Career totals span ${SeasonLabel.display(BOX_SCORE_FIRST_SEASON)} onward. Shot zones count from " +
                "${SeasonLabel.display(SHOT_ZONES_FIRST_SEASON)}, On-Court +/- from ${SeasonLabel.display(ON_COURT_FIRST_SEASON)}, " +
                "and career On-Off is not published."
        }
        if (category == MetricCategory.SHOOTING) {
            return if (season < SHOT_ZONES_FIRST_SEASON) "Shot-zone numbers start in ${SeasonLabel.display(SHOT_ZONES_FIRST_SEASON)}." else null
        }
        if (category == MetricCategory.IMPACT) {
            if (season < ON_COURT_FIRST_SEASON) {
                return "Plus/minus starts in ${SeasonLabel.display(ON_COURT_FIRST_SEASON)}; ESPN's box scores carry none before that."
            }
            return if (hasOnOff(season, phase)) null
            else "On-Off is not published for this ${phaseNoun(phase)}: the replay of the play-by-play did not match the box score closely enough."
        }
        if (category != null) return null
        if (season < SHOT_ZONES_FIRST_SEASON) {
            return "Shot zones start in ${SeasonLabel.display(SHOT_ZONES_FIRST_SEASON)} and plus/minus in ${SeasonLabel.display(ON_COURT_FIRST_SEASON)}."
        }
        if (season < ON_COURT_FIRST_SEASON) {
            return "On-Court +/- and On-Off start later: plus/minus in ${SeasonLabel.display(ON_COURT_FIRST_SEASON)}."
        }
        if (!hasOnOff(season, phase)) {
            return "On-Off is not published for this ${phaseNoun(phase)}: the play-by-play replay did not match the box score closely enough."
        }
        return null
    }

    /** The live season's own gap: a feed that has not caught up with the games already published. */
    fun pendingNote(category: MetricCategory?, shotsStatus: String?, playByPlayStatus: String?): String? {
        fun pending(status: String?): Boolean {
            val s = status?.lowercase() ?: return false
            return s != "ready" && s != "not_applicable" && s != "unavailable"
        }
        val shots = "Shot-zone numbers for the latest games are still arriving"
        val onOff = "On/off numbers for the latest games are still arriving"
        return when (category) {
            MetricCategory.SHOOTING -> if (pending(shotsStatus)) "$shots." else null
            MetricCategory.IMPACT -> if (pending(playByPlayStatus)) "$onOff." else null
            null -> listOfNotNull(if (pending(shotsStatus)) shots else null, if (pending(playByPlayStatus)) onOff else null)
                .joinToString(" ") { "$it." }.ifEmpty { null }
            else -> null
        }
    }

    /** Whether a metric is expected to exist at all in this season: "nobody qualified" versus "not tracked". */
    fun isTracked(label: String, season: Int, phase: SeasonPhase = SeasonPhase.REGULAR): Boolean {
        if (StatScoutSeason.isAllTime(season)) return label != "On-Off"
        return when (label) {
            "Rim Freq", "Rim FG%", "Short Mid Freq", "Short Mid FG%", "Long Mid Freq", "Long Mid FG%",
            "Corner 3%", "Non-Corner 3%", "Assisted FG%" -> season >= SHOT_ZONES_FIRST_SEASON
            "On-Court +/-", "+/-" -> season >= ON_COURT_FIRST_SEASON
            "On-Off" -> hasOnOff(season, phase)
            else -> season >= BOX_SCORE_FIRST_SEASON
        }
    }
}

/**
 * A metric the Trends board can rank by, keyed to the rollup column. The
 * rollup columns are the season metric ids from the contract.
 */
data class TrendMetric(
    val key: String,
    val label: String,
    val unit: String,
    val decimals: Int,
    val lowerIsBetter: Boolean,
    val signed: Boolean = false,
) {
    val id: String get() = key

    /** This metric's then, now and change for one row. */
    data class Values(val then: Double?, val now: Double?, val delta: Double?)

    fun values(form: RecentForm): Values = Values(form.priorMetrics[key], form.metrics[key], form.delta[key])

    fun display(value: Double): String = format(value)

    fun format(value: Double): String {
        var text = if (decimals == 0) NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
        else cFixed(value, decimals)
        if (signed && value > 0) text = "+$text"
        return text + unit
    }

    companion object {
        private fun make(label: String) = TrendMetric(
            key = RecentMetricKey.key(label) ?: label,
            label = label,
            unit = if (RecentMetricKey.isPercent(label)) "%" else "",
            decimals = RecentMetricKey.decimals(label),
            lowerIsBetter = RecentMetricKey.lowerIsBetter(label),
            signed = RecentMetricKey.isSigned(label),
        )

        /** Guards on creation, forwards on scoring efficiency, centers on rim work and the glass. */
        val guardAdvanced = listOf("Pts/100", "TS%", "AST%", "USG%", "TOV%", "AST:TO", "STL%", "On-Off").map(::make)
        val forwardAdvanced = listOf("Pts/100", "TS%", "USG%", "eFG%", "REB%", "STL%", "BLK%", "On-Off").map(::make)
        val centerAdvanced = listOf("REB%", "Rim FG%", "BLK%", "TS%", "Pts/100", "USG%", "OREB%", "On-Off").map(::make)

        /**
         * Per-game averages over the window. No window totals (3PM, +/-): two
         * windows rarely hold the same number of games.
         */
        val standard = listOf("PPG", "RPG", "APG", "SPG", "BPG", "FG%", "3P%", "FT%", "TOV/G", "MPG").map(::make)

        fun advanced(side: TrendSide): List<TrendMetric> = when (side) {
            TrendSide.GUARD -> guardAdvanced
            TrendSide.FORWARD -> forwardAdvanced
            TrendSide.CENTER -> centerAdvanced
        }

        @Suppress("UNUSED_PARAMETER")
        fun standard(side: TrendSide): List<TrendMetric> = standard

        fun list(side: TrendSide, mode: TrendStatMode): List<TrendMetric> =
            if (mode == TrendStatMode.ADVANCED) advanced(side) else standard(side)
    }
}

enum class TrendStatMode(val label: String) { ADVANCED("Advanced"), STANDARD("Standard") }

/** Which position cohort the Trends board ranks; a center's rebound rate is not a guard's. */
enum class TrendSide(val label: String, val playerType: String) {
    GUARD("Guards", "g"),
    FORWARD("Forwards", "f"),
    CENTER("Centers", "c");

    /** Compact label for the equal-width position tabs. */
    val shortLabel: String get() = playerType.uppercase()

    val positionGroup: PlayerPositionGroup
        get() = when (this) {
            GUARD -> PlayerPositionGroup.GUARD
            FORWARD -> PlayerPositionGroup.FORWARD
            CENTER -> PlayerPositionGroup.CENTER
        }

    val hasAdvancedMetrics: Boolean get() = TrendMetric.advanced(this).isNotEmpty()
}
