package com.jackwallner.basketball

import com.jackwallner.basketball.data.DashboardViewModel.QualifierLevel
import com.jackwallner.basketball.model.BasketballMetricRegistry
import com.jackwallner.basketball.model.Game
import com.jackwallner.basketball.model.GameProjection
import com.jackwallner.basketball.model.Metric
import com.jackwallner.basketball.model.MetricAggregation
import com.jackwallner.basketball.model.MetricCategory
import com.jackwallner.basketball.model.MetricWeight
import com.jackwallner.basketball.model.PlayerProfile
import com.jackwallner.basketball.model.RecentForm
import com.jackwallner.basketball.model.StandardStat
import com.jackwallner.basketball.model.StandingsRow
import com.jackwallner.basketball.model.TeamAggregation
import com.jackwallner.basketball.model.TeamRating
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EnrichmentTest {
    private fun player(id: Int, type: String = "g", team: String = "BOS", metrics: List<Metric>, stats: List<StandardStat> = emptyList()) =
        testPlayer(id, "P$id", team, type.uppercase(), TEST_LIVE_SEASON, type = type, metrics = metrics, standard = stats)

    private fun m(label: String, value: String, pct: Int, category: MetricCategory, qualified: Boolean? = null, rankable: Boolean? = null) =
        metric(label, value, pct, category, qualified, rankable, id = "$label-$pct-$value")

    private fun array(json: String) = (Json.parseToJsonElement(json) as JsonArray).map { it as JsonObject }

    @Test
    fun zeroCountingStatIsUnrankedButRatesAndNonZeroCountsAreNot() {
        assertTrue(m("BLK", "0", 47, MetricCategory.DEFENSE).isUnranked)
        assertTrue(m("3PM", "0", 41, MetricCategory.SCORING).isUnranked)
        assertFalse(m("BLK", "12", 80, MetricCategory.DEFENSE).isUnranked)
        assertFalse("a rate at zero is a real rank", m("On-Court +/-", "0.0", 50, MetricCategory.IMPACT).isUnranked)
        assertFalse(m("STL%", "0.0%", 5, MetricCategory.DEFENSE).isUnranked)
        assertTrue(m("BPG", "0", 47, MetricCategory.DEFENSE, rankable = false).isUnranked)
    }

    @Test
    fun overallPercentileLeavesUnrankedZerosOut() {
        val reserve = player(
            1, type = "c",
            metrics = listOf(
                m("TS%", "52.0%", 20, MetricCategory.SCORING),
                m("BLK", "0", 47, MetricCategory.DEFENSE),
                m("3PM", "0", 41, MetricCategory.SCORING),
            ),
        )
        assertEquals(20, reserve.overallPercentile)
        assertEquals("TS%", reserve.headlineMetric?.label)
    }

    @Test
    fun standingsCountRecordsDifferentialAndStreak() {
        fun final(id: String, day: Int, away: String, home: String, a: Int, h: Int) = Game(
            id = id, season = 2026, week = day, tipoff = Instant.ofEpochSecond(1_789_000_000L + day * 86_400L),
            awayTeam = away, homeTeam = home, awayScore = a, homeScore = h,
        )
        val games = listOf(
            final("1", 1, "BOS", "NYK", 110, 104),
            final("2", 2, "LAL", "BOS", 99, 101),
            final("3", 3, "BOS", "MIA", 96, 108),
            Game(id = "4", season = 2026, week = 4, tipoff = null, awayTeam = "NYK", homeTeam = "BOS"),
        )
        val table = StandingsRow.build(games, listOf("BOS", "NYK", "LAL", "MIA"))
        val boston = table.getValue("BOS")
        assertEquals("2-1", boston.record)
        assertEquals((110 + 101 + 96) - (104 + 99 + 108), boston.differential)
        assertEquals("L1", boston.streak)
        assertEquals("1-0", table.getValue("MIA").record)
        assertEquals("W1", table.getValue("MIA").streak)
        assertEquals(listOf("MIA", "BOS", "LAL", "NYK"), StandingsRow.ordered(table.values.toList()).map { it.team })
    }

    @Test
    fun profileDecodesTheFeedRowAndIgnoresTheUnusedNullColumns() {
        val rows = array(
            """[{"player_id":1966,"season":2026,"jersey":23,"birth_date":"1984-12-30","height_in":81,"weight_lb":250,
              "college":null,"years_exp":23,"rookie_season":2004,"draft_year":2003,"draft_round":1,"draft_pick":1,"draft_team":null,
              "contract_apy":null,"contract_cap_pct":null,"contract_years":null,"contract_year_signed":null,
              "contract_value":null,"contract_guaranteed":null,"snap_games":null,"team_games":null,
              "off_snaps":null,"def_snaps":null,"st_snaps":null,"off_snap_pct":null,"def_snap_pct":null,
              "injury_week":null,"injury_status":null,"injury":null,"practice_status":null,
              "updated_at":"2026-10-08T21:45:13.559902+00:00"}]""",
        )
        val profile = PlayerProfile.fromJson(rows.first())
        assertEquals("6-9, 250", profile.sizeLabel)
        assertEquals("2003 R1 #1", profile.draftLabel)
        assertEquals(23, profile.jersey)
        assertEquals(41, profile.age(LocalDate.of(2026, 10, 8)))
    }

    @Test
    fun undraftedPlayerReadsUndrafted() {
        assertNull(PlayerProfile(playerId = 1, season = 2026).draftLabel)
        assertEquals("Undrafted", PlayerProfile(playerId = 1, season = 2026, yearsExperience = 3).draftLabel)
    }

    @Test
    fun projectionLabelsTheFavourite() {
        val rows = array("""[{"game_id":"g","home_margin":-10.8,"home_win_prob":0.211},{"game_id":"h","home_margin":0.4,"home_win_prob":0.51}]""")
            .map(GameProjection::fromJson)
        assertEquals("OKC by 11.0", rows[0].label("WAS", "OKC"))
        assertEquals(0.789, rows[0].winProbability("OKC", "WAS"), 0.0001)
        assertEquals("Toss-up", rows[1].label("WAS", "OKC"))
    }

    @Test
    fun teamRatingDecodesPerHundredPossessionsAndSigns() {
        val rating = TeamRating.fromJson(
            array(
                """[{"season":2026,"team":"OKC","rank":1,"games":82,"through_week":28,"rating":8.41,"offense":2.61,"defense":5.8,"schedule":-0.11,"prior_weight":0.196,"wins":64,"losses":18,"ties":0,"points_for":9760,"points_against":8846,"updated_at":"2026-10-08T21:45:13.559902+00:00"}]""",
            ).first(),
        )
        assertEquals(64, rating.wins)
        assertEquals(rating.rating, rating.offense + rating.defense, 0.001)
        assertEquals("+8.4", TeamRating.signed(rating.rating))
        assertEquals("0.0", TeamRating.signed(-0.04))
        assertEquals("-2.4", TeamRating.signed(-2.37))
    }

    @Test
    fun rosterRatesWeightByMinutesAndCountsAdd() {
        val starter = player(
            1, metrics = listOf(m("TS%", "60.0%", 80, MetricCategory.SCORING), m("PPG", "20.0", 80, MetricCategory.SCORING)),
            stats = listOf(StandardStat("MIN", "2,000", "m")),
        )
        val cameo = player(
            2, metrics = listOf(m("TS%", "90.0%", 99, MetricCategory.SCORING), m("PPG", "2.0", 20, MetricCategory.SCORING)),
            stats = listOf(StandardStat("MIN", "100", "m")),
        )
        val roster = listOf(starter, cameo)
        // 100 minutes at 90% barely moves a 2,000-minute 60%.
        assertEquals(61.4286, TeamAggregation.value("TS%", MetricCategory.SCORING, roster)!!, 0.001)
        // Per-game scoring adds up to the team's.
        assertEquals(22.0, TeamAggregation.value("PPG", MetricCategory.SCORING, roster)!!, 1e-9)
        // No minutes means no weight: dropped rather than let in at weight 1.
        val noMinutes = player(3, metrics = listOf(m("TS%", "99.0%", 99, MetricCategory.SCORING)))
        assertEquals(61.4286, TeamAggregation.value("TS%", MetricCategory.SCORING, roster + noMinutes)!!, 0.001)
        assertEquals(MetricAggregation.Weighted(MetricWeight.GAMES), BasketballMetricRegistry.aggregation("MPG", MetricCategory.IMPACT))
    }

    @Test
    fun teamPercentileRanksAmongTeamsAndFlipsForLowerIsBetter() {
        val values = listOf(10.0, 20.0, 30.0, 40.0)
        assertEquals(88, TeamAggregation.percentile(40.0, values))
        assertEquals(13, TeamAggregation.percentile(40.0, values, higherIsBetter = false))
        assertEquals(50, TeamAggregation.percentile(5.0, emptyList()))
    }

    @Test
    fun recentRowsPoolByMinutes() {
        fun row(id: Int, minutes: Int, ts: Double) = RecentForm.fromJson(
            Json.parseToJsonElement(
                """{"player_id":$id,"season":2026,"player_type":"g","window_weeks":2,"team":"BOS","games":4,
                 "plays":50,"touches":$minutes,"metrics":{"ts_pct":$ts},"prior_metrics":{},"delta":{}}""",
            ) as JsonObject,
        )
        val rows = listOf(row(1, 100, 60.0), row(2, 300, 50.0))
        assertEquals(52.5, TeamAggregation.recentValue("ts_pct", rows)!!, 0.001)
        assertNull(TeamAggregation.recentValue("missing", rows))
    }

    @Test
    fun qualificationIsPerMetric() = runTest {
        val shooter = player(
            1,
            metrics = listOf(
                m("TS%", "61.0%", 90, MetricCategory.SCORING, qualified = true),
                m("Corner 3%", "48.0%", 99, MetricCategory.SHOOTING, qualified = false),
            ),
        )
        val vm = dashboard(MockProvider(listOf(shooter)))
        vm.load()
        vm.qualifierLevel = QualifierLevel.QUALIFIED
        vm.setUserSortMetric("Corner 3%")
        assertTrue("qualified for TS% is not qualified for Corner 3%", vm.leaderboard.isEmpty())
        vm.setUserSortMetric("TS%")
        assertEquals(listOf(1), vm.leaderboard.map { it.playerId })
    }

    @Test
    fun profilesLoadForTheLiveSeason() = runTest {
        val guard = player(1, metrics = listOf(m("TS%", "60.0%", 70, MetricCategory.SCORING)))
        fun provider(profile: PlayerProfile) = object : MockProvider(listOf(guard)) {
            override suspend fun fetchPlayerProfiles(season: Int) = listOf(profile)
        }
        val vm = dashboard(provider(PlayerProfile(playerId = 1, season = TEST_LIVE_SEASON, heightInches = 75)))
        vm.load()
        assertEquals(75, vm.profile(vm.players[0])?.heightInches)

        val stale = dashboard(provider(PlayerProfile(playerId = 1, season = TEST_LIVE_SEASON - 1, heightInches = 75)))
        stale.load()
        assertNull("a profile from another season is not this player's", stale.profile(guard))
    }
}
