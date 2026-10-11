import XCTest
@testable import Hardwood_StatScout

final class SeriesAndStandingsTests: XCTestCase {
    private func game(
        _ id: String,
        day: Int,
        away: String,
        home: String,
        awayScore: Int?,
        homeScore: Int?,
        phase: SeasonPhase = .playoffs,
        type: String = "FIN"
    ) -> Game {
        let tip = Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400)
        return Game(
            id: id, season: 2026, seasonPhase: phase, gameType: type, week: 30, tipoff: tip,
            awayTeam: away, homeTeam: home, awayScore: awayScore, homeScore: homeScore
        )
    }

    func testSeriesCountsGamesAndWinsThroughTheGame() throws {
        let finals = [
            game("1", day: 0, away: "NYK", home: "SAS", awayScore: 100, homeScore: 110),
            game("2", day: 2, away: "NYK", home: "SAS", awayScore: 105, homeScore: 99),
            game("3", day: 4, away: "SAS", home: "NYK", awayScore: 90, homeScore: 101),
            game("4", day: 6, away: "SAS", home: "NYK", awayScore: 95, homeScore: 98),
            game("5", day: 8, away: "NYK", home: "SAS", awayScore: 94, homeScore: 90),
            // Another round between other teams must not count.
            game("9", day: 1, away: "OKC", home: "SAS", awayScore: 99, homeScore: 100, type: "CF"),
        ]
        let opener = try XCTUnwrap(SeriesStatus.of(finals[0], in: finals))
        XCTAssertEqual(opener.gameLabel, "NBA Finals · Game 1")
        XCTAssertEqual(opener.standingLabel, "SAS leads 1-0")
        let second = try XCTUnwrap(SeriesStatus.of(finals[1], in: finals))
        XCTAssertEqual(second.standingLabel, "Series tied 1-1")
        let clincher = try XCTUnwrap(SeriesStatus.of(finals[4], in: finals))
        XCTAssertEqual(clincher.gameNumber, 5)
        XCTAssertEqual(clincher.standingLabel, "NYK wins 4-1")
        XCTAssertEqual(finals[4].contextLine(series: clincher), "NBA Finals · Game 5 · NYK wins 4-1")
    }

    func testUpcomingFirstGameHasNoStanding() throws {
        let opener = game("1", day: 0, away: "BOS", home: "DET", awayScore: nil, homeScore: nil, type: "R1")
        let series = try XCTUnwrap(SeriesStatus.of(opener, in: [opener]))
        XCTAssertEqual(series.round, "East 1st Round")
        XCTAssertNil(series.standingLabel)
    }

    func testRegularSeasonGameHasNoSeries() {
        let regular = game("1", day: 0, away: "BOS", home: "DET", awayScore: 1, homeScore: 2, phase: .regular, type: "REG")
        XCTAssertNil(SeriesStatus.of(regular, in: [regular]))
        XCTAssertNil(regular.contextLine(series: nil))
    }

    func testCupFinalAndPostponedGamesStayOutOfTheStandings() {
        let games = [
            game("1", day: 0, away: "NYK", home: "SAS", awayScore: 124, homeScore: 113, phase: .regular, type: "CUP"),
            game("2", day: 1, away: "NYK", home: "SAS", awayScore: 100, homeScore: 90, phase: .regular, type: "REG"),
            game("3", day: 2, away: "NYK", home: "SAS", awayScore: nil, homeScore: nil, phase: .regular, type: "PPD"),
        ]
        let table = StandingsRow.build(from: games, teams: ["NYK", "SAS"])
        XCTAssertEqual(table["NYK"]?.record, "1-0")
        XCTAssertEqual(table["SAS"]?.record, "0-1")
        XCTAssertEqual(games[0].contextLine(series: nil), "NBA Cup Final")
    }

    func testGamesBackAndMargin() {
        let leader = StandingsRow(team: "OKC", wins: 64, losses: 18, pointsFor: 9760, pointsAgainst: 8846)
        let chaser = StandingsRow(team: "SAS", wins: 62, losses: 20, pointsFor: 9939, pointsAgainst: 9269)
        XCTAssertEqual(chaser.gamesBack(of: leader), 2)
        XCTAssertEqual(StandingsRow.formatGamesBack(3.5), "3.5")
        XCTAssertEqual(StandingsRow.formatGamesBack(12), "12")
        XCTAssertEqual(leader.marginLabel, "+11.1")
        XCTAssertNil(StandingsRow(team: "BOS").marginLabel)
    }

    func testShotProfileStatsAreNotGraded() {
        let style = Metric(id: "a", label: "Long Mid Freq", value: "5.6%", percentile: 99, category: .shooting)
        let skill = Metric(id: "b", label: "TS%", value: "67.0%", percentile: 60, category: .scoring)
        XCTAssertTrue(style.isShotProfile)
        XCTAssertFalse(skill.isShotProfile)
        XCTAssertFalse(PlayerComparisonView.beats(style, skill))
    }

    func testComparisonWinnerUsesValuesAcrossPositionPools() {
        // A center's 99th-percentile AST% is not better than a guard's 40%.
        let center = Metric(id: "c", label: "AST%", value: "20.0%", percentile: 99, category: .playmaking)
        let guardMetric = Metric(id: "g", label: "AST%", value: "40.0%", percentile: 95, category: .playmaking)
        XCTAssertTrue(PlayerComparisonView.beats(guardMetric, center))
        XCTAssertFalse(PlayerComparisonView.beats(center, guardMetric))
        // Lower is better for TOV%.
        let careful = Metric(id: "t1", label: "TOV%", value: "8.0%", percentile: 90, category: .playmaking)
        let loose = Metric(id: "t2", label: "TOV%", value: "15.0%", percentile: 20, category: .playmaking)
        XCTAssertTrue(PlayerComparisonView.beats(careful, loose))
    }

    func testEasternDayParsingIgnoresThePhonesCalendar() {
        let formatter = DataFreshness.makeEasternDayFormatter()
        let date = formatter.date(from: "2026-10-20")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(date.map { calendar.component(.year, from: $0) }, 2026)
    }

    func testTeamFiguresScaleFloorSharesAndDropUsage() {
        XCTAssertEqual(TeamAggregation.teamScale("Pts/100"), 5)
        XCTAssertEqual(TeamAggregation.teamScale("REB%"), 5)
        XCTAssertEqual(TeamAggregation.teamScale("TS%"), 1)
        XCTAssertEqual(TeamAggregation.teamScale("On-Court +/-"), 1)
        XCTAssertNil(TeamAggregation.teamScale("USG%"))
        XCTAssertNil(TeamAggregation.teamScale("On-Off"))
    }
}
