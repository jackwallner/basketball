package com.jackwallner.basketball

import com.jackwallner.basketball.model.LiveScore
import com.jackwallner.basketball.model.parseDay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveScoreTest {
    private fun payload(events: String) = """{"events":[$events]}"""

    private fun event(
        id: String, state: String, detail: String, period: Int, home: String, away: String,
        clock: String = "0.0", completed: Boolean? = null,
    ): String {
        val done = completed ?: (state == "post")
        return """{"id":"$id","status":{"period":$period,"displayClock":"$clock","type":{"state":"$state","completed":$done,"shortDetail":"$detail"}},
            "competitions":[{"competitors":[{"homeAway":"home","score":"$home"},{"homeAway":"away","score":"$away"}]}]}"""
    }

    @Test
    fun parsesGamesUnderwayAndFinalsButNotScheduled() {
        val body = payload(
            listOf(
                event("1", "in", "4:12 - 3rd", 3, "71", "68", clock = "4:12"),
                event("2", "post", "Final/OT", 5, "110", "112"),
                event("3", "pre", "10/20 - 7:00 PM EDT", 0, "0", "0"),
                event("4", "post", "Postponed", 0, "0", "0", completed = false),
            ).joinToString(","),
        )
        val scores = LiveScore.parse(body).associateBy { it.gameId }

        assertEquals(2, scores.size)
        assertEquals(71, scores["1"]?.homeScore)
        assertEquals(68, scores["1"]?.awayScore)
        assertTrue(scores["1"]?.isUnderway == true)
        assertEquals("Q3 4:12", scores["1"]?.clockLabel)
        assertTrue(scores["2"]?.isFinal == true)
        assertEquals("Final/OT", scores["2"]?.clockLabel)
        assertNull(scores["3"])
        assertNull("a postponed game is not a 0-0 final", scores["4"])
    }

    @Test
    fun clockLabelsForBreaks() {
        assertEquals("Half", LiveScore("1", 50, 48, "in", "Halftime", 2, "0.0").clockLabel)
        assertEquals("End Q3", LiveScore("1", 70, 72, "in", "End of 3rd", 3, "0.0").clockLabel)
        assertEquals("OT 1:05", LiveScore("1", 101, 101, "in", "1:05 - OT", 5, "1:05").clockLabel)
        assertEquals("Q4 45.2", LiveScore("1", 90, 88, "in", "45.2 - 4th", 4, "45.2").clockLabel)
        assertEquals("Final/2OT", LiveScore("1", 130, 128, "post", "Final/2OT", 6).clockLabel)
    }

    @Test
    fun badPayloadIsEmpty() {
        assertTrue(LiveScore.parse("nope").isEmpty())
    }

    @Test
    fun dateKeyUsesTheEasternDay() {
        assertEquals("20261020", LiveScore.dateKey(parseDay("2026-10-20")!!))
    }
}
