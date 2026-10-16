package com.jackwallner.basketball.model

import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * A basic box score rebuilt from one game's `player_game_logs` rows. Every
 * number is a sum of per-player counts; nothing here is a roster average or a
 * percentile. Team totals only add columns that do not double count.
 */
class GameBoxScore(logs: List<PlayerGameLog>) {
    data class PlayerLine(val playerId: Int, val team: String, val playerType: String, val metrics: Map<String, Double>) {
        val id: String get() = "$playerId-$playerType"
        fun value(key: String): Double = metrics[key] ?: 0.0
        fun int(key: String): Int = swiftRound(value(key))

        val minutes: Int get() = int("min")
        val isStarter: Boolean get() = value("starter") > 0

        /** A box score lists the players who got on the floor. */
        val played: Boolean get() = minutes > 0

        /** "7/15" from the made and attempted columns. */
        fun made(made: String, attempts: String): String = "${int(made)}/${int(attempts)}"

        /** Signed plus/minus, or "-" before ESPN carries one (null in the feed). */
        val plusMinusText: String
            get() {
                val value = metrics["plus_minus"] ?: return "-"
                val rounded = swiftRound(value)
                return if (rounded > 0) "+$rounded" else "$rounded"
            }
    }

    data class TeamTotals(
        val points: Double = 0.0,
        val fieldGoalsMade: Double = 0.0,
        val fieldGoalsAttempted: Double = 0.0,
        val threesMade: Double = 0.0,
        val threesAttempted: Double = 0.0,
        val freeThrowsMade: Double = 0.0,
        val freeThrowsAttempted: Double = 0.0,
        val offensiveRebounds: Double = 0.0,
        val rebounds: Double = 0.0,
        val assists: Double = 0.0,
        val steals: Double = 0.0,
        val blocks: Double = 0.0,
        val turnovers: Double = 0.0,
        val fouls: Double = 0.0,
    ) {
        val fieldGoalPercentage: Double? get() = if (fieldGoalsAttempted > 0) fieldGoalsMade / fieldGoalsAttempted * 100 else null
        val threePointPercentage: Double? get() = if (threesAttempted > 0) threesMade / threesAttempted * 100 else null
        val freeThrowPercentage: Double? get() = if (freeThrowsAttempted > 0) freeThrowsMade / freeThrowsAttempted * 100 else null

        /** A three counts for a point and a half. */
        val effectiveFieldGoalPercentage: Double?
            get() = if (fieldGoalsAttempted > 0) (fieldGoalsMade + 0.5 * threesMade) / fieldGoalsAttempted * 100 else null
    }

    /** Game leaders across both teams: the top scorer, rebounder and assist man. */
    data class Leader(val title: String, val line: PlayerLine, val summary: String) {
        val id: String get() = title
    }

    val lines: List<PlayerLine> = logs.map { log ->
        PlayerLine(log.playerId, normalizedTeamAbbreviation(log.team ?: ""), log.playerType, log.metrics)
    }

    val isEmpty: Boolean get() = lines.isEmpty()

    fun lines(team: String): List<PlayerLine> {
        val abbr = normalizedTeamAbbreviation(team)
        return lines.filter { it.team == abbr }
    }

    /** Starters first, then everyone else by minutes. Players who never got on the floor are left off. */
    fun rotation(team: String): List<PlayerLine> = lines(team).filter { it.played }.sortedWith(
        compareByDescending<PlayerLine> { it.isStarter }.thenByDescending { it.minutes }.thenByDescending { it.value("pts") },
    )

    fun totals(team: String): TeamTotals = lines(team).fold(TeamTotals()) { t, line ->
        t.copy(
            points = t.points + line.value("pts"),
            fieldGoalsMade = t.fieldGoalsMade + line.value("fgm"),
            fieldGoalsAttempted = t.fieldGoalsAttempted + line.value("fga"),
            threesMade = t.threesMade + line.value("fg3m"),
            threesAttempted = t.threesAttempted + line.value("fg3a"),
            freeThrowsMade = t.freeThrowsMade + line.value("ftm"),
            freeThrowsAttempted = t.freeThrowsAttempted + line.value("fta"),
            offensiveRebounds = t.offensiveRebounds + line.value("oreb"),
            rebounds = t.rebounds + line.value("reb"),
            assists = t.assists + line.value("ast"),
            steals = t.steals + line.value("stl"),
            blocks = t.blocks + line.value("blk"),
            turnovers = t.turnovers + line.value("tov"),
            fouls = t.fouls + line.value("pf"),
        )
    }

    val leaders: List<Leader>
        get() = listOfNotNull(
            best("pts")?.let { Leader("Points", it, scoringSummary(it)) },
            best("reb")?.let { Leader("Rebounds", it, reboundingSummary(it)) },
            best("ast")?.let { Leader("Assists", it, assistSummary(it)) },
        )

    /** Highest of one column, with points then minutes breaking a tie so the same game always names the same player. */
    private fun best(key: String): PlayerLine? = lines.filter { it.value(key) > 0 }.maxWithOrNull(
        compareBy<PlayerLine> { it.value(key) }.thenBy { it.value("pts") }.thenBy { it.minutes.toDouble() },
    )

    companion object {
        fun scoringSummary(line: PlayerLine): String {
            val parts = mutableListOf("${line.int("pts")} pts", "${line.made("fgm", "fga")} FG")
            if (line.int("fg3a") > 0) parts += "${line.made("fg3m", "fg3a")} 3P"
            return parts.joinToString(", ")
        }

        fun reboundingSummary(line: PlayerLine): String {
            val parts = mutableListOf("${line.int("reb")} reb")
            if (line.int("oreb") > 0) parts += "${line.int("oreb")} off"
            parts += "${line.int("pts")} pts"
            return parts.joinToString(", ")
        }

        fun assistSummary(line: PlayerLine): String = "${line.int("ast")} ast, ${line.int("tov")} tov, ${line.int("pts")} pts"

        /** "36 min · 11/19 FG · 2/5 3P · 4/4 FT · +8". Empty attempts drop out. */
        fun shootingLine(line: PlayerLine): String {
            val parts = mutableListOf("${line.minutes} min")
            if (line.int("fga") > 0) parts += "${line.made("fgm", "fga")} FG"
            if (line.int("fg3a") > 0) parts += "${line.made("fg3m", "fg3a")} 3P"
            if (line.int("fta") > 0) parts += "${line.made("ftm", "fta")} FT"
            if (line.metrics["plus_minus"] != null) parts += line.plusMinusText
            return parts.joinToString(" · ")
        }

        /** "24 pts, 8 reb, 6 ast". */
        fun summary(line: PlayerLine): String {
            val parts = mutableListOf("${line.int("pts")} pts")
            if (line.int("reb") > 0) parts += "${line.int("reb")} reb"
            if (line.int("ast") > 0) parts += "${line.int("ast")} ast"
            if (line.int("stl") >= 3) parts += "${line.int("stl")} stl"
            if (line.int("blk") >= 3) parts += "${line.int("blk")} blk"
            return parts.joinToString(", ")
        }
    }
}

/** "1", "1.5": Swift's `.precision(.fractionLength(0...1))`. */
fun formatUpToOneDecimal(value: Double): String {
    val rounded = swiftRoundDouble(value * 10) / 10
    return if (rounded == Math.floor(rounded)) rounded.toLong().toString() else String.format(Locale.US, "%.1f", rounded)
}

/** A number with its percentile among this season's team games or qualifying player games. */
data class RatedValue(val value: Double, val percentile: Int? = null) {
    companion object {
        fun from(element: JsonElement?): RatedValue? = when (element) {
            is JsonPrimitive -> if (element.isString || element is JsonNull) null else element.doubleOrNull?.let { RatedValue(it) }
            is JsonObject -> element.double("value")?.let { RatedValue(it, element.int("pct")) }
            else -> null
        }
    }
}

/**
 * The advanced breakdown for one game, from `public.game_details`: the team
 * four factors and ratings, the score margin through the game, the plays that
 * decided it, and a line for every player with percentiles against the season.
 */
data class GameDetail(
    val gameId: String,
    val awayTeam: String,
    val homeTeam: String,
    val away: Map<String, RatedValue> = emptyMap(),
    val home: Map<String, RatedValue> = emptyMap(),
    val players: List<PlayerLine> = emptyList(),
    val margin: List<MarginPoint> = emptyList(),
    val bigPlays: List<BigPlay> = emptyList(),
) {
    data class PlayerLine(
        val playerId: Int,
        val name: String? = null,
        val team: String,
        val starter: Boolean = false,
        /** Minutes played. A plain count, never ranked. */
        val minutes: Int? = null,
        val points: RatedValue? = null,
        val rebounds: RatedValue? = null,
        val assists: RatedValue? = null,
        val trueShooting: RatedValue? = null,
        val usage: RatedValue? = null,
        val plusMinus: RatedValue? = null,
    ) {
        val id: Int get() = playerId

        companion object {
            fun fromJson(o: JsonObject): PlayerLine {
                // Each stat is rated independently: one malformed cell must not drop the line.
                fun rated(key: String): RatedValue? = RatedValue.from(o[key])
                return PlayerLine(
                    playerId = o.requireInt("player_id"),
                    name = o.string("name"),
                    team = o.requireString("team"),
                    starter = o.bool("starter") ?: false,
                    minutes = o.int("min"),
                    points = rated("pts"),
                    rebounds = rated("reb"),
                    assists = rated("ast"),
                    trueShooting = rated("ts_pct"),
                    usage = rated("usg_pct"),
                    plusMinus = rated("plus_minus"),
                )
            }
        }
    }

    data class BigPlay(
        val qtr: Int,
        val clock: String,
        val team: String,
        val description: String,
        val points: Int,
        /** Home score minus away score after the play. */
        val homeMargin: Int,
        val kind: Kind?,
    ) {
        enum class Kind(val raw: String) {
            /** A scoring play in the last five minutes of the fourth or overtime with the margin inside five afterwards. */
            LATE_SCORE("late_score"),

            /** The play worth the most points that changed the lead. */
            LEAD_CHANGE("lead_change"),
        }

        val id: String get() = "$qtr-$clock-${description.take(24)}"

        companion object {
            fun fromJson(o: JsonObject) = BigPlay(
                qtr = o.requireInt("qtr"),
                clock = o.requireString("clock"),
                team = o.requireString("team"),
                description = o.requireString("description"),
                points = o.int("points") ?: 0,
                homeMargin = o.int("home_margin") ?: 0,
                kind = o.string("kind")?.let { raw -> Kind.entries.firstOrNull { it.raw == raw } },
            )
        }
    }

    /** One step of the score margin: seconds elapsed and home minus away. Positive is the home team ahead. */
    data class MarginPoint(val elapsed: Double, val homeMargin: Double)

    fun stats(team: String): Map<String, RatedValue> =
        if (normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(homeTeam)) home else away

    /** A team's player lines, starters first and then by minutes. */
    fun players(team: String): List<PlayerLine> {
        val abbr = normalizedTeamAbbreviation(team)
        return players.filter { normalizedTeamAbbreviation(it.team) == abbr }
            .sortedWith(compareByDescending<PlayerLine> { it.starter }.thenByDescending { it.minutes ?: 0 })
    }

    /** The largest lead either side held, in points, from the margin series: (away, home). */
    val largestLeads: Pair<Int, Int>
        get() {
            val margins = margin.map { it.homeMargin }
            val away = maxOf(0.0, -(margins.minOrNull() ?: 0.0)).toInt()
            val home = maxOf(0.0, margins.maxOrNull() ?: 0.0).toInt()
            return away to home
        }

    companion object {
        fun fromJson(o: JsonObject): GameDetail {
            val sides = o.obj("team_stats")
            fun side(key: String): Map<String, RatedValue> {
                val raw = sides?.obj(key) ?: return emptyMap()
                return raw.mapNotNull { (k, v) -> RatedValue.from(v)?.let { k to it } }.toMap()
            }
            // The column keeps the name it had before the NBA; it holds the margin series.
            val margin = (o["win_probability"] as? JsonArray).orEmpty().mapNotNull { row ->
                val values = (row as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull } ?: return@mapNotNull null
                if (values.size == 2) MarginPoint(values[0], values[1]) else null
            }
            return GameDetail(
                gameId = o.requireString("game_id"),
                awayTeam = o.requireString("away_team"),
                homeTeam = o.requireString("home_team"),
                away = side("away"),
                home = side("home"),
                players = o["players"]?.lenientList(PlayerLine::fromJson).orEmpty(),
                margin = margin,
                bigPlays = o["big_plays"]?.lenientList(BigPlay::fromJson).orEmpty(),
            )
        }
    }
}
