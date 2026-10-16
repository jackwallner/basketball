package com.jackwallner.basketball.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.json.JsonObject

/**
 * One NBA game from `public.games`, the published hoopR schedule. Scores are
 * null until hoopR posts a final. There is no live score feed: a game past
 * tip-off with no score is "in progress", not 0-0.
 */
data class Game(
    val id: String,
    val season: Int,
    val seasonPhase: SeasonPhase = SeasonPhase.REGULAR,
    /**
     * `REG`; `CUP` for the NBA Cup final (outside the standings and season
     * stats); `PPD` for a postponed game, whose makeup is its own row; a playoff
     * round `R1`, `R2`, `CF`, `FIN` (or plain `POST`).
     */
    val gameType: String = "REG",
    /** Calendar weeks since the season's October epoch. Not a league week: the NBA has none. */
    val week: Int,
    val tipoff: Instant?,
    val gameDate: Instant = tipoff ?: Instant.EPOCH,
    val awayTeam: String,
    val homeTeam: String,
    val awayScore: Int? = null,
    val homeScore: Int? = null,
    val overtime: Boolean = false,
    val stadium: String? = null,
) {
    val isFinal: Boolean get() = awayScore != null && homeScore != null

    /** Postponed or cancelled. Its makeup is a separate game, so this row is never shown. */
    val isPostponed: Boolean get() = gameType == "PPD"

    val isCupFinal: Boolean get() = gameType == "CUP"

    /** Counts toward a team's record: a regular-season game that isn't the NBA Cup final. */
    val countsInStandings: Boolean get() = seasonPhase == SeasonPhase.REGULAR && !isCupFinal && !isPostponed

    /** "West 1st Round", "East Finals", "NBA Finals"; null outside the playoffs or for an unnamed round. */
    val playoffRoundName: String?
        get() {
            val conference = if (LeagueConference.EAST.contains(homeTeam)) "East" else "West"
            return when (gameType) {
                "R1" -> "$conference 1st Round"
                "R2" -> "$conference Semifinals"
                "CF" -> "$conference Finals"
                "FIN" -> "NBA Finals"
                else -> null
            }
        }

    fun involves(team: String): Boolean {
        val abbr = normalizedTeamAbbreviation(team)
        return normalizedTeamAbbreviation(awayTeam) == abbr || normalizedTeamAbbreviation(homeTeam) == abbr
    }

    fun opponent(team: String): String =
        if (normalizedTeamAbbreviation(awayTeam) == normalizedTeamAbbreviation(team)) homeTeam else awayTeam

    fun isHome(team: String): Boolean = normalizedTeamAbbreviation(homeTeam) == normalizedTeamAbbreviation(team)

    fun score(team: String): Int? = if (isHome(team)) homeScore else awayScore

    /** "W" or "L" for a final, from [team]'s side. Basketball has no ties. */
    fun result(team: String): String? {
        val mine = score(team) ?: return null
        val theirs = score(opponent(team)) ?: return null
        return if (mine > theirs) "W" else "L"
    }

    /** "W 118-109", team score first. */
    fun resultLine(team: String): String? {
        val result = result(team) ?: return null
        val mine = score(team) ?: return null
        val theirs = score(opponent(team)) ?: return null
        return "$result $mine-$theirs${if (overtime) " OT" else ""}"
    }

    /** "vs HOU" at home, "at HOU" away. */
    fun matchupLabel(team: String): String = "${if (isHome(team)) "vs" else "at"} ${displayTeamAbbr(opponent(team))}"

    fun status(now: Instant = Instant.now()): GameStatus {
        if (isFinal) return GameStatus.FINAL
        val tipoff = tipoff ?: return GameStatus.UPCOMING
        if (now < tipoff) return GameStatus.UPCOMING
        // No live scores in the feed. Past a normal game length with no posted
        // final, say the score is on its way rather than "in progress" forever.
        return if (Duration.between(tipoff, now).seconds < 3.5 * 3_600) GameStatus.IN_PROGRESS else GameStatus.AWAITING_SCORE
    }

    /** What makes the game more than a date: "NBA Finals · Game 5 · NYK wins 4-1", "NBA Cup Final". */
    fun contextLine(series: SeriesStatus?): String? {
        if (isCupFinal) return "NBA Cup Final"
        series ?: return null
        return (listOf(series.gameLabel) + listOfNotNull(series.standingLabel)).joinToString(" · ")
    }

    /** "Tue 7:30 PM" in the phone's zone. */
    fun tipoffLabel(zone: ZoneId = ZoneId.systemDefault()): String {
        val tipoff = tipoff ?: return DateText.gameDay(gameDate)
        return DateTimeFormatter.ofPattern("EEE h:mm a", Locale.US).format(tipoff.atZone(zone))
    }

    /** "Tue, Oct 20". */
    fun dayLabel(zone: ZoneId = ZoneId.systemDefault()): String {
        val tipoff = tipoff ?: return DateText.gameDay(gameDate)
        return DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US).format(tipoff.atZone(zone))
    }

    val sortInstant: Instant get() = tipoff ?: gameDate

    companion object {
        fun fromJson(o: JsonObject): Game {
            val rawDate = o.requireString("game_date")
            return Game(
                id = o.requireString("game_id"),
                season = o.requireInt("season"),
                seasonPhase = o.string("season_type")?.let { SeasonPhase.from(it) ?: throw RowDecodeException("bad phase") } ?: SeasonPhase.REGULAR,
                gameType = o.string("game_type") ?: "REG",
                week = o.requireInt("week"),
                tipoff = o.string("kickoff_at")?.let(::parseDate),
                gameDate = parseDate(rawDate) ?: throw RowDecodeException("bad game_date"),
                awayTeam = o.requireString("away_team"),
                homeTeam = o.requireString("home_team"),
                awayScore = o.int("away_score"),
                homeScore = o.int("home_score"),
                overtime = o.bool("overtime") ?: false,
                stadium = o.string("stadium"),
            )
        }

        /** In progress, then finals, then upcoming, each by tip-off. */
        fun slateOrder(games: List<Game>, now: Instant = Instant.now()): List<Game> = games.sortedWith(
            compareBy<Game> { it.status(now).sortOrder }.thenBy { it.sortInstant }.thenBy { it.id },
        )
    }
}

enum class GameStatus(val sortOrder: Int) {
    IN_PROGRESS(0), AWAITING_SCORE(1), FINAL(2), UPCOMING(3);

    /** The one word every screen uses for a game with no posted final. */
    val liveLabel: String get() = if (this == AWAITING_SCORE) "Final soon" else "In progress"
}

/**
 * A selectable day of the schedule. The NBA plays nearly every night, so the
 * Games tab is a strip of game days rather than league weeks. Keyed by the
 * Eastern calendar date, the league's calendar.
 */
data class GameDay(val date: LocalDate, val phase: SeasonPhase) {
    /** "2026-10-20". */
    val id: String get() = date.toString()

    /** Eastern midnight of the game date. */
    val start: Instant get() = date.atStartOfDay(EASTERN).toInstant()

    /** Chip text: "Oct 20". */
    val shortLabel: String get() = DateTimeFormatter.ofPattern("MMM d", Locale.US).format(date)

    /** "Tue, Oct 20". */
    val label: String get() = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US).format(date)

    fun games(from: List<Game>): List<Game> = from.filter { day(it) == date && it.seasonPhase == phase }

    companion object {
        /** The Eastern calendar day a game is filed under. */
        fun day(game: Game): LocalDate = game.gameDate.atZone(EASTERN).toLocalDate()

        fun days(games: List<Game>): List<GameDay> {
            val seen = LinkedHashMap<String, GameDay>()
            for (game in games) {
                val d = GameDay(day(game), game.seasonPhase)
                seen[d.id] = d
            }
            return seen.values.sortedBy { it.date }
        }

        /**
         * The day a fan means by "today". A day stays current until 8am Eastern
         * the morning after, so last night's finals are still on screen over
         * breakfast. Before the season it is opening night; after it, the last
         * day played.
         */
        fun current(games: List<Game>, now: Instant = Instant.now()): GameDay? = current(days(games), now)

        /** [current] over days already worked out, in date order. */
        @JvmName("currentOfDays")
        fun current(days: List<GameDay>, now: Instant = Instant.now()): GameDay? =
            days.firstOrNull { now < it.start.plusSeconds(32 * 3_600) } ?: days.lastOrNull()
    }
}

/** Where a playoff series stood after one of its games. */
data class SeriesStatus(val round: String, val gameNumber: Int, val wins: Map<String, Int>) {
    /** "NBA Finals · Game 5". */
    val gameLabel: String get() = "$round · Game $gameNumber"

    /** "NYK wins 4-1", "NYK leads 3-2", "Series tied 2-2"; a first game says nothing. */
    val standingLabel: String?
        get() {
            val sorted = wins.entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            if (sorted.size != 2) return null
            val leader = sorted[0]
            if (leader.value <= 0) return null
            val trailer = sorted[1]
            if (leader.value == trailer.value) return "Series tied ${leader.value}-${trailer.value}"
            val verb = if (leader.value == 4) "wins" else "leads"
            return "${displayTeamAbbr(leader.key)} $verb ${leader.value}-${trailer.value}"
        }

    companion object {
        /** The series a playoff game belongs to, from every game of the season. Null for anything but a named round. */
        fun of(game: Game, games: List<Game>): SeriesStatus? {
            val round = game.playoffRoundName ?: return null
            val pair = setOf(normalizedTeamAbbreviation(game.homeTeam), normalizedTeamAbbreviation(game.awayTeam))
            val series = games
                .filter {
                    it.season == game.season && it.gameType == game.gameType &&
                        setOf(normalizedTeamAbbreviation(it.homeTeam), normalizedTeamAbbreviation(it.awayTeam)) == pair
                }
                .sortedWith(compareBy<Game> { it.sortInstant }.thenBy { it.id })
            val index = series.indexOfFirst { it.id == game.id }
            if (index < 0) return null
            val wins = pair.associateWith { 0 }.toMutableMap()
            for (played in series.subList(0, index + 1)) {
                val winner = listOf(played.homeTeam, played.awayTeam).firstOrNull { played.result(it) == "W" } ?: continue
                val key = normalizedTeamAbbreviation(winner)
                wins[key] = (wins[key] ?: 0) + 1
            }
            return SeriesStatus(round, index + 1, wins)
        }
    }
}

object DateText {
    private val GAME_DAY = DateTimeFormatter.ofPattern("MMM d", Locale.US)

    /** Game dates are Eastern midnight; format them in Eastern so the west coast keeps the right day. */
    fun gameDay(date: Instant): String = GAME_DAY.format(date.atZone(EASTERN))
}
