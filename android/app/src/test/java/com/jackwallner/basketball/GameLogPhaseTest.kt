package com.jackwallner.basketball

import com.jackwallner.basketball.model.GameBoxScore
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.SeasonPhase
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Regular-season and playoff rows must never be read as one phase. Playoff
 * games are the newest rows a season has, so a date-descending list that
 * ignored the phase would put June at the top of a Regular Season heading.
 */
class GameLogPhaseTest {
    private fun parse(json: String) = PlayerGameLog.fromJson(Json.parseToJsonElement(json) as JsonObject)

    private fun log(date: String, seasonType: String?, points: Double): PlayerGameLog {
        val phase = seasonType?.let { ""","season_type":"$it"""" } ?: ""
        return parse(
            """{"player_id":7,"season":2026,"game_date":"$date","game_id":"401859967","player_type":"g","plays":25,"touches":34,""" +
                """"metrics":{"pts":$points,"min":34,"plus_minus":null}$phase}""",
        )
    }

    @Test
    fun seasonPhaseIsDecodedFromSeasonType() {
        assertEquals(SeasonPhase.REGULAR, log("2026-04-12", "REG", 20.0).seasonPhase)
        assertEquals(SeasonPhase.PLAYOFFS, log("2026-06-13", "POST", 30.0).seasonPhase)
    }

    /** A row with no phase is a regular-season row, so fixtures that predate the column keep decoding. */
    @Test
    fun missingSeasonTypeDefaultsToRegular() {
        assertEquals(SeasonPhase.REGULAR, log("2025-12-07", null, 25.0).seasonPhase)
    }

    @Test
    fun nullMetricsDecodeAsAbsentNotZero() {
        val row = log("2026-04-12", "REG", 20.0)
        assertEquals(20.0, row.metrics["pts"]!!, 0.0)
        assertNull(row.metrics["plus_minus"])
        // The box score drops the null, so plus/minus shows "-" rather than 0.
        val line = GameBoxScore(listOf(row)).lines[0]
        assertEquals("-", line.plusMinusText)
        assertEquals(34, line.minutes)
    }

    @Test
    fun boxScoreOrdersStartersFirstThenMinutes() {
        fun row(id: Int, minutes: Double, starter: Double) = parse(
            """{"player_id":$id,"season":2026,"game_date":"2026-04-12","season_type":"REG","player_type":"g","team":"BOS",""" +
                """"plays":1,"touches":1,"metrics":{"min":$minutes,"starter":$starter,"pts":10}}""",
        )
        val box = GameBoxScore(listOf(row(1, 12.0, 0.0), row(2, 30.0, 1.0), row(3, 22.0, 0.0), row(4, 0.0, 0.0)))
        assertEquals(listOf(2, 3, 1), box.rotation("BOS").map { it.playerId })
        assertEquals(40.0, box.totals("BOS").points, 0.0)
    }
}
