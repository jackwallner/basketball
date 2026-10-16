package com.jackwallner.basketball.model

import java.time.LocalDate
import java.time.Period
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/**
 * Who a player is: size, age and how he entered the league, from
 * `public.player_profiles`. Every field is optional; a screen leaves the line
 * out rather than wait for it. The contract, snap and injury columns are
 * always null for the NBA and the app does not read them.
 */
data class PlayerProfile(
    val playerId: Int,
    val season: Int,
    val jersey: Int? = null,
    val birthDate: LocalDate? = null,
    val heightInches: Int? = null,
    val weightPounds: Int? = null,
    val yearsExperience: Int? = null,
    /** The season (end year) of his first NBA season. */
    val rookieSeason: Int? = null,
    val draftYear: Int? = null,
    val draftRound: Int? = null,
    val draftPick: Int? = null,
) {
    /** In his first NBA season. */
    val isRookie: Boolean get() = rookieSeason == season

    fun age(on: LocalDate = LocalDate.now()): Int? = birthDate?.let { Period.between(it, on).years }

    /** "6-9, 250". */
    val sizeLabel: String?
        get() {
            val h = heightInches?.takeIf { it > 0 } ?: return null
            val height = "${h / 12}-${h % 12}"
            val w = weightPounds?.takeIf { it > 0 } ?: return height
            return "$height, $w"
        }

    /** "2003 R1 #1", or "Undrafted" for a player who came in without a pick. */
    val draftLabel: String?
        get() {
            if (draftYear != null && draftRound != null && draftPick != null) return "$draftYear R$draftRound #$draftPick"
            return if (yearsExperience != null) "Undrafted" else null
        }

    companion object {
        fun fromJson(o: JsonObject) = PlayerProfile(
            playerId = o.requireInt("player_id"),
            season = o.requireInt("season"),
            jersey = o.int("jersey"),
            birthDate = o.string("birth_date")?.let { raw ->
                try {
                    LocalDate.parse(raw.take(10))
                } catch (_: DateTimeParseException) {
                    null
                }
            },
            heightInches = o.int("height_in"),
            weightPounds = o.int("weight_lb"),
            yearsExperience = o.int("years_exp"),
            rookieSeason = o.int("rookie_season"),
            draftYear = o.int("draft_year"),
            draftRound = o.int("draft_round"),
            draftPick = o.int("draft_pick"),
        )
    }
}

/**
 * One team's power rating from `public.team_ratings`: points per 100
 * possessions better or worse than an average team, adjusted for schedule,
 * split into an offense and a defense half (positive is good for both).
 */
data class TeamRating(
    val season: Int,
    val team: String,
    val rank: Int,
    val games: Int,
    val throughWeek: Int,
    val rating: Double,
    val offense: Double,
    val defense: Double,
    val schedule: Double,
    val wins: Int,
    val losses: Int,
    val pointsFor: Int,
    val pointsAgainst: Int,
) {
    companion object {
        /** "+6.3", "-1.2", "0.0". */
        fun signed(value: Double): String {
            val rounded = swiftRoundDouble(value * 10) / 10.0
            if (rounded == 0.0) return "0.0"
            return String.format(Locale.US, "%+.1f", rounded)
        }

        fun fromJson(o: JsonObject) = TeamRating(
            season = o.requireInt("season"),
            team = o.requireString("team"),
            rank = o.requireInt("rank"),
            games = o.requireInt("games"),
            throughWeek = o.requireInt("through_week"),
            rating = o.double("rating") ?: throw RowDecodeException("rating"),
            offense = o.double("offense") ?: throw RowDecodeException("offense"),
            defense = o.double("defense") ?: throw RowDecodeException("defense"),
            schedule = o.double("schedule") ?: throw RowDecodeException("schedule"),
            wins = o.requireInt("wins"),
            losses = o.requireInt("losses"),
            pointsFor = o.requireInt("points_for"),
            pointsAgainst = o.requireInt("points_against"),
        )
    }
}

/** A projected margin for an unplayed game, from the two power ratings plus home court. */
data class GameProjection(val gameId: String, val homeMargin: Double, val homeWinProbability: Double) {
    /** "SAS by 4.5", "Toss-up" under a point. */
    fun label(home: String, away: String): String {
        val margin = kotlin.math.abs(homeMargin)
        if (margin < 1) return "Toss-up"
        val favourite = if (homeMargin > 0) home else away
        return "${displayTeamAbbr(favourite)} by ${String.format(Locale.US, "%.1f", swiftRoundDouble(margin * 2) / 2)}"
    }

    fun winProbability(team: String, home: String): Double =
        if (normalizedTeamAbbreviation(team) == normalizedTeamAbbreviation(home)) homeWinProbability else 1 - homeWinProbability

    companion object {
        fun fromJson(o: JsonObject) = GameProjection(
            gameId = o.requireString("game_id"),
            homeMargin = o.double("home_margin") ?: throw RowDecodeException("home_margin"),
            homeWinProbability = o.double("home_win_prob") ?: throw RowDecodeException("home_win_prob"),
        )
    }
}

/** A team's line in the standings, from posted finals. */
data class StandingsRow(
    val team: String,
    val wins: Int = 0,
    val losses: Int = 0,
    val pointsFor: Int = 0,
    val pointsAgainst: Int = 0,
    /** "W2", "L1"; null before a game. */
    val streak: String? = null,
) {
    val games: Int get() = wins + losses
    val differential: Int get() = pointsFor - pointsAgainst
    val winPercentage: Double get() = if (games == 0) 0.0 else wins.toDouble() / games
    val record: String get() = "$wins-$losses"

    /** Average scoring margin, "+8.2"; null before a game. */
    val marginLabel: String?
        get() {
            if (games <= 0) return null
            val margin = differential.toDouble() / games
            val text = String.format(Locale.US, "%.1f", kotlin.math.abs(margin))
            return if (margin > 0.05) "+$text" else if (margin < -0.05) "-$text" else "0.0"
        }

    /** Games behind [leader], in halves: ((W gap) + (L gap)) / 2. */
    fun gamesBack(leader: StandingsRow): Double = ((leader.wins - wins) + (losses - leader.losses)) / 2.0

    companion object {
        /** "3.5", "12"; whole numbers drop the decimal. */
        fun formatGamesBack(value: Double): String =
            if (value == Math.rint(value)) value.toInt().toString() else String.format(Locale.US, "%.1f", value)

        /** Regular-season finals that count in the standings, oldest first so the streak reads off the end. */
        fun build(games: List<Game>, teams: List<String>): Map<String, StandingsRow> {
            val rows = teams.associateWith { StandingsRow(it) }.toMutableMap()
            val finals = games.filter { it.countsInStandings && it.isFinal }.sortedBy { it.sortInstant }
            val results = HashMap<String, MutableList<String>>()
            for (game in finals) {
                for (side in listOf(game.homeTeam, game.awayTeam)) {
                    val team = normalizedTeamAbbreviation(side)
                    val row = rows[team] ?: continue
                    val result = game.result(side) ?: continue
                    val mine = game.score(side) ?: continue
                    val theirs = game.score(game.opponent(side)) ?: continue
                    rows[team] = row.copy(
                        wins = row.wins + if (result == "W") 1 else 0,
                        losses = row.losses + if (result == "W") 0 else 1,
                        pointsFor = row.pointsFor + mine,
                        pointsAgainst = row.pointsAgainst + theirs,
                    )
                    results.getOrPut(team) { mutableListOf() }.add(result)
                }
            }
            for ((team, list) in results) {
                val last = list.lastOrNull() ?: continue
                val run = list.asReversed().takeWhile { it == last }.size
                rows[team] = rows.getValue(team).copy(streak = "$last$run")
            }
            return rows
        }

        /** Win percentage, then point differential, then name: not the NBA's full tiebreaker ladder. */
        fun ordered(rows: List<StandingsRow>): List<StandingsRow> = rows.sortedWith(
            compareByDescending<StandingsRow> { it.winPercentage }
                .thenByDescending { it.differential }
                .thenBy { it.team },
        )
    }
}
