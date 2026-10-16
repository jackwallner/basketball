package com.jackwallner.basketball.model

import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * The running score of a game under way, read from ESPN's public NBA
 * scoreboard. The backend posts a score only once hoopR publishes the final,
 * so this is what lets a game in progress (and a final from the last few
 * hours) show its score. hoopR is an ESPN mirror, so the game ids match.
 */
data class LiveScore(
    val gameId: String,
    val awayScore: Int,
    val homeScore: Int,
    /** ESPN `status.type.state`: only `in` and a completed `post` are kept. */
    val state: String,
    /** ESPN `status.type.shortDetail`, used only to spot halftime and period ends. */
    val detail: String,
    val period: Int,
    /** ESPN `status.displayClock`: "4:12", "45.2", "0.0". */
    val clock: String = "",
) {
    val isFinal: Boolean get() = state == "post"
    val isUnderway: Boolean get() = state == "in"

    private val periodName: String
        get() = when {
            period <= 4 -> "Q${maxOf(period, 1)}"
            period == 5 -> "OT"
            else -> "${period - 4}OT"
        }

    /** "Q3 4:12", "Half", "End Q3", "OT 1:05", "Final/OT". */
    val clockLabel: String
        get() {
            if (isFinal) {
                return when {
                    period <= 4 -> "Final"
                    period == 5 -> "Final/OT"
                    else -> "Final/${period - 4}OT"
                }
            }
            if (detail.contains("halftime", ignoreCase = true)) return "Half"
            if (detail.contains("end of", ignoreCase = true) || clock == "0.0" || clock == "0:00") return "End $periodName"
            return if (clock.isEmpty()) periodName else "$periodName $clock"
        }

    fun score(isHome: Boolean): Int = if (isHome) homeScore else awayScore

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Games from one scoreboard payload that have started. */
        fun parse(body: String): List<LiveScore> {
            val root = runCatching { json.parseToJsonElement(body) as? JsonObject }.getOrNull() ?: return emptyList()
            val events = root.array("events") ?: return emptyList()
            return events.mapNotNull { element ->
                val event = element as? JsonObject ?: return@mapNotNull null
                val id = event.string("id") ?: return@mapNotNull null
                val status = event.obj("status") ?: return@mapNotNull null
                val kind = status.obj("type") ?: return@mapNotNull null
                val state = kind.string("state") ?: return@mapNotNull null
                // A game under way, or one that really finished. A postponed or
                // suspended game is also `post`, with no completion and 0-0.
                if (!(state == "in" || (state == "post" && kind.bool("completed") == true))) return@mapNotNull null
                val competition = event.array("competitions")?.firstOrNull() as? JsonObject ?: return@mapNotNull null
                val competitors = competition.array("competitors")?.mapNotNull { it as? JsonObject } ?: return@mapNotNull null
                val home = competitors.firstOrNull { it.string("homeAway") == "home" } ?: return@mapNotNull null
                val away = competitors.firstOrNull { it.string("homeAway") == "away" } ?: return@mapNotNull null
                val homeScore = home.string("score")?.toIntOrNull() ?: return@mapNotNull null
                val awayScore = away.string("score")?.toIntOrNull() ?: return@mapNotNull null
                LiveScore(
                    gameId = id,
                    awayScore = awayScore,
                    homeScore = homeScore,
                    state = state,
                    detail = kind.string("shortDetail") ?: "",
                    period = status.int("period") ?: 1,
                    clock = status.string("displayClock") ?: "",
                )
            }
        }

        /** The scoreboard files a game under its Eastern date ("20261020"); `Game.gameDate` is Eastern midnight. */
        fun dateKey(date: Instant): String = date.atZone(EASTERN).toLocalDate().toString().replace("-", "")
    }
}

/**
 * The one status every surface shows for a game that has tipped off: the
 * scoreboard's clock when it has one, else "In progress" or, hours on with no
 * score posted, "Final soon".
 */
fun Game.startedLabel(live: LiveScore?, now: Instant = Instant.now()): String {
    if (live != null) return live.clockLabel
    if (isScorePending(now)) return "Score pending"
    return if (status(now) == GameStatus.AWAITING_SCORE) "Final soon" else "In progress"
}

/** Tipped off more than twelve hours ago with no score anywhere: over, but with nothing to show yet. */
fun Game.isScorePending(now: Instant = Instant.now()): Boolean {
    if (isFinal) return false
    val tipoff = tipoff ?: return false
    return Duration.between(tipoff, now).seconds > 12 * 3_600
}
