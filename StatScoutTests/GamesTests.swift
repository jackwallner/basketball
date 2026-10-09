import XCTest
@testable import Hardwood_StatScout

final class GamesTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func game(
        _ id: String,
        day: String,
        tipoff: String,
        away: String = "NYK",
        home: String = "SAS",
        awayScore: Int? = nil,
        homeScore: Int? = nil,
        season: Int = 2026
    ) -> Game {
        Game(
            id: id, season: season, week: 1, tipoff: date(tipoff),
            gameDate: DataFreshness.parseDate(day), awayTeam: away, homeTeam: home,
            awayScore: awayScore, homeScore: homeScore
        )
    }

    func testDecodesPublishedRow() throws {
        let json = """
        [{"game_id":"401859967","season":2026,"season_type":"POST","game_type":"POST","week":37,
          "game_date":"2026-06-13","kickoff_at":"2026-06-14T00:30:00+00:00","away_team":"NYK","home_team":"SAS",
          "away_score":94,"home_score":90,"overtime":false,"stadium":"Frost Bank Center",
          "synced_at":"2026-10-08T22:14:01.690661+00:00"}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder.statScout.decode([Game].self, from: json)
        let game = try XCTUnwrap(decoded.first)
        XCTAssertTrue(game.isFinal)
        XCTAssertEqual(game.seasonPhase, .playoffs)
        XCTAssertEqual(game.resultLine(for: "NYK"), "W 94-90")
        XCTAssertEqual(game.resultLine(for: "SAS"), "L 90-94")
        XCTAssertEqual(game.matchupLabel(for: "NYK"), "at SAS")
        XCTAssertEqual(game.matchupLabel(for: "SAS"), "vs NYK")
        XCTAssertEqual(game.tipoff, date("2026-06-14T00:30:00Z"))
    }

    func testUpcomingScheduleRowHasNoScores() throws {
        let json = """
        [{"game_id":"401910771","season":2027,"season_type":"REG","game_type":"REG","week":25,
          "game_date":"2027-03-19","kickoff_at":"2027-03-20T02:30:00+00:00","away_team":"MIA","home_team":"PHX",
          "away_score":null,"home_score":null,"overtime":false,"stadium":"Mortgage Matchup Center"}]
        """.data(using: .utf8)!
        let game = try XCTUnwrap(JSONDecoder.statScout.decode([Game].self, from: json).first)
        XCTAssertFalse(game.isFinal)
        XCTAssertNil(game.result(for: "MIA"))
        XCTAssertEqual(game.status(now: date("2026-10-08T00:00:00Z")), .upcoming)
    }

    func testStatusWithoutLiveScores() {
        let upcoming = game("a", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z")
        XCTAssertEqual(upcoming.status(now: date("2026-10-20T22:00:00Z")), .upcoming)
        XCTAssertEqual(upcoming.status(now: date("2026-10-21T00:30:00Z")), .inProgress)
        XCTAssertEqual(upcoming.status(now: date("2026-10-21T04:00:00Z")), .awaitingScore)
        let final = game("b", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z", awayScore: 101, homeScore: 99)
        XCTAssertEqual(final.status(now: date("2026-10-21T00:30:00Z")), .final)
    }

    func testNoTies() {
        let g = game("c", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z", awayScore: 100, homeScore: 101)
        XCTAssertEqual(g.result(for: "SAS"), "W")
        XCTAssertEqual(g.result(for: "NYK"), "L")
    }

    func testGameDaysAreDistinctDatesInOrder() {
        let games = [
            game("a", day: "2026-10-21", tipoff: "2026-10-21T23:00:00Z"),
            game("b", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z"),
            game("c", day: "2026-10-21", tipoff: "2026-10-22T01:30:00Z"),
        ]
        let days = GameDay.days(in: games)
        XCTAssertEqual(days.map(\.id), ["2026-10-20", "2026-10-21"])
        XCTAssertEqual(days[0].games(from: games).map(\.id), ["b"])
        XCTAssertEqual(Set(days[1].games(from: games).map(\.id)), ["a", "c"])
        XCTAssertEqual(days[0].shortLabel, "Oct 20")
    }

    func testCurrentDayHoldsUntilTheMorningAfter() {
        let games = [
            game("a", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z"),
            game("b", day: "2026-10-21", tipoff: "2026-10-21T23:00:00Z"),
            game("c", day: "2026-10-23", tipoff: "2026-10-23T23:00:00Z"),
        ]
        // Before the season: opening night.
        XCTAssertEqual(GameDay.current(in: games, now: date("2026-10-08T00:00:00Z"))?.id, "2026-10-20")
        // 1am Eastern the night of the 20th: still that night's slate.
        XCTAssertEqual(GameDay.current(in: games, now: date("2026-10-21T05:00:00Z"))?.id, "2026-10-20")
        // Breakfast on the 21st (9am Eastern): the 21st's slate takes over.
        XCTAssertEqual(GameDay.current(in: games, now: date("2026-10-21T13:00:00Z"))?.id, "2026-10-21")
        // A day with no games rolls to the next one that has some.
        XCTAssertEqual(GameDay.current(in: games, now: date("2026-10-22T15:00:00Z"))?.id, "2026-10-23")
        // After the season: the last day.
        XCTAssertEqual(GameDay.current(in: games, now: date("2027-07-01T00:00:00Z"))?.id, "2026-10-23")
    }

    @MainActor
    func testTeamRecordCountsRegularSeasonFinalsThroughAGame() async {
        let g1 = game("g1", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z", away: "NYK", home: "SAS", awayScore: 110, homeScore: 105)
        let g2 = game("g2", day: "2026-10-22", tipoff: "2026-10-22T23:00:00Z", away: "DET", home: "NYK", awayScore: 99, homeScore: 98)
        let g3 = game("g3", day: "2026-10-24", tipoff: "2026-10-24T23:00:00Z", away: "NYK", home: "LAC")
        let model = makeViewModel(provider: GamesProvider(games: [g3, g1, g2]))
        await model.loadGames(force: true)
        XCTAssertEqual(model.record(forTeam: "NYK"), "1-1")
        XCTAssertEqual(model.record(forTeam: "NYK", through: g1), "1-0")
        XCTAssertEqual(model.record(forTeam: "SAS"), "0-1")
        XCTAssertNil(model.record(forTeam: "LAC"))
        XCTAssertEqual(model.schedule(forTeam: "NYK").map(\.id), ["g1", "g2", "g3"])
        // A game from another season has no record in the live one.
        let future = game("f", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z", season: 2027)
        XCTAssertNil(model.record(forTeam: "NYK", through: future))
    }

    func testSlateOrderPutsLiveFirstThenFinalsThenUpcoming() {
        let now = date("2026-10-20T23:30:00Z")
        let slate = Game.slateOrder([
            game("late", day: "2026-10-20", tipoff: "2026-10-21T02:30:00Z"),
            game("final", day: "2026-10-20", tipoff: "2026-10-20T19:00:00Z", awayScore: 1, homeScore: 2),
            game("live", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z"),
        ], now: now)
        XCTAssertEqual(slate.map(\.id), ["live", "final", "late"])
    }

    /// While the next season is pending the Games tab is drawn from its
    /// schedule, with the last games of the finished one beneath.
    @MainActor
    func testPendingSeasonShowsTheUpcomingSlateAndTheLastGamesPlayed() async {
        let finals = [
            game("f1", day: "2026-06-10", tipoff: "2026-06-11T00:30:00Z", awayScore: 106, homeScore: 107),
            game("f2", day: "2026-06-13", tipoff: "2026-06-14T00:30:00Z", awayScore: 94, homeScore: 90),
        ]
        let opening = game("o1", day: "2026-10-20", tipoff: "2026-10-20T23:00:00Z", away: "PHI", home: "NYK", season: 2027)
        let pending = DataFreshness(
            status: .pending, rawStatus: "source_pending",
            season: 2027, publishedSeason: 2026, lastErrorCode: "season_pending"
        )
        let model = makeViewModel(
            provider: GamesProvider(games: finals + [opening], freshness: pending),
            calendarSeason: 2027
        )
        _ = await model.checkForUpdates(force: true)
        await model.loadGames(force: true)

        XCTAssertEqual(model.slateGames.map(\.id), ["o1"])
        XCTAssertEqual(model.currentGameDay?.id, "2026-10-20")
        XCTAssertEqual(model.lastPlayedGames.map(\.id), ["f2"])
        XCTAssertEqual(model.upcomingSeasonStartsText, "2026-27 starts Oct 20")
        XCTAssertNotNil(model.game(id: "o1"))
        XCTAssertNotNil(model.game(id: "f1"))
        // The team schedule shows both seasons, in the order they happen.
        XCTAssertEqual(model.schedule(forTeam: "NYK").map(\.id), ["f1", "f2", "o1"])
    }

    func testBoxScoreTotalsAddPlayerLinesWithoutDoubleCountingThrees() throws {
        let json = """
        [{"player_id":1,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"g","team":"NYK",
          "metrics":{"min":36,"starter":1,"pts":31,"reb":2,"ast":5,"stl":1,"blk":0,"tov":3,"pf":2,
                     "fgm":11,"fga":22,"fg3m":4,"fg3a":9,"ftm":5,"fta":6,"oreb":0,"plus_minus":-14}},
         {"player_id":2,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"c","team":"NYK",
          "metrics":{"min":28,"starter":1,"pts":10,"reb":11,"ast":1,"stl":0,"blk":3,"tov":1,"pf":4,
                     "fgm":4,"fga":7,"fg3m":0,"fg3a":0,"ftm":2,"fta":2,"oreb":4,"plus_minus":6}},
         {"player_id":3,"season":2026,"season_type":"REG","game_id":"g","game_date":"2026-06-13","player_type":"f","team":"SAS",
          "metrics":{"min":40,"starter":1,"pts":22,"reb":14,"ast":4,"stl":2,"blk":5,"tov":4,"pf":3,
                     "fgm":8,"fga":18,"fg3m":1,"fg3a":5,"ftm":5,"fta":7,"oreb":3,"plus_minus":-9}}]
        """.data(using: .utf8)!
        let logs = try JSONDecoder.statScout.decode([PlayerGameLog].self, from: json)
        XCTAssertEqual(logs.first?.gameId, "g")
        let box = GameBoxScore(logs: logs)
        let totals = box.totals(for: "NYK")
        XCTAssertEqual(totals.points, 41)
        XCTAssertEqual(totals.fieldGoalsMade, 15)
        XCTAssertEqual(totals.fieldGoalsAttempted, 29)
        XCTAssertEqual(try XCTUnwrap(totals.fieldGoalPercentage), 51.72, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(totals.effectiveFieldGoalPercentage), (15 + 2) / 29 * 100, accuracy: 0.01)
        XCTAssertEqual(totals.turnovers, 4)
        XCTAssertEqual(box.leaders.map(\.title), ["Points", "Rebounds", "Assists"])
        XCTAssertEqual(box.leaders[0].line.playerId, 1)
        XCTAssertEqual(box.leaders[1].line.playerId, 3)
        XCTAssertEqual(box.lines[0].plusMinusText, "-14")
        XCTAssertEqual(box.lines[1].plusMinusText, "+6")
        XCTAssertEqual(box.lines[0].made("fg3m", of: "fg3a"), "4/9")
    }

    func testGameDetailDecodesTheMarginSeriesAndRatedLines() throws {
        let json = """
        [{"game_id":"g","season":2026,"season_type":"POST","week":37,"away_team":"NYK","home_team":"SAS",
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
                        "description":"Jalen Brunson makes 25-foot three pointer (Mikal Bridges assists)","home_margin":-1}]}]
        """.data(using: .utf8)!
        let detail = try XCTUnwrap(JSONDecoder.statScout.decode([GameDetail].self, from: json).first)
        XCTAssertEqual(detail.stats(for: "NYK")["ortg"]?.percentile, 29)
        XCTAssertEqual(detail.stats(for: "SAS")["efg_pct"]?.value, 51.2)
        XCTAssertNil(detail.away["largest_lead"])
        // The margin series arrives in the column the win probability used to use.
        XCTAssertEqual(detail.margin.count, 4)
        XCTAssertEqual(detail.margin.last?.elapsed, 2880)
        XCTAssertEqual(detail.margin.last?.homeMargin, -4)
        XCTAssertEqual(detail.largestLeads.away, 4)
        XCTAssertEqual(detail.largestLeads.home, 0)
        // The malformed player row (no stats) still decodes as a bare line.
        XCTAssertEqual(detail.players.count, 2)
        let mobley = try XCTUnwrap(detail.players.first { $0.playerId == 4432158 })
        XCTAssertEqual(mobley.minutes, 36)
        XCTAssertTrue(mobley.starter)
        XCTAssertEqual(mobley.points?.percentile, 87)
        XCTAssertEqual(mobley.trueShooting?.value, 54.5)
        XCTAssertNil(mobley.plusMinus?.percentile)
        XCTAssertEqual(detail.bigPlays.map(\.kind), [.lateScore, .leadChange])
        XCTAssertEqual(detail.bigPlays[0].homeMargin, -2)
        XCTAssertEqual(GameDetailView.quarterLabel(4), "Q4")
        XCTAssertEqual(GameDetailView.quarterLabel(5), "OT")
        XCTAssertEqual(GameDetailView.quarterLabel(6), "2OT")
        XCTAssertEqual(GameDetailView.periodLabel(startingAt: 2160), "Q4")
        XCTAssertEqual(GameDetailView.periodLabel(startingAt: 2880), "OT")
        XCTAssertEqual(GameDetailView.shortName("Shai Gilgeous-Alexander"), "S. Gilgeous-Alexander")
    }

    func testFreshnessReportsAdvancedPending() throws {
        let json = """
        {"status":"degraded","refresh_id":"r","max_game_date":"2026-10-21","max_week":3,
         "observed_games":10,"expected_games":10,"ngs_status":"ready","pfr_status":"pending"}
        """.data(using: .utf8)!
        let freshness = try JSONDecoder.statScout.decode(DataFreshness.self, from: json)
        XCTAssertTrue(freshness.isAdvancedPending)
        XCTAssertEqual(freshness.shotsStatus, "ready")
        XCTAssertEqual(freshness.playByPlayStatus, "pending")
        let roundTrip = try JSONDecoder.statScout.decode(
            DataFreshness.self,
            from: JSONEncoder.statScout.encode(freshness.replacing(isCached: true))
        )
        XCTAssertEqual(roundTrip.playByPlayStatus, "pending")
    }
}

private struct GamesProvider: StatcastProviding {
    let games: [Game]
    var freshness: DataFreshness? = nil
    func fetchGames(season: Int) async throws -> [Game] { games.filter { $0.season == season } }
    func fetchDataFreshness() async throws -> DataFreshness? { freshness }
    func fetchHistoricalPlayers(before season: Int) async throws -> [Player] { [] }
    func fetchCurrentPlayers(season: Int) async throws -> [Player] { [] }
    func fetchGameLogs(playerId: Int, season: Int, seasonPhase: SeasonPhase) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(season: Int, seasonPhase: SeasonPhase, windowWeeks: Int) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
