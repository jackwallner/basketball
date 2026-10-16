package com.jackwallner.basketball.model

import java.text.NumberFormat
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/** One player's line in one game (one row per player_type). Powers the box score on a game page. */
data class PlayerGameLog(
    val playerId: Int,
    val season: Int,
    val seasonPhase: SeasonPhase,
    /** ESPN game id as text, e.g. "401859967". The join key to [Game]. */
    val gameId: String? = null,
    val gameDate: Instant,
    val playerType: String,
    val team: String?,
    val opponent: String?,
    /** Possessions used: field goal attempts + 0.44 free throw attempts + turnovers. */
    val plays: Int,
    /** Minutes played. */
    val touches: Int,
    /** JSONB of nullable numbers; nulls are dropped. */
    val metrics: Map<String, Double>,
) {
    companion object {
        fun fromJson(o: JsonObject) = PlayerGameLog(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
            gameId = o.string("game_id"),
            gameDate = parseDay(o.requireString("game_date")) ?: throw RowDecodeException("bad game_date"),
            playerType = o.requireString("player_type"),
            team = o.string("team"),
            opponent = o.string("opponent"),
            plays = o.int("plays") ?: 0,
            touches = o.int("touches") ?: 0,
            metrics = o.numberMap("metrics"),
        )
    }
}

/**
 * One player's league-anchored weekly window from `player_recent_form`: the
 * current window, the equal-length window before it, and the change.
 */
data class RecentForm(
    val playerId: Int,
    val season: Int,
    val seasonPhase: SeasonPhase,
    val playerType: String,
    val windowWeeks: Int,
    /** Date of the last game in the window, so the UI says "through Feb 8". */
    val asOf: Instant?,
    val startWeek: Int?,
    val endWeek: Int?,
    val team: String?,
    val games: Int,
    /** Possessions used in the window. */
    val plays: Int,
    /** Minutes played in the window. */
    val touches: Int,
    val metrics: Map<String, Double>,
    val priorMetrics: Map<String, Double>,
    val delta: Map<String, Double>,
) {
    val id: String get() = "$playerId-${seasonPhase.raw}-$playerType-$windowWeeks"

    val minutes: Int get() = touches

    /** "1 wk", "2 wk" or "4 wk". */
    val windowLabel: String get() = RecentWindow.of(windowWeeks)?.segmentLabel ?: "$windowWeeks wk"

    /** Dates covered, e.g. "Feb 2 - Feb 8", in Eastern time like every game date. */
    fun weekRangeLabel(notBefore: Instant? = null): String? {
        val asOf = asOf ?: return null
        var start = asOf.atZone(EASTERN).minusDays(windowWeeks * 7L - 1).toInstant()
        if (notBefore != null && notBefore > start && notBefore <= asOf) start = notBefore
        val style = DateTimeFormatter.ofPattern("MMM d", Locale.US)
        return "${style.format(start.atZone(EASTERN))} - ${style.format(asOf.atZone(EASTERN))}"
    }

    /** Small samples make wild deltas. The floor is games and minutes, the two things every role shares. */
    val isSmallSample: Boolean get() = isSmallSample(2)

    fun isSmallSample(minimumGames: Int): Boolean = games < minimumGames || touches < MINIMUM_MINUTES

    companion object {
        /** About two full games of floor time. */
        const val MINIMUM_MINUTES = 60

        fun fromJson(o: JsonObject) = RecentForm(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
            playerType = o.requireString("player_type"),
            windowWeeks = o.int("window_weeks") ?: o.requireInt("window_games"),
            // A Postgres date: Eastern midnight, like every other game date.
            asOf = o.string("as_of")?.let { parseDay(it, EASTERN) },
            startWeek = o.int("start_week"),
            endWeek = o.int("end_week"),
            team = o.string("team"),
            games = o.int("games") ?: 0,
            plays = o.int("plays") ?: 0,
            touches = o.int("touches") ?: 0,
            metrics = o.numberMap("metrics"),
            priorMetrics = o.numberMap("prior_metrics"),
            delta = o.numberMap("delta"),
        )
    }
}

/**
 * Season metric label to the rolling rollup's column, plus the one formatter
 * for a window value. The rollup keys are the contract's season metric ids.
 */
object RecentMetricKey {
    private val keys = mapOf(
        // Scoring
        "Pts/100" to "pts_per_100", "USG%" to "usg_pct", "TS%" to "ts_pct", "eFG%" to "efg_pct",
        "FT Rate" to "ftr", "3PT Rate" to "three_par", "PPG" to "ppg", "FG%" to "fg_pct",
        "3P%" to "three_pct", "FT%" to "ft_pct", "3PM" to "three_pm",
        // Shooting
        "Rim Freq" to "rim_freq", "Rim FG%" to "rim_fg", "Short Mid Freq" to "short_mid_freq",
        "Short Mid FG%" to "short_mid_fg", "Long Mid Freq" to "long_mid_freq",
        "Long Mid FG%" to "long_mid_fg", "Corner 3%" to "corner3_fg",
        "Non-Corner 3%" to "nc3_fg", "Assisted FG%" to "ast_fg_pct",
        // Playmaking
        "AST%" to "ast_pct", "AST/100" to "ast_per_100", "TOV%" to "tov_pct", "AST:TO" to "ast_to",
        "AST:USG" to "ast_usg", "APG" to "apg", "AST" to "ast", "TOV/G" to "tov_pg",
        // Rebounding
        "OREB%" to "oreb_pct", "DREB%" to "dreb_pct", "REB%" to "reb_pct", "RPG" to "rpg",
        "OREB" to "oreb", "DREB" to "dreb",
        // Defense
        "STL%" to "stl_pct", "BLK%" to "blk_pct", "Stocks/100" to "stocks_per_100",
        "Fouls/100" to "foul_per_100", "SPG" to "spg", "BPG" to "bpg", "STL" to "stl", "BLK" to "blk",
        // Impact
        "On-Court +/-" to "on_net", "On-Off" to "on_off", "Min%" to "min_pct", "MPG" to "mpg",
        "GS" to "gs", "+/-" to "plus_minus",
    )

    fun key(label: String): String? = keys[label]

    /** True where a falling number is the improvement. */
    fun lowerIsBetter(label: String): Boolean = label in setOf("TOV%", "TOV/G", "Fouls/100")

    /** Counting stats are whole numbers; ratios with a small range keep two places; everything else is tenths. */
    fun decimals(label: String): Int = when (label) {
        "3PM", "AST", "OREB", "DREB", "STL", "BLK", "GS", "+/-" -> 0
        "FT Rate", "AST:USG" -> 2
        else -> 1
    }

    /** Season totals have no per-week figure on the season's ruler, so they get no recent bar. */
    fun isSeasonTotal(label: String): Boolean = label in setOf("3PM", "AST", "OREB", "DREB", "STL", "BLK", "GS", "+/-")

    /** The rollup value is already a percentage (28.0 is 28.0%). */
    fun isPercent(label: String): Boolean = label.endsWith("%") || label.endsWith("Freq") || label == "3PT Rate"

    fun isSigned(label: String): Boolean = label in setOf("On-Court +/-", "On-Off", "+/-")

    /** A percentage carries its sign, a rate its decimals, and a total its thousands separator. */
    fun format(value: Double, label: String): String {
        val places = decimals(label)
        var text = if (places == 0) NumberFormat.getIntegerInstance(Locale.US).format(swiftRoundDouble(value).toLong())
        else cFixed(value, places)
        if (isSigned(label) && value > 0) text = "+$text"
        return if (isPercent(label)) "$text%" else text
    }
}

/**
 * Windows measured in calendar weeks: 1, 2 and 4. One definition for the
 * player card, the team card and the league Trends board, so "2 wk" means one
 * thing on every screen.
 */
enum class RecentWindow(val value: Int) {
    WEEK(1), TWO_WEEKS(2), FOUR_WEEKS(4);

    /** Control label. */
    val segmentLabel: String get() = "$value wk"
    val shortLabel: String get() = segmentLabel

    /** "last week", "last 2 weeks": used mid-sentence. */
    val prose: String get() = if (this == WEEK) "last week" else "last $value weeks"

    /** "Last week", "Last 2 weeks": used on its own line. */
    val label: String get() = if (this == WEEK) "Last week" else "Last $value weeks"

    val days: Int get() = value * 7

    companion object {
        fun of(value: Int): RecentWindow? = entries.firstOrNull { it.value == value }
    }
}

/** League-anchored windows used by Trends: the same three lengths. */
typealias TrendWindow = RecentWindow

/** Keeps a followed list in the fan's order and in the selected season/phase. */
object FanStatsSelection {
    fun players(ids: List<Int>, from: List<Player>, season: Int, phase: SeasonPhase): List<Player> {
        val byId = LinkedHashMap<Int, Player>()
        for (p in from) if (p.season == season && p.seasonPhase == phase) byId.putIfAbsent(p.playerId, p)
        val seen = HashSet<Int>()
        return ids.mapNotNull { id -> if (seen.add(id)) byId[id] else null }
    }

    /** Scoring, rebounding and playmaking: the three lines a fan checks first. */
    val summaryLabels = listOf("PPG", "RPG", "APG")

    fun summary(player: Player): List<StandardStat> =
        summaryLabels.mapNotNull { label -> player.standardStats?.firstOrNull { it.label == label } }
}

/**
 * Rolls a roster into one team number and ranks it against the other teams.
 * The ruler is the league's thirty teams, not its several hundred players.
 */
object TeamAggregation {
    /** One season metric pooled across a roster: counts add up, rates are weighted by their volume. */
    fun value(label: String, category: MetricCategory, roster: List<Player>): Double? {
        val scale = teamScale(label) ?: return null
        val rule = BasketballMetricRegistry.aggregation(label, category)
        val values = roster.mapNotNull { player ->
            val metric = player.metrics.firstOrNull { it.label == label && it.category == category } ?: return@mapNotNull null
            val value = metricNumericValue(metric.value) ?: return@mapNotNull null
            when (rule) {
                MetricAggregation.Sum -> value to 1.0
                // No volume means no rate to trust: drop the player rather than weight him 1.
                is MetricAggregation.Weighted -> rule.weight.value(player)?.let { value to it }
            }
        }
        if (values.isEmpty()) return null
        return when (rule) {
            MetricAggregation.Sum -> values.sumOf { it.first }
            is MetricAggregation.Weighted -> {
                val total = values.sumOf { it.second }
                if (total <= 0) null else values.sumOf { it.first * it.second } / total * scale
            }
        }
    }

    /**
     * What a minutes-weighted player rate is worth as a team number. A player's
     * share of what happened while he was on the floor is a fifth of the team's,
     * so those are multiplied back up. Usage, minutes share and On-Off average to
     * the same figure for every team, so they have no team figure (null).
     */
    fun teamScale(label: String): Double? {
        if (label in TEAMLESS) return null
        return if (label in FIFTHS) 5.0 else 1.0
    }

    private val FIFTHS = setOf("Pts/100", "AST/100", "Stocks/100", "Fouls/100", "OREB%", "DREB%", "REB%", "STL%", "BLK%")
    private val TEAMLESS = setOf("USG%", "Min%", "AST%", "AST:USG", "On-Off", "MPG", "GS")

    /** A rolling-window metric pooled across a team's rows, weighted by minutes in the window. */
    fun recentValue(key: String, rows: List<RecentForm>, label: String? = null): Double? {
        val scale = if (label == null) 1.0 else teamScale(label) ?: return null
        val pairs = rows.mapNotNull { row ->
            val value = row.metrics[key] ?: return@mapNotNull null
            if (row.touches <= 0) null else value to row.touches.toDouble()
        }
        val total = pairs.sumOf { it.second }
        if (total <= 0) return null
        return pairs.sumOf { it.first * it.second } / total * scale
    }

    /** Midpoint rank of [value] among [values], 1 to 100, flipped when lower is better. */
    fun percentile(value: Double, values: List<Double>, higherIsBetter: Boolean = true): Int {
        val pool = values.ifEmpty { listOf(value) }
        val below = pool.count { it < value }
        val equal = pool.count { it == value }
        val raw = (below + equal / 2.0) / pool.size * 100
        val oriented = if (higherIsBetter) raw else 100 - raw
        return swiftRound(oriented).coerceIn(1, 100)
    }

    fun rosters(players: List<Player>): Map<String, List<Player>> = players.groupBy { normalizedTeamAbbreviation(it.team) }

    fun recentRosters(rows: List<RecentForm>): Map<String, List<RecentForm>> = rows.groupBy { normalizedTeamAbbreviation(it.team ?: "") }
}
