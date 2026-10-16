package com.jackwallner.basketball

import com.jackwallner.basketball.model.DataFreshness
import com.jackwallner.basketball.model.DataFreshnessStatus
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameBoxScore
import com.jackwallner.basketball.model.GameDay
import com.jackwallner.basketball.model.GameDetail
import com.jackwallner.basketball.model.GameStatus
import com.jackwallner.basketball.model.PlayerGameLog
import com.jackwallner.basketball.model.SeasonPhase
import com.jackwallner.basketball.model.parseDay
import com.jackwallner.basketball.ui.screens.periodLabel
import com.jackwallner.basketball.ui.screens.quarterLabel
import com.jackwallner.basketball.ui.screens.shortName
import java.time.Instant
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GamesTest {
    private fun date(iso: String): Instant = Instant.parse(iso)

    private fun game(
        id: String, day: String, tipoff: String, away: String = "NYK", home: String = "SAS",
        awayScore: Int? = null, homeScore: Int? = null, season: Int = 2026,
    ) = Game(
        id = id, season = season, week = 1, tipoff = date(tipoff), gameDate = parseDay(day)!!,
        awayTeam = away, homeTeam = home, awayScore = awayScore, homeScore = homeScore,
    )

    private fun objects(json: String) = (Json.parseToJsonElement(json) as JsonArray).map { it as JsonObject }

    @Test
    fun decodesPublishedRow() {
        val game = Game.fromJson(
            objects(
                """[{"game_id":"401859967","season":2026,"season_type":"POST","game_type":"POST","week":37,
                  "game_date":"2026-06-13","kickoff_at":"2026-06-14T00:30:00+00:00","away_team":"NYK","home_team":"SAS",
                  "away_score":94,"home_score":90,"overtime":false,"stadium":"Frost Bank Center",
                  "synced_at":"2026-10-08T22:14:01.690661+00:00"}]""",
            ).first(),
        )
        assertTrue(game.isFinal)
        assertEquals(SeasonPhase.PLAYOFFS, game.seasonPhase)
        assertEquals("W 94-90", game.resultLine("NYK"))
        assertEquals("L 90-94", game.resultLine("SAS"))
        assertEquals("at SAS", game.matchupLabel("NYK"))
        assertEquals("vs NYK", game.matchupLabel("SAS"))
        assertEquals(date("2026-06-14T00:30:00Z"), game.tipoff)
    }

    @Test
    fun upcomingScheduleRowHasNoScores() {
        val game = Game.fromJson(
            objects(
                """[{"game_id":"401910771","season":2027,"season_type":"REG","game_type":"REG","week":25,
                  "game_date":"2027-03-19","kickoff_at":"2027-03-20T02:30:00+00:00","away_team":"MIA","home_team":"PHX",
                  "away_score":null,"home_score":null,"overtime":false,"stadium":"Mortgage Matchup Center"}]""",
            ).first(),
        )
        assertFalse(game.isFinal)
        assertNull(game.result("MIA"))
        assertEquals(GameStatus.UPCOMING, game.status(date("2026-10-08T00:00:00Z")))
    }

    @Test
    fun statusWithoutLiveScores() {
        val upcoming = game("a", "2026-10-20", "2026-10-20T23:00:00Z")
        assertEquals(GameStatus.UPCOMING, upcoming.status(date("2026-10-20T22:00:00Z")))
        assertEquals(GameStatus.IN_PROGRESS, upcoming.status(date("2026-10-21T00:30:00Z")))
        assertEquals(GameStatus.AWAITING_SCORE, upcoming.status(date("2026-10-21T04:00:00Z")))
        val final = game("b", "2026-10-20", "2026-10-20T23:00:00Z", awayScore = 101, homeScore = 99)
        assertEquals(GameStatus.FINAL, final.status(date("2026-10-21T00:30:00Z")))
    }

    @Test
    fun noTies() {
        val g = game("c", "2026-10-20", "2026-10-20T23:00:00Z", awayScore = 100, homeScore = 101)
        assertEquals("W", g.result("SAS"))
        assertEquals("L", g.result("NYK"))
    }

    @Test
    fun gameDaysAreDistinctDatesInOrder() {
        val games = listOf(
            game("a", "2026-10-21", "2026-10-21T23:00:00Z"),
            game("b", "2026-10-20", "2026-10-20T23:00:00Z"),
            game("c", "2026-10-21", "2026-10-22T01:30:00Z"),
        )
        val days = GameDay.days(games)
        assertEquals(listOf("2026-10-20", "2026-10-21"), days.map { it.id })
        assertEquals(listOf("b"), days[0].games(games).map { it.id })
        assertEquals(setOf("a", "c"), days[1].games(games).map { it.id }.toSet())
        assertEquals("Oct 20", days[0].shortLabel)
    }

    @Test
    fun currentDayHoldsUntilTheMorningAfter() {
        val games = listOf(
            game("a", "2026-10-20", "2026-10-20T23:00:00Z"),
            game("b", "2026-10-21", "2026-10-21T23:00:00Z"),
            game("c", "2026-10-23", "2026-10-23T23:00:00Z"),
        )
        // Before the season: opening night.
        assertEquals("2026-10-20", GameDay.current(games, date("2026-10-08T00:00:00Z"))?.id)
        // 1am Eastern the night of the 20th: still that night's slate.
        assertEquals("2026-10-20", GameDay.current(games, date("2026-10-21T05:00:00Z"))?.id)
        // Breakfast on the 21st (9am Eastern): the 21st's slate takes over.
        assertEquals("2026-10-21", GameDay.current(games, date("2026-10-21T13:00:00Z"))?.id)
        // A day with no games rolls to the next one that has some.
        assertEquals("2026-10-23", GameDay.current(games, date("2026-10-22T15:00:00Z"))?.id)
        // After the season: the last day.
        assertEquals("2026-10-23", GameDay.current(games, date("2027-07-01T00:00:00Z"))?.id)
    }

    @Test
    fun teamRecordCountsRegularSeasonFinalsThroughAGame() = runTest {
        val g1 = game("g1", "2026-10-20", "2026-10-20T23:00:00Z", "NYK", "SAS", 110, 105)
        val g2 = game("g2", "2026-10-22", "2026-10-22T23:00:00Z", "DET", "NYK", 99, 98)
        val g3 = game("g3", "2026-10-24", "2026-10-24T23:00:00Z", "NYK", "LAC")
        val vm = dashboard(GamesProvider(listOf(g3, g1, g2)))
        vm.loadGames(force = true)
        assertEquals("1-1", vm.record("NYK"))
        assertEquals("1-0", vm.record("NYK", g1))
        assertEquals("0-1", vm.record("SAS"))
        assertNull(vm.record("LAC"))
        assertEquals(listOf("g1", "g2", "g3"), vm.schedule("NYK").map { it.id })
        // A game from another season has no record in the live one.
        val future = game("f", "2026-10-20", "2026-10-20T23:00:00Z", season = 2027)
        assertNull(vm.record("NYK", future))
    }

    @Test
    fun slateOrderPutsLiveFirstThenFinalsThenUpcoming() {
        val slate = Game.slateOrder(
            listOf(
                game("late", "2026-10-20", "2026-10-21T02:30:00Z"),
                game("final", "2026-10-20", "2026-10-20T19:00:00Z", awayScore = 1, homeScore = 2),
                game("live", "2026-10-20", "2026-10-20T23:00:00Z"),
            ),
            date("2026-10-20T23:30:00Z"),
        )
        assertEquals(listOf("live", "final", "late"), slate.map { it.id })
    }

    /** While the next season is pending the Games tab is drawn from its schedule, with the last games of the finished one beneath. */
    @Test
    fun pendingSeasonShowsTheUpcomingSlateAndTheLastGamesPlayed() = runTest {
        val finals = listOf(
            game("f1", "2026-06-10", "2026-06-11T00:30:00Z", awayScore = 106, homeScore = 107),
            game("f2", "2026-06-13", "2026-06-14T00:30:00Z", awayScore = 94, homeScore = 90),
        )
        val opening = game("o1", "2026-10-20", "2026-10-20T23:00:00Z", "PHI", "NYK", season = 2027)
        val pending = DataFreshness(
            status = DataFreshnessStatus.PENDING, rawStatus = "source_pending",
            season = 2027, publishedSeason = 2026, lastErrorCode = "season_pending",
        )
        val vm = dashboard(GamesProvider(finals + opening, pending))
        vm.checkForUpdates(force = true)
        vm.loadGames(force = true)

        assertEquals(listOf("o1"), vm.slateGames.map { it.id })
        assertEquals("2026-10-20", vm.currentGameDay?.id)
        assertEquals(listOf("f2"), vm.lastPlayedGames.map { it.id })
        assertEquals("2026-27 starts Oct 20", vm.upcomingSeasonStartsText)
        assertNotNull(vm.game("o1"))
        assertNotNull(vm.game("f1"))
        // The team schedule shows both seasons, in the order they happen.
        assertEquals(listOf("f1", "f2", "o1"), vm.schedule("NYK").map { it.id })
    }

    @Test
    fun boxScoreTotalsAddPlayerLinesWithoutDoubleCountingThrees() {
        val logs = objects(
            """[{"player_id":1,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"g","team":"NYK",
              "metrics":{"min":36,"starter":1,"pts":31,"reb":2,"ast":5,"stl":1,"blk":0,"tov":3,"pf":2,
                         "fgm":11,"fga":22,"fg3m":4,"fg3a":9,"ftm":5,"fta":6,"oreb":0,"plus_minus":-14}},
             {"player_id":2,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"c","team":"NYK",
              "metrics":{"min":28,"starter":1,"pts":10,"reb":11,"ast":1,"stl":0,"blk":3,"tov":1,"pf":4,
                         "fgm":4,"fga":7,"fg3m":0,"fg3a":0,"ftm":2,"fta":2,"oreb":4,"plus_minus":6}},
             {"player_id":3,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"f","team":"SAS",
              "metrics":{"min":40,"starter":1,"pts":22,"reb":14,"ast":4,"stl":2,"blk":5,"tov":4,"pf":3,
                         "fgm":8,"fga":18,"fg3m":1,"fg3a":5,"ftm":5,"fta":7,"oreb":3,"plus_minus":-9}}]""",
        ).map(PlayerGameLog::fromJson)
        assertEquals("g", logs.first().gameId)
        val box = GameBoxScore(logs)
        val totals = box.totals("NYK")
        assertEquals(41.0, totals.points, 0.0)
        assertEquals(15.0, totals.fieldGoalsMade, 0.0)
        assertEquals(29.0, totals.fieldGoalsAttempted, 0.0)
        assertEquals(51.72, totals.fieldGoalPercentage!!, 0.01)
        assertEquals((15.0 + 2) / 29 * 100, totals.effectiveFieldGoalPercentage!!, 0.01)
        assertEquals(4.0, totals.turnovers, 0.0)
        assertEquals(listOf("Points", "Rebounds", "Assists"), box.leaders.map { it.title })
        assertEquals(1, box.leaders[0].line.playerId)
        assertEquals(3, box.leaders[1].line.playerId)
        assertEquals("-14", box.lines[0].plusMinusText)
        assertEquals("+6", box.lines[1].plusMinusText)
        assertEquals("4/9", box.lines[0].made("fg3m", "fg3a"))
    }

    @Test
    fun gameDetailDecodesTheMarginSeriesAndRatedLines() {
        val detail = GameDetail.fromJson(
            objects(
                """[{"game_id":"g","season":2026,"season_type":"POST","week":37,"away_team":"NYK","home_team":"SAS",
                  "team_stats":{"away":{"pts":{"pct":38,"value":111},"ortg":{"pct":29,"value":105.8},"ft_rate":{"pct":27,"value":0.209},"largest_lead":null},
                                "home":{"pts":{"pct":63,"value":119},"efg_pct":{"pct":32,"value":51.2}}},
                  "players":[{"role":"player","player_id":4432158,"name":"Evan Mobley","team":"NYK","starter":true,"min":36,
                              "pts":{"pct":87,"value":22},"reb":{"pct":86,"value":8},"ast":{"pct":63,"value":3},
                              "ts_pct":{"pct":44,"value":54.5},"usg_pct":{"pct":88,"value":28.4},"plus_minus":{"pct":null,"value":0}},
                             {"role":"player","player_id":9,"team":"NYK"}],
                  "win_probability":[[0,0],[52,0],[165,-1],[2880,-4]],
                  "big_plays":[{"qtr":4,"kind":"late_score","team":"NYK","clock":"1:05","points":2,
                                "description":"Jalen Brunson makes 11-foot driving floating jump shot","home_margin":-2},
                               {"qtr":1,"kind":"lead_change","team":"NYK","clock":"9:30","points":3,
                                "description":"Jalen Brunson makes 25-foot three pointer (Mikal Bridges assists)","home_margin":-1}]}]""",
            ).first(),
        )
        assertEquals(29, detail.stats("NYK")["ortg"]?.percentile)
        assertEquals(51.2, detail.stats("SAS")["efg_pct"]!!.value, 0.0)
        assertNull(detail.away["largest_lead"])
        // The margin series arrives in the column the win probability used to use.
        assertEquals(4, detail.margin.size)
        assertEquals(2880.0, detail.margin.last().elapsed, 0.0)
        assertEquals(-4.0, detail.margin.last().homeMargin, 0.0)
        assertEquals(4, detail.largestLeads.first)
        assertEquals(0, detail.largestLeads.second)
        // The malformed player row (no stats) still decodes as a bare line.
        assertEquals(2, detail.players.size)
        val mobley = detail.players.first { it.playerId == 4432158 }
        assertEquals(36, mobley.minutes)
        assertTrue(mobley.starter)
        assertEquals(87, mobley.points?.percentile)
        assertEquals(54.5, mobley.trueShooting!!.value, 0.0)
        assertNull(mobley.plusMinus?.percentile)
        assertEquals(listOf(GameDetail.BigPlay.Kind.LATE_SCORE, GameDetail.BigPlay.Kind.LEAD_CHANGE), detail.bigPlays.map { it.kind })
        assertEquals(-2, detail.bigPlays[0].homeMargin)
        assertEquals("Q4", quarterLabel(4))
        assertEquals("OT", quarterLabel(5))
        assertEquals("2OT", quarterLabel(6))
        assertEquals("Q4", periodLabel(2160.0))
        assertEquals("OT", periodLabel(2880.0))
        assertEquals("S. Gilgeous-Alexander", shortName("Shai Gilgeous-Alexander"))
    }

    @Test
    fun freshnessReportsAdvancedPending() {
        val freshness = DataFreshness.fromJson(
            Json.parseToJsonElement(
                """{"status":"degraded","refresh_id":"r","max_game_date":"2026-10-21","max_week":3,
                 "observed_games":10,"expected_games":10,"ngs_status":"ready","pfr_status":"pending"}""",
            ) as JsonObject,
        )
        assertTrue(freshness.isAdvancedPending)
        assertEquals("ready", freshness.shotsStatus)
        assertEquals("pending", freshness.playByPlayStatus)
        val roundTrip = DataFreshness.fromJson(freshness.withStatus(freshness.status, cached = true).toJson())
        assertEquals("pending", roundTrip.playByPlayStatus)
    }
}

private class GamesProvider(private val games: List<Game>, private val freshness: DataFreshness? = null) : MockProvider() {
    override suspend fun fetchGames(season: Int): List<Game> = games.filter { it.season == season }
    override suspend fun fetchDataFreshness(): DataFreshness? = freshness
}
